import pytest
from rest_framework import status

from apps.transactions.models import Transaction
from tests.conftest import authenticate_client


@pytest.mark.django_db
class TestPermissionsAndScoping:
    def test_merchant_cannot_access_admin_endpoints(self, api_client, merchant_user):
        authenticate_client(api_client, merchant_user)
        # Attempt to reach admin dashboard
        res = api_client.get("/api/v1/admin/dashboard/")
        assert res.status_code == status.HTTP_403_FORBIDDEN

        # Attempt to reach admin audit logs
        res = api_client.get("/api/v1/admin/audit-logs/")
        assert res.status_code == status.HTTP_403_FORBIDDEN

    def test_merchant_cannot_see_other_merchant_data(self, api_client, merchant_user, merchant_user_2):
        # Create transaction for merchant 2
        tx_m2 = Transaction.objects.create(
            reference="TX-MERCHANT2-SECRET",
            merchant=merchant_user_2.merchant,
            transaction_date="2026-11-20T10:00:00Z",
            amount="50000.00",
            payment_channel="CIB",
            transaction_status="ACCEPTED",
            merchant_category=merchant_user_2.merchant.merchant_category,
        )

        # Login as merchant 1
        authenticate_client(api_client, merchant_user)

        # 1. Listing should not contain merchant 2's transaction
        res = api_client.get("/api/v1/merchant/transactions/")
        assert res.status_code == status.HTTP_200_OK
        results = res.data["results"]
        refs = [t["reference"] for t in results]
        assert "TX-MERCHANT2-SECRET" not in refs

        # 2. Detail of merchant 2's transaction should 404 for merchant 1
        res_detail = api_client.get(f"/api/v1/merchant/transactions/{tx_m2.transaction_id}/")
        assert res_detail.status_code == status.HTTP_404_NOT_FOUND

    def test_admin_viewer_is_read_only(self, api_client, viewer_user, merchant_user):
        authenticate_client(api_client, viewer_user)

        # Viewer can read admin dashboard
        res = api_client.get("/api/v1/admin/dashboard/")
        assert res.status_code == status.HTTP_200_OK

        # Viewer cannot write / patch merchant
        m_id = merchant_user.merchant.id
        res_patch = api_client.patch(
            f"/api/v1/admin/merchants/{m_id}/",
            {"phone": "+213 99 99 99 99"},
            format="json",
        )
        assert res_patch.status_code == status.HTTP_403_FORBIDDEN

    def test_super_admin_only_for_deactivation_and_audit(
        self, api_client, analyst_user, super_admin_user, merchant_user
    ):
        m_id = merchant_user.merchant.id

        # Analyst cannot deactivate
        authenticate_client(api_client, analyst_user)
        res_deact = api_client.post(
            f"/api/v1/admin/merchants/{m_id}/deactivate/",
            {"reason": "Dossier suspendu"},
            format="json",
        )
        assert res_deact.status_code == status.HTTP_403_FORBIDDEN

        # Super admin can deactivate
        authenticate_client(api_client, super_admin_user)
        res_deact_ok = api_client.post(
            f"/api/v1/admin/merchants/{m_id}/deactivate/",
            {"reason": "Suspension administrative"},
            format="json",
        )
        assert res_deact_ok.status_code == status.HTTP_200_OK
        assert res_deact_ok.data["merchant"]["status"] == "INACTIVE"
