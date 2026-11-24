import uuid

from django.db import models

from apps.core.enums import (
    MerchantCategory,
    PaymentChannel,
    RejectionReason,
    TransactionStatus,
)
from apps.merchants.models import Merchant


class Transaction(models.Model):
    transaction_id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    reference = models.CharField(max_length=64, unique=True, db_index=True)
    merchant = models.ForeignKey(
        Merchant,
        on_delete=models.CASCADE,
        related_name="transactions",
        db_index=True,
    )
    transaction_date = models.DateTimeField(db_index=True)
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    payment_channel = models.CharField(max_length=64, choices=PaymentChannel.choices)
    transaction_status = models.CharField(
        max_length=32,
        choices=TransactionStatus.choices,
        db_index=True,
    )
    merchant_category = models.CharField(max_length=64, choices=MerchantCategory.choices)
    rejection_reason = models.CharField(
        max_length=64,
        choices=RejectionReason.choices,
        null=True,
        blank=True,
    )
    card_last4 = models.CharField(max_length=4, default="0000")
    terminal_id = models.CharField(max_length=64, default="TPE-01")
    refunded_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        null=True,
        blank=True,
    )

    class Meta:
        ordering = ["-transaction_date"]
        indexes = [
            models.Index(fields=["merchant", "transaction_date"]),
            models.Index(fields=["merchant", "transaction_status"]),
            models.Index(fields=["transaction_date", "transaction_status"]),
        ]
        verbose_name = "Transaction"
        verbose_name_plural = "Transactions"

    def __str__(self):
        return f"{self.reference} - {self.amount} DZD ({self.transaction_status})"
