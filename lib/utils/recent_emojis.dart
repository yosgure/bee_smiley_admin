import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentEmojis {
  static const _key = 'chat_recent_emojis_v1';
  static const _max = 8;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> add(String emoji) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((e) => e == emoji);
    list.insert(0, emoji);
    if (list.length > _max) list.removeRange(_max, list.length);
    await prefs.setString(_key, jsonEncode(list));
  }
}

bool _isEmojiCodePoint(int code) {
  // Variation selector / ZWJ / keycap などの修飾子は許容
  if (code == 0x200D || code == 0xFE0F || code == 0x20E3) return true;
  // Regional indicator（国旗）
  if (code >= 0x1F1E6 && code <= 0x1F1FF) return true;
  // Misc symbols / Dingbats / Supplemental arrows など
  if (code >= 0x2600 && code <= 0x27BF) return true;
  // Misc Symbols and Pictographs ～ Symbols and Pictographs Extended-A
  if (code >= 0x1F300 && code <= 0x1FAFF) return true;
  // Emoticons など追加面の記号類
  if (code >= 0x1F000 && code <= 0x1F2FF) return true;
  return false;
}

bool isEmojiOnlyMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final chars = trimmed.characters.toList();
  if (chars.length > 3) return false;
  var hasEmoji = false;
  for (final c in chars) {
    if (c.trim().isEmpty) continue;
    // 文字（grapheme cluster）内のいずれかの code point が絵文字なら可
    final runes = c.runes.toList();
    final allEmoji = runes.every(_isEmojiCodePoint);
    if (!allEmoji) return false;
    if (runes.any(_isEmojiCodePoint)) hasEmoji = true;
  }
  return hasEmoji;
}
