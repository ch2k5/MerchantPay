import uuid

from django.conf import settings
from django.db import models

from apps.core.enums import AuditAction


class AuditLog(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="audit_logs",
    )
    action = models.CharField(max_length=64, choices=AuditAction.choices)
    target_type = models.CharField(max_length=64, blank=True, default="")
    target_id = models.CharField(max_length=128, blank=True, default="")
    before = models.JSONField(null=True, blank=True)
    after = models.JSONField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Journal d'audit"
        verbose_name_plural = "Journaux d'audit"

    def __str__(self):
        actor_email = self.actor.email if self.actor else "Système"
        return f"[{self.created_at.strftime('%Y-%m-%d %H:%M')}] {actor_email} -> {self.action} ({self.target_type}:{self.target_id})"

    def save(self, *args, **kwargs):
        # Audit logs are immutable once written
        if not self._state.adding:
            raise ValueError("Les entrées de journal d'audit sont immuables et ne peuvent pas être modifiées.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("Les entrées de journal d'audit ne peuvent pas être supprimées.")
