import 'package:mime/mime.dart' as mime_pkg;

/// Extensões que o pacote `mime` não reconhece de fábrica (ou reconhece
/// de forma inconsistente entre plataformas), comuns em álbuns de fotos
/// do Android/iOS.
const Map<String, String> _extraMimeTypes = {
  'heic': 'image/heic',
  'heif': 'image/heif',
  'gif': 'image/gif',
};

/// Resolve o MIME type a partir do nome do arquivo (extensão).
/// Cobre JPG/JPEG, PNG, WEBP, GIF, HEIC/HEIF e cai para
/// 'application/octet-stream' se não reconhecer a extensão.
String resolveMimeType(String fileName) {
  final byExtension = mime_pkg.lookupMimeType(fileName);
  if (byExtension != null) return byExtension;

  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  return _extraMimeTypes[ext] ?? 'application/octet-stream';
}
