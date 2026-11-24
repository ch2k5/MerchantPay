import csv
import io

from django.http import HttpResponse
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from apps.analytics.services import compute_channel_distribution, compute_kpis
from apps.core.utils import format_dzd
from apps.merchants.models import Merchant
from apps.risk.models import RiskFlag
from apps.transactions.models import Transaction


def export_platform_report_csv(date_from, date_to) -> HttpResponse:
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = 'attachment; filename="rapport_plateforme_satim.csv"'
    response.write("\ufeff")

    qs = Transaction.objects.filter(transaction_date__range=(date_from, date_to))
    kpis = compute_kpis(qs)
    channels = compute_channel_distribution(qs)

    writer = csv.writer(response, delimiter=";")
    writer.writerow(["Rapport d'activité Plateforme SATIM", ""])
    writer.writerow(["Période du", date_from.strftime("%d/%m/%Y"), "au", date_to.strftime("%d/%m/%Y")])
    writer.writerow([])
    writer.writerow(["Indicateur", "Valeur"])
    writer.writerow(["Volume total de transactions", kpis["total_transactions"]])
    writer.writerow(["Transactions acceptées", kpis["accepted_count"]])
    writer.writerow(["Transactions rejetées", kpis["rejected_count"]])
    writer.writerow(["Transactions remboursées", kpis["refunded_count"]])
    writer.writerow(["Chiffre d'affaires net (DZD)", f"{kpis['net_revenue']:.2f}".replace(".", ",")])
    writer.writerow(["Taux de succès (%)", f"{kpis['success_rate']:.2f}".replace(".", ",")])
    writer.writerow(["Taux de rejet (%)", f"{kpis['rejection_rate']:.2f}".replace(".", ",")])
    writer.writerow(["Panier moyen (DZD)", f"{kpis['avg_ticket']:.2f}".replace(".", ",")])

    writer.writerow([])
    writer.writerow(["Répartition par canal de paiement", ""])
    writer.writerow(["Canal", "Transactions", "Part (%)", "Montant accepté (DZD)"])
    for ch in channels["channels"]:
        writer.writerow(
            [
                ch["label"],
                ch["count"],
                f"{ch['count_pct']:.1f}".replace(".", ","),
                f"{ch['accepted_amount']:.2f}".replace(".", ","),
            ]
        )

    return response


def export_platform_report_pdf(date_from, date_to) -> HttpResponse:
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
        fontSize=20,
        leading=24,
        textColor=colors.HexColor("#E53A2F"),
    )
    subtitle_style = ParagraphStyle(
        "DocSubtitle",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#5E6368"),
    )

    qs = Transaction.objects.filter(transaction_date__range=(date_from, date_to))
    kpis = compute_kpis(qs)
    channels = compute_channel_distribution(qs)

    elements = [
        Paragraph("<b>SATIM × MERCHANT PAY</b>", title_style),
        Paragraph("Rapport d'activité consolidé de la plateforme", styles["Heading2"]),
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
        ["Transactions totales", str(kpis["total_transactions"])],
        ["Transactions acceptées", str(kpis["accepted_count"])],
        ["Transactions rejetées", str(kpis["rejected_count"])],
        ["Chiffre d'affaires net", format_dzd(kpis["net_revenue"])],
        ["Taux de succès", f"{kpis['success_rate']:.1f} %"],
        ["Taux de rejet", f"{kpis['rejection_rate']:.1f} %"],
        ["Panier moyen accepté", format_dzd(kpis["avg_ticket"])],
    ]
    t1 = Table(kpi_data, colWidths=[300, 240])
    t1.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E53A2F")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9F9F9")]),
                ("PADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    elements.append(t1)
    elements.append(Spacer(1, 20))

    # Channels table
    elements.append(Paragraph("<b>Répartition par canal de paiement</b>", styles["Heading3"]))
    ch_data = [["Canal", "Transactions", "Part (%)", "Volume accepté (DZD)"]]
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
                ("PADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    elements.append(t2)

    doc.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    response["Content-Disposition"] = 'attachment; filename="rapport_plateforme_satim.pdf"'
    return response


def export_merchants_report_csv() -> HttpResponse:
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = 'attachment; filename="repertoire_commercants_satim.csv"'
    response.write("\ufeff")

    writer = csv.writer(response, delimiter=";")
    writer.writerow(
        [
            "Code Commerçant",
            "Raison Sociale",
            "Catégorie",
            "Wilaya",
            "Statut",
            "Terminaux",
            "Registre de Commerce (RC)",
            "Email",
        ]
    )

    for m in Merchant.objects.all().order_by("merchant_code"):
        writer.writerow(
            [
                m.merchant_code,
                m.business_name,
                m.merchant_category,
                m.wilaya,
                m.get_status_display(),
                m.terminal_count,
                m.registration_number,
                m.email or (m.owner.email if m.owner else ""),
            ]
        )

    return response


def export_merchants_report_pdf() -> HttpResponse:
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

    elements = [
        Paragraph("<b>SATIM × GIE Monétique</b> — Répertoire Officiel des Commerçants Adhérents", styles["Heading1"]),
        Paragraph(
            f"Document édité le {timezone.now().strftime('%d/%m/%Y à %H:%M')} | Réseau national d'acceptation monétique CIB & EDAHABIA",
            ParagraphStyle("Subtitle", parent=styles["Normal"], textColor=colors.HexColor("#5E6368"), fontSize=9),
        ),
        Spacer(1, 15),
    ]

    merchants = Merchant.objects.all().order_by("merchant_code")
    headers = ["Code", "Raison Sociale", "Catégorie", "Wilaya", "Statut", "TPE", "RC", "Contact"]
    rows = [headers]
    for m in merchants:
        contact = m.email or (m.owner.email if m.owner else "")
        rows.append(
            [
                m.merchant_code,
                m.business_name[:24],
                m.get_merchant_category_display() if hasattr(m, 'get_merchant_category_display') else m.merchant_category,
                m.wilaya,
                m.get_status_display(),
                str(m.terminal_count),
                m.registration_number[:18],
                contact[:22],
            ]
        )

    table = Table(rows, colWidths=[75, 150, 110, 85, 75, 45, 95, 115])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E53A2F")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9F9F9")]),
                ("PADDING", (0, 0), (-1, -1), 5),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(table)

    doc.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    response["Content-Disposition"] = 'attachment; filename="repertoire_commercants_satim.pdf"'
    return response


def export_risk_report_csv(date_from, date_to) -> HttpResponse:
    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = 'attachment; filename="rapport_risques_satim.csv"'
    response.write("\ufeff")

    writer = csv.writer(response, delimiter=";")
    writer.writerow(
        [
            "Score",
            "Niveau",
            "Commerçant",
            "Statut",
            "Règles déclenchées",
            "Date de détection",
        ]
    )

    flags = RiskFlag.objects.filter(detected_at__range=(date_from, date_to)).order_by("-risk_score")[:500]
    for f in flags:
        rule_labels = ", ".join(r.get("label_fr", r.get("code", "")) for r in f.triggered_rules[:3])
        writer.writerow(
            [
                f.risk_score,
                f.risk_level,
                f.merchant.business_name,
                f.get_status_display(),
                rule_labels,
                f.detected_at.strftime("%d/%m/%Y %H:%M"),
            ]
        )

    return response


def export_risk_report_pdf(date_from, date_to) -> HttpResponse:
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

    elements = [
        Paragraph("<b>SATIM × Surveillance des Risques</b> — Rapport des Alertes", styles["Heading1"]),
        Paragraph(
            "Notice : Une transaction ou activité signalée n'est pas automatiquement frauduleuse. "
            "Le système identifie un risque ; l'administrateur décide.",
            ParagraphStyle("Warning", parent=styles["Normal"], textColor=colors.HexColor("#B71C1C"), fontSize=9),
        ),
        Spacer(1, 15),
    ]

    flags = RiskFlag.objects.filter(detected_at__range=(date_from, date_to)).order_by("-risk_score")[:100]
    headers = ["Score", "Niveau", "Commerçant", "Statut", "Règles déclenchées", "Date de détection"]
    rows = [headers]
    for f in flags:
        rule_labels = ", ".join(r.get("label_fr", r.get("code", "")) for r in f.triggered_rules[:2])
        rows.append(
            [
                f"{f.risk_score}/100",
                f.risk_level,
                f.merchant.business_name[:25],
                f.get_status_display(),
                rule_labels[:45],
                f.detected_at.strftime("%d/%m/%Y %H:%M"),
            ]
        )

    table = Table(rows, colWidths=[70, 70, 170, 130, 200, 110])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E53A2F")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#E6E8EB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F9F9F9")]),
                ("PADDING", (0, 0), (-1, -1), 5),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(table)

    doc.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
    response["Content-Disposition"] = 'attachment; filename="rapport_risques_satim.pdf"'
    return response
