from datetime import datetime, timedelta
from decimal import Decimal

import pytest

from apps.core.dates import ALGIERS_TZ
from apps.core.enums import PaymentChannel, TransactionStatus
from apps.simulator.services import get_simulator_baseline, run_simulation
from apps.transactions.models import Transaction


class TestSimulatorServices:
    def test_run_simulation_positive_growth(self):
        """
        Baseline: 100 transactions, 2 000 DZD avg ticket -> 200 000 DZD baseline revenue.
        Inputs: +15% count -> 115 transactions.
        +200 DZD ticket -> 2 200 DZD avg ticket.
        Simulated revenue: 115 * 2 200 = 253 000 DZD.
        delta_abs: 53 000 DZD.
        delta_pct: 26.5 %.
        """
        res = run_simulation(
            base_count=100,
            base_avg=Decimal("2000.00"),
            growth_rate_pct=15.0,
            avg_amount_delta_dzd=Decimal("200.00"),
            monthly_goal=Decimal("250000.00"),
            period="month",
        )

        assert res["baseline"]["count"] == 100
        assert res["baseline"]["revenue"] == Decimal("200000.00")
        assert res["simulated"]["count"] == 115
        assert res["simulated"]["avg_ticket"] == Decimal("2200.00")
        assert res["simulated"]["revenue"] == Decimal("253000.00")
        assert res["delta_abs"] == Decimal("53000.00")
        assert res["delta_pct"] == 26.5
        assert res["goal_impact"]["goal_reached"] is True
        assert len(res["series"]) == 12

    def test_run_simulation_zero_baseline(self):
        """Zero transactions baseline should not crash or divide by zero."""
        res = run_simulation(
            base_count=0,
            base_avg=Decimal("0.00"),
            growth_rate_pct=10.0,
            avg_amount_delta_dzd=Decimal("500.00"),
            monthly_goal=Decimal("100000.00"),
        )
        assert res["baseline"]["count"] == 0
        assert res["simulated"]["count"] == 0
        assert res["delta_abs"] == Decimal("0.00")
        assert res["delta_pct"] is None

    def test_run_simulation_negative_delta(self):
        """Simulated avg ticket should not fall below 0."""
        res = run_simulation(
            base_count=50,
            base_avg=Decimal("1000.00"),
            growth_rate_pct=-20.0,
            avg_amount_delta_dzd=Decimal("-1500.00"),  # exceeds base_avg
        )
        assert res["simulated"]["count"] == 40
        assert res["simulated"]["avg_ticket"] == Decimal("0.00")
        assert res["simulated"]["revenue"] == Decimal("0.00")
        assert res["delta_abs"] == Decimal("-50000.00")

    @pytest.mark.django_db
    def test_get_simulator_baseline_service(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        Transaction.objects.create(
            reference="TX-BASE-1",
            merchant=merchant,
            transaction_date=now - timedelta(days=5),
            amount=Decimal("3000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )
        base = get_simulator_baseline(merchant, now=now)
        assert base["base_count"] == 1
        assert base["base_revenue"] == Decimal("3000.00")
        assert base["base_avg"] == Decimal("3000.00")

    @pytest.mark.django_db
    def test_simulator_api_with_volume_pct_and_ticket_delta(self, api_client, merchant_user):
        """Test POST /api/v1/merchant/simulator/ accepts volume_pct and ticket_delta aliases."""
        api_client.force_authenticate(user=merchant_user)
        payload = {
            "volume_pct": 20.0,
            "ticket_delta": 500.0,
        }
        res = api_client.post("/api/v1/merchant/simulator/", data=payload, format="json")
        assert res.status_code == 200
        assert "baseline_kpis" in res.data
        assert "simulated_kpis" in res.data
        assert "deltas" in res.data
        assert "projections" in res.data
