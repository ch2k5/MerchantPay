from datetime import datetime, timedelta
from decimal import Decimal

from django.utils import timezone

from apps.alerts import config
from apps.analytics.services import compute_channel_distribution, compute_heatmap, compute_kpis
from apps.core.dates import ALGIERS_TZ
from apps.core.enums import (
    ACCEPTED_STATUSES,
    AlertSeverity,
    AlertType,
    REJECTED_STATUSES,
    TransactionStatus,
)
from apps.core.utils import format_dzd


class BaseAlertRule:
    rule_type: str = ""

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        raise NotImplementedError


class RevenueDropRule(BaseAlertRule):
    rule_type = AlertType.REVENUE_DROP

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        today = now.date()
        curr_start = datetime.combine(today - timedelta(days=6), datetime.min.time(), tzinfo=ALGIERS_TZ)
        curr_end = datetime.combine(today, datetime.max.time(), tzinfo=ALGIERS_TZ)
        prev_start = datetime.combine(today - timedelta(days=13), datetime.min.time(), tzinfo=ALGIERS_TZ)
        prev_end = datetime.combine(today - timedelta(days=7), datetime.max.time(), tzinfo=ALGIERS_TZ)

        qs_curr = merchant.transactions.filter(transaction_date__range=(curr_start, curr_end))
        qs_prev = merchant.transactions.filter(transaction_date__range=(prev_start, prev_end))

        kpis_curr = compute_kpis(qs_curr)
        kpis_prev = compute_kpis(qs_prev)

        curr_rev = kpis_curr["net_revenue"]
        prev_rev = kpis_prev["net_revenue"]

        if prev_rev > Decimal("0.00") and curr_rev < prev_rev:
            drop_pct = float(((prev_rev - curr_rev) / prev_rev) * 100)
            if drop_pct >= config.REVENUE_DROP_WARNING_THRESHOLD_PCT:
                severity = (
                    AlertSeverity.CRITICAL
                    if drop_pct >= config.REVENUE_DROP_CRITICAL_THRESHOLD_PCT
                    else AlertSeverity.WARNING
                )
                drop_formatted = f"{drop_pct:.0f} %"
                period_str = f"{curr_start.strftime('%Y%m%d')}_{curr_end.strftime('%Y%m%d')}"
                dedupe_key = f"REVENUE_DROP_{period_str}"

                return {
                    "type": self.rule_type,
                    "severity": severity,
                    "title": f"Baisse de chiffre d'affaires (-{drop_formatted})",
                    "message": f"Votre chiffre d'affaires a diminué de {drop_formatted} par rapport à la semaine précédente ({format_dzd(curr_rev)} contre {format_dzd(prev_rev)}).",
                    "recommendation": "Analysez vos créneaux creux via la carte d'activité thermique et envisagez une offre promotionnelle ciblée.",
                    "metric_snapshot": {
                        "chiffre_affaires_actuel": float(curr_rev),
                        "chiffre_affaires_precedent": float(prev_rev),
                        "baisse_pourcentage": round(drop_pct, 1),
                        "seuil_alerte": config.REVENUE_DROP_WARNING_THRESHOLD_PCT,
                    },
                    "period_start": curr_start,
                    "period_end": curr_end,
                    "dedupe_key": dedupe_key,
                }
        return None


class NoActivityRule(BaseAlertRule):
    rule_type = AlertType.NO_ACTIVITY

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        latest_tx = merchant.transactions.order_by("-transaction_date").first()
        if not latest_tx:
            # Merchant with 0 transactions
            return None

        diff = now - latest_tx.transaction_date.astimezone(ALGIERS_TZ)
        days_without_activity = diff.days

        if days_without_activity >= config.NO_ACTIVITY_DAYS_THRESHOLD:
            date_anchor = now.strftime("%Y%m%d")
            dedupe_key = f"NO_ACTIVITY_{date_anchor}"
            return {
                "type": self.rule_type,
                "severity": AlertSeverity.CRITICAL,
                "title": f"Inactivité prolongée ({days_without_activity} jours)",
                "message": f"Vous n'avez enregistré aucune transaction depuis {days_without_activity} jours. Dernière transaction le {latest_tx.transaction_date.strftime('%d/%m/%Y à %H:%M')}.",
                "recommendation": "Vérifiez le bon fonctionnement et la connectivité réseau de vos terminaux de paiement.",
                "metric_snapshot": {
                    "jours_inactivite": days_without_activity,
                    "seuil_jours": config.NO_ACTIVITY_DAYS_THRESHOLD,
                    "derniere_transaction": latest_tx.transaction_date.isoformat(),
                },
                "period_start": latest_tx.transaction_date,
                "period_end": now,
                "dedupe_key": dedupe_key,
            }
        return None


class RejectionSpikeRule(BaseAlertRule):
    rule_type = AlertType.REJECTION_SPIKE

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        today = now.date()
        curr_start = datetime.combine(today - timedelta(days=6), datetime.min.time(), tzinfo=ALGIERS_TZ)
        curr_end = datetime.combine(today, datetime.max.time(), tzinfo=ALGIERS_TZ)
        prev_start = datetime.combine(today - timedelta(days=13), datetime.min.time(), tzinfo=ALGIERS_TZ)
        prev_end = datetime.combine(today - timedelta(days=7), datetime.max.time(), tzinfo=ALGIERS_TZ)

        qs_curr = merchant.transactions.filter(transaction_date__range=(curr_start, curr_end))
        qs_prev = merchant.transactions.filter(transaction_date__range=(prev_start, prev_end))

        kpis_curr = compute_kpis(qs_curr)
        kpis_prev = compute_kpis(qs_prev)

        if kpis_curr["total_transactions"] < config.REJECTION_SPIKE_MIN_TRANSACTIONS:
            return None

        curr_rate = kpis_curr["rejection_rate"]
        prev_rate = kpis_prev["rejection_rate"]

        is_spike = False
        if prev_rate > 0:
            if (
                curr_rate >= prev_rate + config.REJECTION_SPIKE_DIFF_POINTS
                and curr_rate >= prev_rate * config.REJECTION_SPIKE_RATIO_MULTIPLIER
            ):
                is_spike = True
        else:
            if curr_rate >= config.REJECTION_SPIKE_DIFF_POINTS and kpis_curr["rejected_count"] >= 3:
                is_spike = True

        if is_spike:
            # Top rejection reason
            from django.db.models import Count

            top_reason_qs = (
                qs_curr.filter(transaction_status__in=REJECTED_STATUSES)
                .values("rejection_reason")
                .annotate(cnt=Count("transaction_id"))
                .order_by("-cnt")
                .first()
            )
            reason = top_reason_qs["rejection_reason"] if top_reason_qs else "Erreur technique"

            period_str = f"{curr_start.strftime('%Y%m%d')}_{curr_end.strftime('%Y%m%d')}"
            dedupe_key = f"REJECTION_SPIKE_{period_str}"

            return {
                "type": self.rule_type,
                "severity": AlertSeverity.WARNING,
                "title": "Hausse inhabituelle des rejets",
                "message": f"Une hausse inhabituelle des transactions rejetées a été détectée ({curr_rate:.1f} % vs {prev_rate:.1f} % précédemment). Motif principal : {reason}.",
                "recommendation": f"Contrôlez les terminaux concernant le motif « {reason} » ou contactez le support technique SATIM.",
                "metric_snapshot": {
                    "taux_rejet_actuel": curr_rate,
                    "taux_rejet_precedent": prev_rate,
                    "transactions_rejetees": kpis_curr["rejected_count"],
                    "motif_principal": reason,
                },
                "period_start": curr_start,
                "period_end": curr_end,
                "dedupe_key": dedupe_key,
            }
        return None


class GoalProgressRule(BaseAlertRule):
    rule_type = AlertType.GOAL_PROGRESS

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        if not merchant.monthly_goal or merchant.monthly_goal <= Decimal("0.00"):
            return None

        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        first_day_month = datetime.combine(now.date().replace(day=1), datetime.min.time(), tzinfo=ALGIERS_TZ)
        qs = merchant.transactions.filter(transaction_date__range=(first_day_month, now))
        kpis = compute_kpis(qs)
        achieved = kpis["net_revenue"]
        progress_pct = float((achieved / merchant.monthly_goal) * 100)

        month_str = now.strftime("%Y%m")
        period_start = first_day_month
        period_end = now

        if progress_pct >= config.GOAL_PROGRESS_SUCCESS_PCT:
            return {
                "type": self.rule_type,
                "severity": AlertSeverity.SUCCESS,
                "title": "Objectif mensuel atteint !",
                "message": f"Félicitations ! Votre chiffre d'affaires ce mois ({format_dzd(achieved)}) dépasse votre objectif de {format_dzd(merchant.monthly_goal)} ({progress_pct:.1f} %).",
                "recommendation": "Maintenez cette dynamique ou ajustez votre objectif pour le mois prochain.",
                "metric_snapshot": {
                    "objectif": float(merchant.monthly_goal),
                    "realise": float(achieved),
                    "pourcentage": round(progress_pct, 1),
                },
                "period_start": period_start,
                "period_end": period_end,
                "dedupe_key": f"GOAL_PROGRESS_SUCCESS_{month_str}",
            }
        elif progress_pct >= config.GOAL_PROGRESS_INFO_PCT:
            return {
                "type": self.rule_type,
                "severity": AlertSeverity.INFO,
                "title": "Objectif mensuel presque atteint",
                "message": f"Vous êtes à {progress_pct:.0f} % de votre objectif mensuel ({format_dzd(achieved)} réalisés sur {format_dzd(merchant.monthly_goal)}).",
                "recommendation": "Plus que quelques transactions pour franchir le palier mensuel.",
                "metric_snapshot": {
                    "objectif": float(merchant.monthly_goal),
                    "realise": float(achieved),
                    "pourcentage": round(progress_pct, 1),
                },
                "period_start": period_start,
                "period_end": period_end,
                "dedupe_key": f"GOAL_PROGRESS_85_{month_str}",
            }
        elif now.day >= config.GOAL_PROGRESS_LATE_MONTH_DAY and progress_pct < config.GOAL_PROGRESS_LATE_MONTH_MIN_PCT:
            return {
                "type": self.rule_type,
                "severity": AlertSeverity.WARNING,
                "title": "Retard sur l'objectif mensuel",
                "message": f"Au {now.day} du mois, vous n'avez atteint que {progress_pct:.0f} % de votre objectif de {format_dzd(merchant.monthly_goal)}.",
                "recommendation": "Consultez le simulateur d'activité pour identifier les leviers d'augmentation du ticket moyen.",
                "metric_snapshot": {
                    "objectif": float(merchant.monthly_goal),
                    "realise": float(achieved),
                    "pourcentage": round(progress_pct, 1),
                    "jour_du_mois": now.day,
                },
                "period_start": period_start,
                "period_end": period_end,
                "dedupe_key": f"GOAL_PROGRESS_DELAY_{month_str}",
            }
        return None


class PeakActivityRule(BaseAlertRule):
    rule_type = AlertType.PEAK_ACTIVITY

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        start_30d = now - timedelta(days=30)
        qs = merchant.transactions.filter(transaction_date__range=(start_30d, now))
        if qs.count() < 15:
            return None

        heatmap_res = compute_heatmap(qs)
        peak = heatmap_res["peak_slot"]
        hour = peak["hour"]
        next_hour = (hour + 2) % 24
        slot_str = f"{hour:02d}h00 et {next_hour:02d}h00"

        month_str = now.strftime("%Y%m")
        return {
            "type": self.rule_type,
            "severity": AlertSeverity.INFO,
            "title": "Créneau de forte affluence identifié",
            "message": f"Votre activité est particulièrement élevée entre {slot_str} ({peak['day']}) avec un pic de transactions enregistrées.",
            "recommendation": "Renforcez la présence de votre équipe et veillez à la disponibilité de vos terminaux durant ces heures de pointe.",
            "metric_snapshot": {
                "creneau": slot_str,
                "jour_pic": peak["day"],
                "nombre_transactions_pic": peak["count"],
            },
            "period_start": start_30d,
            "period_end": now,
            "dedupe_key": f"PEAK_ACTIVITY_{month_str}",
        }


class ChannelShiftRule(BaseAlertRule):
    rule_type = AlertType.CHANNEL_SHIFT

    def evaluate(self, merchant, now: datetime | None = None) -> dict | None:
        now = (now or timezone.now()).astimezone(ALGIERS_TZ)
        today = now.date()
        curr_start = datetime.combine(today - timedelta(days=14), datetime.min.time(), tzinfo=ALGIERS_TZ)
        curr_end = datetime.combine(today, datetime.max.time(), tzinfo=ALGIERS_TZ)
        prev_start = datetime.combine(today - timedelta(days=29), datetime.min.time(), tzinfo=ALGIERS_TZ)
        prev_end = datetime.combine(today - timedelta(days=15), datetime.max.time(), tzinfo=ALGIERS_TZ)

        qs_curr = merchant.transactions.filter(transaction_date__range=(curr_start, curr_end))
        qs_prev = merchant.transactions.filter(transaction_date__range=(prev_start, prev_end))

        if qs_curr.count() < 20 or qs_prev.count() < 20:
            return None

        dist_curr = compute_channel_distribution(qs_curr)
        dist_prev = compute_channel_distribution(qs_prev)

        curr_cib = next((c["count_pct"] for c in dist_curr["channels"] if c["channel"] == "CIB"), 0.0)
        prev_cib = next((c["count_pct"] for c in dist_prev["channels"] if c["channel"] == "CIB"), 0.0)

        diff = abs(curr_cib - prev_cib)
        if diff >= config.CHANNEL_SHIFT_THRESHOLD_POINTS:
            direction = "hausse" if curr_cib > prev_cib else "baisse"
            period_str = f"{curr_start.strftime('%Y%m%d')}_{curr_end.strftime('%Y%m%d')}"
            return {
                "type": self.rule_type,
                "severity": AlertSeverity.INFO,
                "title": f"Évolution de l'usage des cartes ({direction.capitalize()})",
                "message": f"La part de la carte CIB a varié de {diff:.1f} points ({curr_cib:.1f} % vs {prev_cib:.1f} % précédemment).",
                "recommendation": "Adaptez vos promotions selon les habitudes de paiement de votre clientèle.",
                "metric_snapshot": {
                    "part_cib_actuelle": curr_cib,
                    "part_cib_precedente": prev_cib,
                    "variation_points": round(diff, 1),
                },
                "period_start": curr_start,
                "period_end": curr_end,
                "dedupe_key": f"CHANNEL_SHIFT_{period_str}",
            }
        return None


RULES = [
    RevenueDropRule(),
    NoActivityRule(),
    RejectionSpikeRule(),
    GoalProgressRule(),
    PeakActivityRule(),
    ChannelShiftRule(),
]
