from django.db import models


class UserRole(models.TextChoices):
    MERCHANT = "MERCHANT", "Commerçant"
    ADMIN = "ADMIN", "Administrateur SATIM"


class AdminLevel(models.TextChoices):
    SUPER_ADMIN = "SUPER_ADMIN", "Super Administrateur"
    ANALYST = "ANALYST", "Analyste Risque"
    VIEWER = "VIEWER", "Observateur (Lecture seule)"


class MerchantCategory(models.TextChoices):
    # Official FINOVIA × ENSM × SATIM Dataset Categories
    DIGITAL_SERVICES = "Digital Services & Telecom", "Digital Services & Telecom"
    GROCERIES = "Groceries & Supermarkets", "Groceries & Supermarkets"
    ELECTRONICS = "Electronics & Tech", "Electronics & Tech"
    FOOD_DINING = "Food & Dining", "Food & Dining"
    TRAVEL = "Travel & Hospitality", "Travel & Hospitality"
    RETAIL = "Retail & Apparel", "Retail & Apparel"
    HEALTHCARE = "Healthcare & Pharmacy", "Healthcare & Pharmacy"

    # French & legacy aliases
    RESTAURATION = "Restauration", "Restauration"
    COMMERCE_DETAIL = "Commerce de détail", "Commerce de détail"
    PHARMACIE = "Pharmacie", "Pharmacie"
    ALIMENTATION = "Alimentation", "Alimentation"
    ELECTRONIQUE = "Électronique", "Électronique"
    HABILLEMENT = "Habillement", "Habillement"
    SERVICES = "Services", "Services"
    CARBURANT = "Carburant", "Carburant"
    HOTELLERIE = "Hôtellerie", "Hôtellerie"
    AUTRE = "Autre", "Autre"


class MerchantStatus(models.TextChoices):
    ACTIVE = "ACTIVE", "Actif"
    INACTIVE = "INACTIVE", "Inactif"


class PaymentChannel(models.TextChoices):
    # Official FINOVIA × ENSM × SATIM Dataset Channels
    ECOMMERCE = "E-commerce (CIB / Edahabia)", "E-commerce (CIB / Edahabia)"
    POS_TERMINAL = "TPE / POS Terminal", "TPE / POS Terminal"
    MOBILE_APP = "Mobile App", "Mobile App"
    CONTACTLESS = "Contactless / NFC", "Contactless / NFC"
    BANK_TRANSFER = "Bank Transfer / Virement", "Bank Transfer / Virement"

    # Card networks
    CIB = "CIB", "Carte CIB"
    EDAHABIA = "EDAHABIA", "Carte EDAHABIA"


class TransactionStatus(models.TextChoices):
    # Official FINOVIA × ENSM × SATIM Dataset Statuses
    ACCEPTED = "Accepted", "Acceptée"
    DECLINED = "Declined", "Refusée (Declined)"
    REFUNDED = "Refunded", "Remboursée"
    CANCELLED = "Cancelled", "Annulée"

    # Uppercase aliases
    COMPLETED = "COMPLETED", "Acceptée (COMPLETED)"
    REJECTED = "REJECTED", "Rejetée (REJECTED)"


# Global sets for status matching across services and rules
ACCEPTED_STATUSES = [TransactionStatus.ACCEPTED, "COMPLETED", "ACCEPTED"]
REJECTED_STATUSES = [TransactionStatus.DECLINED, "REJECTED", "DECLINED"]
CANCELLED_STATUSES = [TransactionStatus.CANCELLED, "CANCELLED"]
REFUNDED_STATUSES = [TransactionStatus.REFUNDED, "REFUNDED"]


class RejectionReason(models.TextChoices):
    SOLDE_INSUFFISANT = "Solde insuffisant", "Solde insuffisant"
    CARTE_EXPIREE = "Carte expirée", "Carte expirée"
    CODE_PIN_ERRONE = "Code PIN erroné", "Code PIN erroné"
    PLAFOND_DEPASSE = "Plafond dépassé", "Plafond dépassé"
    REFUS_EMETTEUR = "Refus de l'émetteur", "Refus de l'émetteur"
    ERREUR_TECHNIQUE = "Erreur technique", "Erreur technique"


class AlertSeverity(models.TextChoices):
    INFO = "INFO", "Information"
    WARNING = "WARNING", "Avertissement"
    CRITICAL = "CRITICAL", "Critique"
    SUCCESS = "SUCCESS", "Succès"


class AlertType(models.TextChoices):
    REVENUE_DROP = "REVENUE_DROP", "Baisse de chiffre d'affaires"
    NO_ACTIVITY = "NO_ACTIVITY", "Inactivité prolongée"
    REJECTION_SPIKE = "REJECTION_SPIKE", "Hausse anormale des rejets"
    GOAL_PROGRESS = "GOAL_PROGRESS", "Suivi de l'objectif mensuel"
    PEAK_ACTIVITY = "PEAK_ACTIVITY", "Créneau de forte affluence"
    LOW_ACTIVITY_SLOT = "LOW_ACTIVITY_SLOT", "Créneau creux récurrent"
    CHANNEL_SHIFT = "CHANNEL_SHIFT", "Glissement des canaux de paiement"


class RiskLevel(models.TextChoices):
    LOW = "LOW", "Faible"
    MEDIUM = "MEDIUM", "Moyen"
    HIGH = "HIGH", "Élevé"


class RiskStatus(models.TextChoices):
    NEW = "NEW", "Nouveau"
    UNDER_INVESTIGATION = "UNDER_INVESTIGATION", "En cours d'investigation"
    FALSE_POSITIVE = "FALSE_POSITIVE", "Faux positif"
    CONFIRMED_SUSPICIOUS = "CONFIRMED_SUSPICIOUS", "Suspect confirmé"
    CLOSED = "CLOSED", "Dossier clôturé"


class AuditAction(models.TextChoices):
    LOGIN = "LOGIN", "Connexion utilisateur"
    MERCHANT_UPDATED = "MERCHANT_UPDATED", "Mise à jour profil commerçant"
    MERCHANT_DEACTIVATED = "MERCHANT_DEACTIVATED", "Désactivation commerçant"
    MERCHANT_ACTIVATED = "MERCHANT_ACTIVATED", "Activation commerçant"
    FLAG_STATUS_CHANGED = "FLAG_STATUS_CHANGED", "Changement statut risque"
    NOTE_ADDED = "NOTE_ADDED", "Ajout note investigation"
    EXPORT_GENERATED = "EXPORT_GENERATED", "Génération d'export"
    RISK_SCAN_RUN = "RISK_SCAN_RUN", "Exécution scan risque"
    PASSWORD_CHANGED = "PASSWORD_CHANGED", "Changement de mot de passe"
