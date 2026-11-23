import pytest
from rest_framework import status

from apps.core.enums import UserRole
from tests.conftest import authenticate_client


@pytest.mark.django_db
class TestAuthAPI:
    def test_merchant_registration_success(self, api_client):
        payload = {
            "email": "nouveau@merchantpay.dz",
            "password": "Password123!",
            "full_name": "Karim Commerçant",
            "business_name": "Boulangerie El Baraka",
            "merchant_category": "Alimentation",
            "registration_number": "16/00-8888888B23",
            "wilaya": "Alger",
            "address": "El Biar, Alger",
            "phone": "+213 21 92 00 00",
            "terminal_count": 2,
            "monthly_goal": "800000.00",
        }
        res = api_client.post("/api/v1/auth/register/", payload, format="json")
        assert res.status_code == status.HTTP_201_CREATED
        data = res.data
        assert "access" in data
        assert "refresh" in data
        assert data["user"]["email"] == "nouveau@merchantpay.dz"
        assert data["user"]["role"] == UserRole.MERCHANT
        assert data["user"]["merchant"]["business_name"] == "Boulangerie El Baraka"

    def test_registration_validation_short_password(self, api_client):
        payload = {
            "email": "court@merchantpay.dz",
            "password": "pass",  # < 8 chars
            "full_name": "Test Short",
            "business_name": "Test Commerce",
            "merchant_category": "Alimentation",
            "registration_number": "16/00-1111111B23",
            "wilaya": "Alger",
        }
        res = api_client.post("/api/v1/auth/register/", payload, format="json")
        assert res.status_code == status.HTTP_400_BAD_REQUEST

    def test_login_success_merchant(self, api_client, merchant_user):
        payload = {"email": "marchand1@merchantpay.dz", "password": "Password123!"}
        res = api_client.post("/api/v1/auth/login/", payload, format="json")
        assert res.status_code == status.HTTP_200_OK
        assert "access" in res.data
        assert res.data["user"]["role"] == UserRole.MERCHANT

    def test_login_inactive_merchant_blocked(self, api_client, inactive_merchant_user):
        payload = {"email": "inactif@merchantpay.dz", "password": "Password123!"}
        res = api_client.post("/api/v1/auth/login/", payload, format="json")
        assert res.status_code == status.HTTP_400_BAD_REQUEST
        error_msg = str(res.data)
        assert "Votre compte est désactivé. Contactez SATIM." in error_msg or "inactif" in error_msg

    def test_me_endpoint_authenticated(self, api_client, merchant_user):
        authenticate_client(api_client, merchant_user)
        res = api_client.get("/api/v1/auth/me/")
        assert res.status_code == status.HTTP_200_OK
        assert res.data["email"] == merchant_user.email
        assert res.data["merchant"]["merchant_code"] == "MRC-0001"

    def test_me_endpoint_unauthenticated(self, api_client):
        res = api_client.get("/api/v1/auth/me/")
        assert res.status_code == status.HTTP_401_UNAUTHORIZED

    def test_change_password_success(self, api_client, merchant_user):
        authenticate_client(api_client, merchant_user)
        payload = {
            "old_password": "Password123!",
            "new_password": "NewStrongPassword2026!",
        }
        res = api_client.post("/api/v1/auth/change-password/", payload, format="json")
        assert res.status_code == status.HTTP_200_OK
        assert res.data["message"] == "Mot de passe modifié avec succès."
