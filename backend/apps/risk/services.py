from datetime import datetime, timedelta

from django.utils import timezone

from apps.core.enums import RiskLevel, RiskStatus
from apps.risk.models import RiskFlag
from apps.risk.rules import (
    check_rule_amount_high,
    check_rule_frequency_abnormal,
    check_rule_history_deviation,
    check_rule_rejection_spike,
    check_rule_velocity,
    compute_merchant_baseline_stats,
)


def determine_risk_level(score: int) -> str:
    if score >= 70:
        return RiskLevel.HIGH
    elif score >= 40:
        return RiskLevel.MEDIUM
    return RiskLevel.LOW


def scan_merchant_risk(merchant, now: datetime | None = None) -> list[RiskFlag]:
    """
    Evaluates explainable fraud/risk rules for the merchant over a rolling window.
    Only creates a RiskFlag when score >= 40.
    """
    now = now or timezone.now()
    baseline = compute_merchant_baseline_stats(merchant)
    created_flags = []

    # Window for velocity and recent activity
    window_start = now - timedelta(hours=2)
    window_end = now

    # 1. Global merchant-level checks
    velocity_res = check_rule_velocity(merchant, window_start, window_end)
    rej_res = check_rule_rejection_spike(merchant, now)
    freq_res = check_rule_frequency_abnormal(merchant, now)
    dev_res = check_rule_history_deviation(merchant, now)

    # 2. Check recent suspicious transactions (last 2 hours)
    recent_txs = merchant.transactions.filter(
        transaction_date__gte=window_start,
        transaction_date__lte=window_end,
    ).order_by("-transaction_date")[:50]

    # Check each recent transaction for specific transaction-level risk (e.g. high amount)
    for tx in recent_txs:
        amt_res = check_rule_amount_high(tx, baseline)

        # Combine rules that apply to this transaction or burst
        triggered = []
        reasons = []
        total_weight = 0

        if amt_res["triggered"]:
            triggered.append(amt_res)
            reasons.extend(amt_res["reasons"])
            total_weight += amt_res["weight"]

        if velocity_res["triggered"]:
            triggered.append(velocity_res)
            reasons.extend(velocity_res["reasons"])
            total_weight += velocity_res["weight"]

        if freq_res["triggered"]:
            triggered.append(freq_res)
            reasons.extend(freq_res["reasons"])
            total_weight += freq_res["weight"]

        if rej_res["triggered"]:
            triggered.append(rej_res)
            reasons.extend(rej_res["reasons"])
            total_weight += rej_res["weight"]

        if dev_res["triggered"]:
            triggered.append(dev_res)
            reasons.extend(dev_res["reasons"])
            total_weight += dev_res["weight"]

        score = min(100, total_weight)
        if score >= 40:
            level = determine_risk_level(score)
            rule_codes = "_".join(sorted(r["code"] for r in triggered))
            window_str = window_start.strftime("%Y%m%d%H%M")
            dedupe_key = f"FLAG_{merchant.id}_{window_str}_{rule_codes}"

            flag, is_new = RiskFlag.objects.get_or_create(
                merchant=merchant,
                dedupe_key=dedupe_key,
                defaults={
                    "transaction": tx,
                    "risk_score": score,
                    "risk_level": level,
                    "triggered_rules": [
                        {
                            "code": r["code"],
                            "label_fr": r["label_fr"],
                            "weight": r["weight"],
                            "observed": r["observed"],
                            "threshold": r["threshold"],
                        }
                        for r in triggered
                    ],
                    "reasons": reasons,
                    "status": RiskStatus.NEW,
                    "window_start": window_start,
                    "window_end": window_end,
                },
            )
            if is_new:
                created_flags.append(flag)
            break  # Burst represented by one comprehensive flag for the window

    # If no transaction-specific flag was created but merchant-level rules fired >= 40
    if not created_flags:
        m_triggered = []
        m_reasons = []
        m_weight = 0
        for r in [velocity_res, rej_res, freq_res, dev_res]:
            if r["triggered"]:
                m_triggered.append(r)
                m_reasons.extend(r["reasons"])
                m_weight += r["weight"]
        m_score = min(100, m_weight)
        if m_score >= 40:
            level = determine_risk_level(m_score)
            rule_codes = "_".join(sorted(r["code"] for r in m_triggered))
            date_hour = now.strftime("%Y%m%d%H")
            dedupe_key = f"FLAG_M_{merchant.id}_{date_hour}_{rule_codes}"
            flag, is_new = RiskFlag.objects.get_or_create(
                merchant=merchant,
                dedupe_key=dedupe_key,
                defaults={
                    "transaction": None,
                    "risk_score": m_score,
                    "risk_level": level,
                    "triggered_rules": [
                        {
                            "code": r["code"],
                            "label_fr": r["label_fr"],
                            "weight": r["weight"],
                            "observed": r["observed"],
                            "threshold": r["threshold"],
                        }
                        for r in m_triggered
                    ],
                    "reasons": m_reasons,
                    "status": RiskStatus.NEW,
                    "window_start": window_start,
                    "window_end": window_end,
                },
            )
            if is_new:
                created_flags.append(flag)

    return created_flags


def scan_all_merchants_risk(now: datetime | None = None) -> int:
    from apps.core.enums import MerchantStatus
    from apps.merchants.models import Merchant

    now = now or timezone.now()
    active_merchants = Merchant.objects.filter(status=MerchantStatus.ACTIVE)
    total_flags = 0
    for m in active_merchants:
        flags = scan_merchant_risk(m, now=now)
        total_flags += len(flags)
    return total_flags
