from decimal import Decimal

import django_filters
from django.utils import timezone
from django.db.models import Case, Count, DecimalField, F, IntegerField, Q, Sum, When
from django.db.models.functions import Coalesce
from rest_framework import generics, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import User
from apps.accounts.serializers import (
    AdminUserManagementSerializer,
    MerchantDetailSerializer,
)
from apps.analytics.services import (
    compute_admin_platform_analytics,
    compute_channel_distribution,
    compute_kpis,
    compute_payment_transactions_summary,
    compute_trends,
)
from apps.audit.models import AuditLog
from apps.core.renderers import IgnoreClientContentNegotiation, PassthroughRenderer
from apps.audit.services import record_audit
from apps.core.dates import resolve_period_range
from apps.core.enums import (
    ACCEPTED_STATUSES,
    REJECTED_STATUSES,
    AuditAction,
    MerchantStatus,
    RiskLevel,
    RiskStatus,
    TransactionStatus,
    UserRole,
)
from apps.core.permissions import (
    AdminActionPermission,
    IsAdmin,
    IsAnalystOrAbove,
    IsSuperAdmin,
)
from apps.merchants.models import Merchant
from apps.reports.services import (
    export_merchants_report_csv,
    export_merchants_report_pdf,
    export_platform_report_csv,
    export_platform_report_pdf,
    export_risk_report_csv,
    export_risk_report_pdf,
)
from apps.risk.models import InvestigationNote, RiskFlag
from apps.risk.serializers import (
    InvestigationNoteSerializer,
    RiskFlagDetailSerializer,
    RiskFlagListSerializer,
)
from apps.risk.services import scan_all_merchants_risk
from apps.transactions.export import (
    export_transactions_csv,
    export_transactions_pdf,
)
from apps.transactions.filters import TransactionFilter
from apps.transactions.models import Transaction
from apps.transactions.serializers import TransactionSerializer


# 1. Admin Dashboard View
class AdminDashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        preset = request.query_params.get("preset", "30d")
        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=preset,
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )

        # Merchants counts
        total_merchants = Merchant.objects.count()
        active_merchants = Merchant.objects.filter(status=MerchantStatus.ACTIVE).count()
        inactive_merchants = Merchant.objects.filter(status=MerchantStatus.INACTIVE).count()

        # Platform volume in period
        qs_tx = Transaction.objects.filter(transaction_date__range=(c_from, c_to))
        kpis = compute_kpis(qs_tx)
        channels = compute_channel_distribution(qs_tx)
        trends = compute_trends(qs_tx, c_from, c_to, granularity="day")

        # Open risk flags by level
        open_flags = RiskFlag.objects.filter(status__in=[RiskStatus.NEW, RiskStatus.UNDER_INVESTIGATION])
        flags_summary = {
            "total_open": open_flags.count(),
            "high": open_flags.filter(risk_level=RiskLevel.HIGH).count(),
            "medium": open_flags.filter(risk_level=RiskLevel.MEDIUM).count(),
            "low": open_flags.filter(risk_level=RiskLevel.LOW).count(),
        }

        # Top 5 merchants by revenue
        merchants_revenue = (
            Merchant.objects.filter(transactions__transaction_date__range=(c_from, c_to))
            .annotate(
                rev=Coalesce(
                    Sum(
                        Case(
                            When(
                                transactions__transaction_status__in=ACCEPTED_STATUSES,
                                then=F("transactions__amount"),
                            ),
                            output_field=DecimalField(),
                        )
                    ),
                    Decimal("0.00"),
                ),
                tx_count=Count("transactions__transaction_id"),
            )
            .order_by("-rev")[:5]
        )
        top_revenue_merchants = [
            {
                "id": str(m.id),
                "name": m.business_name,
                "merchant_code": m.merchant_code,
                "category": m.merchant_category,
                "wilaya": m.wilaya,
                "revenue": m.rev,
                "tx_count": m.tx_count,
            }
            for m in merchants_revenue
        ]

        # Top 5 merchants by rejection rate (minimum 10 transactions)
        merchants_rejections = (
            Merchant.objects.filter(transactions__transaction_date__range=(c_from, c_to))
            .annotate(
                total_tx=Count("transactions__transaction_id"),
                rejected_tx=Count(
                    Case(
                        When(
                            transactions__transaction_status__in=REJECTED_STATUSES,
                            then=1,
                        ),
                        output_field=IntegerField(),
                    )
                ),
            )
            .filter(total_tx__gte=10)
            .order_by("-rejected_tx")[:5]
        )
        top_rejection_merchants = []
        for m in merchants_rejections:
            rate = round((m.rejected_tx / m.total_tx) * 100, 1) if m.total_tx > 0 else 0.0
            top_rejection_merchants.append(
                {
                    "id": str(m.id),
                    "name": m.business_name,
                    "merchant_code": m.merchant_code,
                    "category": m.merchant_category,
                    "wilaya": m.wilaya,
                    "total_tx": m.total_tx,
                    "rejected_tx": m.rejected_tx,
                    "rejection_rate": rate,
                }
            )

        return Response(
            {
                "period": {"from": c_from, "to": c_to, "preset": preset},
                "merchants": {
                    "total": total_merchants,
                    "active": active_merchants,
                    "inactive": inactive_merchants,
                },
                "platform_volume": {
                    "total_transactions": kpis["total_transactions"],
                    "accepted_amount": kpis["accepted_amount"],
                    "net_revenue": kpis["net_revenue"],
                    "success_rate": kpis["success_rate"],
                    "rejection_rate": kpis["rejection_rate"],
                },
                "channels": channels,
                "activity_trend": trends,
                "suspicious_summary": flags_summary,
                "top_merchants_by_revenue": top_revenue_merchants,
                "top_merchants_by_rejection": top_rejection_merchants,
                "summary_tables": compute_payment_transactions_summary(qs_tx),
            }
        )


class AdminAnalyticsView(APIView):
    """
    Dedicated comprehensive platform-wide analytics for SATIM Administrators.
    Provides 4 core pillars with interactive visualizations:
    1. Vue d'ensemble (Totals, Volume, Growth, Comparison)
    2. Analyse temporelle (Granularity trends, Heatmap matrix, Peak slots)
    3. Analyse des commerçants (Ranking, Category breakdown, Anomaly detection)
    4. Analyse des transactions (Status distribution, Channel distribution, Amount brackets, Rejections)
    """
    permission_classes = [IsAdmin]

    def get(self, request):
        preset = request.query_params.get("preset", "30d")
        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=preset,
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        raw_granularity = request.query_params.get("granularity", "day").lower()
        if raw_granularity in ["daily", "day"]:
            granularity = "day"
        elif raw_granularity in ["weekly", "week"]:
            granularity = "week"
        elif raw_granularity in ["monthly", "month"]:
            granularity = "month"
        elif raw_granularity in ["hourly", "hour"]:
            granularity = "hour"
        else:
            granularity = "day"

        base_qs = Transaction.objects.all().select_related("merchant")
        filtered_qs = TransactionFilter(request.query_params, queryset=base_qs).qs
        curr_qs = filtered_qs.filter(transaction_date__range=(c_from, c_to))
        prev_qs = filtered_qs.filter(transaction_date__range=(p_from, p_to))

        analytics_data = compute_admin_platform_analytics(
            queryset=curr_qs,
            prev_queryset=prev_qs,
            date_from=c_from,
            date_to=c_to,
            granularity=granularity,
        )
        analytics_data["period"] = {
            "preset": preset,
            "current_from": c_from,
            "current_to": c_to,
            "previous_from": p_from,
            "previous_to": p_to,
        }
        return Response(analytics_data)


class AdminAnalyticsExportView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        fmt = request.query_params.get("format", "csv").lower()
        preset = request.query_params.get("preset", "30d")
        c_from, c_to, _, _ = resolve_period_range(
            preset=preset,
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        base_qs = Transaction.objects.all().select_related("merchant")
        filtered_qs = TransactionFilter(request.query_params, queryset=base_qs).qs
        qs = filtered_qs.filter(transaction_date__range=(c_from, c_to)).order_by("-transaction_date")

        filename = f"satim_statistiques_{timezone.now().strftime('%Y%m%d_%H%M%S')}"
        if fmt == "pdf":
            return export_platform_report_pdf(c_from, c_to, filename=f"{filename}.pdf")
        return export_platform_report_csv(c_from, c_to, filename=f"{filename}.csv")


# 2. Merchants Management
class AdminMerchantFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method="filter_search")
    status = django_filters.CharFilter(field_name="status")
    category = django_filters.CharFilter(field_name="merchant_category")
    wilaya = django_filters.CharFilter(field_name="wilaya")

    class Meta:
        model = Merchant
        fields = ["search", "status", "category", "wilaya"]

    def filter_search(self, queryset, name, value):
        if not value:
            return queryset
        val = value.strip()
        return queryset.filter(
            Q(business_name__icontains=val)
            | Q(merchant_code__icontains=val)
            | Q(registration_number__icontains=val)
            | Q(email__icontains=val)
        )


class AdminMerchantListView(generics.ListAPIView):
    permission_classes = [IsAdmin]
    serializer_class = MerchantDetailSerializer
    filterset_class = AdminMerchantFilter
    ordering_fields = ["business_name", "merchant_code", "created_at"]
    ordering = ["business_name"]
    queryset = Merchant.objects.all().select_related("owner")


class AdminMerchantDetailView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAdmin, AdminActionPermission]
    serializer_class = MerchantDetailSerializer
    queryset = Merchant.objects.all().select_related("owner")

    def perform_update(self, serializer):
        before = {"status": self.get_object().status, "business_name": self.get_object().business_name}
        instance = serializer.save()
        record_audit(
            request=self.request,
            actor=self.request.user,
            action=AuditAction.MERCHANT_UPDATED,
            target_type="Merchant",
            target_id=str(instance.id),
            before=before,
            after={"status": instance.status, "business_name": instance.business_name},
        )


class AdminMerchantActivationView(APIView):
    """
    SUPER_ADMIN only: activate or deactivate merchant with mandatory reason.
    """

    permission_classes = [IsSuperAdmin]

    def post(self, request, pk, action_type):
        action_type = action_type.lower()
        if action_type not in ["activate", "deactivate"]:
            return Response(
                {"code": "INVALID_ACTION", "message": "Action invalide."}, status=status.HTTP_400_BAD_REQUEST
            )

        reason = request.data.get("reason", "").strip()
        if not reason:
            return Response(
                {"code": "MISSING_REASON", "message": "Le motif de l'action est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            merchant = Merchant.objects.get(pk=pk)
        except Merchant.DoesNotExist:
            return Response(
                {"code": "NOT_FOUND", "message": "Commerçant introuvable."}, status=status.HTTP_404_NOT_FOUND
            )

        old_status = merchant.status
        new_status = MerchantStatus.ACTIVE if action_type == "activate" else MerchantStatus.INACTIVE
        merchant.status = new_status
        merchant.save()

        # Update owner active status
        if hasattr(merchant, "owner"):
            merchant.owner.is_active = new_status == MerchantStatus.ACTIVE
            merchant.owner.save()

        action_enum = AuditAction.MERCHANT_ACTIVATED if action_type == "activate" else AuditAction.MERCHANT_DEACTIVATED
        record_audit(
            request=request,
            actor=request.user,
            action=action_enum,
            target_type="Merchant",
            target_id=str(merchant.id),
            before={"status": old_status},
            after={"status": new_status, "reason": reason},
        )

        msg = "Commerçant activé avec succès." if action_type == "activate" else "Commerçant désactivé avec succès."
        return Response(
            {
                "message": msg,
                "merchant": MerchantDetailSerializer(merchant).data,
                "reason": reason,
            }
        )


class AdminMerchantStatsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        try:
            merchant = Merchant.objects.get(pk=pk)
        except Merchant.DoesNotExist:
            return Response(
                {"code": "NOT_FOUND", "message": "Commerçant introuvable."}, status=status.HTTP_404_NOT_FOUND
            )

        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=request.query_params.get("preset", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        qs = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        kpis = compute_kpis(qs)
        trends = compute_trends(qs, c_from, c_to, granularity="day")
        channels = compute_channel_distribution(qs)

        return Response(
            {
                "merchant": MerchantDetailSerializer(merchant).data,
                "kpis": kpis,
                "trends": trends,
                "channels": channels,
            }
        )


class AdminMerchantTransactionsView(generics.ListAPIView):
    permission_classes = [IsAdmin]
    serializer_class = TransactionSerializer
    filterset_class = TransactionFilter
    ordering = ["-transaction_date"]

    def get_queryset(self):
        pk = self.kwargs["pk"]
        return Transaction.objects.filter(merchant_id=pk).select_related("merchant")


# 3. Global Transactions Explorer
class AdminTransactionListView(generics.ListAPIView):
    permission_classes = [IsAdmin]
    serializer_class = TransactionSerializer
    filterset_class = TransactionFilter
    ordering_fields = ["transaction_date", "amount"]
    ordering = ["-transaction_date"]
    queryset = Transaction.objects.all().select_related("merchant")


class AdminTransactionDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        try:
            tx = Transaction.objects.select_related("merchant").get(pk=pk)
        except Transaction.DoesNotExist:
            return Response(
                {"code": "NOT_FOUND", "message": "Transaction introuvable."}, status=status.HTTP_404_NOT_FOUND
            )

        data = TransactionSerializer(tx).data
        linked_flags = tx.risk_flags.all()
        data["risk_flags"] = RiskFlagListSerializer(linked_flags, many=True).data
        return Response(data)


class AdminTransactionExportView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        fmt = request.query_params.get("format", "csv").lower()
        filterset = TransactionFilter(
            request.query_params,
            queryset=Transaction.objects.all().select_related("merchant"),
        )
        if not filterset.is_valid():
            return Response(filterset.errors, status=status.HTTP_400_BAD_REQUEST)
        qs = filterset.qs.order_by("-transaction_date")

        filename = f"satim_transactions_{timezone.now().strftime('%Y%m%d_%H%M%S')}"
        if fmt == "pdf":
            return export_transactions_pdf(
                qs,
                filters_desc="Toutes les opérations réseau consolidées (CIB & EDAHABIA)",
                filename=f"{filename}.pdf",
            )
        return export_transactions_csv(qs, filename=f"{filename}.csv")


# 4. Risk & Fraud Management
class RiskFlagFilter(django_filters.FilterSet):
    status = django_filters.CharFilter(field_name="status")
    level = django_filters.CharFilter(field_name="risk_level")
    merchant = django_filters.UUIDFilter(field_name="merchant_id")
    date_from = django_filters.DateTimeFilter(field_name="detected_at", lookup_expr="gte")
    date_to = django_filters.DateTimeFilter(field_name="detected_at", lookup_expr="lte")

    class Meta:
        model = RiskFlag
        fields = ["status", "level", "merchant", "date_from", "date_to"]


class AdminRiskFlagListView(generics.ListAPIView):
    permission_classes = [IsAdmin]
    serializer_class = RiskFlagListSerializer
    filterset_class = RiskFlagFilter
    ordering_fields = ["risk_score", "detected_at"]
    ordering = ["-risk_score"]
    queryset = RiskFlag.objects.all().select_related("merchant", "transaction")


class AdminRiskFlagDetailView(generics.RetrieveAPIView):
    permission_classes = [IsAdmin]
    serializer_class = RiskFlagDetailSerializer
    queryset = (
        RiskFlag.objects.all()
        .select_related("merchant", "transaction", "assigned_to")
        .prefetch_related("notes__author")
    )

    def get_queryset(self):
        return (
            RiskFlag.objects.all()
            .select_related("merchant", "transaction", "assigned_to")
            .prefetch_related("notes__author")
        )


class AdminRiskFlagStatusView(APIView):
    """
    Update status of risk flag. Requires ANALYST or SUPER_ADMIN.
    """

    permission_classes = [IsAnalystOrAbove]

    def patch(self, request, pk):
        try:
            flag = RiskFlag.objects.get(pk=pk)
        except RiskFlag.DoesNotExist:
            return Response(
                {"code": "NOT_FOUND", "message": "Signalement introuvable."}, status=status.HTTP_404_NOT_FOUND
            )

        new_status = request.data.get("status")
        if not new_status or new_status not in RiskStatus.values:
            return Response(
                {"code": "INVALID_STATUS", "message": f"Statut invalide. Choix possibles : {RiskStatus.values}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        old_status = flag.status
        flag.status = new_status
        flag.save()

        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.FLAG_STATUS_CHANGED,
            target_type="RiskFlag",
            target_id=str(flag.id),
            before={"status": old_status},
            after={"status": new_status},
        )

        return Response(RiskFlagDetailSerializer(flag).data)


class AdminRiskFlagNoteCreateView(APIView):
    permission_classes = [IsAnalystOrAbove]

    def post(self, request, pk):
        try:
            flag = RiskFlag.objects.get(pk=pk)
        except RiskFlag.DoesNotExist:
            return Response(
                {"code": "NOT_FOUND", "message": "Signalement introuvable."}, status=status.HTTP_404_NOT_FOUND
            )

        text = request.data.get("text", "").strip()
        if not text:
            return Response(
                {"code": "EMPTY_NOTE", "message": "Le texte de la note ne peut pas être vide."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        note = InvestigationNote.objects.create(
            risk_flag=flag,
            author=request.user,
            text=text,
        )

        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.NOTE_ADDED,
            target_type="RiskFlag",
            target_id=str(flag.id),
            after={"note_id": str(note.id), "text": text[:100]},
        )

        return Response(InvestigationNoteSerializer(note).data, status=status.HTTP_201_CREATED)


class AdminRiskScanView(APIView):
    permission_classes = [IsAnalystOrAbove]

    def post(self, request):
        count = scan_all_merchants_risk()
        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.RISK_SCAN_RUN,
            target_type="Platform",
            target_id="global_risk_scan",
            after={"flags_generated": count},
        )
        return Response({"message": f"Scan de risque exécuté. {count} signalement(s) généré(s).", "count": count})


class AdminRiskSummaryView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        open_flags = RiskFlag.objects.filter(status__in=[RiskStatus.NEW, RiskStatus.UNDER_INVESTIGATION])
        return Response(
            {
                "total_open": open_flags.count(),
                "high": open_flags.filter(risk_level=RiskLevel.HIGH).count(),
                "medium": open_flags.filter(risk_level=RiskLevel.MEDIUM).count(),
                "low": open_flags.filter(risk_level=RiskLevel.LOW).count(),
                "notice": "Une transaction signalée n'est pas automatiquement frauduleuse. Le système identifie un risque ; l'administrateur décide.",
            }
        )


# 5. Reports
class AdminReportPlatformView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        fmt = request.query_params.get("format", "csv").lower()
        c_from, c_to, _, _ = resolve_period_range(
            preset=request.query_params.get("period", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.EXPORT_GENERATED,
            target_type="Report",
            target_id="platform",
            after={"format": fmt},
        )
        if fmt == "pdf":
            return export_platform_report_pdf(c_from, c_to)
        return export_platform_report_csv(c_from, c_to)


class AdminReportMerchantsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        fmt = request.query_params.get("format", "csv").lower()
        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.EXPORT_GENERATED,
            target_type="Report",
            target_id="merchants_directory",
            after={"format": fmt},
        )
        if fmt == "pdf":
            return export_merchants_report_pdf()
        return export_merchants_report_csv()


class AdminReportRiskView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        fmt = request.query_params.get("format", "pdf").lower()
        c_from, c_to, _, _ = resolve_period_range(
            preset=request.query_params.get("period", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.EXPORT_GENERATED,
            target_type="Report",
            target_id="risk_flags",
            after={"format": fmt},
        )
        if fmt == "csv":
            return export_risk_report_csv(c_from, c_to)
        return export_risk_report_pdf(c_from, c_to)


class AdminReportGenerateView(APIView):
    """
    Unified endpoint for Admin Reports generation supporting both POST and GET.
    Used by AdminReportsScreen in Flutter.
    """
    permission_classes = [IsAdmin]
    renderer_classes = [PassthroughRenderer]
    content_negotiation_class = IgnoreClientContentNegotiation

    def _generate(self, request, report_type, fmt, preset, date_from_str, date_to_str):
        c_from, c_to, _, _ = resolve_period_range(
            preset=preset,
            date_from_str=date_from_str,
            date_to_str=date_to_str,
        )
        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.EXPORT_GENERATED,
            target_type="Report",
            target_id=report_type,
            after={"format": fmt, "preset": preset},
        )

        if report_type == "RISK_AUDIT" or report_type == "risk":
            if fmt == "csv":
                return export_risk_report_csv(c_from, c_to)
            return export_risk_report_pdf(c_from, c_to)
        elif report_type == "MERCHANT_ACTIVITY" or report_type == "merchants":
            if fmt == "pdf":
                return export_merchants_report_pdf()
            return export_merchants_report_csv()
        else:
            # Default MONTHLY_VOLUME / platform report
            if fmt == "pdf":
                return export_platform_report_pdf(c_from, c_to)
            return export_platform_report_csv(c_from, c_to)

    def get(self, request):
        report_type = request.query_params.get("report_type", "MONTHLY_VOLUME")
        fmt = request.query_params.get("format", "pdf").lower()
        preset = request.query_params.get("preset") or request.query_params.get("period", "30d")
        return self._generate(
            request,
            report_type,
            fmt,
            preset,
            request.query_params.get("date_from"),
            request.query_params.get("date_to"),
        )

    def post(self, request):
        data = request.data or {}
        report_type = data.get("report_type", "MONTHLY_VOLUME")
        fmt = str(data.get("format", "pdf")).lower()
        preset = data.get("preset") or data.get("period", "30d")
        return self._generate(
            request,
            report_type,
            fmt,
            preset,
            data.get("date_from"),
            data.get("date_to"),
        )


# 6. Audit Logs (SUPER_ADMIN only)
class AuditLogFilter(django_filters.FilterSet):
    actor = django_filters.UUIDFilter(field_name="actor_id")
    action = django_filters.CharFilter(field_name="action")
    target = django_filters.CharFilter(field_name="target_type")
    date_from = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")
    date_to = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = AuditLog
        fields = ["actor", "action", "target", "date_from", "date_to"]


class AuditLogSerializer(serializers.ModelSerializer):
    actor_email = serializers.CharField(source="actor.email", read_only=True)
    actor_name = serializers.CharField(source="actor.full_name", read_only=True)

    class Meta:
        model = AuditLog
        fields = [
            "id",
            "actor",
            "actor_email",
            "actor_name",
            "action",
            "target_type",
            "target_id",
            "before",
            "after",
            "ip_address",
            "created_at",
        ]


class AdminAuditLogListView(generics.ListAPIView):
    permission_classes = [IsSuperAdmin]
    serializer_class = AuditLogSerializer
    filterset_class = AuditLogFilter
    ordering = ["-created_at"]
    queryset = AuditLog.objects.all().select_related("actor")


# 7. Admin Users & Roles Management (SUPER_ADMIN only)
class AdminUserListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsSuperAdmin]
    serializer_class = AdminUserManagementSerializer
    ordering = ["-created_at"]
    queryset = User.objects.filter(role=UserRole.ADMIN)


class AdminUserDetailView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsSuperAdmin]
    serializer_class = AdminUserManagementSerializer
    queryset = User.objects.filter(role=UserRole.ADMIN)
