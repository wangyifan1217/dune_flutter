import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveImageToGalleryImpl(Uint8List bytes, String fileName) async {
  final blob = html.Blob(<Uint8List>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'image.jpg' : fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
