import uuid

from django.conf import settings
from django.db import models

from apps.core.enums import RiskLevel, RiskStatus
from apps.merchants.models import Merchant
from apps.transactions.models import Transaction


class RiskFlag(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    merchant = models.ForeignKey(
        Merchant,
        on_delete=models.CASCADE,
        related_name="risk_flags",
        db_index=True,
    )
    transaction = models.ForeignKey(
        Transaction,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="risk_flags",
        help_text="Transaction ciblée ou null si anomalie globale au niveau commerçant",
    )
    risk_score = models.PositiveIntegerField(help_text="Score de risque de 0 à 100")
    risk_level = models.CharField(max_length=20, choices=RiskLevel.choices, db_index=True)
    triggered_rules = models.JSONField(
        default=list,
        help_text="Liste JSON des règles déclenchées: {code, label_fr, weight, observed, threshold}",
    )
    reasons = models.JSONField(
        default=list,
        help_text="Phrases explicatives générées en français",
    )
    status = models.CharField(
        max_length=32,
        choices=RiskStatus.choices,
        default=RiskStatus.NEW,
        db_index=True,
    )
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_risk_flags",
    )
    detected_at = models.DateTimeField(auto_now_add=True)
    window_start = models.DateTimeField(null=True, blank=True)
    window_end = models.DateTimeField(null=True, blank=True)
    dedupe_key = models.CharField(max_length=255, db_index=True, blank=True, default="")

    class Meta:
        ordering = ["-risk_score", "-detected_at"]
        verbose_name = "Signalement de Risque"
        verbose_name_plural = "Signalements de Risques"

    def __str__(self):
        return f"[{self.risk_level} - {self.risk_score}/100] {self.merchant.business_name} ({self.status})"


class InvestigationNote(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    risk_flag = models.ForeignKey(
        RiskFlag,
        on_delete=models.CASCADE,
        related_name="notes",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="investigation_notes",
    )
    text = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        verbose_name = "Note d'investigation"
        verbose_name_plural = "Notes d'investigation"

    def __str__(self):
        author_name = self.author.full_name if self.author else "Système"
        return f"Note par {author_name} le {self.created_at.strftime('%d/%m/%Y %H:%M')}"
