import 'dart:html' as html;

Future<bool> openXrxsH5InBrowserImpl(Uri uri) async {
  html.window.location.assign(uri.toString());
  return true;
}
