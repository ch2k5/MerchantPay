from datetime import date, datetime, timedelta
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
    MerchantStatus,
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
    if granularity in ["week", "weekly"]:
        granularity = "week"
        trunc_fn = TruncWeek
    elif granularity in ["month", "monthly"]:
        granularity = "month"
        trunc_fn = TruncMonth
    else:
        granularity = "day"
        trunc_fn = TruncDate

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
            cancelled_count=Count(
                Case(When(transaction_status__in=CANCELLED_STATUSES, then=1), output_field=IntegerField())
            ),
            refunded_count=Count(
                Case(When(transaction_status__in=REFUNDED_STATUSES, then=1), output_field=IntegerField())
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
            p_str = p.astimezone(ALGIERS_TZ).strftime("%Y-%m-%d") if p.tzinfo else p.strftime("%Y-%m-%d")
        elif isinstance(p, date):
            p_str = p.strftime("%Y-%m-%d")
        else:
            p_str = str(p)[:10]
        agg_map[p_str] = row

    # Fill gaps from date_from to date_to
    current_dt = date_from.astimezone(ALGIERS_TZ).date()
    end_dt = date_to.astimezone(ALGIERS_TZ).date()

    if granularity == "week":
        # Align to Monday of week (ISO weekday 1, Python weekday() == 0)
        current_dt = current_dt - timedelta(days=current_dt.weekday())
    elif granularity == "month":
        # Align to the 1st of month
        current_dt = current_dt.replace(day=1)

    series = []
    while current_dt <= end_dt:
        key = current_dt.strftime("%Y-%m-%d")
        existing = agg_map.get(key)

        if granularity == "week":
            label = f"S{current_dt.isocalendar()[1]} ({current_dt.strftime('%d/%m')})"
        elif granularity == "month":
            label = current_dt.strftime("%m/%Y")
        else:
            label = current_dt.strftime("%d/%m")

        rev = existing["revenue"] if existing else Decimal("0.00")
        tot = existing["total_count"] if existing else 0
        acc = existing["accepted_count"] if existing else 0
        rej = existing["rejected_count"] if existing else 0
        can = existing["cancelled_count"] if existing else 0
        ref = existing["refunded_count"] if existing else 0

        series.append(
            {
                "date": key,
                "label": label,
                "period_label": label,
                "total_count": tot,
                "accepted_count": acc,
                "rejected_count": rej,
                "cancelled_count": can,
                "refunded_count": ref,
                "revenue": rev,
                "net_revenue": rev,
                "volume": rev,
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


def compute_admin_platform_analytics(
    queryset,
    prev_queryset=None,
    date_from=None,
    date_to=None,
    granularity="day",
) -> dict:
    """
    Consolidated enterprise-grade analytics engine for SATIM Administrators.
    Calculates 4 core pillars:
    1. Vue d'ensemble (Totals, Volume, Rates, Comparison)
    2. Analyse temporelle (Trends, Peak slots, Heatmap matrix)
    3. Analyse des commerçants (Ranking, Category breakdown, Anomaly detection)
    4. Analyse des transactions (Status distribution, Channel distribution, Amount brackets, Rejection patterns)
    """
    total_tx = queryset.count()
    kpis_curr = compute_kpis(queryset)

    # 1. Comparison with previous period
    comparison = {}
    if prev_queryset is not None:
        kpis_prev = compute_kpis(prev_queryset)
        comparison = compare_kpis(kpis_curr, kpis_prev)

    # Active merchants
    from apps.merchants.models import Merchant
    total_merchants_count = Merchant.objects.count()
    active_merchants_count = Merchant.objects.filter(status=MerchantStatus.ACTIVE).count()

    overview = {
        "total_volume": kpis_curr["accepted_amount"],
        "net_revenue": kpis_curr["net_revenue"],
        "total_transactions": kpis_curr["total_transactions"],
        "accepted_count": kpis_curr["accepted_count"],
        "rejected_count": kpis_curr["rejected_count"],
        "refunded_count": kpis_curr["refunded_count"],
        "cancelled_count": kpis_curr["cancelled_count"],
        "success_rate": kpis_curr["success_rate"],
        "rejection_rate": kpis_curr["rejection_rate"],
        "avg_ticket": kpis_curr["avg_ticket"],
        "active_merchants": active_merchants_count,
        "total_merchants": total_merchants_count,
        "comparison": comparison,
    }

    # 2. Analyse temporelle
    if date_from and date_to:
        trends = compute_trends(queryset, date_from, date_to, granularity=granularity)
    else:
        # default to 30 days window
        now = timezone.now().astimezone(ALGIERS_TZ)
        d_from = now - timedelta(days=30)
        trends = compute_trends(queryset, d_from, now, granularity=granularity)

    heatmap_res = compute_heatmap(queryset)
    day_names = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
    matrix_2d = heatmap_res.get("matrix", [[0] * 24 for _ in range(7)])

    # Flat cells for UI
    flat_matrix = []
    for d in range(7):
        for h in range(24):
            flat_matrix.append({
                "day_index": d,
                "day_name": day_names[d],
                "hour": h,
                "count": matrix_2d[d][h] if d < len(matrix_2d) and h < len(matrix_2d[d]) else 0,
            })

    peak_slot = heatmap_res.get("peak_slot") or {"day": "Dimanche", "day_name": "Dimanche", "hour": 12, "count": 0}
    if "day_name" not in peak_slot:
        peak_slot["day_name"] = peak_slot.get("day", "Dimanche")

    low_slot = heatmap_res.get("low_slot") or {"day": "Dimanche", "day_name": "Dimanche", "hour": 8, "count": 0}
    if "day_name" not in low_slot:
        low_slot["day_name"] = low_slot.get("day", "Dimanche")

    temporal = {
        "granularity": granularity,
        "trends": trends,
        "heatmap": {
            "matrix": flat_matrix,
            "matrix_2d": matrix_2d,
            "peak_slot": peak_slot,
            "low_slot": low_slot,
            "top_3_hours": heatmap_res.get("top_3_hours", []),
            "top_3_weekdays": heatmap_res.get("top_3_weekdays", []),
            "hourly_totals": heatmap_res.get("hourly_totals", []),
            "weekday_totals": heatmap_res.get("weekday_totals", []),
        },
    }

    # 3. Analyse des commerçants
    merchants_agg = (
        Merchant.objects.filter(transactions__in=queryset)
        .annotate(
            total_tx=Count("transactions__transaction_id"),
            accepted_tx=Count(
                Case(When(transactions__transaction_status__in=ACCEPTED_STATUSES, then=1), output_field=IntegerField())
            ),
            rejected_tx=Count(
                Case(When(transactions__transaction_status__in=REJECTED_STATUSES, then=1), output_field=IntegerField())
            ),
            volume=Coalesce(
                Sum(
                    Case(
                        When(transactions__transaction_status__in=ACCEPTED_STATUSES, then=F("transactions__amount")),
                        output_field=DecimalField(),
                    )
                ),
                Decimal("0.00"),
            ),
        )
        .distinct()
    )

    top_volume_merchants = []
    for m in merchants_agg.order_by("-volume")[:10]:
        tot = m.total_tx
        rej = m.rejected_tx
        acc = m.accepted_tx
        rate = round((acc / tot * 100), 2) if tot > 0 else 0.0
        rej_rate = round((rej / tot * 100), 2) if tot > 0 else 0.0
        top_volume_merchants.append({
            "id": str(m.id),
            "code": m.merchant_code,
            "name": m.business_name,
            "category": m.merchant_category,
            "wilaya": m.wilaya,
            "volume": m.volume,
            "tx_count": tot,
            "success_rate": rate,
            "rejection_rate": rej_rate,
        })

    # Top by rejection count
    top_rejection_merchants = []
    for m in merchants_agg.filter(rejected_tx__gt=0).order_by("-rejected_tx")[:10]:
        tot = m.total_tx
        rej = m.rejected_tx
        rej_rate = round((rej / tot * 100), 2) if tot > 0 else 0.0
        top_rejection_merchants.append({
            "id": str(m.id),
            "code": m.merchant_code,
            "name": m.business_name,
            "category": m.merchant_category,
            "wilaya": m.wilaya,
            "rejected_count": rej,
            "total_count": tot,
            "rejection_rate": rej_rate,
        })

    # Category performance
    categories_agg = (
        queryset.values("merchant_category")
        .annotate(
            total_count=Count("transaction_id"),
            accepted_count=Count(
                Case(When(transaction_status__in=ACCEPTED_STATUSES, then=1), output_field=IntegerField())
            ),
            rejected_count=Count(
                Case(When(transaction_status__in=REJECTED_STATUSES, then=1), output_field=IntegerField())
            ),
            total_amount=Coalesce(
                Sum(
                    Case(
                        When(transaction_status__in=ACCEPTED_STATUSES, then=F("amount")),
                        output_field=DecimalField(),
                    )
                ),
                Decimal("0.00"),
            ),
        )
        .order_by("-total_amount")
    )

    total_accepted_volume = kpis_curr["accepted_amount"]
    category_performance = []
    for c in categories_agg:
        cat_name = c["merchant_category"] or "Non catégorisé"
        c_tot = c["total_count"]
        c_acc = c["accepted_count"]
        c_rej = c["rejected_count"]
        c_vol = c["total_amount"]
        avg = round(c_vol / Decimal(str(c_acc)), 2) if c_acc > 0 else Decimal("0.00")
        rej_rate = round((c_rej / c_tot * 100), 2) if c_tot > 0 else 0.0
        share_pct = round(float((c_vol / total_accepted_volume) * 100), 2) if total_accepted_volume > Decimal("0.00") else 0.0

        category_performance.append({
            "category": cat_name,
            "total_count": c_tot,
            "accepted_count": c_acc,
            "rejected_count": c_rej,
            "volume": c_vol,
            "avg_ticket": avg,
            "rejection_rate": rej_rate,
            "share_pct": share_pct,
        })

    # Anomalous merchants (e.g. rejection rate > 25% with >= 5 transactions)
    anomalous_merchants = [
        m for m in top_rejection_merchants if m["rejection_rate"] >= 25.0 and m["total_count"] >= 5
    ]

    merchants_analysis = {
        "top_by_volume": top_volume_merchants,
        "top_by_rejections": top_rejection_merchants,
        "category_performance": category_performance,
        "anomalous_merchants": anomalous_merchants,
        "active_merchants_count": active_merchants_count,
        "total_merchants_count": total_merchants_count,
    }

    # 4. Analyse des transactions
    # Status breakdown
    official_summary = compute_payment_transactions_summary(queryset)
    status_distribution = official_summary.get("breakdown_by_status", {}).get("rows", [])
    channel_distribution = official_summary.get("breakdown_by_channel", {}).get("rows", [])

    # Amount brackets
    b1 = queryset.filter(amount__lt=Decimal("1000.00")).count()
    b2 = queryset.filter(amount__gte=Decimal("1000.00"), amount__lt=Decimal("5000.00")).count()
    b3 = queryset.filter(amount__gte=Decimal("5000.00"), amount__lt=Decimal("20000.00")).count()
    b4 = queryset.filter(amount__gte=Decimal("20000.00"), amount__lt=Decimal("50000.00")).count()
    b5 = queryset.filter(amount__gte=Decimal("50000.00")).count()

    amount_brackets = [
        {"label": "< 1 000 DA", "count": b1, "pct": round(b1 / total_tx * 100, 2) if total_tx > 0 else 0.0},
        {"label": "1 000 - 5 000 DA", "count": b2, "pct": round(b2 / total_tx * 100, 2) if total_tx > 0 else 0.0},
        {"label": "5 000 - 20 000 DA", "count": b3, "pct": round(b3 / total_tx * 100, 2) if total_tx > 0 else 0.0},
        {"label": "20 000 - 50 000 DA", "count": b4, "pct": round(b4 / total_tx * 100, 2) if total_tx > 0 else 0.0},
        {"label": "≥ 50 000 DA", "count": b5, "pct": round(b5 / total_tx * 100, 2) if total_tx > 0 else 0.0},
    ]

    # Rejection reasons breakdown
    rejection_reasons_qs = (
        queryset.filter(transaction_status__in=REJECTED_STATUSES)
        .exclude(rejection_reason__isnull=True)
        .exclude(rejection_reason__exact="")
        .values("rejection_reason")
        .annotate(count=Count("transaction_id"))
        .order_by("-count")[:7]
    )
    total_rejections = kpis_curr["rejected_count"]
    rejection_reasons = [
        {
            "reason": r["rejection_reason"],
            "count": r["count"],
            "pct": round(r["count"] / total_rejections * 100, 2) if total_rejections > 0 else 0.0,
        }
        for r in rejection_reasons_qs
    ]

    transactions_analysis = {
        "status_distribution": status_distribution,
        "channel_distribution": channel_distribution,
        "amount_brackets": amount_brackets,
        "rejection_reasons": rejection_reasons,
        "refund_stats": {
            "count": kpis_curr["refunded_count"],
            "amount": kpis_curr["refunded_amount"],
            "rate_pct": round(kpis_curr["refunded_count"] / total_tx * 100, 2) if total_tx > 0 else 0.0,
        },
        "cancellation_stats": {
            "count": kpis_curr["cancelled_count"],
            "amount": kpis_curr["cancelled_amount"],
            "rate_pct": round(kpis_curr["cancelled_count"] / total_tx * 100, 2) if total_tx > 0 else 0.0,
        },
    }

    # Statistical distribution & outlier boxplot analysis across platform transactions
    from apps.analytics.statistics import compute_fraud_statistical_analytics, compute_statistical_summary
    stats_data = compute_statistical_summary(queryset)
    fraud_stats = compute_fraud_statistical_analytics(queryset)
    transactions_analysis["statistical_distribution"] = stats_data

    return {
        "overview": overview,
        "temporal": temporal,
        "merchants_analysis": merchants_analysis,
        "transactions_analysis": transactions_analysis,
        "fraud_analytics": fraud_stats,
    }

