from rest_framework import serializers

from apps.merchants.models import Merchant
from apps.transactions.models import Transaction


class MerchantSummarySerializer(serializers.ModelSerializer):
    class Meta:
        model = Merchant
        fields = ["id", "merchant_code", "business_name", "merchant_category", "wilaya"]


class TransactionSerializer(serializers.ModelSerializer):
    merchant_details = MerchantSummarySerializer(source="merchant", read_only=True)
    merchant_name = serializers.CharField(source="merchant.business_name", read_only=True, default="")
    timestamp = serializers.DateTimeField(source="transaction_date", read_only=True)
    status = serializers.CharField(source="transaction_status", read_only=True)
    status_display = serializers.CharField(source="get_transaction_status_display", read_only=True)
    channel = serializers.CharField(source="payment_channel", read_only=True)
    channel_display = serializers.CharField(source="get_payment_channel_display", read_only=True)

    class Meta:
        model = Transaction
        fields = [
            "transaction_id",
            "reference",
            "merchant",
            "merchant_details",
            "merchant_name",
            "transaction_date",
            "timestamp",
            "amount",
            "payment_channel",
            "channel",
            "channel_display",
            "transaction_status",
            "status",
            "status_display",
            "merchant_category",
            "rejection_reason",
            "card_last4",
            "terminal_id",
            "refunded_amount",
        ]
