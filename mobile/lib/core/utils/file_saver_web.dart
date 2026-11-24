import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void saveBytesToFile(Uint8List bytes, String filename, String mimeType) {
  try {
    final blobParts = [bytes.toJS].toJS;
    final blobPropertyBag = web.BlobPropertyBag(type: mimeType);
    final blob = web.Blob(blobParts, blobPropertyBag);
    final url = web.URL.createObjectURL(blob);

    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    web.document.body?.appendChild(anchor);
    anchor.click();
    web.document.body?.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  } catch (e) {
    // Fallback if web library has issues
  }
}
