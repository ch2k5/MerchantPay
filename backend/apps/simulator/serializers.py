from decimal import Decimal

from rest_framework import serializers


class SimulationInputSerializer(serializers.Serializer):
    growth_rate_pct = serializers.FloatField(
        required=False,
        default=None,
        min_value=-50.0,
        max_value=200.0,
        error_messages={
            "min_value": "Le taux de croissance des transactions doit être supérieur ou égal à -50 %.",
            "max_value": "Le taux de croissance des transactions ne peut pas dépasser +200 %.",
        },
    )
    volume_pct = serializers.FloatField(
        required=False,
        default=None,
        min_value=-50.0,
        max_value=200.0,
    )
    avg_amount_delta_dzd = serializers.DecimalField(
        required=False,
        default=None,
        max_digits=12,
        decimal_places=2,
        min_value=Decimal("-5000.00"),
        max_value=Decimal("10000.00"),
        error_messages={
            "min_value": "La variation du panier moyen doit être supérieure ou égale à -5 000 DZD.",
            "max_value": "La variation du panier moyen ne peut pas dépasser +10 000 DZD.",
        },
    )
    ticket_delta = serializers.DecimalField(
        required=False,
        default=None,
        max_digits=12,
        decimal_places=2,
        min_value=Decimal("-5000.00"),
        max_value=Decimal("10000.00"),
    )
    period = serializers.ChoiceField(
        choices=["month", "week"],
        default="month",
        required=False,
    )

    def validate(self, attrs):
        growth = attrs.get("growth_rate_pct")
        if growth is None:
            growth = attrs.get("volume_pct")
        if growth is None:
            growth = 15.0
        attrs["growth_rate_pct"] = float(growth)

        delta = attrs.get("avg_amount_delta_dzd")
        if delta is None:
            delta = attrs.get("ticket_delta")
        if delta is None:
            delta = Decimal("0.00")
        attrs["avg_amount_delta_dzd"] = Decimal(str(delta))
        return attrs
