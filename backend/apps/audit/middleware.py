class AuditMiddleware:
    """
    Middleware to attach remote IP to request object for audit logging.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        return self.get_response(request)
