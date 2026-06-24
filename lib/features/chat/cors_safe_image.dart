import 'package:flutter/widgets.dart';

import 'cors_safe_image_stub.dart'
    if (dart.library.html) 'cors_safe_image_web.dart';

Widget buildCorsSafeImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
}) {
  return buildCorsSafeImageImpl(
    url: url,
    width: width,
    height: height,
    fit: fit,
  );
}
