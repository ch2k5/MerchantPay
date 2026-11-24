import random
import uuid
from datetime import datetime, time, timedelta
from decimal import Decimal

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import User
from apps.alerts.services import evaluate_merchant_alerts
from apps.analytics.services import compute_payment_transactions_summary
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    AdminLevel,
    MerchantCategory,
    MerchantStatus,
    PaymentChannel,
    RejectionReason,
    RiskLevel,
    RiskStatus,
    TransactionStatus,
    UserRole,
)
from apps.merchants.models import Merchant
from apps.risk.models import InvestigationNote, RiskFlag
from apps.risk.services import scan_merchant_risk
from apps.transactions.models import Transaction


class Command(BaseCommand):
    help = "Generates rich multi-period synthetic demo data (3500+ transactions over 90 days) for SATIM & Merchants."

    def add_arguments(self, parser):
        parser.add_argument("--count", type=int, default=3000, help="Number of additional transactions to generate")
        parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility")

    def handle(self, *args, **options):
        # 1. Run ingest_payment_dataset first to ensure 150 official transactions and 30 merchants exist
        self.stdout.write(self.style.NOTICE("Étape 1 : Vérification de la base officielle (150 transactions, 30 commerçants)..."))
        call_command("ingest_payment_dataset")

        count_to_generate = options["count"]
        seed_val = options["seed"]
        random.seed(seed_val)

        self.stdout.write(self.style.NOTICE(f"Étape 2 : Génération de {count_to_generate} transactions sur les 90 derniers jours (Seed: {seed_val})..."))

        merchants = list(Merchant.objects.all())
        if not merchants:
            self.stdout.write(self.style.ERROR("Aucun commerçant trouvé."))
            return

        now = timezone.now().astimezone(ALGIERS_TZ)
        today = now.date()
        start_date = today - timedelta(days=90)

        channels_weights = [
            ("E-commerce (CIB / Edahabia)", 33),
            ("TPE / POS Terminal", 33),
            ("Mobile App", 20),
            ("Contactless / NFC", 9),
            ("Bank Transfer / Virement", 5),
        ]
        channels_choices, channels_probs = zip(*channels_weights)

        statuses_weights = [
            ("Accepted", 70),
            ("Declined", 12),
            ("Refunded", 9),
            ("Cancelled", 9),
        ]
        status_choices, status_probs = zip(*statuses_weights)

        rejection_reasons = [
            "Solde insuffisant",
            "Plafond de paiement dépassé",
            "Code PIN erroné (3 tentatives)",
            "Carte expirée",
            "Time-out réseau SATIM",
            "Transaction suspecte bloquée par émetteur",
            "Carte mise en opposition",
        ]

        tx_to_create = []
        batch_size = 500
        total_created = 0

        # Merchant weights: give demo merchant (Algérie Télécom - MER-3615) higher activity
        demo_merchant = Merchant.objects.filter(merchant_code="MER-3615").first()

        for i in range(count_to_generate):
            # Pick merchant
            if demo_merchant and random.random() < 0.15:
                merchant = demo_merchant
            else:
                merchant = random.choice(merchants)

            # Date distribution: slightly more transactions in recent days
            days_ago = int(random.triangular(0, 90, 10))
            tx_date = today - timedelta(days=days_ago)

            # Hour distribution: peaks at 12h-14h and 17h-20h, low nights
            hour_weights = [
                1, 1, 1, 1, 1, 2, 4, 8, 15, 20, 25, 30,
                35, 30, 22, 20, 25, 35, 32, 28, 20, 12, 6, 2
            ]
            hour = random.choices(range(24), weights=hour_weights)[0]
            minute = random.randint(0, 59)
            second = random.randint(0, 59)

            tx_datetime = datetime.combine(tx_date, time(hour, minute, second), tzinfo=ALGIERS_TZ)

            # Payment channel
            channel = random.choices(channels_choices, weights=channels_probs)[0]

            # Status
            status = random.choices(status_choices, weights=status_probs)[0]

            # Amount by category
            cat_str = str(merchant.merchant_category).lower()
            if "super" in cat_str or "alim" in cat_str or "retail" in cat_str:
                amt_raw = random.uniform(800, 12000)
            elif "rest" in cat_str or "food" in cat_str or "caf" in cat_str:
                amt_raw = random.uniform(400, 4500)
            elif "electr" in cat_str or "tech" in cat_str:
                amt_raw = random.uniform(5000, 65000)
            elif "habil" in cat_str or "mode" in cat_str or "apparel" in cat_str:
                amt_raw = random.uniform(2500, 22000)
            elif "sant" in cat_str or "pharm" in cat_str or "health" in cat_str:
                amt_raw = random.uniform(600, 7500)
            elif "voyag" in cat_str or "tour" in cat_str or "travel" in cat_str:
                amt_raw = random.uniform(15000, 85000)
            else:
                amt_raw = random.uniform(1000, 15000)

            amount = Decimal(str(round(amt_raw, 2)))

            rejection_reason = None
            refunded_amount = None

            if status == "Declined":
                rejection_reason = random.choice(rejection_reasons)
            elif status == "Refunded":
                refunded_amount = amount
            elif status == "Cancelled":
                rejection_reason = "Annulation demandée par le client avant compensation"

            ref_num = f"TXN-{tx_date.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
            card_last4 = f"{random.randint(1000, 9999)}"
            terminal_id = f"TPE-{random.randint(100, 999)}"

            tx = Transaction(
                reference=ref_num,
                merchant=merchant,
                transaction_date=tx_datetime,
                amount=amount,
                payment_channel=channel,
                transaction_status=status,
                merchant_category=merchant.merchant_category,
                rejection_reason=rejection_reason,
                card_last4=card_last4,
                terminal_id=terminal_id,
                refunded_amount=refunded_amount,
            )
            tx_to_create.append(tx)
            total_created += 1

            if len(tx_to_create) >= batch_size:
                Transaction.objects.bulk_create(tx_to_create)
                tx_to_create = []

        if tx_to_create:
            Transaction.objects.bulk_create(tx_to_create)

        self.stdout.write(self.style.SUCCESS(f"{total_created} transactions supplémentaires insérées."))

        # 3. Inject Specific Anomalous / Fraud scenarios for demo
        self.stdout.write(self.style.NOTICE("Étape 3 : Injection de scénarios de risque & fraude (fraude vélocité, rejets massifs)..."))

        # Scenario A: Velocity fraud burst on TechZone (MER-5506)
        tech_zone = Merchant.objects.filter(merchant_code="MER-5506").first()
        if tech_zone:
            burst_time = now - timedelta(days=2, hours=3)
            for j in range(8):
                Transaction.objects.create(
                    reference=f"TXN-FRAUD-{uuid.uuid4().hex[:8].upper()}",
                    merchant=tech_zone,
                    transaction_date=burst_time + timedelta(minutes=j * 2),
                    amount=Decimal("49900.00"),
                    payment_channel="E-commerce (CIB / Edahabia)",
                    transaction_status="Accepted" if j == 0 else "Declined",
                    rejection_reason="Plafond de paiement dépassé" if j > 0 else None,
                    card_last4="7788",
                    terminal_id="WEB-GATEWAY-01",
                    merchant_category=tech_zone.merchant_category,
                )

        # Scenario B: High rejection spike on Djezzy Pro Center (MER-4811)
        djezzy = Merchant.objects.filter(merchant_code="MER-4811").first()
        if djezzy:
            spike_time = now - timedelta(days=1, hours=6)
            for k in range(12):
                Transaction.objects.create(
                    reference=f"TXN-SPIKE-{uuid.uuid4().hex[:8].upper()}",
                    merchant=djezzy,
                    transaction_date=spike_time + timedelta(minutes=k * 3),
                    amount=Decimal("15000.00"),
                    payment_channel="TPE / POS Terminal",
                    transaction_status="Declined",
                    rejection_reason="Code PIN erroné (3 tentatives)",
                    card_last4=f"{random.randint(1000, 9999)}",
                    terminal_id="TPE-DJZ-99",
                    merchant_category=djezzy.merchant_category,
                )

        # 4. Evaluate alerts and risk heuristics for all merchants
        self.stdout.write(self.style.NOTICE("Étape 4 : Détection automatique des alertes et scores de risque..."))
        total_alerts = 0
        total_flags = 0

        for m in Merchant.objects.all():
            try:
                alerts = evaluate_merchant_alerts(m)
                total_alerts += len(alerts)
            except Exception:
                pass
            try:
                flags = scan_merchant_risk(m)
                total_flags += len(flags)
            except Exception:
                pass

        # Ensure an analyst user exists to add realistic investigation notes
        analyst = User.objects.filter(email="analyste@satim.dz").first()
        if not analyst:
            analyst = User.objects.create_user(
                email="analyste@satim.dz",
                password="Admin2026!",
                full_name="Amine Analyste Fraude",
                role=UserRole.ADMIN,
                admin_level=AdminLevel.ANALYST,
            )

        # Add notes to high risk flags
        high_flags = RiskFlag.objects.filter(risk_level=RiskLevel.HIGH)
        for hf in high_flags[:5]:
            hf.assigned_to = analyst
            hf.status = RiskStatus.UNDER_INVESTIGATION
            hf.save()
            InvestigationNote.objects.get_or_create(
                risk_flag=hf,
                author=analyst,
                defaults={"text": "Dossier pris en charge. Vérification des logs SATIM et contact initié avec la banque émettrice."},
            )

        if RiskFlag.objects.count() == 0 and tech_zone:
            rf1 = RiskFlag.objects.create(
                merchant=tech_zone,
                risk_score=85,
                risk_level=RiskLevel.HIGH,
                status=RiskStatus.UNDER_INVESTIGATION,
                reasons=[
                    "Vélocité anormale : 8 tentatives consécutives en 15 minutes",
                    "Montants proches du plafond légal (49 900 DA)",
                    "Cartes multiples depuis la même IP passerelle",
                ],
                triggered_rules=[
                    {"code": "VELOCITY_BURST", "label_fr": "Rafale de transactions rapprochées", "score": 45},
                    {"code": "HIGH_AMOUNT_SPIKE", "label_fr": "Montants atypiques élevés", "score": 40},
                ],
            )
            InvestigationNote.objects.create(
                risk_flag=rf1,
                author=analyst,
                text="Alerte prioritaire. Suspension préventive du terminal virtuel et demande de justificatifs au commerçant.",
            )

        if djezzy and RiskFlag.objects.filter(merchant=djezzy).count() == 0:
            rf2 = RiskFlag.objects.create(
                merchant=djezzy,
                risk_score=65,
                risk_level=RiskLevel.MEDIUM,
                status=RiskStatus.NEW,
                reasons=[
                    "Pic soudain de rejets : 12 rejets consécutifs (PIN erroné)",
                    "Taux de rejet sur 24h supérieur à 35%",
                ],
                triggered_rules=[
                    {"code": "REJECTION_BURST", "label_fr": "Série anormale de rejets de paiement", "score": 35},
                    {"code": "PIN_FAIL_THRESHOLD", "label_fr": "Tentatives répétées de code erroné", "score": 30},
                ],
            )

        total_tx = Transaction.objects.count()
        total_flags = RiskFlag.objects.count()
        self.stdout.write(self.style.SUCCESS(f"\n========================================================"))
        self.stdout.write(self.style.SUCCESS(f"JEU DE DONNÉES DE DÉMONSTRATION GÉNÉRÉ AVEC SUCCÈS !"))
        self.stdout.write(self.style.SUCCESS(f"• Total Transactions : {total_tx}"))
        self.stdout.write(self.style.SUCCESS(f"• Commerçants Actifs : {Merchant.objects.filter(status=MerchantStatus.ACTIVE).count()}"))
        self.stdout.write(self.style.SUCCESS(f"• Alertes Commerçants : {total_alerts}"))
        self.stdout.write(self.style.SUCCESS(f"• Signalements de Risque : {total_flags}"))
        self.stdout.write(self.style.SUCCESS(f"========================================================\n"))
