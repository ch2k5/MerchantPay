from django.contrib.auth import authenticate
from rest_framework import serializers

from apps.accounts.models import User
from apps.core.enums import AdminLevel, MerchantCategory, MerchantStatus, UserRole
from apps.merchants.models import Merchant


class MerchantDetailSerializer(serializers.ModelSerializer):
    class Meta:
        model = Merchant
        fields = [
            "id",
            "merchant_code",
            "business_name",
            "merchant_category",
            "address",
            "wilaya",
            "phone",
            "email",
            "registration_number",
            "terminal_count",
            "monthly_goal",
            "status",
            "created_at",
        ]


class UserSerializer(serializers.ModelSerializer):
    merchant = MerchantDetailSerializer(read_only=True)

    class Meta:
        model = User
        fields = [
            "id",
            "email",
            "full_name",
            "role",
            "admin_level",
            "is_active",
            "created_at",
            "merchant",
        ]


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    full_name = serializers.CharField(max_length=255)
    # Merchant fields
    business_name = serializers.CharField(max_length=255)
    merchant_category = serializers.ChoiceField(choices=MerchantCategory.choices)
    registration_number = serializers.CharField(max_length=64)
    wilaya = serializers.CharField(max_length=100)
    address = serializers.CharField(max_length=255, required=False, allow_blank=True)
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    terminal_count = serializers.IntegerField(default=1, min_value=1)
    monthly_goal = serializers.DecimalField(max_digits=14, decimal_places=2, required=False, allow_null=True)

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("Cette adresse email est déjà enregistrée.")
        return value.lower()

    def create(self, validated_data):
        email = validated_data.pop("email")
        password = validated_data.pop("password")
        full_name = validated_data.pop("full_name")

        user = User.objects.create_user(
            email=email,
            password=password,
            full_name=full_name,
            role=UserRole.MERCHANT,
        )

        # Generate unique merchant code
        count = Merchant.objects.count() + 1
        merchant_code = f"MRC-{count:04d}"
        while Merchant.objects.filter(merchant_code=merchant_code).exists():
            count += 1
            merchant_code = f"MRC-{count:04d}"

        merchant = Merchant.objects.create(
            owner=user,
            merchant_code=merchant_code,
            email=email,
            **validated_data,
        )
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs.get("email", "").lower().strip()
        password = attrs.get("password")

        user = authenticate(username=email, password=password)
        if not user:
            # Check if user exists but is inactive or merchant is inactive
            user_obj = User.objects.filter(email__iexact=email).first()
            if user_obj and user_obj.check_password(password):
                if (
                    user_obj.role == UserRole.MERCHANT
                    and hasattr(user_obj, "merchant")
                    and user_obj.merchant.status == MerchantStatus.INACTIVE
                ):
                    raise serializers.ValidationError("Votre compte est désactivé. Contactez SATIM.")
                if not user_obj.is_active:
                    raise serializers.ValidationError("Votre compte est désactivé. Contactez SATIM.")
            raise serializers.ValidationError("Identifiants incorrects. Veuillez vérifier votre email et mot de passe.")

        if not user.is_active:
            raise serializers.ValidationError("Votre compte est désactivé. Contactez SATIM.")

        if user.role == UserRole.MERCHANT:
            if hasattr(user, "merchant") and user.merchant.status == MerchantStatus.INACTIVE:
                raise serializers.ValidationError("Votre compte est désactivé. Contactez SATIM.")

        attrs["user"] = user
        return attrs


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate_old_password(self, value):
        user = self.context["request"].user
        if not user.check_password(value):
            raise serializers.ValidationError("L'ancien mot de passe est incorrect.")
        return value


class AdminUserManagementSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8, required=False)

    class Meta:
        model = User
        fields = [
            "id",
            "email",
            "full_name",
            "role",
            "admin_level",
            "is_active",
            "created_at",
            "password",
        ]

    def create(self, validated_data):
        password = validated_data.pop("password", None)
        validated_data["role"] = UserRole.ADMIN
        if "admin_level" not in validated_data:
            validated_data["admin_level"] = AdminLevel.VIEWER
        user = User.objects.create_user(**validated_data)
        if password:
            user.set_password(password)
            user.save()
        return user
