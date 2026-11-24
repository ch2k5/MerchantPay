from rest_framework import renderers
from rest_framework.negotiation import DefaultContentNegotiation


class PassthroughRenderer(renderers.BaseRenderer):
    """
    A renderer that performs no rendering and allows binary/file streams
    (PDF, CSV, Excel, etc.) to pass through untouched.
    """
    media_type = "*/*"
    format = "txt"

    def render(self, data, accepted_media_type=None, renderer_context=None):
        return data


class IgnoreClientContentNegotiation(DefaultContentNegotiation):
    """
    Content negotiation that allows file download endpoints to ignore the
    client ?format= query parameter and return whatever HttpResponse
    (PDF/CSV) the view generates.
    """
    def select_renderer(self, request, renderers, format_suffix=None):
        return (renderers[0], renderers[0].media_type)
