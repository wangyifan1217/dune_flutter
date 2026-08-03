import 'ctrip_h5_browser_stub.dart'
    if (dart.library.html) 'ctrip_h5_browser_web.dart';

import 'ctrip_h5_service.dart';

Future<bool> openCtripH5InBrowser(CtripH5Form form) {
  return openCtripH5InBrowserImpl(form.browserUri());
}
