import django_filters
from django.db.models import Q

from apps.transactions.models import Transaction


class TransactionFilter(django_filters.FilterSet):
    search = django_filters.CharFilter(method="filter_search")
    status = django_filters.BaseInFilter(field_name="transaction_status")
    channel = django_filters.BaseInFilter(field_name="payment_channel")
    date_from = django_filters.DateTimeFilter(field_name="transaction_date", lookup_expr="gte")
    date_to = django_filters.DateTimeFilter(field_name="transaction_date", lookup_expr="lte")
    amount_min = django_filters.NumberFilter(field_name="amount", lookup_expr="gte")
    amount_max = django_filters.NumberFilter(field_name="amount", lookup_expr="lte")
    merchant = django_filters.UUIDFilter(field_name="merchant_id")
    category = django_filters.CharFilter(field_name="merchant_category")
    wilaya = django_filters.CharFilter(field_name="merchant__wilaya")

    class Meta:
        model = Transaction
        fields = [
            "search",
            "status",
            "channel",
            "date_from",
            "date_to",
            "amount_min",
            "amount_max",
            "merchant",
            "category",
            "wilaya",
        ]

    def filter_search(self, queryset, name, value):
        if not value:
            return queryset
        val = value.strip()
        q = Q(reference__icontains=val) | Q(card_last4__icontains=val) | Q(terminal_id__icontains=val)
        try:
            amt = float(val.replace(" ", "").replace(",", "."))
            q |= Q(amount=amt)
        except ValueError:
            pass
        return queryset.filter(q)
