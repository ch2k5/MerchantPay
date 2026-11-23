import csv
import io

from django.http import HttpResponse
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from apps.core.utils import format_dzd


def export_transactions_csv(queryset, filename="transactions.csv") -> HttpResponse:
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    response.write("\ufeff")  # BOM for Excel French UTF-8

    writer = csv.writer(response, delimiter=";")
    writer.writerow(
        [
            "Référence",
            "Date (UTC)",
            "Montant (DZD)",
            "Canal",
            "Statut",
            "Catégorie",
            "Motif de rejet",
            "Carte (4 derniers)",
            "Terminal",
            "Montant remboursé (DZD)",
        ]
    )

    for tx in queryset.iterator():
        writer.writerow(
            [
                tx.reference,
                tx.transaction_date.strftime("%Y-%m-%d %H:%M:%S"),
                f"{tx.amount:.2f}".replace(".", ","),
                tx.get_payment_channel_display(),
                tx.get_transaction_status_display(),
                tx.merchant_category,
                tx.rejection_reason or "",
                f"****{tx.card_last4}",
                tx.terminal_id,
                f"{tx.refunded_amount:.2f}".replace(".", ",") if tx.refunded_amount else "",
            ]
        )

    return response


def export_transactions_pdf(queryset, merchant=None, filters_desc="", filename="transactions.pdf") -> HttpResponse:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=landscape(letter),
        leftMargin=30,
        rightMargin=30,
        topMargin=30,
        bottomMargin=30,
    )
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        "DocTitle",
        parent=styles["Heading1"],
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#E53A2F"),
    )
    subtitle_style = ParagraphStyle(
        "DocSubtitle",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#5E6368"),
    )
    cell_style = ParagraphStyle(
        "CellText",
        parent=styles["Normal"],
        fontSize=8,
        leading=10,
    )

    elements = []

    # Header
    brand = "SATIM × MERCHANT PAY"
    merchant_name = merchant.business_name if merchant else "Plateforme Globale SATIM"
    elements.append(Paragraph(f"<b>{brand}</b> — Relevé des Transactions", title_style))
    elements.append(Spacer(1, 5))
    gen_date = timezone.now().strftime("%d/%m/%Y à %H:%M (UTC)")
    elements.append(Paragraph(f"Commerçant : <b>{merchant_name}</b> | Généré le : {gen_date}", subtitle_style))
    if filters_desc:
        elements.append(Paragraph(f"Filtres appliqués : {filters_desc}", subtitle_style))
    elements.append(Spacer(1, 15))

    # Aggregates
    tx_list = list(queryset[:1000])  # limit PDF rows for performance
    total_count = len(tx_list)
    accepted_sum = sum(tx.amount for tx in tx_list if tx.transaction_status == "ACCEPTED")
    rejected_sum = sum(tx.amount for tx in tx_list if tx.transaction_status == "REJECTED")

    summary_data = [
        ["Total transactions (extrait)", "Volume Accepté", "Volume Rejeté"],
        [str(total_count), format_dzd(accepted_sum), format_dzd(rejected_sum)],
    ]
    summary_table = Table(summary_data, colWidths=[200, 200, 200])
    summary_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F7F7F8")),
                ("TEXTCOLOR", (0, 0), (-1, -1), colors.HexColor("#1F1F1F")),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    elements.append(summary_table)
    elements.append(Spacer(1, 15))

    # Table of transactions
    headers = ["Référence", "Date", "Montant", "Canal", "Statut", "Carte", "Terminal", "Motif rejet"]
    rows = [headers]
    for tx in tx_list:
        rows.append(
            [
                tx.reference,
                tx.transaction_date.strftime("%d/%m/%Y %H:%M"),
                format_dzd(tx.amount),
                tx.payment_channel,
                tx.get_transaction_status_display(),
                f"*{tx.card_last4}",
                tx.terminal_id,
                tx.rejection_reason or "-",
            ]
        )

    table = Table(rows, colWidths=[120, 95, 95, 75, 80, 55, 75, 130])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E53A2F")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FDFDFD")]),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(table)

    doc.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response
