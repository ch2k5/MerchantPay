import 'dart:typed_data';
import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as platform;

/// Downloads raw bytes as a file with the specified filename and MIME type.
/// Uses native web Blob / Anchor download on Web, and stubs/logs on desktop/server VM.
void saveFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  platform.saveBytesToFile(Uint8List.fromList(bytes), filename, mimeType);
}
