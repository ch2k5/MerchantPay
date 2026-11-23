from django.core.management.base import BaseCommand

from apps.risk.services import scan_all_merchants_risk


class Command(BaseCommand):
    help = "Exécute le scan de détection de risque et d'activités suspectes pour tous les commerçants actifs"

    def handle(self, *args, **options):
        count = scan_all_merchants_risk()
        self.stdout.write(self.style.SUCCESS(f"Scan de risque terminé. {count} signalement(s) généré(s)."))
