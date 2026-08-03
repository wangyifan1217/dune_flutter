import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget buildCorsSafeImageImpl({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  bool hitTestOverlay = false,
}) {
  final viewType =
      'dunes-cors-img-${url.hashCode}-${fit.name}-${width.toInt()}-${height.toInt()}';
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
  final view = SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
  if (!hitTestOverlay) return view;
  // HtmlElementView 在 Flutter Web 上仍会占据命中测试，挡掉外层 onTap。
  // 盖一层透明 Flutter 组件，让气泡 GestureDetector 能收到点击。
  return SizedBox(
    width: width,
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        view,
        const ColoredBox(color: Color(0x00000000)),
      ],
    ),
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
