import zoneinfo
from datetime import datetime, time, timedelta
from datetime import timezone as dt_timezone

from django.utils import timezone

ALGIERS_TZ = zoneinfo.ZoneInfo("Africa/Algiers")

# Week starts on Sunday in Algeria and national banking system
# In Python datetime.weekday(): Monday=0, ..., Sunday=6.
WEEK_START_DAY = 6


def get_now_algiers() -> datetime:
    """Returns the current aware datetime in Africa/Algiers timezone."""
    return timezone.now().astimezone(ALGIERS_TZ)


def parse_date_param(param_str: str | None) -> datetime | None:
    if not param_str:
        return None
    try:
        if "T" in param_str:
            dt = datetime.fromisoformat(param_str)
        else:
            d = datetime.strptime(param_str, "%Y-%m-%d").date()
            dt = datetime.combine(d, time.min)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=ALGIERS_TZ)
        return dt.astimezone(dt_timezone.utc)
    except Exception:
        return None


def resolve_period_range(
    preset: str | None = None,
    date_from_str: str | None = None,
    date_to_str: str | None = None,
    anchor_now: datetime | None = None,
) -> tuple[datetime, datetime, datetime, datetime]:
    """
    Returns (current_from, current_to, previous_from, previous_to) in UTC.
    All bounds are full days in Africa/Algiers.
    """
    now = (anchor_now or get_now_algiers()).astimezone(ALGIERS_TZ)
    today = now.date()

    preset = preset or "30d"

    if preset == "today":
        curr_start_date = today
        curr_end_date = today
        prev_start_date = today - timedelta(days=1)
        prev_end_date = today - timedelta(days=1)
    elif preset in ["all", "all_time", "global", "total"]:
        curr_start_date = datetime(2026, 1, 1).date()
        curr_end_date = datetime(2026, 12, 31).date()
        prev_start_date = datetime(2025, 1, 1).date()
        prev_end_date = datetime(2025, 12, 31).date()
    elif preset in ["6m", "180d"]:
        curr_start_date = today - timedelta(days=180)
        curr_end_date = today
        prev_start_date = curr_start_date - timedelta(days=180)
        prev_end_date = curr_start_date - timedelta(days=1)
    elif preset in ["90d", "3m"]:
        curr_start_date = today - timedelta(days=90)
        curr_end_date = today
        prev_start_date = curr_start_date - timedelta(days=90)
        prev_end_date = curr_start_date - timedelta(days=1)
    elif preset == "7d":
        curr_start_date = today - timedelta(days=6)
        curr_end_date = today
        prev_start_date = curr_start_date - timedelta(days=7)
        prev_end_date = curr_start_date - timedelta(days=1)
    elif preset == "30d":
        curr_start_date = today - timedelta(days=29)
        curr_end_date = today
        prev_start_date = curr_start_date - timedelta(days=30)
        prev_end_date = curr_start_date - timedelta(days=1)
    elif preset == "month":
        curr_start_date = today.replace(day=1)
        curr_end_date = today
        # Previous month
        last_day_prev_month = curr_start_date - timedelta(days=1)
        prev_start_date = last_day_prev_month.replace(day=1)
        prev_end_date = last_day_prev_month
    elif preset == "prev_month":
        first_of_this_month = today.replace(day=1)
        last_day_prev = first_of_this_month - timedelta(days=1)
        curr_start_date = last_day_prev.replace(day=1)
        curr_end_date = last_day_prev
        # Month before previous
        last_day_month_before = curr_start_date - timedelta(days=1)
        prev_start_date = last_day_month_before.replace(day=1)
        prev_end_date = last_day_month_before
    elif preset == "custom" and date_from_str and date_to_str:
        df = parse_date_param(date_from_str)
        dt = parse_date_param(date_to_str)
        if df and dt:
            curr_start_date = df.astimezone(ALGIERS_TZ).date()
            curr_end_date = dt.astimezone(ALGIERS_TZ).date()
            if curr_start_date > curr_end_date:
                curr_start_date, curr_end_date = curr_end_date, curr_start_date
            delta_days = (curr_end_date - curr_start_date).days + 1
            prev_start_date = curr_start_date - timedelta(days=delta_days)
            prev_end_date = curr_start_date - timedelta(days=1)
        else:
            curr_start_date = today - timedelta(days=29)
            curr_end_date = today
            prev_start_date = curr_start_date - timedelta(days=30)
            prev_end_date = curr_start_date - timedelta(days=1)
    else:
        curr_start_date = today - timedelta(days=29)
        curr_end_date = today
        prev_start_date = curr_start_date - timedelta(days=30)
        prev_end_date = curr_start_date - timedelta(days=1)

    # Convert to UTC bounds [start 00:00:00, end 23:59:59.999999] in Algiers
    c_from = datetime.combine(curr_start_date, time.min, tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)
    c_to = datetime.combine(curr_end_date, time.max, tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)
    p_from = datetime.combine(prev_start_date, time.min, tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)
    p_to = datetime.combine(prev_end_date, time.max, tzinfo=ALGIERS_TZ).astimezone(dt_timezone.utc)

    return c_from, c_to, p_from, p_to
