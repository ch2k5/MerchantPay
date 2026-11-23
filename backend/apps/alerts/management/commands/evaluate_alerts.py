from django.core.management.base import BaseCommand

from apps.alerts.services import evaluate_all_active_merchants


class Command(BaseCommand):
    help = "Évalue les règles d'alertes et de recommandations pour tous les commerçants actifs"

    def handle(self, *args, **options):
        total_created = evaluate_all_active_merchants()
        self.stdout.write(self.style.SUCCESS(f"Évaluation terminée avec succès. {total_created} alertes traitées."))
