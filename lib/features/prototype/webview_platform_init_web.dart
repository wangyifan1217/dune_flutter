import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

/// Web 平台必须手动注册 WebView 实现。
void initWebViewPlatform() {
  WebViewPlatform.instance = WebWebViewPlatform();
}
