import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

Future<void> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  throw UnsupportedError('请使用系统分享或浏览器打开下载链接');
}

Future<void> openUrlAsFileImpl(String url, String fileName) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('下载链接无效');
  // ignore: depend_on_referenced_packages
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) throw Exception('无法打开下载链接');
}
