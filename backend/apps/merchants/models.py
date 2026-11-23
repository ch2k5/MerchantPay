import uuid

from django.conf import settings
from django.db import models

from apps.core.enums import MerchantCategory, MerchantStatus


class Merchant(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="merchant",
    )
    merchant_code = models.CharField(max_length=32, unique=True, db_index=True)
    business_name = models.CharField(max_length=255)
    merchant_category = models.CharField(
        max_length=64,
        choices=MerchantCategory.choices,
        default=MerchantCategory.COMMERCE_DETAIL,
    )
    address = models.CharField(max_length=255, blank=True, default="")
    wilaya = models.CharField(max_length=100)
    phone = models.CharField(max_length=32, blank=True, default="")
    email = models.EmailField(blank=True, default="")
    registration_number = models.CharField(max_length=64, verbose_name="Registre de Commerce (RC)")
    terminal_count = models.PositiveIntegerField(default=1)
    monthly_goal = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        null=True,
        blank=True,
        help_text="Objectif mensuel de chiffre d'affaires en DZD",
    )
    status = models.CharField(
        max_length=20,
        choices=MerchantStatus.choices,
        default=MerchantStatus.ACTIVE,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["business_name"]
        verbose_name = "Commerçant"
        verbose_name_plural = "Commerçants"

    def __str__(self):
        return f"{self.business_name} ({self.merchant_code})"
