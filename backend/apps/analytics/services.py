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
from apps.core.enums import PaymentChannel, TransactionStatus


def compute_kpis(queryset) -> dict:
    """
    Computes single-period KPIs over the given queryset according to Section 5.
    Pure function, zero float usage for money.
    """
    agg = queryset.aggregate(
        total_tx=Count("transaction_id"),
        accepted_cnt=Count(
            Case(When(transaction_status=TransactionStatus.ACCEPTED, then=1), output_field=IntegerField())
        ),
        rejected_cnt=Count(
            Case(When(transaction_status=TransactionStatus.REJECTED, then=1), output_field=IntegerField())
        ),
        cancelled_cnt=Count(
            Case(When(transaction_status=TransactionStatus.CANCELLED, then=1), output_field=IntegerField())
        ),
        refunded_cnt=Count(
            Case(When(transaction_status=TransactionStatus.REFUNDED, then=1), output_field=IntegerField())
        ),
        accepted_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status=TransactionStatus.ACCEPTED, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        rejected_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status=TransactionStatus.REJECTED, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        cancelled_amt=Coalesce(
            Sum(
                Case(
                    When(transaction_status=TransactionStatus.CANCELLED, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
        refunded_amt=Coalesce(
            Sum(
                Case(
                    When(
                        transaction_status=TransactionStatus.REFUNDED,
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
    Computes CIB and EDAHABIA breakdown (count, accepted amount, and percentages).
    """
    channels = [PaymentChannel.CIB, PaymentChannel.EDAHABIA]
    dist = {}
    total_count = 0
    total_accepted_amount = Decimal("0.00")

    raw_agg = queryset.values("payment_channel").annotate(
        count=Count("transaction_id"),
        accepted_sum=Coalesce(
            Sum(
                Case(
                    When(transaction_status=TransactionStatus.ACCEPTED, then=F("amount")),
                    output_field=DecimalField(),
                )
            ),
            Decimal("0.00"),
        ),
    )

    by_channel = {item["payment_channel"]: item for item in raw_agg}

    for ch in channels:
        item = by_channel.get(ch, {"count": 0, "accepted_sum": Decimal("0.00")})
        c = item["count"]
        amt = item["accepted_sum"]
        dist[ch] = {
            "channel": ch,
            "label": "Carte CIB" if ch == PaymentChannel.CIB else "Carte EDAHABIA",
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


def compare_kpis(current_kpis: dict, previous_kpis: dict) -> dict:
    """
    Produces comparison deltas: current, previous, delta_abs, delta_pct (null if previous == 0).
    """
    comparison = {}
    keys = [
        "total_transactions",
        "accepted_count",
        "rejected_count",
        "accepted_amount",
        "rejected_amount",
        "net_revenue",
        "success_rate",
        "rejection_rate",
        "avg_ticket",
    ]

    for key in keys:
        curr = current_kpis.get(key, 0)
        prev = previous_kpis.get(key, 0)

        if isinstance(curr, Decimal) or isinstance(prev, Decimal):
            curr_dec = Decimal(str(curr))
            prev_dec = Decimal(str(prev))
            delta_abs = curr_dec - prev_dec
            delta_pct = None
            if prev_dec != 0:
                delta_pct = round(float((delta_abs / prev_dec) * 100), 2)
        else:
            curr_float = float(curr)
            prev_float = float(prev)
            delta_abs = round(curr_float - prev_float, 2)
            delta_pct = None
            if prev_float != 0:
                delta_pct = round((delta_abs / prev_float) * 100, 2)

        comparison[key] = {
            "current": curr,
            "previous": prev,
            "delta_abs": delta_abs,
            "delta_pct": delta_pct,
        }

    return comparison


def compute_trends(queryset, date_from: datetime, date_to: datetime, granularity: str = "day") -> list[dict]:
    """
    Groups accepted revenue and counts by day / week / month with zero-filled gaps.
    Dates are handled in Africa/Algiers timezone.
    """
    granularity = granularity.lower()
    if granularity == "week":
        trunc_fn = TruncWeek
        step = timedelta(weeks=1)
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
                Case(When(transaction_status=TransactionStatus.ACCEPTED, then=1), output_field=IntegerField())
            ),
            rejected_count=Count(
                Case(When(transaction_status=TransactionStatus.REJECTED, then=1), output_field=IntegerField())
            ),
            revenue=Coalesce(
                Sum(
                    Case(
                        When(transaction_status=TransactionStatus.ACCEPTED, then=F("amount")),
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
            # next month
            year = current_dt.year + (current_dt.month // 12)
            month = (current_dt.month % 12) + 1
            current_dt = current_dt.replace(year=year, month=month, day=1)

    return series


def compute_heatmap(queryset) -> dict:
    """
    7 (weekday) × 24 (hour) matrix of accepted transaction counts.
    Algeria week: Sunday (index 0 or 6). We map 0=Dimanche, 1=Lundi, ..., 6=Samedi.
    Identifies peak and low slots (low counts hours inside typical opening time, 08:00–22:00).
    """
    # Initialize 7x24 matrix with 0
    # days: 0=Dimanche, 1=Lundi, 2=Mardi, 3=Mercredi, 4=Jeudi, 5=Vendredi, 6=Samedi
    day_names = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
    matrix = [[0 for _ in range(24)] for _ in range(7)]

    # Filter to ACCEPTED
    accepted_txs = queryset.filter(transaction_status=TransactionStatus.ACCEPTED)

    # Use python iteration over values_list for exact tzinfo hour & weekday
    for tx_dt in accepted_txs.values_list("transaction_date", flat=True).iterator():
        local_dt = tx_dt.astimezone(ALGIERS_TZ)
        # Python weekday: Mon=0, ..., Sat=5, Sun=6.
        # Map so Sunday is index 0: (weekday + 1) % 7
        weekday_idx = (local_dt.weekday() + 1) % 7
        hour_idx = local_dt.hour
        matrix[weekday_idx][hour_idx] += 1

    # Find peak slot
    max_val = -1
    peak_slot = {"day": "Dimanche", "hour": 12, "count": 0}
    # Low slot inside 08:00 - 22:00
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

    # Hourly and weekday summaries
    hourly_totals = [sum(matrix[d][h] for d in range(7)) for h in range(24)]
    weekday_totals = [sum(matrix[d]) for d in range(7)]

    # Top 3 hours and top 3 weekdays
    sorted_hours = sorted(range(24), key=lambda h: hourly_totals[h], reverse=True)
    sorted_days = sorted(range(7), key=lambda d: weekday_totals[d], reverse=True)

    top_3_hours = [
        {"hour": h, "label": f"{h:02d}h00 - {(h + 1):02d}h00", "count": hourly_totals[h]} for h in sorted_hours[:3]
    ]
    top_3_weekdays = [{"day": day_names[d], "day_idx": d, "count": weekday_totals[d]} for d in sorted_days[:3]]
    low_3_hours = [
        {"hour": h, "label": f"{h:02d}h00 - {(h + 1):02d}h00", "count": hourly_totals[h]} for h in sorted_hours[-3:]
    ]

    return {
        "matrix": matrix,
        "day_names": day_names,
        "peak_slot": peak_slot,
        "low_slot": low_slot,
        "top_3_hours": top_3_hours,
        "top_3_weekdays": top_3_weekdays,
        "low_3_hours": low_3_hours,
    }
