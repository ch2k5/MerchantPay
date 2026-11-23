from drf_spectacular.utils import extend_schema
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.serializers import (
    ChangePasswordSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserSerializer,
)
from apps.audit.services import record_audit
from apps.core.enums import AuditAction


class LoginRateThrottle(AnonRateThrottle):
    rate = "5/minute"
    scope = "login"


class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    @extend_schema(request=RegisterSerializer, responses={201: UserSerializer})
    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            refresh = RefreshToken.for_user(user)
            record_audit(
                request=request,
                actor=user,
                action="REGISTER",
                target_type="Merchant",
                target_id=str(user.merchant.id),
                after={"business_name": user.merchant.business_name, "email": user.email},
            )
            return Response(
                {
                    "user": UserSerializer(user).data,
                    "access": str(refresh.access_token),
                    "refresh": str(refresh),
                },
                status=status.HTTP_201_CREATED,
            )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes = [LoginRateThrottle]

    @extend_schema(request=LoginSerializer)
    def post(self, request):
        serializer = LoginSerializer(data=request.data, context={"request": request})
        if serializer.is_valid():
            user = serializer.validated_data["user"]
            refresh = RefreshToken.for_user(user)
            record_audit(
                request=request,
                actor=user,
                action=AuditAction.LOGIN,
                target_type="User",
                target_id=str(user.id),
                after={"email": user.email, "role": user.role},
            )
            return Response(
                {
                    "user": UserSerializer(user).data,
                    "access": str(refresh.access_token),
                    "refresh": str(refresh),
                }
            )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LogoutView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh")
        if not refresh_token:
            return Response(
                {"code": "MISSING_TOKEN", "message": "Le jeton de rafraîchissement est requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response({"message": "Déconnexion réussie."})
        except Exception:
            return Response(
                {"code": "INVALID_TOKEN", "message": "Jeton invalide ou déjà révoqué."},
                status=status.HTTP_400_BAD_REQUEST,
            )


class MeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @extend_schema(responses={200: UserSerializer})
    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)


class ChangePasswordView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @extend_schema(request=ChangePasswordSerializer)
    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data, context={"request": request})
        if serializer.is_valid():
            user = request.user
            user.set_password(serializer.validated_data["new_password"])
            user.save()
            record_audit(
                request=request,
                actor=user,
                action=AuditAction.PASSWORD_CHANGED,
                target_type="User",
                target_id=str(user.id),
            )
            return Response({"message": "Mot de passe modifié avec succès."})
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
