import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  final blob = html.Blob(<Uint8List>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'download' : fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return null;
}

Future<String?> openUrlAsFileImpl(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
}) async {
  onProgress?.call(0);
  try {
    final response = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'blob',
    );
    final blob = response.response as html.Blob?;
    if (blob != null) {
      onProgress?.call(1);
      return saveBytesAsFileImpl(
        Uint8List.fromList(await _blobToBytes(blob)),
        fileName,
      );
    }
  } catch (_) {
    /* fall through to anchor download */
  }

  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'download' : fileName
    ..rel = 'noopener'
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  onProgress?.call(1);
  return null;
}

Future<List<int>> _blobToBytes(html.Blob blob) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(blob);
  await reader.onLoad.first;
  return (reader.result as ByteBuffer).asUint8List();
}
