import 'package:flutter/foundation.dart';

void saveBytesToFile(Uint8List bytes, String filename, String mimeType) {
  debugPrint('[FileSaver] Enregistrement simulé de $filename (${bytes.length} octets, type: $mimeType)');
}
