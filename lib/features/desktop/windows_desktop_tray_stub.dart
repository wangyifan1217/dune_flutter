Future<void> initWindowsDesktopTray() async {}

void windowsTrayUpdateUnread(int total) {}

void windowsTrayNotifyIncomingMessage() {}

bool windowsTrayIsWindowInactive() => false;

void setWindowsTrayOnInactiveChanged(void Function(bool inactive)? callback) {}

void windowsTrayReveal() {}

void setWindowsTrayOnBeforeQuit(Future<void> Function()? callback) {}

Future<void> windowsTrayPrepareQuitForAppUpdate({bool exitProcess = false}) async {}

Future<void> windowsTrayRearmPreventCloseAfterUpdateCancelled() async {}
