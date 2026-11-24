from decimal import Decimal

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.serializers import MerchantDetailSerializer
from apps.alerts.models import MerchantAlert
from apps.alerts.serializers import MerchantAlertSerializer
from apps.alerts.services import evaluate_merchant_alerts
from apps.analytics.services import (
    compare_kpis,
    compute_channel_distribution,
    compute_heatmap,
    compute_kpis,
    compute_payment_transactions_summary,
    compute_trends,
)
from apps.audit.services import record_audit
from apps.core.dates import parse_date_param, resolve_period_range
from apps.core.enums import AuditAction
from apps.core.permissions import IsMerchant
from apps.core.utils import format_dzd
from apps.simulator.models import SimulationScenario
from apps.simulator.serializers import SimulationInputSerializer
from apps.simulator.services import get_simulator_baseline, run_simulation
from apps.transactions.export import export_transactions_csv, export_transactions_pdf
from apps.transactions.filters import TransactionFilter
from apps.transactions.serializers import TransactionSerializer


class MerchantProfileView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        serializer = MerchantDetailSerializer(merchant)
        return Response(serializer.data)

    def patch(self, request):
        merchant = request.user.merchant
        serializer = MerchantDetailSerializer(merchant, data=request.data, partial=True)
        if serializer.is_valid():
            before_data = {"monthly_goal": str(merchant.monthly_goal), "phone": merchant.phone}
            updated = serializer.save()
            record_audit(
                request=request,
                actor=request.user,
                action=AuditAction.MERCHANT_UPDATED,
                target_type="Merchant",
                target_id=str(merchant.id),
                before=before_data,
                after={"monthly_goal": str(updated.monthly_goal), "phone": updated.phone},
            )
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class MerchantDashboardView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        preset = request.query_params.get("preset", "30d")
        date_from_str = request.query_params.get("date_from")
        date_to_str = request.query_params.get("date_to")

        # Allow passing anchor date for testing/reproducibility
        anchor_str = request.query_params.get("anchor")
        anchor_now = parse_date_param(anchor_str) if anchor_str else None

        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=preset,
            date_from_str=date_from_str,
            date_to_str=date_to_str,
            anchor_now=anchor_now,
        )

        qs_curr = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        qs_prev = merchant.transactions.filter(transaction_date__range=(p_from, p_to))

        # KPIs and comparison
        kpis_curr = compute_kpis(qs_curr)
        kpis_prev = compute_kpis(qs_prev)
        comparison = compare_kpis(kpis_curr, kpis_prev)

        # Revenue trend (daily)
        trends = compute_trends(qs_curr, c_from, c_to, granularity="day")
        prev_trends = compute_trends(qs_prev, p_from, p_to, granularity="day")

        # Channel distribution
        channel_dist = compute_channel_distribution(qs_curr)

        # Heatmap & peak periods
        heatmap = compute_heatmap(qs_curr)

        # Monthly goal progress
        goal_data = None
        if merchant.monthly_goal and merchant.monthly_goal > Decimal("0.00"):
            achieved = kpis_curr["net_revenue"]
            pct = round(float((achieved / merchant.monthly_goal) * 100), 1)
            goal_data = {
                "goal": merchant.monthly_goal,
                "achieved": achieved,
                "percent": pct,
                "is_reached": pct >= 100.0,
            }

        # Latest 5 transactions
        latest_txs = merchant.transactions.order_by("-transaction_date")[:5]
        latest_txs_data = TransactionSerializer(latest_txs, many=True).data

        # Latest 3 alerts
        latest_alerts = merchant.alerts.filter(is_read=False).order_by("-created_at")[:3]
        if not latest_alerts.exists():
            latest_alerts = merchant.alerts.order_by("-created_at")[:3]
        latest_alerts_data = MerchantAlertSerializer(latest_alerts, many=True).data

        return Response(
            {
                "period": {
                    "preset": preset,
                    "current_from": c_from,
                    "current_to": c_to,
                    "previous_from": p_from,
                    "previous_to": p_to,
                },
                "kpis": kpis_curr,
                "comparison": comparison,
                "trends": trends,
                "prev_trends": prev_trends,
                "channel_distribution": channel_dist,
                "peak_periods": {
                    "top_hours": heatmap["top_3_hours"],
                    "top_weekdays": heatmap["top_3_weekdays"],
                    "peak_slot": heatmap["peak_slot"],
                    "low_slot": heatmap["low_slot"],
                },
                "monthly_goal": goal_data,
                "latest_transactions": latest_txs_data,
                "latest_alerts": latest_alerts_data,
                "summary_tables": compute_payment_transactions_summary(qs_curr),
            }
        )


class MerchantTransactionListView(generics.ListAPIView):
    permission_classes = [IsMerchant]
    serializer_class = TransactionSerializer
    filterset_class = TransactionFilter
    ordering_fields = ["transaction_date", "amount"]
    ordering = ["-transaction_date"]

    def get_queryset(self):
        return self.request.user.merchant.transactions.all().select_related("merchant")


class MerchantTransactionDetailView(generics.RetrieveAPIView):
    permission_classes = [IsMerchant]
    serializer_class = TransactionSerializer

    def get_queryset(self):
        return self.request.user.merchant.transactions.all().select_related("merchant")


class MerchantTransactionExportView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        fmt = request.query_params.get("format", "csv").lower()
        filterset = TransactionFilter(
            request.query_params,
            queryset=merchant.transactions.all().select_related("merchant"),
        )
        qs = filterset.qs

        record_audit(
            request=request,
            actor=request.user,
            action=AuditAction.EXPORT_GENERATED,
            target_type="TransactionExport",
            target_id=f"merchant_{merchant.id}_{fmt}",
            after={"count": qs.count(), "format": fmt},
        )

        if fmt == "pdf":
            return export_transactions_pdf(
                qs,
                merchant=merchant,
                filters_desc="Relevé filtré commerçant",
                filename=f"transactions_{merchant.merchant_code}.pdf",
            )
        return export_transactions_csv(
            qs,
            filename=f"transactions_{merchant.merchant_code}.csv",
        )


class MerchantCollectionsView(APIView):
    """
    Module 3: Suivi des encaissements
    Accepted vs rejected vs cancelled vs refunded totals and counts,
    per-period breakdown table (day/week/month),
    two-period comparison, and a textual summary in French.
    """

    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        preset = request.query_params.get("preset", "30d")
        granularity = request.query_params.get("granularity", "day")

        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=preset,
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )

        # Custom comparison range override if supplied
        cmp_a_from = parse_date_param(request.query_params.get("compare_a_from")) or c_from
        cmp_a_to = parse_date_param(request.query_params.get("compare_a_to")) or c_to
        cmp_b_from = parse_date_param(request.query_params.get("compare_b_from")) or p_from
        cmp_b_to = parse_date_param(request.query_params.get("compare_b_to")) or p_to

        qs_a = merchant.transactions.filter(transaction_date__range=(cmp_a_from, cmp_a_to))
        qs_b = merchant.transactions.filter(transaction_date__range=(cmp_b_from, cmp_b_to))

        kpis_a = compute_kpis(qs_a)
        kpis_b = compute_kpis(qs_b)
        comparison = compare_kpis(kpis_a, kpis_b)

        breakdown = compute_trends(qs_a, cmp_a_from, cmp_a_to, granularity=granularity)

        # Textual summary in French
        net_rev_a = kpis_a["net_revenue"]
        delta_rev = comparison["net_revenue"]["delta_abs"]
        delta_pct = comparison["net_revenue"]["delta_pct"]
        if delta_pct is not None and delta_pct >= 0:
            trend_word = f"en hausse de {delta_pct:+.1f} %"
        elif delta_pct is not None:
            trend_word = f"en baisse de {abs(delta_pct):.1f} %"
        else:
            trend_word = "stable"

        summary = (
            f"Sur la période sélectionnée, vos encaissements nets s'élèvent à {format_dzd(net_rev_a)} "
            f"pour un total de {kpis_a['accepted_count']} transactions acceptées ({trend_word} "
            f"par rapport à la période précédente). Le taux de succès technique est de {kpis_a['success_rate']:.1f} %."
        )

        return Response(
            {
                "totals": kpis_a,
                "breakdown": breakdown,
                "comparison": {
                    "period_a": {"from": cmp_a_from, "to": cmp_a_to, "kpis": kpis_a},
                    "period_b": {"from": cmp_b_from, "to": cmp_b_to, "kpis": kpis_b},
                    "deltas": comparison,
                },
                "summary": summary,
            }
        )


class MerchantAnalyticsTrendsView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        granularity = request.query_params.get("granularity", "day")
        c_from, c_to, _, _ = resolve_period_range(
            preset=request.query_params.get("preset", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        qs = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        trends = compute_trends(qs, c_from, c_to, granularity=granularity)
        return Response({"granularity": granularity, "series": trends})


class MerchantAnalyticsHeatmapView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        c_from, c_to, _, _ = resolve_period_range(
            preset=request.query_params.get("preset", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        qs = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        heatmap_data = compute_heatmap(qs)
        return Response(heatmap_data)


class MerchantAnalyticsChannelsView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        c_from, c_to, _, _ = resolve_period_range(
            preset=request.query_params.get("preset", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        qs = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        channels = compute_channel_distribution(qs)
        return Response(channels)


class MerchantAnalyticsVolumeView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        c_from, c_to, p_from, p_to = resolve_period_range(
            preset=request.query_params.get("preset", "30d"),
            date_from_str=request.query_params.get("date_from"),
            date_to_str=request.query_params.get("date_to"),
        )
        qs = merchant.transactions.filter(transaction_date__range=(c_from, c_to))
        kpis = compute_kpis(qs)
        return Response(kpis)


class MerchantAlertListView(generics.ListAPIView):
    permission_classes = [IsMerchant]
    serializer_class = MerchantAlertSerializer

    def get_queryset(self):
        merchant = self.request.user.merchant
        qs = merchant.alerts.all()
        is_read = self.request.query_params.get("is_read")
        if is_read is not None:
            qs = qs.filter(is_read=is_read.lower() in ["true", "1"])
        sev = self.request.query_params.get("severity")
        if sev:
            qs = qs.filter(severity=sev.upper())
        atype = self.request.query_params.get("type")
        if atype:
            qs = qs.filter(type=atype)
        return qs


class MerchantAlertReadView(APIView):
    permission_classes = [IsMerchant]

    def post(self, request, pk):
        merchant = request.user.merchant
        try:
            alert = merchant.alerts.get(pk=pk)
            alert.is_read = True
            alert.save()
            return Response({"message": "Alerte marquée comme lue.", "alert": MerchantAlertSerializer(alert).data})
        except MerchantAlert.DoesNotExist:
            return Response({"code": "NOT_FOUND", "message": "Alerte introuvable."}, status=status.HTTP_404_NOT_FOUND)


class MerchantAlertReadAllView(APIView):
    permission_classes = [IsMerchant]

    def post(self, request):
        merchant = request.user.merchant
        count = merchant.alerts.filter(is_read=False).update(is_read=True)
        return Response({"message": f"{count} alerte(s) marquée(s) comme lue(s).", "updated_count": count})


class MerchantAlertEvaluateView(APIView):
    permission_classes = [IsMerchant]

    def post(self, request):
        merchant = request.user.merchant
        alerts = evaluate_merchant_alerts(merchant)
        return Response(
            {
                "message": "Évaluation des règles effectuée avec succès.",
                "alerts": MerchantAlertSerializer(alerts, many=True).data,
                "total_alerts": merchant.alerts.count(),
            }
        )


class MerchantSimulatorBaselineView(APIView):
    permission_classes = [IsMerchant]

    def get(self, request):
        merchant = request.user.merchant
        baseline = get_simulator_baseline(merchant)
        return Response(baseline)


class MerchantSimulatorRunView(APIView):
    permission_classes = [IsMerchant]

    def post(self, request):
        serializer = SimulationInputSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(
                {
                    "code": "VALIDATION_ERROR",
                    "message": "Données de simulation invalides.",
                    "details": serializer.errors,
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )

        merchant = request.user.merchant
        growth_rate = serializer.validated_data["growth_rate_pct"]
        avg_delta = serializer.validated_data["avg_amount_delta_dzd"]
        period = serializer.validated_data.get("period", "month")

        baseline_data = get_simulator_baseline(merchant)
        sim_res = run_simulation(
            base_count=baseline_data["base_count"],
            base_avg=baseline_data["base_avg"],
            growth_rate_pct=growth_rate,
            avg_amount_delta_dzd=avg_delta,
            monthly_goal=merchant.monthly_goal,
            period=period,
        )

        # Optional persistence
        SimulationScenario.objects.create(
            merchant=merchant,
            growth_rate=growth_rate,
            avg_amount_delta=avg_delta,
            result=sim_res,
        )

        return Response(sim_res)
