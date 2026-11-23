from decimal import Decimal

import pytest
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import User
from apps.core.enums import (
    AdminLevel,
    MerchantCategory,
    MerchantStatus,
    UserRole,
)
from apps.merchants.models import Merchant


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def super_admin_user(db):
    return User.objects.create_superuser(
        email="superadmin@satim.dz",
        password="Password123!",
        full_name="Super Admin SATIM",
    )


@pytest.fixture
def analyst_user(db):
    return User.objects.create_user(
        email="analyst@satim.dz",
        password="Password123!",
        full_name="Analyste SATIM",
        role=UserRole.ADMIN,
        admin_level=AdminLevel.ANALYST,
    )


@pytest.fixture
def viewer_user(db):
    return User.objects.create_user(
        email="viewer@satim.dz",
        password="Password123!",
        full_name="Observateur SATIM",
        role=UserRole.ADMIN,
        admin_level=AdminLevel.VIEWER,
    )


@pytest.fixture
def merchant_user(db):
    user = User.objects.create_user(
        email="marchand1@merchantpay.dz",
        password="Password123!",
        full_name="Commerçant Un",
        role=UserRole.MERCHANT,
    )
    Merchant.objects.create(
        owner=user,
        merchant_code="MRC-0001",
        business_name="Supermarché Un",
        merchant_category=MerchantCategory.COMMERCE_DETAIL,
        wilaya="Alger",
        address="12 Rue Didouche, Alger",
        phone="+213 21 00 11 22",
        email="marchand1@merchantpay.dz",
        registration_number="16/00-1234567B22",
        terminal_count=2,
        monthly_goal=Decimal("1000000.00"),
        status=MerchantStatus.ACTIVE,
    )
    return user


@pytest.fixture
def merchant_user_2(db):
    user = User.objects.create_user(
        email="marchand2@merchantpay.dz",
        password="Password123!",
        full_name="Commerçant Deux",
        role=UserRole.MERCHANT,
    )
    Merchant.objects.create(
        owner=user,
        merchant_code="MRC-0002",
        business_name="Café Deux",
        merchant_category=MerchantCategory.RESTAURATION,
        wilaya="Oran",
        address="Boulevard Front de Mer, Oran",
        phone="+213 41 22 33 44",
        email="marchand2@merchantpay.dz",
        registration_number="31/00-7654321B21",
        terminal_count=1,
        monthly_goal=Decimal("500000.00"),
        status=MerchantStatus.ACTIVE,
    )
    return user


@pytest.fixture
def inactive_merchant_user(db):
    user = User.objects.create_user(
        email="inactif@merchantpay.dz",
        password="Password123!",
        full_name="Commerçant Inactif",
        role=UserRole.MERCHANT,
        is_active=False,
    )
    Merchant.objects.create(
        owner=user,
        merchant_code="MRC-0999",
        business_name="Boutique Inactive",
        merchant_category=MerchantCategory.HABILLEMENT,
        wilaya="Blida",
        registration_number="09/00-9999999B20",
        status=MerchantStatus.INACTIVE,
    )
    return user


def authenticate_client(client, user):
    refresh = RefreshToken.for_user(user)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
    return client
