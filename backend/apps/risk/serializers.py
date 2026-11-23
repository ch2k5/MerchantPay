from rest_framework import serializers

from apps.accounts.serializers import UserSerializer
from apps.risk.models import InvestigationNote, RiskFlag
from apps.transactions.serializers import TransactionSerializer


class InvestigationNoteSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source="author.full_name", read_only=True)

    class Meta:
        model = InvestigationNote
        fields = [
            "id",
            "risk_flag",
            "author",
            "author_name",
            "text",
            "created_at",
        ]
        read_only_fields = ["author", "created_at"]


class RiskFlagListSerializer(serializers.ModelSerializer):
    merchant_name = serializers.CharField(source="merchant.business_name", read_only=True)
    merchant_code = serializers.CharField(source="merchant.merchant_code", read_only=True)
    merchant_wilaya = serializers.CharField(source="merchant.wilaya", read_only=True)
    transaction_amount = serializers.DecimalField(
        source="transaction.amount", max_digits=14, decimal_places=2, read_only=True, allow_null=True
    )
    transaction_reference = serializers.CharField(source="transaction.reference", read_only=True, allow_null=True)

    class Meta:
        model = RiskFlag
        fields = [
            "id",
            "merchant",
            "merchant_name",
            "merchant_code",
            "merchant_wilaya",
            "transaction",
            "transaction_reference",
            "transaction_amount",
            "risk_score",
            "risk_level",
            "triggered_rules",
            "reasons",
            "status",
            "detected_at",
            "window_start",
            "window_end",
        ]


class RiskFlagDetailSerializer(serializers.ModelSerializer):
    merchant_details = serializers.SerializerMethodField()
    transaction_details = TransactionSerializer(source="transaction", read_only=True)
    notes = InvestigationNoteSerializer(many=True, read_only=True)
    assigned_to_details = UserSerializer(source="assigned_to", read_only=True)

    class Meta:
        model = RiskFlag
        fields = [
            "id",
            "merchant",
            "merchant_details",
            "transaction",
            "transaction_details",
            "risk_score",
            "risk_level",
            "triggered_rules",
            "reasons",
            "status",
            "assigned_to",
            "assigned_to_details",
            "detected_at",
            "window_start",
            "window_end",
            "notes",
        ]

    def get_merchant_details(self, obj):
        m = obj.merchant
        return {
            "id": str(m.id),
            "business_name": m.business_name,
            "merchant_code": m.merchant_code,
            "category": m.merchant_category,
            "wilaya": m.wilaya,
            "status": m.status,
            "terminal_count": m.terminal_count,
        }
