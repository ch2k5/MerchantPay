import csv
from datetime import datetime
from decimal import Decimal
from pathlib import Path

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.models import User
from apps.alerts.services import evaluate_merchant_alerts
from apps.analytics.services import compute_payment_transactions_summary
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    MerchantCategory,
    MerchantStatus,
    PaymentChannel,
    TransactionStatus,
    UserRole,
)
from apps.merchants.models import Merchant
from apps.risk.services import scan_merchant_risk
from apps.transactions.models import Transaction

MERCHANT_METADATA = {
    "MER-3615": {"name": "Algérie Télécom Services", "wilaya": "Alger", "commune": "Bab El Oued"},
    "MER-1520": {"name": "Mobilis Connect Blida", "wilaya": "Blida", "commune": "Ouled Yaïch"},
    "MER-5012": {"name": "Supermarché Uno Oran", "wilaya": "Oran", "commune": "Es Senia"},
    "MER-5506": {"name": "TechZone Algérie", "wilaya": "Alger", "commune": "Hydra"},
    "MER-2535": {"name": "Café Restaurant El Bahdja", "wilaya": "Alger", "commune": "Casbah"},
    "MER-1488": {"name": "Hôtel & Voyages Maghreb", "wilaya": "Constantine", "commune": "Sidi M'Cid"},
    "MER-5552": {"name": "Boutique El Mordjane", "wilaya": "Sétif", "commune": "Ain Oulmene"},
    "MER-7873": {"name": "Superette En-Nour", "wilaya": "Alger", "commune": "Kouba"},
    "MER-2424": {"name": "Ooredoo Espace Services", "wilaya": "Annaba", "commune": "Sidi Amar"},
    "MER-7924": {"name": "Marché Soummam", "wilaya": "Béjaïa", "commune": "El Kseur"},
    "MER-1409": {"name": "Zianides Travel & Tours", "wilaya": "Tlemcen", "commune": "Mansourah"},
    "MER-1106": {"name": "Pâtisserie & Salon La Rose", "wilaya": "Alger", "commune": "El Biar"},
    "MER-4811": {"name": "Djezzy Pro Center", "wilaya": "Oran", "commune": "Bir El Djir"},
    "MER-4257": {"name": "Pharmacie Centrale Didouche", "wilaya": "Alger", "commune": "Didouche Mourad"},
    "MER-4527": {"name": "Maison de Couture Cirta", "wilaya": "Constantine", "commune": "El Khroub"},
    "MER-7912": {"name": "Mode & Confection Djurdjura", "wilaya": "Tizi Ouzou", "commune": "Draa Ben Khedda"},
    "MER-6574": {"name": "Agence Tourisme El Aurassi", "wilaya": "Alger", "commune": "Telemly"},
    "MER-4611": {"name": "Restaurant Le Bahia", "wilaya": "Oran", "commune": "Front de Mer"},
    "MER-3547": {"name": "Pharmacie Ain Fouara", "wilaya": "Sétif", "commune": "Centre-ville"},
    "MER-9928": {"name": "Pizzeria Gouraya", "wilaya": "Béjaïa", "commune": "Port"},
    "MER-2679": {"name": "Caféteria Chréa", "wilaya": "Blida", "commune": "Chréa"},
    "MER-5557": {"name": "Boutique Bône Élégance", "wilaya": "Annaba", "commune": "Cours de la Révolution"},
    "MER-8359": {"name": "Cyber & Télécom Mansourah", "wilaya": "Tlemcen", "commune": "Chetouane"},
    "MER-9935": {"name": "NetCom Solutions", "wilaya": "Alger", "commune": "Bordj El Kiffan"},
    "MER-3286": {"name": "Maroquinerie Saint-Pierre", "wilaya": "Oran", "commune": "Maraval"},
    "MER-9279": {"name": "Pharmacie El Amir", "wilaya": "Constantine", "commune": "Ali Mendjeli"},
    "MER-4657": {"name": "Boutique Sidi Yahia", "wilaya": "Alger", "commune": "Sidi Yahia"},
    "MER-4582": {"name": "Galerie Park Mall", "wilaya": "Sétif", "commune": "Park Mall"},
    "MER-1434": {"name": "Boulangerie Santa Cruz", "wilaya": "Oran", "commune": "Canastel"},
    "MER-2824": {"name": "Textile Mitidja", "wilaya": "Blida", "commune": "Boufarik"},
}


class Command(BaseCommand):
    help = "Ingests the official 150-row payment transactions dataset and generates full summary analytics."

    def add_arguments(self, parser):
        parser.add_argument(
            "--file",
            type=str,
            default=None,
            help="Path to CSV dataset file. Defaults to data/payment_transactions_dataset.csv",
        )

    def handle(self, *args, **options):
        file_path = options.get("file")
        if not file_path:
            candidates = [
                Path(__file__).resolve().parents[5] / "data" / "payment_transactions_dataset.csv",
                Path(__file__).resolve().parents[4] / "data" / "payment_transactions_dataset.csv",
                Path("data/payment_transactions_dataset.csv"),
            ]
            for c in candidates:
                if c.exists():
                    file_path = str(c)
                    break

        if not file_path or not Path(file_path).exists():
            self.stderr.write(self.style.ERROR(f"Dataset file not found at {file_path}"))
            return

        self.stdout.write(f"Reading official dataset from: {file_path}")

        rows = []
        with open(file_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("transaction_id") and row.get("transaction_id").startswith("TXN-"):
                    rows.append(row)

        self.stdout.write(f"Parsed {len(rows)} transactions.")

        merchants_data = {}
        for r in rows:
            mid = r["merchant_id"]
            if mid not in merchants_data:
                merchants_data[mid] = {
                    "category": r["merchant_category"],
                    "rows": [],
                }
            merchants_data[mid]["rows"].append(r)

        self.stdout.write(f"Found {len(merchants_data)} unique merchants.")

        with transaction.atomic():
            created_merchants = {}
            for mid, mdata in merchants_data.items():
                cat = mdata["category"]
                meta = MERCHANT_METADATA.get(
                    mid,
                    {"name": f"Commerçant {mid}", "wilaya": "Alger", "commune": "Centre"},
                )

                # Find existing merchant with this code if any
                merchant = Merchant.objects.filter(merchant_code=mid).first()

                if not merchant:
                    # Create dedicated user
                    email = f"{mid.lower().replace('-', '')}@merchantpay.dz"
                    user, _ = User.objects.get_or_create(
                        email=email,
                        defaults={
                            "full_name": meta["name"],
                            "role": UserRole.MERCHANT,
                            "is_active": True,
                        },
                    )
                    if not user.check_password("Demo@2026"):
                        user.set_password("Demo@2026")
                        user.save()

                    # If this user already had a merchant (e.g. from previous run)
                    if hasattr(user, "merchant"):
                        merchant = user.merchant
                        merchant.merchant_code = mid
                        merchant.business_name = meta["name"]
                        merchant.merchant_category = cat
                        merchant.wilaya = meta["wilaya"]
                        merchant.address = f"{meta['commune']}, {meta['wilaya']}"
                        merchant.save()
                    else:
                        merchant = Merchant.objects.create(
                            owner=user,
                            merchant_code=mid,
                            business_name=meta["name"],
                            merchant_category=cat,
                            wilaya=meta["wilaya"],
                            address=f"{meta['commune']}, {meta['wilaya']}",
                            phone=f"+213 550 {mid.split('-')[1]}",
                            email=email,
                            registration_number=f"RC-2026-{mid}",
                            terminal_count=2,
                            monthly_goal=Decimal("350000.00"),
                            status=MerchantStatus.ACTIVE,
                        )
                else:
                    merchant.business_name = meta["name"]
                    merchant.merchant_category = cat
                    merchant.wilaya = meta["wilaya"]
                    merchant.save()

                created_merchants[mid] = merchant

            # 2. Ingest Transactions
            created_tx_cnt = 0
            for r in rows:
                mid = r["merchant_id"]
                merchant = created_merchants[mid]
                raw_dt = datetime.strptime(r["transaction_date"], "%Y-%m-%d %H:%M:%S")
                tx_date = raw_dt.replace(tzinfo=ALGIERS_TZ)
                amount = Decimal(r["amount"])
                status = r["transaction_status"]
                channel = r["payment_channel"]
                category = r["merchant_category"]

                refunded_amt = amount if status == "Refunded" else None
                rejection_reason = "Refus bancaire" if status == "Declined" else None

                Transaction.objects.update_or_create(
                    reference=r["transaction_id"],
                    defaults={
                        "merchant": merchant,
                        "transaction_date": tx_date,
                        "amount": amount,
                        "payment_channel": channel,
                        "transaction_status": status,
                        "merchant_category": category,
                        "terminal_id": f"TPE-{mid}",
                        "card_last4": r["transaction_id"][-4:],
                        "refunded_amount": refunded_amt,
                        "rejection_reason": rejection_reason,
                    },
                )
                created_tx_cnt += 1

            self.stdout.write(self.style.SUCCESS(f"Successfully ingested {created_tx_cnt} transactions into database."))

            # 3. Evaluate Alerts & Risk for these merchants
            alerts_cnt = 0
            for merchant in created_merchants.values():
                created = evaluate_merchant_alerts(merchant)
                alerts_cnt += len(created)
                scan_merchant_risk(merchant)

            self.stdout.write(f"Evaluated alerts ({alerts_cnt} generated) and risk heuristic scans.")

        # 4. Print the exact official breakdown tables requested by the prompt
        all_official_txs = Transaction.objects.filter(reference__startswith="TXN-")
        summary = compute_payment_transactions_summary(all_official_txs)

        self.stdout.write("\n" + "=" * 70)
        self.stdout.write(self.style.SUCCESS("Payment Transactions Summary Dashboard (DZD)"))
        self.stdout.write("=" * 70)

        self.stdout.write("\n1. Breakdown by Transaction Status")
        self.stdout.write(f"{'Transaction Status':<22} | {'Count':<8} | {'% Total':<8} | {'Total Amount (DA)':<18} | {'Average Amount (DA)':<20}")
        self.stdout.write("-" * 88)
        for row in summary["breakdown_by_status"]["rows"]:
            self.stdout.write(
                f"{row['status']:<22} | {row['count']:<8} | {row['pct_of_total']:<7.2f}% | {row['total_amount']:<18.2f} | {row['avg_amount']:<20.2f}"
            )
        tot_s = summary["breakdown_by_status"]["total"]
        self.stdout.write("-" * 88)
        self.stdout.write(
            f"{tot_s['status']:<22} | {tot_s['count']:<8} | {tot_s['pct_of_total']:<7.2f}% | {tot_s['total_amount']:<18.2f} | {tot_s['avg_amount']:<20.2f}"
        )

        self.stdout.write("\n2. Breakdown by Payment Channel")
        self.stdout.write(f"{'Payment Channel':<30} | {'Count':<8} | {'% Total':<8} | {'Total Amount (DA)':<18} | {'Average Amount (DA)':<20}")
        self.stdout.write("-" * 96)
        for row in summary["breakdown_by_channel"]["rows"]:
            self.stdout.write(
                f"{row['channel']:<30} | {row['count']:<8} | {row['pct_of_total']:<7.2f}% | {row['total_amount']:<18.2f} | {row['avg_amount']:<20.2f}"
            )
        tot_c = summary["breakdown_by_channel"]["total"]
        self.stdout.write("-" * 96)
        self.stdout.write(
            f"{tot_c['channel']:<30} | {tot_c['count']:<8} | {tot_c['pct_of_total']:<7.2f}% | {tot_c['total_amount']:<18.2f} | {tot_c['avg_amount']:<20.2f}"
        )
        self.stdout.write("=" * 70 + "\n")
