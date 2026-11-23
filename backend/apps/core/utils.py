import datetime
import uuid
from decimal import Decimal


def format_dzd(amount: Decimal | float | int | None) -> str:
    """Format decimal amount according to Algerian/French conventions: 48 000,00 DZD"""
    if amount is None:
        amount = Decimal("0.00")
    elif not isinstance(amount, Decimal):
        amount = Decimal(str(amount))

    val = round(amount, 2)
    s = f"{val:,.2f}".replace(",", " ").replace(".", ",")
    return f"{s} DZD"


def format_percentage(pct: float | None) -> str:
    if pct is None:
        return "0,0 %"
    return f"{pct:.1f} %".replace(".", ",")


def generate_transaction_reference() -> str:
    now_str = datetime.datetime.now().strftime("%Y%m%d")
    short_uuid = uuid.uuid4().hex[:6].upper()
    return f"TX-{now_str}-{short_uuid}"
