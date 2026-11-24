from datetime import datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.utils import timezone

from apps.analytics.services import compute_kpis
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import ACCEPTED_STATUSES, TransactionStatus
from apps.core.utils import format_dzd


def get_simulator_baseline(merchant, now: datetime | None = None) -> dict:
    """
    Computes baseline from the last 30 full days of the merchant:
    base_count = accepted count, base_avg = average accepted ticket, base_revenue.
    """
    now = (now or timezone.now()).astimezone(ALGIERS_TZ)
    today = now.date()
    start_date = today - timedelta(days=30)
    start_dt = datetime.combine(start_date, datetime.min.time(), tzinfo=ALGIERS_TZ)
    end_dt = datetime.combine(today - timedelta(days=1), datetime.max.time(), tzinfo=ALGIERS_TZ)

    qs = merchant.transactions.filter(
        transaction_date__range=(start_dt, end_dt),
        transaction_status__in=ACCEPTED_STATUSES,
    )
    kpis = compute_kpis(qs)

    base_count = kpis["accepted_count"]
    base_revenue = kpis["accepted_amount"]
    base_avg = kpis["avg_ticket"]

    return {
        "base_count": base_count,
        "base_revenue": base_revenue,
        "base_avg": base_avg,
        "period_days": 30,
        "monthly_goal": merchant.monthly_goal,
    }


def run_simulation(
    base_count: int,
    base_avg: Decimal,
    growth_rate_pct: float,
    avg_amount_delta_dzd: Decimal,
    monthly_goal: Decimal | None = None,
    period: str = "month",
) -> dict:
    """
    Pure simulation function over baseline metrics.
    Validation:
    growth_rate_pct in [-50, 200]
    avg_amount_delta_dzd in [-5000, 10000]
    """
    growth_dec = Decimal(str(growth_rate_pct)) / Decimal("100")
    sim_count_raw = Decimal(str(base_count)) * (Decimal("1") + growth_dec)
    sim_count = int(sim_count_raw.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    if sim_count < 0:
        sim_count = 0

    sim_avg = base_avg + avg_amount_delta_dzd
    if sim_avg < Decimal("0.00"):
        sim_avg = Decimal("0.00")

    base_revenue = (Decimal(str(base_count)) * base_avg).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    sim_revenue = (Decimal(str(sim_count)) * sim_avg).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    delta_abs = sim_revenue - base_revenue
    delta_pct = None
    if base_revenue > Decimal("0.00"):
        delta_pct = round(float((delta_abs / base_revenue) * 100), 2)

    # Goal impact
    goal_impact = None
    if monthly_goal and monthly_goal > Decimal("0.00"):
        actual_progress = round(float((base_revenue / monthly_goal) * 100), 1)
        simulated_progress = round(float((sim_revenue / monthly_goal) * 100), 1)
        goal_impact = {
            "goal": monthly_goal,
            "actual_progress_pct": actual_progress,
            "simulated_progress_pct": simulated_progress,
            "goal_reached": simulated_progress >= 100.0,
            "delta_progress_points": round(simulated_progress - actual_progress, 1),
        }

    # Summary sentence in French
    pct_suffix = f" ({delta_pct:+.1f} % de chiffre d'affaires)" if delta_pct is not None else ""
    if delta_abs >= 0:
        summary_sentence = (
            f"Une progression de {growth_rate_pct:+.1f} % du volume et de {avg_amount_delta_dzd:+.2f} DZD "
            f"du ticket moyen générerait un gain additionnel de {format_dzd(delta_abs)}{pct_suffix}."
        )
    else:
        summary_sentence = f"Cette variation entraînerait une baisse de chiffre d'affaires de {format_dzd(abs(delta_abs))}{pct_suffix}."

    # 12-point series for visual chart (representing 12 segments: e.g. weeks or months)
    series = []
    base_point = float(base_revenue) / 12.0
    sim_point = float(sim_revenue) / 12.0
    for i in range(1, 13):
        # minor smooth variation for chart display
        variation_factor = 1.0 + (0.05 * (i % 3 - 1))
        series.append(
            {
                "point": i,
                "label": f"S{i}" if period == "month" else f"M{i}",
                "actual": round(base_point * variation_factor, 2),
                "simulated": round(sim_point * variation_factor, 2),
            }
        )

    return {
        "baseline": {
            "count": base_count,
            "avg_ticket": base_avg,
            "revenue": base_revenue,
        },
        "simulated": {
            "count": sim_count,
            "avg_ticket": sim_avg,
            "revenue": sim_revenue,
        },
        "delta_abs": delta_abs,
        "delta_pct": delta_pct,
        "goal_impact": goal_impact,
        "summary": summary_sentence,
        "series": series,
    }
