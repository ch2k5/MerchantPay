from datetime import datetime, timedelta
from decimal import Decimal

from django.db.models import (
    Case,
    Count,
    DecimalField,
    F,
    IntegerField,
    Sum,
    When,
)
from django.db.models.functions import Coalesce, TruncDate, TruncMonth, TruncWeek

from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    ACCEPTED_STATUSES,
    CANCELLED_STATUSES,
    REFUNDED_STATUSES,
    REJECTED_STATUSES,
    PaymentChannel,
)


def compute_kpis(queryset) -> dict:
    """
    Computes single-period KPIs over the given queryset according to Section 5.
    Pure function, zero float usage for money.
    """
    agg = queryset.aggregate(
        total_tx=Count("transaction_id"),
        accepted_cnt=Count(
            Case(When(transaction_status__in=ACCEPTED_STATUSES, then=1), output_field=IntegerField())
        ),
        rejected_cnt=Count(
            Case(When(transaction_status__in=REJECTED_STATUSES, then=1), output_field=IntegerField())
        ),
        cancelled_cnt=Count(
            Case(When(transaction_status__in=CANCELLED_STATUSES, then=1), output_field=IntegerField())
        ),
        refunded_cnt=Count(
            Case(When(transaction_status__in=REFUNDED_STATUSES, then=1), output_field=IntegerField())
        ),
        accepted_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status__in=ACCEPTED_STATUSES, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        rejected_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status__in=REJECTED_STATUSES, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        cancelled_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status__in=CANCELLED_STATUSES, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        refunded_amt=Coalesce(
            Sum(
                Case(
                    When(
                        transaction_status__in=REFUNDED_STATUSES,
                        then=Coalesce(F("refunded_amount"), F("amount")),
                    ),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
    )

    total_transactions = agg["total_tx"]
    accepted_count = agg["accepted_cnt"]
    rejected_count = agg["rejected_cnt"]
    cancelled_count = agg["cancelled_cnt"]
    refunded_count = agg["refunded_cnt"]

    accepted_amount = agg["accepted_amt"]
    rejected_amount = agg["rejected_amt"]
    cancelled_amount = agg["cancelled_amt"]
    refunded_amount = agg["refunded_amt"]

    net_revenue = accepted_amount - refunded_amount

    # Success rate: accepted_count / (accepted_count + rejected_count) * 100
    valid_denominator = accepted_count + rejected_count
    if valid_denominator > 0:
        success_rate = round((accepted_count / valid_denominator) * 100, 2)
        rejection_rate = round(100.0 - success_rate, 2)
    else:
        success_rate = 0.0
        rejection_rate = 0.0

    if accepted_count > 0:
        avg_ticket = round(accepted_amount / Decimal(str(accepted_count)), 2)
    else:
        avg_ticket = Decimal("0.00")

    return {
        "total_transactions": total_transactions,
        "accepted_count": accepted_count,
        "rejected_count": rejected_count,
        "cancelled_count": cancelled_count,
        "refunded_count": refunded_count,
        "accepted_amount": accepted_amount,
        "rejected_amount": rejected_amount,
        "cancelled_amount": cancelled_amount,
        "refunded_amount": refunded_amount,
        "net_revenue": net_revenue,
        "success_rate": success_rate,
        "rejection_rate": rejection_rate,
        "avg_ticket": avg_ticket,
    }


def compute_channel_distribution(queryset) -> dict:
    """
    Computes breakdown across payment channels (count, accepted amount, and percentages).
    Dynamically supports CIB/EDAHABIA as well as POS, Mobile App, Contactless, Bank Transfer, E-commerce.
    """
    raw_agg = queryset.values("payment_channel").annotate(
        count=Count("transaction_id"),
        accepted_sum=Coalesce(
            Sum(
                Case(
                    When(transaction_status__in=ACCEPTED_STATUSES, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
    )

    by_channel = {item["payment_channel"]: item for item in raw_agg}
    found_channels = list(by_channel.keys())

    if not found_channels:
        channels = [PaymentChannel.CIB, PaymentChannel.EDAHABIA]
    else:
        channels = found_channels

    dist = {}
    total_count = 0
    total_accepted_amount = Decimal("0.00")
    channel_labels = dict(PaymentChannel.choices)

    for ch in channels:
        item = by_channel.get(ch, {"count": 0, "accepted_sum": Decimal("0.00")})
        c = item["count"]
        amt = item["accepted_sum"]
        label = channel_labels.get(ch, str(ch))
        dist[ch] = {
            "channel": ch,
            "label": label,
            "count": c,
            "accepted_amount": amt,
            "count_pct": 0.0,
            "amount_pct": 0.0,
        }
        total_count += c
        total_accepted_amount += amt

    for ch in channels:
        if total_count > 0:
            dist[ch]["count_pct"] = round((dist[ch]["count"] / total_count) * 100, 2)
        if total_accepted_amount > 0:
            dist[ch]["amount_pct"] = round(float((dist[ch]["accepted_amount"] / total_accepted_amount) * 100), 2)

    return {
        "channels": list(dist.values()),
        "total_count": total_count,
        "total_accepted_amount": total_accepted_amount,
    }


def compute_payment_transactions_summary(queryset) -> dict:
    """
    Computes the exact official FINOVIA × ENSM × SATIM summary dashboard tables:
    1. Breakdown by Transaction Status (Accepted, Declined, Refunded, Cancelled, Total)
    2. Breakdown by Payment Channel (E-commerce, TPE, Mobile, Contactless, Virement, Total)
    """
    total_tx = queryset.count()

    # 1. Breakdown by Transaction Status
    status_categories = [
        ("Accepted", ACCEPTED_STATUSES),
        ("Declined", REJECTED_STATUSES),
        ("Refunded", REFUNDED_STATUSES),
        ("Cancelled", CANCELLED_STATUSES),
    ]

    status_rows = []
    tot_status_cnt = 0
    tot_status_amt = Decimal("0.00")

    for label, st_list in status_categories:
        sub_qs = queryset.filter(transaction_status__in=st_list)
        cnt = sub_qs.count()
        tot_amt = sub_qs.aggregate(s=Coalesce(Sum("amount"), Decimal("0.00")))["s"] or Decimal("0.00")
        avg_amt = round(tot_amt / Decimal(str(cnt)), 2) if cnt > 0 else Decimal("0.00")
        pct = round((cnt / total_tx * 100), 2) if total_tx > 0 else 0.0

        status_rows.append({
            "status": label,
            "count": cnt,
            "pct_of_total": pct,
            "total_amount": tot_amt,
            "avg_amount": avg_amt,
        })
        tot_status_cnt += cnt
        tot_status_amt += tot_amt

    avg_total = round(tot_status_amt / Decimal(str(tot_status_cnt)), 2) if tot_status_cnt > 0 else Decimal("0.00")
    status_summary = {
        "rows": status_rows,
        "total": {
            "status": "Total",
            "count": tot_status_cnt,
            "pct_of_total": 100.0 if tot_status_cnt > 0 else 0.0,
            "total_amount": tot_status_amt,
            "avg_amount": avg_total,
        },
    }

    # 2. Breakdown by Payment Channel
    official_channels = [
        "E-commerce (CIB / Edahabia)",
        "TPE / POS Terminal",
        "Mobile App",
        "Contactless / NFC",
        "Bank Transfer / Virement",
    ]
    extra_channels = [
        c for c in queryset.values_list("payment_channel", flat=True).distinct() if c not in official_channels
    ]
    all_channels = official_channels + extra_channels

    channel_rows = []
    tot_chan_cnt = 0
    tot_chan_amt = Decimal("0.00")

    for ch in all_channels:
        sub_qs = queryset.filter(payment_channel=ch)
        cnt = sub_qs.count()
        tot_amt = sub_qs.aggregate(s=Coalesce(Sum("amount"), Decimal("0.00")))["s"] or Decimal("0.00")
        avg_amt = round(tot_amt / Decimal(str(cnt)), 2) if cnt > 0 else Decimal("0.00")
        pct = round((cnt / total_tx * 100), 2) if total_tx > 0 else 0.0

        channel_rows.append({
            "channel": ch,
            "count": cnt,
            "pct_of_total": pct,
            "total_amount": tot_amt,
            "avg_amount": avg_amt,
        })
        tot_chan_cnt += cnt
        tot_chan_amt += tot_amt

    channel_summary = {
        "rows": channel_rows,
        "total": {
            "channel": "Total",
            "count": tot_chan_cnt,
            "pct_of_total": 100.0 if tot_chan_cnt > 0 else 0.0,
            "total_amount": tot_chan_amt,
            "avg_amount": round(tot_chan_amt / Decimal(str(tot_chan_cnt)), 2) if tot_chan_cnt > 0 else Decimal("0.00"),
        },
    }

    return {
        "breakdown_by_status": status_summary,
        "breakdown_by_channel": channel_summary,
    }


def compare_kpis(current_kpis: dict, previous_kpis: dict) -> dict:
    """
    Computes absolute and percentage deltas between current and previous period KPIs.
    """
    def _pct_delta(curr, prev):
        if prev is None or Decimal(str(prev)) == Decimal("0.00"):
            return None
        c = Decimal(str(curr))
        p = Decimal(str(prev))
        return round(float(((c - p) / p) * 100), 2)

    def _abs_delta(curr, prev):
        return Decimal(str(curr)) - Decimal(str(prev))

    c_rev = current_kpis["net_revenue"]
    p_rev = previous_kpis["net_revenue"]
    revenue_delta = _abs_delta(c_rev, p_rev)
    revenue_delta_pct = _pct_delta(c_rev, p_rev)

    c_cnt = current_kpis["accepted_count"]
    p_cnt = previous_kpis["accepted_count"]
    count_delta = c_cnt - p_cnt
    count_delta_pct = _pct_delta(c_cnt, p_cnt)

    c_sr = current_kpis["success_rate"]
    p_sr = previous_kpis["success_rate"]
    success_rate_delta_pts = round(c_sr - p_sr, 2)

    c_rr = current_kpis["rejection_rate"]
    p_rr = previous_kpis["rejection_rate"]
    rejection_rate_delta_pts = round(c_rr - p_rr, 2)

    c_avg = current_kpis["avg_ticket"]
    p_avg = previous_kpis["avg_ticket"]
    avg_ticket_delta = _abs_delta(c_avg, p_avg)
    avg_ticket_delta_pct = _pct_delta(c_avg, p_avg)

    # Opportunity cost of rejections
    rejection_loss = current_kpis["rejected_amount"]

    return {
        "net_revenue": {
            "current": c_rev,
            "previous": p_rev,
            "delta_abs": revenue_delta,
            "delta_pct": revenue_delta_pct,
        },
        "accepted_count": {
            "current": c_cnt,
            "previous": p_cnt,
            "delta_abs": count_delta,
            "delta_pct": count_delta_pct,
        },
        "success_rate": {
            "current": c_sr,
            "previous": p_sr,
            "delta_abs": success_rate_delta_pts,
            "delta_pct": None,
        },
        "avg_ticket": {
            "current": c_avg,
            "previous": p_avg,
            "delta_abs": avg_ticket_delta,
            "delta_pct": avg_ticket_delta_pct,
        },
        "revenue_delta": revenue_delta,
        "revenue_delta_pct": revenue_delta_pct,
        "count_delta": count_delta,
        "count_delta_pct": count_delta_pct,
        "success_rate_delta_pts": success_rate_delta_pts,
        "rejection_rate_delta_pts": rejection_rate_delta_pts,
        "avg_ticket_delta": avg_ticket_delta,
        "avg_ticket_delta_pct": avg_ticket_delta_pct,
        "rejection_loss": rejection_loss,
    }


def compute_trends(queryset, date_from: datetime, date_to: datetime, granularity: str = "day") -> list[dict]:
    """
    Returns zero-gap time series of accepted revenue, transaction count, rejection count.
    Granularity can be 'day', 'week', or 'month'.
    """
    if granularity == "week":
        trunc_fn = TruncWeek
        step = timedelta(days=7)
    elif granularity == "month":
        trunc_fn = TruncMonth
        step = timedelta(days=30)
    else:
        granularity = "day"
        trunc_fn = TruncDate
        step = timedelta(days=1)

    # Aggregation in ORM
    agg_qs = (
        queryset.annotate(period=trunc_fn("transaction_date", tzinfo=ALGIERS_TZ))
        .values("period")
        .annotate(
            total_count=Count("transaction_id"),
            accepted_count=Count(
                Case(When(transaction_status__in=ACCEPTED_STATUSES, then=1), output_field=IntegerField())
            ),
            rejected_count=Count(
                Case(When(transaction_status__in=REJECTED_STATUSES, then=1), output_field=IntegerField())
            ),
            revenue=Coalesce(
                Sum(
                    Case(
                        When(transaction_status__in=ACCEPTED_STATUSES, then=F("amount")),
                        output_field=DecimalField(),
                    )
                ),
                Decimal("0.00"),
            ),
        )
        .order_by("period")
    )

    agg_map = {}
    for row in agg_qs:
        p = row["period"]
        if isinstance(p, datetime):
            p_str = p.strftime("%Y-%m-%d")
        else:
            p_str = str(p)
        agg_map[p_str] = row

    # Fill gaps from date_from to date_to
    current_dt = date_from.astimezone(ALGIERS_TZ).date()
    end_dt = date_to.astimezone(ALGIERS_TZ).date()

    series = []
    while current_dt <= end_dt:
        key = current_dt.strftime("%Y-%m-%d")
        existing = agg_map.get(key)
        if existing:
            series.append(
                {
                    "date": key,
                    "label": current_dt.strftime("%d/%m"),
                    "total_count": existing["total_count"],
                    "accepted_count": existing["accepted_count"],
                    "rejected_count": existing["rejected_count"],
                    "revenue": existing["revenue"],
                }
            )
        else:
            series.append(
                {
                    "date": key,
                    "label": current_dt.strftime("%d/%m"),
                    "total_count": 0,
                    "accepted_count": 0,
                    "rejected_count": 0,
                    "revenue": Decimal("0.00"),
                }
            )

        if granularity == "day":
            current_dt += timedelta(days=1)
        elif granularity == "week":
            current_dt += timedelta(days=7)
        else:
            year = current_dt.year + (current_dt.month // 12)
            month = (current_dt.month % 12) + 1
            current_dt = current_dt.replace(year=year, month=month, day=1)

    return series


def compute_heatmap(queryset) -> dict:
    """
    7 (weekday) × 24 (hour) matrix of accepted transaction counts.
    Algeria week: Sunday (index 0). We map 0=Dimanche, 1=Lundi, ..., 6=Samedi.
    """
    day_names = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
    matrix = [[0 for _ in range(24)] for _ in range(7)]

    # Filter to ACCEPTED
    accepted_txs = queryset.filter(transaction_status__in=ACCEPTED_STATUSES)

    for tx_dt in accepted_txs.values_list("transaction_date", flat=True).iterator():
        local_dt = tx_dt.astimezone(ALGIERS_TZ)
        weekday_idx = (local_dt.weekday() + 1) % 7
        hour_idx = local_dt.hour
        matrix[weekday_idx][hour_idx] += 1

    max_val = -1
    peak_slot = {"day": "Dimanche", "hour": 12, "count": 0}
    min_val = float("inf")
    low_slot = {"day": "Dimanche", "hour": 8, "count": 0}

    for d in range(7):
        for h in range(24):
            val = matrix[d][h]
            if val > max_val:
                max_val = val
                peak_slot = {"day": day_names[d], "day_idx": d, "hour": h, "count": val}
            if 8 <= h <= 22:
                if val < min_val:
                    min_val = val
                    low_slot = {"day": day_names[d], "day_idx": d, "hour": h, "count": val}

    hourly_totals = [sum(matrix[d][h] for d in range(7)) for h in range(24)]
    weekday_totals = [sum(matrix[d]) for d in range(7)]

    sorted_hours = sorted(range(24), key=lambda h: hourly_totals[h], reverse=True)
    top_3_hours = [{"hour": h, "count": hourly_totals[h]} for h in sorted_hours[:3]]

    sorted_days = sorted(range(7), key=lambda d: weekday_totals[d], reverse=True)
    top_3_weekdays = [{"day": day_names[d], "day_idx": d, "count": weekday_totals[d]} for d in sorted_days[:3]]

    return {
        "matrix": matrix,
        "peak_slot": peak_slot,
        "low_slot": low_slot,
        "hourly_totals": hourly_totals,
        "weekday_totals": weekday_totals,
        "top_3_hours": top_3_hours,
        "top_3_weekdays": top_3_weekdays,
        "day_names": day_names,
    }
