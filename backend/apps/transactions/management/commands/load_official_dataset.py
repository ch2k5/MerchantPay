import csv
import os
import random
import uuid
from datetime import datetime
from datetime import timezone as dt_timezone
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import User
from apps.alerts.models import MerchantAlert
from apps.alerts.services import evaluate_all_active_merchants
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
from apps.transactions.models import Transaction


class Command(BaseCommand):
    help = "Charge le jeu de données officiel FINOVIA × ENSM × SATIM (150 transactions, 30 commerçants) depuis le fichier CSV."

    def add_arguments(self, parser):
        parser.add_argument(
            "--csv-path",
            type=str,
            default=os.path.join(settings.BASE_DIR.parent, "data", "payment_transactions_dataset.csv"),
            help="Chemin vers le fichier CSV officiel",
        )

    def handle(self, *args, **options):
        csv_path = options["csv_path"]
        if not os.path.exists(csv_path):
            self.stdout.write(self.style.ERROR(f"Fichier introuvable : {csv_path}"))
            return

        self.stdout.write(self.style.NOTICE(f"Chargement du jeu de données officiel depuis {csv_path}..."))

        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        if not rows:
            self.stdout.write(self.style.ERROR("Aucune transaction trouvée dans le CSV."))
            return

        self.stdout.write(f"{len(rows)} transactions lues depuis le fichier CSV.")

        # Nettoyage sécurisé des transactions, alertes et risques
        InvestigationNote.objects.all().delete()
        RiskFlag.objects.all().delete()
        MerchantAlert.objects.all().delete()
        Transaction.objects.all().delete()

        # 1. Comptes Administrateurs SATIM
        admin, _ = User.objects.get_or_create(
            email="admin@satim.dz",
            defaults={
                "full_name": "Directeur Système SATIM",
                "role": UserRole.ADMIN,
                "admin_level": AdminLevel.SUPER_ADMIN,
                "is_staff": True,
                "is_superuser": True,
            },
        )
        admin.set_password("Admin@2026")
        admin.save()

        analyst, _ = User.objects.get_or_create(
            email="analyste@satim.dz",
            defaults={
                "full_name": "Amine Analyste Fraude",
                "role": UserRole.ADMIN,
                "admin_level": AdminLevel.ANALYST,
                "is_staff": False,
            },
        )
        analyst.set_password("Admin@2026")
        analyst.save()

        viewer, _ = User.objects.get_or_create(
            email="viewer@satim.dz",
            defaults={
                "full_name": "Samir Observateur",
                "role": UserRole.ADMIN,
                "admin_level": AdminLevel.VIEWER,
                "is_staff": False,
            },
        )
        viewer.set_password("Admin@2026")
        viewer.save()
        self.stdout.write(self.style.SUCCESS("Administrateurs SATIM configurés."))

        # 2. Commerçants officiels du dataset (30 commerçants)
        merchant_names = {
            "MER-1106": ("Boutique Numérique Didouche", "Alger"),
            "MER-1409": ("Mobilis Telecom Agence", "Oran"),
            "MER-1434": ("Boulangerie Santa Cruz", "Oran"),
            "MER-1488": ("Pharmacie Ibn Sina", "Constantine"),
            "MER-1520": ("Algérie Télécom Centre", "Alger"),
            "MER-2424": ("Restaurant Le Dauphin", "Alger"),
            "MER-2535": ("Café Restaurant El Bahdja", "Alger"),
            "MER-2679": ("Cafétéria Chréa", "Blida"),
            "MER-2824": ("Textile Mitidja", "Blida"),
            "MER-3286": ("Hôtel Cirta Palace", "Constantine"),
            "MER-3547": ("Supermarché Uno City", "Alger"),
            "MER-3615": ("Algérie Télécom Services", "Alger"),
            "MER-4257": ("Agence Voyage Nomade", "Tlemcen"),
            "MER-4527": ("Maison du PC & Mobile", "Sétif"),
            "MER-4582": ("Pizzeria Bella Vista", "Annaba"),
            "MER-4611": ("Superette El Afia", "Blida"),
            "MER-4657": ("Boutique Sidi Yahia", "Alger"),
            "MER-4811": ("Djezzy Pro Center", "Alger"),
            "MER-5012": ("Supérette Les Dunes", "Oran"),
            "MER-5506": ("Pharmacie Ain Fouara", "Sétif"),
            "MER-5552": ("Boutique El Mordjane", "Annaba"),
            "MER-5557": ("Boutique Bône Élégance", "Annaba"),
            "MER-6574": ("Agence Tourisme El Aurassi", "Alger"),
            "MER-7873": ("Supermarché Al Baraka", "Batna"),
            "MER-7912": ("Boutique Chic Tlemcen", "Tlemcen"),
            "MER-7924": ("Ooredoo Espace Client", "Alger"),
            "MER-8359": ("Cyber & Télécom Mansourah", "Tlemcen"),
            "MER-9279": ("Parapharmacie La Soummam", "Béjaïa"),
            "MER-9928": ("Restaurant Cirta Gourmand", "Constantine"),
            "MER-9935": ("Optique Médicale Numidie", "Constantine"),
        }

        # Déduire la catégorie principale de chaque commerçant
        merchant_categories = {}
        for r in rows:
            m_code = r["merchant_id"]
            if m_code not in merchant_categories:
                merchant_categories[m_code] = r["merchant_category"]

        merchant_map = {}
        for m_code, cat in merchant_categories.items():
            name, wilaya = merchant_names.get(m_code, (f"Commerce {m_code}", "Alger"))
            email = f"{m_code.lower().replace('-', '')}@merchantpay.dz"

            user, _ = User.objects.get_or_create(
                email=email,
                defaults={
                    "full_name": f"Gérant {name}",
                    "role": UserRole.MERCHANT,
                    "is_active": True,
                },
            )
            user.set_password("Demo@2026")
            user.save()

            merchant, _ = Merchant.objects.get_or_create(
                merchant_code=m_code,
                defaults={
                    "owner": user,
                    "business_name": name,
                    "merchant_category": cat,
                    "wilaya": wilaya,
                    "address": f"Boulevard Principal, {wilaya}",
                    "phone": "+213 21 00 11 22",
                    "email": email,
                    "registration_number": f"16/00-{random.randint(100000, 999999)}B22",
                    "terminal_count": random.randint(1, 3),
                    "monthly_goal": Decimal("1500000.00"),
                    "status": MerchantStatus.ACTIVE,
                },
            )
            merchant_map[m_code] = merchant

        # Clean up legacy synthetic merchant MRC-0001 if present
        Merchant.objects.filter(merchant_code="MRC-0001").delete()

        # Ensure demo@merchantpay.dz is the owner of MER-2535 (Café Restaurant El Bahdja)
        demo_user, _ = User.objects.get_or_create(
            email="demo@merchantpay.dz",
            defaults={
                "full_name": "Commerçant Démonstration",
                "role": UserRole.MERCHANT,
                "is_active": True,
            },
        )
        demo_user.set_password("Demo@2026")
        demo_user.save()

        m_2535 = merchant_map.get("MER-2535")
        if m_2535:
            former_owner = m_2535.owner
            m_2535.owner = demo_user
            m_2535.email = "demo@merchantpay.dz"
            m_2535.save()
            if former_owner and former_owner.id != demo_user.id:
                former_owner.delete()

        self.stdout.write(self.style.SUCCESS("30 commerçants officiels synchronisés."))

        # 3. Insertion des 150 transactions exactes
        random.seed(42)
        rej_pool = [
            RejectionReason.SOLDE_INSUFFISANT,
            RejectionReason.CODE_PIN_ERRONE,
            RejectionReason.PLAFOND_DEPASSE,
            RejectionReason.CARTE_EXPIREE,
            RejectionReason.REFUS_EMETTEUR,
            RejectionReason.ERREUR_TECHNIQUE,
        ]

        tx_objs = []
        for r in rows:
            m_code = r["merchant_id"]
            merchant = merchant_map[m_code]
            dt = datetime.strptime(r["transaction_date"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)
            amt = Decimal(r["amount"])
            st = r["transaction_status"]
            ch = r["payment_channel"]
            cat = r["merchant_category"]

            rej = random.choice(rej_pool) if st in ["Declined", "REJECTED"] else None
            ref_amt = amt if st in ["Refunded", "REFUNDED"] else None

            tx = Transaction(
                transaction_id=uuid.uuid4(),
                reference=r["transaction_id"],
                merchant=merchant,
                transaction_date=dt,
                amount=amt,
                payment_channel=ch,
                transaction_status=st,
                merchant_category=cat,
                rejection_reason=rej,
                card_last4=f"{random.randint(1000, 9999)}",
                terminal_id=f"TPE-{random.randint(1, 2):02d}",
                refunded_amount=ref_amt,
            )
            tx_objs.append(tx)

        Transaction.objects.bulk_create(tx_objs)
        self.stdout.write(self.style.SUCCESS(f"150 transactions insérées avec succès dans la base de données !"))

        # 4. Génération de dossiers de risque explicatifs pour les anomalies réelles du dataset
        # Dossier 1: Pharmacie Ain Fouara (MER-5506) - Montant très élevé (135 244,71 DZD)
        m_5506 = merchant_map.get("MER-5506")
        tx_114 = Transaction.objects.filter(reference="TXN-20260114").first()
        if m_5506 and tx_114:
            RiskFlag.objects.create(
                merchant=m_5506,
                transaction=tx_114,
                risk_score=85,
                risk_level=RiskLevel.HIGH,
                status=RiskStatus.NEW,
                reasons=["Montant atypique très supérieur au panier moyen sectoriel (+860 %)", "Règlement par canal E-commerce à heure inhabituelle"],
                triggered_rules=[
                    {"code": "R_AMOUNT_CRITICAL", "rule_name": "Montant exceptionnel", "score_delta": 45, "description": "Transaction de 135 244,71 DZD supérieure au seuil d'alerte"},
                    {"code": "R_SECTOR_DEVIATION", "rule_name": "Déviation panier sectoriel", "score_delta": 40, "description": "Écart de plus de 5 écarts-types par rapport à la catégorie Pharmacie"},
                ],
                window_start=tx_114.transaction_date,
                window_end=tx_114.transaction_date,
            )

        # Dossier 2: Cyber & Télécom Mansourah (MER-8359) - Montant 120 490,11 DZD
        m_8359 = merchant_map.get("MER-8359")
        tx_74 = Transaction.objects.filter(reference="TXN-20260074").first()
        if m_8359 and tx_74:
            RiskFlag.objects.create(
                merchant=m_8359,
                transaction=tx_74,
                risk_score=65,
                risk_level=RiskLevel.MEDIUM,
                status=RiskStatus.UNDER_INVESTIGATION,
                reasons=["Montant transactionnel élevé sur application mobile", "Profil commerçant en phase de consolidation"],
                triggered_rules=[
                    {"code": "R_AMOUNT_HIGH", "rule_name": "Montant élevé", "score_delta": 35, "description": "Transaction de 120 490,11 DZD"},
                    {"code": "R_CHANNEL_SPIKE", "rule_name": "Surveillance canal mobile", "score_delta": 30, "description": "Volume inhabituel sur application mobile"},
                ],
                window_start=tx_74.transaction_date,
                window_end=tx_74.transaction_date,
            )

        # Dossier 3: Restaurant Cirta Gourmand (MER-9928) - Rejets répétés
        m_9928 = merchant_map.get("MER-9928")
        tx_29 = Transaction.objects.filter(reference="TXN-20260029").first()
        if m_9928 and tx_29:
            RiskFlag.objects.create(
                merchant=m_9928,
                transaction=tx_29,
                risk_score=30,
                risk_level=RiskLevel.LOW,
                status=RiskStatus.NEW,
                reasons=["Transaction refusée pour solde insuffisant", "Profil régulier par ailleurs"],
                triggered_rules=[
                    {"code": "R_DECLINE_NOTICE", "rule_name": "Notification de refus", "score_delta": 30, "description": "Refus standard sur virement"},
                ],
                window_start=tx_29.transaction_date,
                window_end=tx_29.transaction_date,
            )

        # 5. Évaluation des alertes commerçants
        alerts_count = evaluate_all_active_merchants()
        self.stdout.write(self.style.SUCCESS(f"{alerts_count} alertes commerçants générées."))
        self.stdout.write(self.style.SUCCESS("=== CHARGEMENT DU JEU DE DONNÉES TERMINÉ AVEC SUCCÈS ==="))
