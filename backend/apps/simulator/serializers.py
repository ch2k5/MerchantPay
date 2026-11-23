from decimal import Decimal

from rest_framework import serializers


class SimulationInputSerializer(serializers.Serializer):
    growth_rate_pct = serializers.FloatField(
        default=15.0,
        min_value=-50.0,
        max_value=200.0,
        error_messages={
            "min_value": "Le taux de croissance des transactions doit être supérieur ou égal à -50 %.",
            "max_value": "Le taux de croissance des transactions ne peut pas dépasser +200 %.",
        },
    )
    avg_amount_delta_dzd = serializers.DecimalField(
        default=Decimal("200.00"),
        max_digits=12,
        decimal_places=2,
        min_value=Decimal("-5000.00"),
        max_value=Decimal("10000.00"),
        error_messages={
            "min_value": "La variation du panier moyen doit être supérieure ou égale à -5 000 DZD.",
            "max_value": "La variation du panier moyen ne peut pas dépasser +10 000 DZD.",
        },
    )
    period = serializers.ChoiceField(
        choices=["month", "week"],
        default="month",
        required=False,
    )
