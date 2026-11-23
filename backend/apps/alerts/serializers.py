from rest_framework import serializers

from apps.alerts.models import MerchantAlert


class MerchantAlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = MerchantAlert
        fields = [
            "id",
            "type",
            "severity",
            "title",
            "message",
            "recommendation",
            "metric_snapshot",
            "period_start",
            "period_end",
            "dedupe_key",
            "is_read",
            "created_at",
        ]
