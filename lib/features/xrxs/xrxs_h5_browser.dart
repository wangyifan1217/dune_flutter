import 'xrxs_h5_browser_stub.dart'
    if (dart.library.html) 'xrxs_h5_browser_web.dart';

Future<bool> openXrxsH5InBrowser(Uri uri) {
  return openXrxsH5InBrowserImpl(uri);
}
