from django.utils import timezone

from apps.alerts.models import MerchantAlert
from apps.alerts.rules import RULES


def evaluate_merchant_alerts(merchant, now=None) -> list[MerchantAlert]:
    """
    Evaluates all alert rules for the merchant and persists newly triggered alerts.
    Existing alerts with same dedupe_key are not duplicated.
    """
    now = now or timezone.now()
    generated_alerts = []

    for rule in RULES:
        alert_dict = rule.evaluate(merchant, now=now)
        if alert_dict:
            alert, created = MerchantAlert.objects.get_or_create(
                merchant=merchant,
                dedupe_key=alert_dict["dedupe_key"],
                defaults={
                    "type": alert_dict["type"],
                    "severity": alert_dict["severity"],
                    "title": alert_dict["title"],
                    "message": alert_dict["message"],
                    "recommendation": alert_dict["recommendation"],
                    "metric_snapshot": alert_dict["metric_snapshot"],
                    "period_start": alert_dict["period_start"],
                    "period_end": alert_dict["period_end"],
                },
            )
            generated_alerts.append(alert)

    return generated_alerts


def evaluate_all_active_merchants(now=None) -> int:
    from apps.core.enums import MerchantStatus
    from apps.merchants.models import Merchant

    active_merchants = Merchant.objects.filter(status=MerchantStatus.ACTIVE)
    count = 0
    for m in active_merchants:
        alerts = evaluate_merchant_alerts(m, now=now)
        count += len(alerts)
    return count
