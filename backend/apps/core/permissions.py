from rest_framework.permissions import SAFE_METHODS, BasePermission

from apps.core.enums import AdminLevel, MerchantStatus, UserRole


class IsMerchant(BasePermission):
    """
    Allows access only to active merchants.
    """

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if user.role != UserRole.MERCHANT:
            return False
        if not hasattr(user, "merchant"):
            return False
        if user.merchant.status != MerchantStatus.ACTIVE:
            return False
        return True


class IsAdmin(BasePermission):
    """
    Allows access only to SATIM administrators.
    """

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.role == UserRole.ADMIN)


class IsSuperAdmin(BasePermission):
    """
    Allows access only to SUPER_ADMIN level administrators.
    """

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and user.role == UserRole.ADMIN
            and user.admin_level == AdminLevel.SUPER_ADMIN
        )


class IsAnalystOrAbove(BasePermission):
    """
    Allows write operations to SUPER_ADMIN and ANALYST.
    VIEWER is restricted to read-only (SAFE_METHODS).
    """

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and user.role == UserRole.ADMIN):
            return False
        if request.method in SAFE_METHODS:
            return True
        return user.admin_level in [AdminLevel.SUPER_ADMIN, AdminLevel.ANALYST]


class AdminActionPermission(BasePermission):
    """
    Generic permission to check if admin can perform a write operation.
    """

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and user.role == UserRole.ADMIN):
            return False
        if request.method in SAFE_METHODS:
            return True
        return user.admin_level != AdminLevel.VIEWER
