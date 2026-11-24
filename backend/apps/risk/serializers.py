from rest_framework import serializers

from apps.accounts.serializers import UserSerializer
from apps.risk.models import InvestigationNote, RiskFlag
from apps.transactions.serializers import TransactionSerializer


class InvestigationNoteSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source="author.full_name", read_only=True)
    author_email = serializers.CharField(source="author.email", read_only=True)
    note = serializers.CharField(source="text", read_only=True)

    class Meta:
        model = InvestigationNote
        fields = [
            "id",
            "risk_flag",
            "author",
            "author_name",
            "author_email",
            "text",
            "note",
            "created_at",
        ]
        read_only_fields = ["author", "created_at"]


class RiskFlagListSerializer(serializers.ModelSerializer):
    merchant_name = serializers.CharField(source="merchant.business_name", read_only=True)
    merchant_code = serializers.CharField(source="merchant.merchant_code", read_only=True)
    merchant_wilaya = serializers.CharField(source="merchant.wilaya", read_only=True)
    score = serializers.IntegerField(source="risk_score", read_only=True)
    transaction_amount = serializers.DecimalField(
        source="transaction.amount", max_digits=14, decimal_places=2, read_only=True, allow_null=True
    )
    transaction_reference = serializers.CharField(source="transaction.reference", read_only=True, allow_null=True)
    notes = InvestigationNoteSerializer(many=True, read_only=True)
    metric_snapshot = serializers.SerializerMethodField()

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
            "score",
            "risk_level",
            "triggered_rules",
            "reasons",
            "metric_snapshot",
            "status",
            "notes",
            "detected_at",
            "window_start",
            "window_end",
        ]

    def get_metric_snapshot(self, obj):
        # Build explanation snapshot from triggered rules and transaction data
        snapshot = {
            "score_risque": obj.risk_score,
            "niveau_gravite": obj.risk_level,
        }
        if obj.transaction:
            snapshot["montant"] = f"{obj.transaction.amount} DZD"
            snapshot["canal"] = obj.transaction.payment_channel
        if obj.reasons:
            snapshot["motifs"] = ", ".join(obj.reasons[:2])
        return snapshot


class RiskFlagDetailSerializer(serializers.ModelSerializer):
    score = serializers.IntegerField(source="risk_score", read_only=True)
    merchant_details = serializers.SerializerMethodField()
    transaction_details = TransactionSerializer(source="transaction", read_only=True)
    notes = InvestigationNoteSerializer(many=True, read_only=True)
    assigned_to_details = UserSerializer(source="assigned_to", read_only=True)
    metric_snapshot = serializers.SerializerMethodField()

    class Meta:
        model = RiskFlag
        fields = [
            "id",
            "merchant",
            "merchant_details",
            "transaction",
            "transaction_details",
            "risk_score",
            "score",
            "risk_level",
            "triggered_rules",
            "reasons",
            "metric_snapshot",
            "status",
            "assigned_to",
            "assigned_to_details",
            "detected_at",
            "window_start",
            "window_end",
            "notes",
        ]

    def get_metric_snapshot(self, obj):
        snapshot = {
            "score_risque": obj.risk_score,
            "niveau_gravite": obj.risk_level,
        }
        if obj.transaction:
            snapshot["montant"] = f"{obj.transaction.amount} DZD"
            snapshot["canal"] = obj.transaction.payment_channel
        if obj.reasons:
            snapshot["motifs"] = ", ".join(obj.reasons[:2])
        return snapshot

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
