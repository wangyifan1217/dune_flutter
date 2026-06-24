import 'package:flutter/widgets.dart';

Widget buildCorsSafeImageImpl({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
}) {
  return Image.network(
    url,
    width: width,
    height: height,
    fit: fit,
    gaplessPlayback: true,
  );
}
