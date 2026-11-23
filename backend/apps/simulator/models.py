import uuid

from django.db import models

from apps.merchants.models import Merchant


class SimulationScenario(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    merchant = models.ForeignKey(
        Merchant,
        on_delete=models.CASCADE,
        related_name="simulations",
        db_index=True,
    )
    growth_rate = models.FloatField(help_text="Taux de croissance des transactions en %")
    avg_amount_delta = models.DecimalField(
        max_digits=12, decimal_places=2, help_text="Variation du panier moyen en DZD"
    )
    result = models.JSONField(help_text="Résultat complet de la simulation")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Scénario de Simulation"
        verbose_name_plural = "Scénarios de Simulation"

    def __str__(self):
        return f"Simulation {self.growth_rate:+}% / {self.avg_amount_delta:+} DZD ({self.merchant.business_name})"
