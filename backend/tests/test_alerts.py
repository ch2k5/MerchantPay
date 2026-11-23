from datetime import datetime, time, timedelta
from decimal import Decimal

import pytest

from apps.alerts.rules import (
    GoalProgressRule,
    NoActivityRule,
    PeakActivityRule,
    RejectionSpikeRule,
    RevenueDropRule,
)
from apps.alerts.services import evaluate_merchant_alerts
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import AlertSeverity, AlertType, PaymentChannel, TransactionStatus
from apps.transactions.models import Transaction


@pytest.mark.django_db
class TestAlertRules:
    def test_revenue_drop_rule_triggers_warning_and_critical(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        today = now.date()

        # Previous 7 days: 100 000 DZD
        prev_date = datetime.combine(today - timedelta(days=9), time(12, 0), tzinfo=ALGIERS_TZ)
        Transaction.objects.create(
            reference="TX-PREV-REV",
            merchant=merchant,
            transaction_date=prev_date,
            amount=Decimal("100000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )

        # Current 7 days: 70 000 DZD (30% drop -> CRITICAL)
        curr_date = datetime.combine(today - timedelta(days=2), time(12, 0), tzinfo=ALGIERS_TZ)
        Transaction.objects.create(
            reference="TX-CURR-REV",
            merchant=merchant,
            transaction_date=curr_date,
            amount=Decimal("70000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )

        rule = RevenueDropRule()
        res = rule.evaluate(merchant, now=now)
        assert res is not None
        assert res["type"] == AlertType.REVENUE_DROP
        assert res["severity"] == AlertSeverity.CRITICAL
        assert "30 %" in res["title"]

    def test_no_activity_rule_triggers(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        old_date = now - timedelta(days=7)

        Transaction.objects.create(
            reference="TX-OLD",
            merchant=merchant,
            transaction_date=old_date,
            amount=Decimal("5000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )

        rule = NoActivityRule()
        res = rule.evaluate(merchant, now=now)
        assert res is not None
        assert res["type"] == AlertType.NO_ACTIVITY
        assert res["severity"] == AlertSeverity.CRITICAL

    def test_goal_progress_rule(self, merchant_user):
        merchant = merchant_user.merchant
        merchant.monthly_goal = Decimal("100000.00")
        merchant.save()

        now = datetime.now(ALGIERS_TZ)
        Transaction.objects.create(
            reference="TX-GOAL",
            merchant=merchant,
            transaction_date=now - timedelta(days=1),
            amount=Decimal("105000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )

        rule = GoalProgressRule()
        res = rule.evaluate(merchant, now=now)
        assert res is not None
        assert res["type"] == AlertType.GOAL_PROGRESS
        assert res["severity"] == AlertSeverity.SUCCESS

    def test_alert_deduplication(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        # Create an old transaction to trigger no activity
        Transaction.objects.create(
            reference="TX-OLD-DEDUPE",
            merchant=merchant,
            transaction_date=now - timedelta(days=8),
            amount=Decimal("2000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            merchant_category=merchant.merchant_category,
        )

        # Run evaluate twice
        alerts_run1 = evaluate_merchant_alerts(merchant, now=now)
        count_run1 = merchant.alerts.count()
        alerts_run2 = evaluate_merchant_alerts(merchant, now=now)
        count_run2 = merchant.alerts.count()

        assert count_run1 == count_run2  # Zero duplicates created!

    def test_rejection_spike_rule(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        today = now.date()

        # Prev week: 15 accepted, 1 rejected
        for i in range(15):
            Transaction.objects.create(
                reference=f"TX-PREV-ACC-{i}",
                merchant=merchant,
                transaction_date=datetime.combine(today - timedelta(days=9), time(12, i), tzinfo=ALGIERS_TZ),
                amount=Decimal("1000.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
            )
        Transaction.objects.create(
            reference="TX-PREV-REJ",
            merchant=merchant,
            transaction_date=datetime.combine(today - timedelta(days=9), time(13, 0), tzinfo=ALGIERS_TZ),
            amount=Decimal("1000.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.REJECTED,
            merchant_category=merchant.merchant_category,
        )

        # Curr week: 10 accepted, 5 rejected (33% rejection rate spike)
        for j in range(10):
            Transaction.objects.create(
                reference=f"TX-CURR-ACC-{j}",
                merchant=merchant,
                transaction_date=datetime.combine(today - timedelta(days=2), time(12, j), tzinfo=ALGIERS_TZ),
                amount=Decimal("1000.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
            )
        for k in range(5):
            Transaction.objects.create(
                reference=f"TX-CURR-REJ-{k}",
                merchant=merchant,
                transaction_date=datetime.combine(today - timedelta(days=2), time(13, k), tzinfo=ALGIERS_TZ),
                amount=Decimal("1000.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.REJECTED,
                merchant_category=merchant.merchant_category,
            )

        rule = RejectionSpikeRule()
        res = rule.evaluate(merchant, now=now)
        assert res is not None
        assert res["type"] == AlertType.REJECTION_SPIKE

    def test_peak_activity_rule(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)
        for i in range(25):
            day_offset = i % 20
            Transaction.objects.create(
                reference=f"TX-PEAK-{i}",
                merchant=merchant,
                transaction_date=now - timedelta(days=day_offset, hours=2),
                amount=Decimal("1200.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
            )
        rule = PeakActivityRule()
        res = rule.evaluate(merchant, now=now)
        assert res is not None
        assert res["type"] == AlertType.PEAK_ACTIVITY
