import uuid

from django.db import models

from apps.core.enums import AlertSeverity, AlertType
from apps.merchants.models import Merchant


class MerchantAlert(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    merchant = models.ForeignKey(
        Merchant,
        on_delete=models.CASCADE,
        related_name="alerts",
        db_index=True,
    )
    type = models.CharField(max_length=64, choices=AlertType.choices)
    severity = models.CharField(max_length=20, choices=AlertSeverity.choices, default=AlertSeverity.INFO)
    title = models.CharField(max_length=255)
    message = models.TextField(help_text="Message explicatif en français")
    recommendation = models.TextField(help_text="Recommandation d'action en français")
    metric_snapshot = models.JSONField(
        default=dict,
        help_text="Chiffres et métriques ayant déclenché l'alerte pour affichage Pourquoi cette alerte ?",
    )
    period_start = models.DateTimeField(null=True, blank=True)
    period_end = models.DateTimeField(null=True, blank=True)
    dedupe_key = models.CharField(max_length=255, db_index=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["merchant", "dedupe_key"],
                name="unique_merchant_dedupe_alert",
            )
        ]
        verbose_name = "Alerte Commerçant"
        verbose_name_plural = "Alertes Commerçants"

    def __str__(self):
        return f"[{self.severity}] {self.title} ({self.merchant.business_name})"
