import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget buildCorsSafeImageImpl({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
}) {
  final viewType = 'dunes-cors-img-${url.hashCode}-${fit.name}-${width.toInt()}-${height.toInt()}';
  if (!_registeredViewTypes.contains(viewType)) {
    _registeredViewTypes.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final root = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none'
        ..style.overflow = 'hidden';
      final img = html.ImageElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _cssObjectFit(fit)
        ..style.pointerEvents = 'none'
        ..style.display = 'block';
      root.append(img);
      return root;
    });
  }
  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}

String _cssObjectFit(BoxFit fit) {
  switch (fit) {
    case BoxFit.fill:
      return 'fill';
    case BoxFit.contain:
      return 'contain';
    case BoxFit.cover:
      return 'cover';
    case BoxFit.fitWidth:
      return 'scale-down';
    case BoxFit.fitHeight:
      return 'scale-down';
    case BoxFit.none:
      return 'none';
    case BoxFit.scaleDown:
      return 'scale-down';
  }
}
