from datetime import datetime, time, timedelta
from decimal import Decimal

import pytest

from apps.analytics.services import (
    compare_kpis,
    compute_channel_distribution,
    compute_heatmap,
    compute_kpis,
    compute_trends,
)
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import PaymentChannel, TransactionStatus
from apps.transactions.models import Transaction


@pytest.mark.django_db
class TestAnalyticsServices:
    def test_kpi_computation_exact_fixture(self, merchant_user):
        """
        Hand-computed test fixture:
        1. Accepted: 1000.00 DZD, CIB
        2. Accepted: 2000.00 DZD, EDAHABIA
        3. Rejected: 500.00 DZD, CIB
        4. Cancelled: 300.00 DZD, EDAHABIA (excluded from success rate)
        5. Refunded: 400.00 DZD (refunded_amount=400.00), CIB

        Expected Hand-Computed values:
        - total_transactions = 5
        - accepted_count = 2
        - rejected_count = 1
        - cancelled_count = 1
        - refunded_count = 1
        - accepted_amount = 3000.00
        - rejected_amount = 500.00
        - refunded_amount = 400.00
        - net_revenue = 3000.00 - 400.00 = 2600.00
        - success_rate = 2 / (2 + 1) * 100 = 66.67 %
        - rejection_rate = 100 - 66.67 = 33.33 %
        - avg_ticket = 3000.00 / 2 = 1500.00
        """
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)

        Transaction.objects.create(
            reference="TX-TEST-01",
            merchant=merchant,
            transaction_date=now - timedelta(days=2),
            amount=Decimal("1000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )
        Transaction.objects.create(
            reference="TX-TEST-02",
            merchant=merchant,
            transaction_date=now - timedelta(days=2),
            amount=Decimal("2000.00"),
            payment_channel=PaymentChannel.EDAHABIA,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )
        Transaction.objects.create(
            reference="TX-TEST-03",
            merchant=merchant,
            transaction_date=now - timedelta(days=2),
            amount=Decimal("500.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.REJECTED,
            merchant_category=merchant.merchant_category,
        )
        Transaction.objects.create(
            reference="TX-TEST-04",
            merchant=merchant,
            transaction_date=now - timedelta(days=2),
            amount=Decimal("300.00"),
            payment_channel=PaymentChannel.EDAHABIA,
            transaction_status=TransactionStatus.CANCELLED,
            merchant_category=merchant.merchant_category,
        )
        Transaction.objects.create(
            reference="TX-TEST-05",
            merchant=merchant,
            transaction_date=now - timedelta(days=2),
            amount=Decimal("400.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.REFUNDED,
            refunded_amount=Decimal("400.00"),
            merchant_category=merchant.merchant_category,
        )

        kpis = compute_kpis(merchant.transactions.all())

        assert kpis["total_transactions"] == 5
        assert kpis["accepted_count"] == 2
        assert kpis["rejected_count"] == 1
        assert kpis["cancelled_count"] == 1
        assert kpis["refunded_count"] == 1
        assert kpis["accepted_amount"] == Decimal("3000.00")
        assert kpis["rejected_amount"] == Decimal("500.00")
        assert kpis["refunded_amount"] == Decimal("400.00")
        assert kpis["net_revenue"] == Decimal("2600.00")
        assert kpis["success_rate"] == 66.67
        assert kpis["rejection_rate"] == 33.33
        assert kpis["avg_ticket"] == Decimal("1500.00")

    def test_zero_denominator_edge_cases(self, merchant_user):
        """When 0 transactions, rates and averages should return 0 without division by zero."""
        kpis = compute_kpis(merchant_user.merchant.transactions.none())
        assert kpis["total_transactions"] == 0
        assert kpis["accepted_amount"] == Decimal("0.00")
        assert kpis["net_revenue"] == Decimal("0.00")
        assert kpis["success_rate"] == 0.0
        assert kpis["rejection_rate"] == 0.0
        assert kpis["avg_ticket"] == Decimal("0.00")

    def test_comparison_with_zero_previous_period(self):
        """When previous period is 0, delta_pct must be None (not divide by zero)."""
        curr = {
            "total_transactions": 10,
            "accepted_count": 8,
            "rejected_count": 2,
            "accepted_amount": Decimal("15000.00"),
            "rejected_amount": Decimal("2000.00"),
            "net_revenue": Decimal("15000.00"),
            "success_rate": 80.0,
            "rejection_rate": 20.0,
            "avg_ticket": Decimal("1875.00"),
        }
        prev = {
            "total_transactions": 0,
            "accepted_count": 0,
            "rejected_count": 0,
            "accepted_amount": Decimal("0.00"),
            "rejected_amount": Decimal("0.00"),
            "net_revenue": Decimal("0.00"),
            "success_rate": 0.0,
            "rejection_rate": 0.0,
            "avg_ticket": Decimal("0.00"),
        }
        cmp = compare_kpis(curr, prev)
        assert cmp["net_revenue"]["current"] == Decimal("15000.00")
        assert cmp["net_revenue"]["previous"] == Decimal("0.00")
        assert cmp["net_revenue"]["delta_abs"] == Decimal("15000.00")
        assert cmp["net_revenue"]["delta_pct"] is None  # Safe handling of zero previous

    def test_channel_distribution(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        Transaction.objects.create(
            reference="TX-CIB-1",
            merchant=merchant,
            transaction_date=now,
            amount=Decimal("3000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )
        Transaction.objects.create(
            reference="TX-EDAHABIA-1",
            merchant=merchant,
            transaction_date=now,
            amount=Decimal("1000.00"),
            payment_channel=PaymentChannel.EDAHABIA,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )
        dist = compute_channel_distribution(merchant.transactions.all())
        assert dist["total_count"] == 2
        assert dist["total_accepted_amount"] == Decimal("4000.00")
        cib = next(c for c in dist["channels"] if c["channel"] == "CIB")
        eda = next(c for c in dist["channels"] if c["channel"] == "EDAHABIA")
        assert cib["count_pct"] == 50.0
        assert cib["amount_pct"] == 75.0
        assert eda["amount_pct"] == 25.0

    def test_compute_trends_daily_weekly_monthly(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        today = now.date()
        for i in range(10):
            Transaction.objects.create(
                reference=f"TX-TREND-{i}",
                merchant=merchant,
                transaction_date=now - timedelta(days=i),
                amount=Decimal("1500.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
            )

        start = now - timedelta(days=9)
        end = now
        daily_trends = compute_trends(merchant.transactions.all(), start, end, granularity="day")
        assert len(daily_trends) >= 10
        weekly_trends = compute_trends(merchant.transactions.all(), start, end, granularity="week")
        assert len(weekly_trends) >= 1
        monthly_trends = compute_trends(merchant.transactions.all(), start, end, granularity="month")
        assert len(monthly_trends) >= 1

    def test_compute_heatmap_matrix_and_peaks(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        for h in range(8, 20):
            Transaction.objects.create(
                reference=f"TX-HEAT-{h}",
                merchant=merchant,
                transaction_date=datetime.combine(now.date(), time(h, 30), tzinfo=ALGIERS_TZ),
                amount=Decimal("1000.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
            )
        heatmap = compute_heatmap(merchant.transactions.all())
        assert len(heatmap["matrix"]) == 7
        assert len(heatmap["matrix"][0]) == 24
        assert "peak_slot" in heatmap
        assert "low_slot" in heatmap
        assert len(heatmap["top_3_hours"]) == 3
        assert len(heatmap["top_3_weekdays"]) == 3

    def test_merchant_analytics_api(self, api_client, merchant_user):
        """Test GET /api/v1/merchant/analytics/ with preset and granularity."""
        api_client.force_authenticate(user=merchant_user)
        res = api_client.get("/api/v1/merchant/analytics/?preset=30d&granularity=daily")
        assert res.status_code == 200
        assert "trends" in res.data
        assert "channel_distribution" in res.data
        assert "heatmap" in res.data
        assert "matrix" in res.data["heatmap"]

    def test_admin_analytics_api(self, api_client, admin_user):
        """Test GET /api/v1/admin/analytics/ with 4 pillars."""
        api_client.force_authenticate(user=admin_user)
        res = api_client.get("/api/v1/admin/analytics/?preset=30d&granularity=day")
        assert res.status_code == 200
        assert "overview" in res.data
        assert "temporal" in res.data
        assert "merchants_analysis" in res.data
        assert "transactions_analysis" in res.data
