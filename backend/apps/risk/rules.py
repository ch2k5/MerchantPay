from datetime import datetime, timedelta

import numpy as np
import pandas as pd

from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    ACCEPTED_STATUSES,
    REJECTED_STATUSES,
    RiskLevel,
    TransactionStatus,
)
from apps.core.utils import format_dzd

# Risk Rule Codes
RULE_AMOUNT_HIGH = "R_AMOUNT_HIGH"
RULE_VELOCITY = "R_VELOCITY"
RULE_REJECTION_SPIKE = "R_REJECTION_SPIKE"
RULE_FREQUENCY_ABNORMAL = "R_FREQUENCY_ABNORMAL"
RULE_HISTORY_DEVIATION = "R_HISTORY_DEVIATION"


def compute_merchant_baseline_stats(merchant, fallback_category: str | None = None) -> dict:
    """
    Computes statistical baselines for merchant's accepted transactions.
    Minimum 30 historical transactions, otherwise fall back to platform category medians.
    """
    qs = merchant.transactions.filter(transaction_status__in=ACCEPTED_STATUSES).values(
        "amount", "transaction_date"
    )
    df = pd.DataFrame(list(qs))

    if len(df) >= 30:
        amounts = df["amount"].astype(float)
        mean_amt = float(amounts.mean())
        std_amt = float(amounts.std(ddof=0))
        median_amt = float(amounts.median())
    else:
        # Fallback to category or default
        from apps.transactions.models import Transaction

        cat_qs = Transaction.objects.filter(
            merchant_category=fallback_category or merchant.merchant_category,
            transaction_status__in=ACCEPTED_STATUSES,
        ).values("amount")[:500]
        cat_df = pd.DataFrame(list(cat_qs))
        if len(cat_df) > 0:
            amounts = cat_df["amount"].astype(float)
            mean_amt = float(amounts.mean())
            std_amt = float(amounts.std(ddof=0))
            median_amt = float(amounts.median())
        else:
            mean_amt = 3500.0
            std_amt = 1500.0
            median_amt = 3000.0

    return {
        "mean_amt": mean_amt,
        "std_amt": max(std_amt, 100.0),
        "median_amt": max(median_amt, 500.0),
    }


def check_rule_amount_high(tx, baseline: dict) -> dict:
    """
    R_AMOUNT_HIGH (weight 30): amount > mean + 3σ of the merchant's history OR > 5× median.
    """
    amt = float(tx.amount)
    mean = baseline["mean_amt"]
    std = baseline["std_amt"]
    median = baseline["median_amt"]
    threshold_3sigma = mean + (3 * std)
    threshold_5median = 5 * median
    threshold = min(threshold_3sigma, threshold_5median)

    triggered = (amt > threshold_3sigma) or (amt > threshold_5median)
    reasons = []
    if triggered:
        reasons.append(
            f"Le montant de la transaction ({format_dzd(tx.amount)}) est nettement supérieur "
            f"à la moyenne du commerçant ({format_dzd(mean)} en moyenne, seuil d'alerte : {format_dzd(threshold)})."
        )

    return {
        "code": RULE_AMOUNT_HIGH,
        "label_fr": "Montant anormalement élevé",
        "weight": 30,
        "observed": amt,
        "threshold": round(threshold, 2),
        "triggered": triggered,
        "reasons": reasons,
    }


def check_rule_velocity(merchant, window_start: datetime, window_end: datetime) -> dict:
    """
    R_VELOCITY (weight 35):
    >= 10 transactions within any 2-minute window for the same merchant,
    or >= 5 transactions for the same card_last4 within 5 minutes.
    """
    qs = (
        merchant.transactions.filter(
            transaction_date__gte=window_start,
            transaction_date__lte=window_end,
        )
        .order_by("transaction_date")
        .values("transaction_id", "transaction_date", "card_last4")
    )

    tx_list = list(qs)
    triggered = False
    observed_max = len(tx_list)
    reasons = []

    # Check 2-minute rolling window for merchant
    for i in range(len(tx_list)):
        t_start = tx_list[i]["transaction_date"]
        t_end = t_start + timedelta(minutes=2)
        count_in_2m = sum(1 for t in tx_list if t_start <= t["transaction_date"] <= t_end)
        if count_in_2m >= 10:
            triggered = True
            observed_max = max(observed_max, count_in_2m)
            reasons.append(
                f"La fréquence des transactions dépasse le seuil normal "
                f"({count_in_2m} transactions enregistrées en moins de 2 minutes, seuil : 10)."
            )
            break

    # Check 5-minute rolling window per card
    if not triggered and len(tx_list) >= 5:
        card_groups = {}
        for t in tx_list:
            c = t["card_last4"]
            card_groups.setdefault(c, []).append(t["transaction_date"])
        for card, dates in card_groups.items():
            if len(dates) >= 5:
                for i in range(len(dates)):
                    t_s = dates[i]
                    t_e = t_s + timedelta(minutes=5)
                    cnt = sum(1 for d in dates if t_s <= d <= t_e)
                    if cnt >= 5:
                        triggered = True
                        observed_max = max(observed_max, cnt)
                        reasons.append(
                            f"Activité répétitive anormale sur la carte finissant par {card} "
                            f"({cnt} transactions en 5 minutes, seuil : 5)."
                        )
                        break
            if triggered:
                break

    return {
        "code": RULE_VELOCITY,
        "label_fr": "Vélocité et rafale de transactions",
        "weight": 35,
        "observed": observed_max,
        "threshold": 10,
        "triggered": triggered,
        "reasons": reasons,
    }


def check_rule_rejection_spike(merchant, now: datetime) -> dict:
    """
    R_REJECTION_SPIKE (weight 20):
    rejection rate over the last 60 min >= 2× the merchant's baseline AND >= 5 rejections.
    """
    t_start = now - timedelta(minutes=60)
    qs_hour = merchant.transactions.filter(
        transaction_date__gte=t_start,
        transaction_date__lte=now,
    )
    total_hour = qs_hour.count()
    rejected_hour = qs_hour.filter(transaction_status__in=REJECTED_STATUSES).count()
    rate_hour = (rejected_hour / total_hour * 100.0) if total_hour > 0 else 0.0

    # Merchant baseline rejection rate
    hist_qs = merchant.transactions.filter(
        transaction_date__lt=t_start,
        transaction_date__gte=now - timedelta(days=30),
    )
    hist_total = hist_qs.count()
    hist_rejected = hist_qs.filter(transaction_status__in=REJECTED_STATUSES).count()
    hist_rate = (hist_rejected / hist_total * 100.0) if hist_total > 0 else 5.0
    baseline_threshold = max(hist_rate * 2.0, 15.0)

    triggered = (rejected_hour >= 5) and (rate_hour >= baseline_threshold)
    reasons = []
    if triggered:
        reasons.append(
            f"Augmentation abrupte des rejets sur la dernière heure "
            f"({rejected_hour} rejets observés, taux horaire de {rate_hour:.1f} % vs {hist_rate:.1f} % en moyenne historique)."
        )

    return {
        "code": RULE_REJECTION_SPIKE,
        "label_fr": "Pic de rejets horaire",
        "weight": 20,
        "observed": round(rate_hour, 1),
        "threshold": round(baseline_threshold, 1),
        "triggered": triggered,
        "reasons": reasons,
    }


def check_rule_frequency_abnormal(merchant, now: datetime) -> dict:
    """
    R_FREQUENCY_ABNORMAL (weight 15): hourly count z-score > 3 vs the same weekday-hour baseline.
    """
    local_now = now.astimezone(ALGIERS_TZ)
    target_hour = local_now.hour
    target_weekday = local_now.weekday()

    # Current hour count
    t_start = now - timedelta(hours=1)
    current_cnt = merchant.transactions.filter(transaction_date__gte=t_start, transaction_date__lte=now).count()

    # Historical samples for the same weekday and hour
    qs_hist = merchant.transactions.filter(
        transaction_date__gte=now - timedelta(days=60),
        transaction_date__lt=t_start,
    ).values("transaction_date")

    hour_counts = []
    daily_bins = {}
    for item in qs_hist:
        dt = item["transaction_date"].astimezone(ALGIERS_TZ)
        if dt.weekday() == target_weekday and dt.hour == target_hour:
            d_key = dt.date()
            daily_bins[d_key] = daily_bins.get(d_key, 0) + 1

    hour_counts = list(daily_bins.values())
    if len(hour_counts) >= 4:
        mean_cnt = float(np.mean(hour_counts))
        std_cnt = float(np.std(hour_counts)) or 1.0
        z_score = (current_cnt - mean_cnt) / std_cnt
    else:
        mean_cnt = 2.0
        std_cnt = 2.0
        z_score = (current_cnt - mean_cnt) / std_cnt

    triggered = z_score > 3.0 and current_cnt >= 8
    reasons = []
    if triggered:
        reasons.append(
            f"Volume horaire inhabituel (Z-Score : {z_score:.1f} > 3, "
            f"{current_cnt} transactions observées contre {mean_cnt:.1f} habituellement à cette heure)."
        )

    return {
        "code": RULE_FREQUENCY_ABNORMAL,
        "label_fr": "Fréquence inhabituelle (Z-Score > 3)",
        "weight": 15,
        "observed": round(z_score, 2),
        "threshold": 3.0,
        "triggered": triggered,
        "reasons": reasons,
    }


def check_rule_history_deviation(merchant, now: datetime) -> dict:
    """
    R_HISTORY_DEVIATION (weight 15): daily revenue deviates > 3σ from the 30-day mean.
    """
    today_start = datetime.combine(now.astimezone(ALGIERS_TZ).date(), datetime.min.time(), tzinfo=ALGIERS_TZ)
    today_revenue_qs = merchant.transactions.filter(
        transaction_date__gte=today_start,
        transaction_date__lte=now,
        transaction_status__in=ACCEPTED_STATUSES,
    ).values("amount")

    today_rev = float(sum(item["amount"] for item in today_revenue_qs))

    # Daily revenues over past 30 days
    past_start = today_start - timedelta(days=30)
    past_txs = merchant.transactions.filter(
        transaction_date__gte=past_start,
        transaction_date__lt=today_start,
        transaction_status__in=ACCEPTED_STATUSES,
    ).values("transaction_date", "amount")

    days_map = {}
    for item in past_txs:
        d = item["transaction_date"].astimezone(ALGIERS_TZ).date()
        days_map[d] = days_map.get(d, 0.0) + float(item["amount"])

    if len(days_map) >= 10:
        revs = list(days_map.values())
        mean_rev = float(np.mean(revs))
        std_rev = float(np.std(revs)) or 1000.0
    else:
        mean_rev = 50000.0
        std_rev = 20000.0

    threshold = mean_rev + (3 * std_rev)
    triggered = today_rev > threshold
    reasons = []
    if triggered:
        reasons.append(
            f"Chiffre d'affaires journalier en forte déviation par rapport à la moyenne "
            f"({format_dzd(today_rev)} vs {format_dzd(mean_rev)} en moyenne, écart > 3σ)."
        )

    return {
        "code": RULE_HISTORY_DEVIATION,
        "label_fr": "Déviation extrême du chiffre d'affaires",
        "weight": 15,
        "observed": round(today_rev, 2),
        "threshold": round(threshold, 2),
        "triggered": triggered,
        "reasons": reasons,
    }
