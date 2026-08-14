#ifndef RUNNER_TRAY_PEEK_H_
#define RUNNER_TRAY_PEEK_H_

#include <flutter/binary_messenger.h>

void RegisterTrayPeekChannel(flutter::BinaryMessenger* messenger);
void TrayPeekShutdown();

#endif
