import 'package:flutter/widgets.dart';

import 'cors_safe_image_stub.dart'
    if (dart.library.html) 'cors_safe_image_web.dart';

Widget buildCorsSafeImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  /// Web 的 HtmlElementView 会吃掉点击；气泡等需要外层 GestureDetector 时打开。
  bool hitTestOverlay = false,
}) {
  return buildCorsSafeImageImpl(
    url: url,
    width: width,
    height: height,
    fit: fit,
    hitTestOverlay: hitTestOverlay,
  );
}
