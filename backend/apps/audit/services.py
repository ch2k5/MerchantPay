from apps.audit.models import AuditLog


def get_client_ip(request) -> str | None:
    if not request:
        return None
    x_forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
    if x_forwarded_for:
        return x_forwarded_for.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


def record_audit(
    request=None,
    actor=None,
    action: str = "",
    target_type: str = "",
    target_id: str = "",
    before: dict | None = None,
    after: dict | None = None,
) -> AuditLog:
    user = actor
    ip = None
    if request:
        if user is None and getattr(request, "user", None) and request.user.is_authenticated:
            user = request.user
        ip = get_client_ip(request)

    return AuditLog.objects.create(
        actor=user,
        action=action,
        target_type=target_type,
        target_id=str(target_id),
        before=before,
        after=after,
        ip_address=ip,
    )
