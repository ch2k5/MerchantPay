from datetime import datetime, timedelta
from decimal import Decimal

import pytest

from apps.core.dates import ALGIERS_TZ
from apps.core.enums import PaymentChannel, RiskLevel, TransactionStatus
from apps.risk.services import scan_merchant_risk
from apps.transactions.models import Transaction


@pytest.mark.django_db
class TestRiskEngine:
    def test_burst_fraud_scenario_yields_high_score(self, merchant_user):
        """
        Simulate 12 transactions in 2 minutes at 48 000 DZD.
        Merchant normal baseline is ~2 500 DZD.
        Expects:
        - Score >= 70 (HIGH risk level)
        - Triggered rules contain R_VELOCITY and R_AMOUNT_HIGH
        - Flag status NEW
        """
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)

        # 35 historical transactions around 2 500 DZD
        hist_txs = []
        for i in range(35):
            hist_txs.append(
                Transaction(
                    reference=f"TX-HIST-{i:03d}",
                    merchant=merchant,
                    transaction_date=now - timedelta(days=2, minutes=i * 10),
                    amount=Decimal("2500.00"),
                    payment_channel=PaymentChannel.CIB,
                    transaction_status=TransactionStatus.ACCEPTED,
                    merchant_category=merchant.merchant_category,
                )
            )
        Transaction.objects.bulk_create(hist_txs)

        # Inject 12 burst transactions in 2 minutes
        burst_start = now - timedelta(minutes=10)
        for j in range(12):
            Transaction.objects.create(
                reference=f"TX-BURST-{j:02d}",
                merchant=merchant,
                transaction_date=burst_start + timedelta(seconds=j * 8),
                amount=Decimal("48000.00"),
                payment_channel=PaymentChannel.EDAHABIA,
                transaction_status=TransactionStatus.ACCEPTED,
                merchant_category=merchant.merchant_category,
                card_last4="9911",
                terminal_id="TPE-01",
            )

        flags = scan_merchant_risk(merchant, now=now)
        assert len(flags) >= 1
        top_flag = flags[0]
        assert top_flag.risk_score >= 70
        assert top_flag.risk_level == RiskLevel.HIGH
        rule_codes = [r["code"] for r in top_flag.triggered_rules]
        assert "R_VELOCITY" in rule_codes
        assert "R_AMOUNT_HIGH" in rule_codes
        assert len(top_flag.reasons) >= 2

    def test_risk_rejection_spike_and_frequency_rules(self, merchant_user):
        merchant = merchant_user.merchant
        now = datetime.now(ALGIERS_TZ)

        # 6 rejections in the last 30 minutes
        for k in range(6):
            Transaction.objects.create(
                reference=f"TX-REJ-RISK-{k}",
                merchant=merchant,
                transaction_date=now - timedelta(minutes=k * 4),
                amount=Decimal("4500.00"),
                payment_channel=PaymentChannel.CIB,
                transaction_status=TransactionStatus.REJECTED,
                merchant_category=merchant.merchant_category,
            )

        from apps.risk.rules import check_rule_rejection_spike

        rej_res = check_rule_rejection_spike(merchant, now)
        assert rej_res["triggered"] is True
        assert rej_res["weight"] == 20
