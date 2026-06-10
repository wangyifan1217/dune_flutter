import 'dart:convert';

/// 向 WebView 注入 IM 数据刷新（C1 消息列表、C3/C7/C9 通讯录）。
abstract final class ContactsBridge {
  static String refreshScreen(String screenId) {
    final id = jsonEncode(screenId);
    return 'try{'
        'if(window.DunesInbox)window.DunesInbox.onScreen($id);'
        'if(window.DunesContacts)window.DunesContacts.onScreen($id);'
        'if(window.DunesImChat)window.DunesImChat.onScreen($id);'
        '}catch(e){console.warn(e);}';
  }
}
