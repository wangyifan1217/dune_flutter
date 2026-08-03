import 'dart:html' as html;

Future<bool> openCtripH5InBrowserImpl(Uri uri) async {
  // 浏览器版本使用携程文档提供的 SsoData GET 方式，并在当前标签页打开，
  // 这样用户可以用浏览器返回键回到沙丘工作台。
  html.window.location.assign(uri.toString());
  return true;
}
