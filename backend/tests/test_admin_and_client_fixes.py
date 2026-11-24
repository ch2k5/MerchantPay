from decimal import Decimal
import pytest
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.core.enums import AdminLevel, MerchantStatus, RiskLevel, RiskStatus, UserRole
from apps.risk.models import RiskFlag


@pytest.mark.django_db
class TestAdminAndClientFixes:
    def test_admin_dashboard_keys_and_kpis(self, admin_user, merchant_user):
        """
        Verify Admin Dashboard provides all keys expected by Flutter AdminDashboardScreen:
        kpis, comparison, risk_distribution, top_merchants_by_rejections, top_merchants_by_revenue.
        """
        client = APIClient()
        client.force_authenticate(user=admin_user)

        res = client.get("/api/v1/admin/dashboard/?preset=30d")
        assert res.status_code == status.HTTP_200_OK

        data = res.data
        assert "kpis" in data
        assert "comparison" in data
        assert "risk_distribution" in data
        assert "top_merchants_by_rejections" in data
        assert "top_merchants_by_revenue" in data

        kpis = data["kpis"]
        assert "total_volume" in kpis
        assert "transaction_count" in kpis
        assert "success_rate" in kpis
        assert "active_merchants_count" in kpis
        assert "total_merchants_count" in kpis

    def test_admin_url_aliases_resolve(self, admin_user):
        """
        Verify /admin/risk/ and /admin/audit/ alias endpoints resolve to 200.
        """
        client = APIClient()
        client.force_authenticate(user=admin_user)

        res_risk = client.get("/api/v1/admin/risk/")
        assert res_risk.status_code == status.HTTP_200_OK

        res_audit = client.get("/api/v1/admin/audit/")
        assert res_audit.status_code == status.HTTP_200_OK

    def test_merchant_toggle_active_status(self, admin_user, merchant_user):
        """
        Verify /admin/merchants/{id}/toggle-active/ successfully toggles merchant status.
        """
        client = APIClient()
        client.force_authenticate(user=admin_user)
        merchant = merchant_user.merchant

        init_status = merchant.status
        res = client.post(
            f"/api/v1/admin/merchants/{merchant.id}/toggle-active/",
            data={"reason": "Suspension temporaire pour vérification"},
        )
        assert res.status_code == status.HTTP_200_OK
        merchant.refresh_from_db()
        assert merchant.status != init_status

        # Toggle back
        res2 = client.post(
            f"/api/v1/admin/merchants/{merchant.id}/toggle-active/",
            data={"reason": "Rétablissement du compte"},
        )
        assert res2.status_code == status.HTTP_200_OK
        merchant.refresh_from_db()
        assert merchant.status == init_status

    def test_admin_risk_flag_status_and_notes(self, admin_user, merchant_user):
        """
        Verify risk status update via POST with frontend status codes and note creation.
        """
        client = APIClient()
        client.force_authenticate(user=admin_user)
        merchant = merchant_user.merchant

        flag = RiskFlag.objects.create(
            merchant=merchant,
            risk_score=75,
            risk_level=RiskLevel.HIGH,
            status=RiskStatus.NEW,
            reasons=["Volume inhabituel"],
            triggered_rules=[{"rule_name": "R_VELOCITY", "score_delta": 40}],
        )

        # Status update via POST with UNDER_REVIEW
        res_status = client.post(
            f"/api/v1/admin/risk/{flag.id}/status/",
            data={"status": "UNDER_REVIEW", "note": "Prise en charge par l'analyste"},
        )
        assert res_status.status_code == status.HTTP_200_OK
        flag.refresh_from_db()
        assert flag.status == RiskStatus.UNDER_INVESTIGATION

        # Add investigation note with 'note' key
        res_note = client.post(
            f"/api/v1/admin/risk/{flag.id}/notes/",
            data={"note": "Justificatif d'activité conforme."},
        )
        assert res_note.status_code == status.HTTP_201_CREATED
        assert "note" in res_note.data
        assert res_note.data["note"] == "Justificatif d'activité conforme."

        # Verify SATIM note is pushed as a MerchantAlert
        from apps.alerts.models import MerchantAlert
        from apps.core.enums import AlertType
        admin_alert = MerchantAlert.objects.filter(
            merchant=merchant,
            type=AlertType.ADMIN_OBSERVATION,
        ).first()
        assert admin_alert is not None
        assert "Justificatif d'activité conforme." in admin_alert.message

    def test_merchant_transaction_decline_and_refund(self, merchant_user):
        """
        Verify merchant can decline an accepted transaction and issue refunds.
        """
        from apps.transactions.models import Transaction
        from apps.core.enums import PaymentChannel, TransactionStatus
        from django.utils import timezone

        merchant = merchant_user.merchant
        client = APIClient()
        client.force_authenticate(user=merchant_user)

        # Create an accepted transaction for testing
        tx = Transaction.objects.create(
            merchant=merchant,
            reference="TX-DEC-REF-TEST-001",
            amount=Decimal("12500.00"),
            payment_channel=PaymentChannel.CIB,
            transaction_status=TransactionStatus.ACCEPTED,
            transaction_date=timezone.now(),
        )

        # 1. Partial refund test
        res_refund = client.post(
            f"/api/v1/merchant/transactions/{tx.transaction_id}/refund/",
            data={"refund_amount": "5000.00"},
        )
        assert res_refund.status_code == status.HTTP_200_OK
        tx.refresh_from_db()
        assert tx.refunded_amount == Decimal("5000.00")
        assert tx.transaction_status in ["Accepted", "ACCEPTED"]

        # 2. Decline test
        res_decline = client.post(
            f"/api/v1/merchant/transactions/{tx.transaction_id}/decline/",
        )
        assert res_decline.status_code == status.HTTP_200_OK
        tx.refresh_from_db()
        assert tx.transaction_status == "Declined"
        assert tx.rejection_reason == "Refus commerçant"

    def test_admin_user_creation_with_role_and_names(self, admin_user):
        """
        Verify admin user creation accepts first_name, last_name, and role from frontend dropdown.
        """
        client = APIClient()
        client.force_authenticate(user=admin_user)

        new_email = "nouvel_analyste_satim@satim.dz"
        User.objects.filter(email=new_email).delete()

        res = client.post(
            "/api/v1/admin/users/",
            data={
                "email": new_email,
                "password": "SuperSecretPassword123!",
                "first_name": "Amine",
                "last_name": "Khelifi",
                "role": "ANALYST",
            },
        )
        assert res.status_code == status.HTTP_201_CREATED
        created_user = User.objects.get(email=new_email)
        assert created_user.role == UserRole.ADMIN
        assert created_user.admin_level == AdminLevel.ANALYST
        assert "Amine" in created_user.full_name
        created_user.delete()

    def test_merchant_analytics_view_returns_ok_with_statistics(self, merchant_user):
        """
        Verify merchant analytics endpoint returns 200 without NameError and contains statistics.
        """
        client = APIClient()
        client.force_authenticate(user=merchant_user)

        res = client.get("/api/v1/merchant/analytics/?preset=30d&granularity=day")
        assert res.status_code == status.HTTP_200_OK
        data = res.data
        assert "kpis" in data
        assert "trends" in data
        assert "statistics" in data
        assert "heatmap" in data
        assert "histogram" in data["statistics"]
        assert "boxplot" in data["statistics"]
