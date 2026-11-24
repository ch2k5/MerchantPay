import csv
import io

from django.http import HttpResponse
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from apps.analytics.services import compute_channel_distribution, compute_kpis
from apps.core.utils import format_dzd


def export_merchant_activity_report_pdf(merchant, date_from, date_to) -> HttpResponse:
    """
    Generates a comprehensive executive PDF report for an individual merchant.
    Includes merchant header, RC, period KPIs, comparison with previous period,
    channel distribution (CIB vs EDAHABIA), and recent representative transactions.
    """
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=36,
    )
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        "DocTitle",
        parent=styles["Heading1"],
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#0D6EFD"),
    )
    subtitle_style = ParagraphStyle(
        "DocSubtitle",
        parent=styles["Normal"],
        fontSize=9,
        textColor=colors.HexColor("#5E6368"),
    )

    qs = merchant.transactions.filter(transaction_date__range=(date_from, date_to))
    kpis = compute_kpis(qs)
    channels = compute_channel_distribution(qs)

    elements = [
        Paragraph(f"<b>MERCHANT PAY</b> — Relevé & Synthèse d'Activité", title_style),
        Paragraph(
            f"Commerçant : <b>{merchant.business_name}</b> (Code SATIM : {merchant.merchant_code}) | "
            f"RC : {merchant.registration_number or 'N/A'} | Wilaya : {merchant.wilaya}",
            styles["Heading3"],
        ),
        Paragraph(
            f"Période analysée : du {date_from.strftime('%d/%m/%Y')} au {date_to.strftime('%d/%m/%Y')} | "
            f"Généré le {timezone.now().strftime('%d/%m/%Y à %H:%M')}",
            subtitle_style,
        ),
        Spacer(1, 15),
    ]

    # Global KPI table
    kpi_data = [
        ["Indicateur clé", "Valeur"],
        ["Volume d'affaires net", format_dzd(kpis["net_revenue"])],
        ["Nombre total de transactions", str(kpis["total_transactions"])],
        ["Transactions acceptées", str(kpis["accepted_count"])],
        ["Transactions rejetées", str(kpis["rejected_count"])],
        ["Transactions remboursées", str(kpis["refunded_count"])],
        ["Taux de succès", f"{kpis['success_rate']:.1f} %"],
        ["Taux de rejet", f"{kpis['rejection_rate']:.1f} %"],
        ["Panier moyen accepté", format_dzd(kpis["avg_ticket"])],
    ]
    t1 = Table(kpi_data, colWidths=[280, 260])
    t1.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0D6EFD")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9FBFD")]),
                ("PADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    elements.append(t1)
    elements.append(Spacer(1, 15))

    # Channels table
    elements.append(Paragraph("<b>Ventilation par réseau (CIB & EDAHABIA)</b>", styles["Heading3"]))
    ch_data = [["Canal de paiement", "Transactions", "Part (%)", "Volume accepté (DZD)"]]
    for ch in channels["channels"]:
        ch_data.append(
            [
                ch["label"],
                str(ch["count"]),
                f"{ch['count_pct']:.1f} %",
                format_dzd(ch["accepted_amount"]),
            ]
        )
    t2 = Table(ch_data, colWidths=[160, 100, 100, 180])
    t2.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1F1F1F")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("PADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    elements.append(t2)
    elements.append(Spacer(1, 15))

    # Recent Transactions sample
    elements.append(Paragraph("<b>Dernières transactions enregistrées sur la période</b>", styles["Heading3"]))
    tx_sample = qs.order_by("-transaction_date")[:15]
    tx_data = [["Référence", "Date", "Montant", "Canal", "Statut"]]
    for tx in tx_sample:
        tx_data.append(
            [
                tx.reference,
                tx.transaction_date.strftime("%d/%m/%Y %H:%M"),
                format_dzd(tx.amount),
                tx.payment_channel,
                tx.get_transaction_status_display(),
            ]
        )
    t3 = Table(tx_data, colWidths=[160, 110, 110, 80, 80])
    t3.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F1F5F9")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#1F1F1F")),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FDFDFD")]),
                ("PADDING", (0, 0), (-1, -1), 4),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(t3)

    doc.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    p_from = date_from.strftime("%Y%m%d")
    p_to = date_to.strftime("%Y%m%d")
    response["Content-Disposition"] = f'attachment; filename="rapport_activite_{merchant.merchant_code}_{p_from}_{p_to}.pdf"'
    return response


def export_merchant_activity_report_csv(merchant, date_from, date_to) -> HttpResponse:
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    p_from = date_from.strftime("%Y%m%d")
    p_to = date_to.strftime("%Y%m%d")
    response["Content-Disposition"] = f'attachment; filename="rapport_activite_{merchant.merchant_code}_{p_from}_{p_to}.csv"'
    response.write("\ufeff")

    qs = merchant.transactions.filter(transaction_date__range=(date_from, date_to))
    kpis = compute_kpis(qs)

    writer = csv.writer(response, delimiter=";")
    writer.writerow(["Rapport d'activité commerçant - MERCHANT PAY", merchant.business_name])
    writer.writerow(["Code Marchand", merchant.merchant_code, "RC", merchant.registration_number])
    writer.writerow(["Période du", date_from.strftime("%d/%m/%Y"), "au", date_to.strftime("%d/%m/%Y")])
    writer.writerow([])
    writer.writerow(["Indicateur", "Valeur"])
    writer.writerow(["Volume d'affaires net (DZD)", f"{kpis['net_revenue']:.2f}".replace(".", ",")])
    writer.writerow(["Nombre total de transactions", kpis["total_transactions"]])
    writer.writerow(["Transactions acceptées", kpis["accepted_count"]])
    writer.writerow(["Transactions rejetées", kpis["rejected_count"]])
    writer.writerow(["Transactions remboursées", kpis["refunded_count"]])
    writer.writerow(["Taux de succès (%)", f"{kpis['success_rate']:.2f}".replace(".", ",")])
    writer.writerow(["Taux de rejet (%)", f"{kpis['rejection_rate']:.2f}".replace(".", ",")])
    writer.writerow(["Panier moyen (DZD)", f"{kpis['avg_ticket']:.2f}".replace(".", ",")])
    return response
