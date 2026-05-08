import 'package:shared_preferences/shared_preferences.dart';

/// チャット入力欄のキー設定（端末ローカル）。
class ChatPrefs {
  static const _kSendOnEnter = 'chat_send_on_enter';

  /// true:  Enter で送信 / Shift+Enter で改行
  /// false: Shift+Enter で送信 / Enter で改行（既定）
  static Future<bool> getSendOnEnter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSendOnEnter) ?? false;
  }

  static Future<void> setSendOnEnter(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSendOnEnter, value);
  }
}
