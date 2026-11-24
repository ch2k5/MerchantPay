import pytest
from rest_framework.test import APIClient
from apps.accounts.models import User
from apps.core.enums import UserRole, AdminLevel
from apps.merchants.models import Merchant


@pytest.mark.django_db
class TestReportsAPI:
    def test_admin_reports_generate_platform_pdf(self, api_client, admin_user):
        api_client.force_authenticate(user=admin_user)
        res = api_client.post("/api/v1/admin/reports/generate/", {
            "report_type": "MONTHLY_VOLUME",
            "format": "pdf",
            "preset": "30d",
        })
        assert res.status_code == 200
        assert res["Content-Type"] == "application/pdf"
        assert len(res.content) > 100

    def test_admin_reports_generate_merchants_pdf(self, api_client, admin_user):
        api_client.force_authenticate(user=admin_user)
        res = api_client.post("/api/v1/admin/reports/generate/", {
            "report_type": "MERCHANT_ACTIVITY",
            "format": "pdf",
        })
        assert res.status_code == 200
        assert res["Content-Type"] == "application/pdf"
        assert len(res.content) > 100

    def test_admin_reports_generate_risk_pdf(self, api_client, admin_user):
        api_client.force_authenticate(user=admin_user)
        res = api_client.post("/api/v1/admin/reports/generate/", {
            "report_type": "RISK_AUDIT",
            "format": "pdf",
            "preset": "30d",
        })
        assert res.status_code == 200
        assert res["Content-Type"] == "application/pdf"
        assert len(res.content) > 100

    def test_admin_reports_generate_csv(self, api_client, admin_user):
        api_client.force_authenticate(user=admin_user)
        res = api_client.get("/api/v1/admin/reports/generate/", {"report_type": "MONTHLY_VOLUME", "format": "csv"})
        assert res.status_code == 200
        assert "text/csv" in res["Content-Type"]
        assert len(res.content) > 50

    def test_merchant_reports_generate_pdf(self, api_client, merchant_user):
        api_client.force_authenticate(user=merchant_user)
        res = api_client.post("/api/v1/merchant/reports/generate/", {
            "format": "pdf",
            "preset": "30d",
        })
        assert res.status_code == 200
        assert res["Content-Type"] == "application/pdf"
        assert len(res.content) > 100

    def test_merchant_reports_generate_csv(self, api_client, merchant_user):
        api_client.force_authenticate(user=merchant_user)
        res = api_client.get("/api/v1/merchant/reports/generate/", {"format": "csv", "preset": "30d"})
        assert res.status_code == 200
        assert "text/csv" in res["Content-Type"]
        assert len(res.content) > 50
