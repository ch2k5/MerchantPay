import csv
import os
import random
import uuid
from datetime import datetime, time, timedelta
from datetime import timezone as dt_timezone
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import User
from apps.alerts.services import evaluate_all_active_merchants
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    AdminLevel,
    MerchantCategory,
    MerchantStatus,
    PaymentChannel,
    RejectionReason,
    TransactionStatus,
    UserRole,
)
from apps.merchants.models import Merchant
from apps.risk.services import scan_all_merchants_risk
from apps.transactions.models import Transaction


class Command(BaseCommand):
    help = "Seed deterministic demo dataset (~60k transactions, 12 merchants, injected scenarios, CSV export)"

    def add_arguments(self, parser):
        parser.add_argument("--seed", type=int, default=42, help="Random seed for deterministic generation")
        parser.add_argument("--fast", action="store_true", help="Generate a smaller set (~6k) for fast testing")

    def handle(self, *args, **options):
        seed_val = options["seed"]
        random.seed(seed_val)
        is_fast = options["fast"]
        self.stdout.write(self.style.NOTICE(f"Initialisation du seeding (Seed: {seed_val}, Fast: {is_fast})..."))

        now = timezone.now().astimezone(ALGIERS_TZ)
        today = now.date()

        # Clear existing data safely
        Transaction.objects.all().delete()
        Merchant.objects.all().delete()
        User.objects.all().delete()

        # 1. Create Admins
        super_admin = User.objects.create_superuser(
            email="admin@satim.dz",
            password="Admin@2026",
            full_name="Directeur Système SATIM",
        )
        analyst = User.objects.create_user(
            email="analyste@satim.dz",
            password="Admin@2026",
            full_name="Amine Analyste Fraude",
            role=UserRole.ADMIN,
            admin_level=AdminLevel.ANALYST,
        )
        viewer = User.objects.create_user(
            email="viewer@satim.dz",
            password="Admin@2026",
            full_name="Samir Observateur",
            role=UserRole.ADMIN,
            admin_level=AdminLevel.VIEWER,
        )
        self.stdout.write(self.style.SUCCESS("Administrateurs SATIM créés."))

        # 2. Merchants definitions (12 merchants across 8 categories, 6 wilayas)
        merchants_specs = [
            # 0: Primary Demo Merchant
            {
                "email": "demo@merchantpay.dz",
                "name": "Café El Bahdja",
                "category": MerchantCategory.RESTAURATION,
                "wilaya": "Alger",
                "address": "14 Rue Didouche Mourad, Alger-Centre",
                "phone": "+213 21 63 12 45",
                "rc": "16/00-0982341B22",
                "terminals": 2,
                "monthly_goal": Decimal("1800000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 300,
                "max_amt": 1500,
            },
            # 1: Inactive Merchant (NO_ACTIVITY >= 5 days)
            {
                "email": "inactif@merchantpay.dz",
                "name": "Boutique L'Élégance",
                "category": MerchantCategory.HABILLEMENT,
                "wilaya": "Oran",
                "address": "Boulevard de la Soummam, Oran",
                "phone": "+213 41 33 55 77",
                "rc": "31/00-0112453B21",
                "terminals": 1,
                "monthly_goal": Decimal("900000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 4000,
                "max_amt": 25000,
            },
            # 2: Fraud Burst Merchant (High Velocity + High Amount)
            {
                "email": "electronique@merchantpay.dz",
                "name": "TechZone Algérie",
                "category": MerchantCategory.COMMERCE_DETAIL,
                "wilaya": "Sétif",
                "address": "Avenue 8 Mai 1945, Sétif",
                "phone": "+213 36 84 90 12",
                "rc": "19/00-0543211B20",
                "terminals": 3,
                "monthly_goal": Decimal("4500000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 1200,
                "max_amt": 5200,
            },
            # 3: Pharmacy
            {
                "email": "pharmacie.centrale@merchantpay.dz",
                "name": "Pharmacie Centrale Ibn Sina",
                "category": MerchantCategory.PHARMACIE,
                "wilaya": "Constantine",
                "address": "Place des Martyrs, Constantine",
                "phone": "+213 31 92 44 11",
                "rc": "25/00-0876543A21",
                "terminals": 2,
                "monthly_goal": Decimal("2200000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 800,
                "max_amt": 12000,
            },
            # 4: Supermarket
            {
                "email": "superette.mitidja@merchantpay.dz",
                "name": "Supermarché Mitidja Frais",
                "category": MerchantCategory.ALIMENTATION,
                "wilaya": "Blida",
                "address": "Boulevard Larbi Tebessi, Blida",
                "phone": "+213 25 31 18 90",
                "rc": "09/00-0456123B23",
                "terminals": 4,
                "monthly_goal": Decimal("5000000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 1200,
                "max_amt": 35000,
            },
            # 5: Hotel
            {
                "email": "hotel.tipaza@merchantpay.dz",
                "name": "Hôtel Les Ruines Bleues",
                "category": MerchantCategory.HOTELLERIE,
                "wilaya": "Tipaza",
                "address": "Route Côtière Ouest, Tipaza",
                "phone": "+213 24 47 01 22",
                "rc": "42/00-0321456B19",
                "terminals": 3,
                "monthly_goal": Decimal("6500000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 18000,
                "max_amt": 95000,
            },
            # 6: Fuel station
            {
                "email": "station.reghaia@merchantpay.dz",
                "name": "Relais Autoroutier Sahel",
                "category": MerchantCategory.CARBURANT,
                "wilaya": "Alger",
                "address": "RN5 Sortie Réghaïa, Alger",
                "phone": "+213 23 85 14 30",
                "rc": "16/00-0765984B22",
                "terminals": 5,
                "monthly_goal": Decimal("3800000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 1500,
                "max_amt": 14000,
            },
            # 7: Retail
            {
                "email": "librairie.diwan@merchantpay.dz",
                "name": "Librairie Moderne Diwan",
                "category": MerchantCategory.COMMERCE_DETAIL,
                "wilaya": "Alger",
                "address": "Rue Hassiba Ben Bouali, Alger",
                "phone": "+213 21 74 19 82",
                "rc": "16/00-0234567B23",
                "terminals": 2,
                "monthly_goal": Decimal("1100000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 900,
                "max_amt": 8500,
            },
            # 8: Services
            {
                "email": "autocare.oran@merchantpay.dz",
                "name": "Centre Auto Services Express",
                "category": MerchantCategory.SERVICES,
                "wilaya": "Oran",
                "address": "Zone Industrielle Es Sénia, Oran",
                "phone": "+213 41 58 72 00",
                "rc": "31/00-0987123B21",
                "terminals": 2,
                "monthly_goal": Decimal("2400000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 5000,
                "max_amt": 45000,
            },
            # 9: Bakery
            {
                "email": "boulangerie.elassima@merchantpay.dz",
                "name": "Pâtisserie Royale El Assima",
                "category": MerchantCategory.ALIMENTATION,
                "wilaya": "Alger",
                "address": "Kouba Centre, Alger",
                "phone": "+213 23 78 40 15",
                "rc": "16/00-0345678B24",
                "terminals": 1,
                "monthly_goal": Decimal("1300000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 400,
                "max_amt": 3800,
            },
            # 10: Optical store
            {
                "email": "optique.numidie@merchantpay.dz",
                "name": "Optique Médicale Numidie",
                "category": MerchantCategory.COMMERCE_DETAIL,
                "wilaya": "Constantine",
                "address": "Cité Sidi Mabrouk, Constantine",
                "phone": "+213 31 66 12 90",
                "rc": "25/00-0456789B20",
                "terminals": 1,
                "monthly_goal": Decimal("1600000.00"),
                "status": MerchantStatus.ACTIVE,
                "min_amt": 6000,
                "max_amt": 50000,
            },
            # 11: Deactivated Merchant for admin demo
            {
                "email": "desactive@merchantpay.dz",
                "name": "Bazar Bab Ezzouar",
                "category": MerchantCategory.AUTRE,
                "wilaya": "Alger",
                "address": "Cité 5 Juillet, Bab Ezzouar",
                "phone": "+213 23 92 11 00",
                "rc": "16/00-0891234B22",
                "terminals": 1,
                "monthly_goal": Decimal("800000.00"),
                "status": MerchantStatus.INACTIVE,
                "min_amt": 1000,
                "max_amt": 15000,
            },
        ]

        created_merchants = []
        for i, spec in enumerate(merchants_specs):
            user = User.objects.create_user(
                email=spec["email"],
                password="Demo@2026",
                full_name=f"Propriétaire {spec['name']}",
                role=UserRole.MERCHANT,
                is_active=(spec["status"] == MerchantStatus.ACTIVE),
            )
            merchant = Merchant.objects.create(
                owner=user,
                merchant_code=f"MRC-{i + 1:04d}",
                business_name=spec["name"],
                merchant_category=spec["category"],
                wilaya=spec["wilaya"],
                address=spec["address"],
                phone=spec["phone"],
                email=spec["email"],
                registration_number=spec["rc"],
                terminal_count=spec["terminals"],
                monthly_goal=spec["monthly_goal"],
                status=spec["status"],
            )
            created_merchants.append((merchant, spec))

        self.stdout.write(self.style.SUCCESS("12 commerçants créés avec succès."))

        # 3. Generate Historical Transactions (~6 months)
        # 180 days history
        total_days = 180
        start_date = today - timedelta(days=total_days)

        rejection_reasons_pool = [
            (RejectionReason.SOLDE_INSUFFISANT, 0.40),
            (RejectionReason.CODE_PIN_ERRONE, 0.25),
            (RejectionReason.PLAFOND_DEPASSE, 0.15),
            (RejectionReason.CARTE_EXPIREE, 0.10),
            (RejectionReason.REFUS_EMETTEUR, 0.06),
            (RejectionReason.ERREUR_TECHNIQUE, 0.04),
        ]
        reasons, reason_weights = zip(*rejection_reasons_pool)

        # Batch buffer for fast inserts
        tx_batch = []
        csv_rows = []
        tx_counter = 1

        self.stdout.write("Génération des transactions réalistes...")

        # Base count per merchant per day
        base_tx_per_day = 3 if is_fast else 28

        for m_idx, (merchant, spec) in enumerate(created_merchants):
            # Skip historical transactions for merchant 11 (inactive with very few txs)
            if m_idx == 11:
                days_range = 10
            else:
                days_range = total_days

            for day_offset in range(days_range):
                curr_d = start_date + timedelta(days=day_offset)
                days_ago = (today - curr_d).days

                # Merchant 1: Inactive for last 6 days
                if m_idx == 1 and days_ago <= 6:
                    continue

                # Multipliers: Lunch & evening peak, weekend (Fri/Sat)
                is_weekend = curr_d.weekday() in [4, 5]  # Friday/Saturday
                daily_volume = int(base_tx_per_day * (1.35 if is_weekend else 1.0))

                # Inject Scenario 1 for Demo Merchant (`Café El Bahdja`, m_idx == 0):
                # - Revenue drop of ~20% in the last 7 days vs previous 7 days
                # - Rejection spike in last 3 days
                if m_idx == 0:
                    if days_ago <= 6:
                        # Current 7 days: decrease volume & ticket by 20%
                        daily_volume = int(daily_volume * 0.78)
                    elif 7 <= days_ago <= 13:
                        # Previous 7 days: slightly higher volume
                        daily_volume = int(daily_volume * 1.15)

                for _ in range(daily_volume):
                    # Time weighting: strong lunch peak 12h-14h and evening 18h-21h
                    r_hour = random.random()
                    if r_hour < 0.45:
                        h = random.choice([12, 13])  # Lunch peak
                    elif r_hour < 0.75:
                        h = random.choice([18, 19, 20])  # Evening
                    elif r_hour < 0.90:
                        h = random.choice([9, 10, 11])
                    else:
                        h = random.choice([14, 15, 16, 17, 21])

                    m = random.randint(0, 59)
                    s = random.randint(0, 59)
                    tx_time = time(h, m, s)
                    tx_datetime = datetime.combine(curr_d, tx_time, tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)

                    # Amount calculation
                    min_a = spec["min_amt"]
                    max_a = spec["max_amt"]
                    if m_idx == 0 and days_ago <= 6:
                        # Reduced average ticket for drop
                        amt_val = round(random.uniform(min_a, max_a * 0.8), 2)
                    else:
                        amt_val = round(random.uniform(min_a, max_a), 2)
                    amt = Decimal(f"{amt_val:.2f}")

                    # Payment channel: CIB ≈ 65%, EDAHABIA ≈ 35%
                    ch = PaymentChannel.CIB if random.random() < 0.65 else PaymentChannel.EDAHABIA

                    # Status: ~92% ACCEPTED, ~5% REJECTED, ~2% CANCELLED, ~1% REFUNDED
                    # For demo merchant, inject rejection spike in last 3 days (e.g. 25% rejection rate)
                    if m_idx == 0 and days_ago <= 3:
                        r_status = random.random()
                        if r_status < 0.28:
                            st = TransactionStatus.REJECTED
                        elif r_status < 0.96:
                            st = TransactionStatus.ACCEPTED
                        elif r_status < 0.98:
                            st = TransactionStatus.CANCELLED
                        else:
                            st = TransactionStatus.REFUNDED
                    else:
                        r_status = random.random()
                        if r_status < 0.92:
                            st = TransactionStatus.ACCEPTED
                        elif r_status < 0.97:
                            st = TransactionStatus.REJECTED
                        elif r_status < 0.99:
                            st = TransactionStatus.CANCELLED
                        else:
                            st = TransactionStatus.REFUNDED

                    rej_reason = None
                    if st == TransactionStatus.REJECTED:
                        rej_reason = random.choices(reasons, weights=reason_weights)[0]

                    ref_amt = None
                    if st == TransactionStatus.REFUNDED:
                        ref_amt = amt

                    card_last4 = f"{random.randint(1000, 9999)}"
                    terminal_id = f"TPE-{random.randint(1, spec['terminals']):02d}"
                    ref = f"TX-{curr_d.strftime('%Y%m%d')}-{tx_counter:06d}"
                    t_id = uuid.uuid4()

                    tx_obj = Transaction(
                        transaction_id=t_id,
                        reference=ref,
                        merchant=merchant,
                        transaction_date=tx_datetime,
                        amount=amt,
                        payment_channel=ch,
                        transaction_status=st,
                        merchant_category=spec["category"],
                        rejection_reason=rej_reason,
                        card_last4=card_last4,
                        terminal_id=terminal_id,
                        refunded_amount=ref_amt,
                    )
                    tx_batch.append(tx_obj)

                    csv_rows.append(
                        [
                            str(t_id),
                            merchant.merchant_code,
                            tx_datetime.strftime("%Y-%m-%d %H:%M:%S"),
                            f"{amt:.2f}",
                            ch,
                            st,
                            spec["category"],
                            rej_reason or "",
                            card_last4,
                            terminal_id,
                            f"{ref_amt:.2f}" if ref_amt else "",
                        ]
                    )

                    tx_counter += 1

                    if len(tx_batch) >= 5000:
                        Transaction.objects.bulk_create(tx_batch)
                        tx_batch = []

        # 4. Inject Fraud Burst Scenario (Merchant 2: TechZone Algérie)
        # Scenario: 12 transactions in 2 minutes at 48 000 DZD
        # Occurring 15 minutes ago
        self.stdout.write("Injection du scénario de risque / rafale de fraude...")
        burst_merchant, _ = created_merchants[2]
        burst_base_time = now - timedelta(minutes=25)
        burst_card = "7821"

        for b_i in range(12):
            burst_dt = (burst_base_time + timedelta(seconds=b_i * 9)).astimezone(dt_timezone.utc)
            t_id = uuid.uuid4()
            amt = Decimal("48000.00")
            ref = f"TX-{today.strftime('%Y%m%d')}-BURST{b_i + 1:02d}"
            tx_obj = Transaction(
                transaction_id=t_id,
                reference=ref,
                merchant=burst_merchant,
                transaction_date=burst_dt,
                amount=amt,
                payment_channel=PaymentChannel.EDAHABIA,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=MerchantCategory.ELECTRONIQUE,
                rejection_reason=None,
                card_last4=burst_card,
                terminal_id="TPE-01",
                refunded_amount=None,
            )
            tx_batch.append(tx_obj)
            csv_rows.append(
                [
                    str(t_id),
                    burst_merchant.merchant_code,
                    burst_dt.strftime("%Y-%m-%d %H:%M:%S"),
                    "48000.00",
                    PaymentChannel.EDAHABIA,
                    TransactionStatus.ACCEPTED,
                    MerchantCategory.ELECTRONIQUE,
                    "",
                    burst_card,
                    "TPE-01",
                    "",
                ]
            )

        # Flush remaining transactions
        if tx_batch:
            Transaction.objects.bulk_create(tx_batch)

        # 4b. Inject 2 Minor Medium Risk Scenarios
        # Minor flag 1: Pharmacy - High amount transaction
        pharmacy_m, _ = created_merchants[3]
        t_id1 = uuid.uuid4()
        ref1 = f"TX-{today.strftime('%Y%m%d')}-MED01"
        Transaction.objects.create(
            transaction_id=t_id1,
            reference=ref1,
            merchant=pharmacy_m,
            transaction_date=now - timedelta(minutes=40),
            amount=Decimal("38500.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=MerchantCategory.PHARMACIE,
            card_last4="4412",
            terminal_id="TPE-01",
        )

        # Minor flag 2: Supermarket - Rejection burst in last hour
        supermarket_m, _ = created_merchants[4]
        for s_i in range(7):
            t_id2 = uuid.uuid4()
            ref2 = f"TX-{today.strftime('%Y%m%d')}-REJ{s_i + 1:02d}"
            Transaction.objects.create(
                transaction_id=t_id2,
                reference=ref2,
                merchant=supermarket_m,
                transaction_date=now - timedelta(minutes=20 - s_i * 2),
                amount=Decimal("78000.00"),
                payment_channel=PaymentChannel.EDAHABIA,
                transaction_status=TransactionStatus.REJECTED,
                rejection_reason=RejectionReason.PLAFOND_DEPASSE,
                merchant_category=MerchantCategory.ALIMENTATION,
                card_last4="9014",
                terminal_id="TPE-02",
            )

        total_tx_created = Transaction.objects.count()
        self.stdout.write(self.style.SUCCESS(f"Total transactions insérées : {total_tx_created}."))

        # 5. Export Deliverable: data/transactions_seed.csv
        data_dir = os.path.join(settings.BASE_DIR.parent, "data")
        os.makedirs(data_dir, exist_ok=True)
        csv_path = os.path.join(data_dir, "transactions_seed.csv")

        self.stdout.write(f"Exportation du fichier {csv_path}...")
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "transaction_id",
                    "merchant_id",
                    "transaction_date",
                    "amount",
                    "payment_channel",
                    "transaction_status",
                    "merchant_category",
                    "rejection_reason",
                    "card_last4",
                    "terminal_id",
                    "refunded_amount",
                ]
            )
            writer.writerows(csv_rows)

        self.stdout.write(self.style.SUCCESS(f"Fichier CSV exporté avec succès ({len(csv_rows)} lignes)."))

        # 6. Automatic Evaluation of Alerts and Risk Scan
        self.stdout.write("Exécution automatique du moteur d'alertes commerçants...")
        alerts_count = evaluate_all_active_merchants(now=now)
        self.stdout.write(self.style.SUCCESS(f"{alerts_count} alertes évaluées et générées."))

        self.stdout.write("Exécution automatique du moteur de risque et détection de fraude...")
        flags_count = scan_all_merchants_risk(now=now)
        self.stdout.write(self.style.SUCCESS(f"{flags_count} signalements de risque générés."))

        self.stdout.write(self.style.SUCCESS("=== SEEDING TERMINÉ AVEC SUCCÈS ==="))
