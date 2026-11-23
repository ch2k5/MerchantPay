import logging

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger(__name__)


def custom_exception_handler(exc, context):
    """
    Standardizes error responses to:
    {"code": "...", "message": "...(fr)", "details": {...}}
    """
    response = exception_handler(exc, context)

    if response is not None:
        data = response.data
        code = getattr(exc, "default_code", "ERROR")
        if isinstance(code, str):
            code = code.upper()

        if isinstance(data, dict):
            if "detail" in data:
                message = str(data["detail"])
                details = {k: v for k, v in data.items() if k != "detail"}
            else:
                message = "Une erreur de validation des données est survenue."
                details = data
        elif isinstance(data, list):
            message = "Erreurs multiples rencontrées."
            details = {"errors": data}
        else:
            message = str(data)
            details = {}

        response.data = {
            "code": code or "ERROR",
            "message": message,
            "details": details,
        }
    else:
        logger.exception("Unhandled server exception: %s", exc)
        response = Response(
            {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "Une erreur interne est survenue sur le serveur. Veuillez réessayer ultérieurement.",
                "details": {},
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    return response
