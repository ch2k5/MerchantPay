from rest_framework import serializers

from apps.merchants.models import Merchant
from apps.transactions.models import Transaction


class MerchantSummarySerializer(serializers.ModelSerializer):
    class Meta:
        model = Merchant
        fields = ["id", "merchant_code", "business_name", "merchant_category", "wilaya"]


class TransactionSerializer(serializers.ModelSerializer):
    merchant_details = MerchantSummarySerializer(source="merchant", read_only=True)

    class Meta:
        model = Transaction
        fields = [
            "transaction_id",
            "reference",
            "merchant",
            "merchant_details",
            "transaction_date",
            "amount",
            "payment_channel",
            "transaction_status",
            "merchant_category",
            "rejection_reason",
            "card_last4",
            "terminal_id",
            "refunded_amount",
        ]
