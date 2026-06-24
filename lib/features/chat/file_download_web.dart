import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  final blob = html.Blob(<Uint8List>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'download' : fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<void> openUrlAsFileImpl(String url, String fileName) async {
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'download' : fileName
    ..target = '_blank'
    ..rel = 'noopener'
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
}
