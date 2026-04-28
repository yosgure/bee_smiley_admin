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

bool isEmojiOnlyMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final chars = trimmed.characters.toList();
  if (chars.length > 3) return false;
  final asciiAlnum = RegExp(r'[A-Za-z0-9]');
  for (final c in chars) {
    if (c.trim().isEmpty) continue;
    if (asciiAlnum.hasMatch(c)) return false;
    final code = c.runes.first;
    if (code < 0x2000) return false;
  }
  return true;
}
