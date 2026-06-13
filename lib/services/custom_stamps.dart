import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// チャットで使う「オリジナル画像スタンプ」1件。
class CustomStamp {
  final String id;
  final String url;
  final String? createdBy;
  const CustomStamp({required this.id, required this.url, this.createdBy});
}

/// 全スタッフ共通のオリジナルスタンプ帳（Slack のカスタム絵文字に相当）。
///
/// `chat_stamps` コレクションを購読し、ピッカー表示用の一覧と
/// id→URL の解決マップを保持する。リアクションのキーは `stamp:{id}` で表現し、
/// メッセージ送信時は type='stamp' + url で保存する。
class CustomStampsService {
  CustomStampsService._();
  static final CustomStampsService instance = CustomStampsService._();

  /// ピッカー表示用。追加日時の昇順。
  final ValueNotifier<List<CustomStamp>> stamps =
      ValueNotifier<List<CustomStamp>>([]);

  final Map<String, String> _urlById = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// 購読を開始（多重呼び出しは無視）。
  void start() {
    if (_sub != null) return;
    _sub = FirebaseFirestore.instance
        .collection('chat_stamps')
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) {
      final list = <CustomStamp>[];
      _urlById.clear();
      for (final doc in snap.docs) {
        final data = doc.data();
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) continue;
        list.add(CustomStamp(
          id: doc.id,
          url: url,
          createdBy: data['createdBy'] as String?,
        ));
        _urlById[doc.id] = url;
      }
      stamps.value = list;
    }, onError: (e) {
      debugPrint('[CustomStamps] listen failed: $e');
    });
  }

  /// id（`stamp:` プレフィックスは除いた純粋な doc id）から URL を解決。
  String? urlFor(String id) => _urlById[id];

  /// 画像バイト列から新しいスタンプを登録（誰でも可）。
  Future<void> addStamp(Uint8List bytes, String ext) async {
    final e = ext.toLowerCase();
    final contentType = e == 'png'
        ? 'image/png'
        : e == 'gif'
            ? 'image/gif'
            : e == 'webp'
                ? 'image/webp'
                : 'image/jpeg';
    final docRef = FirebaseFirestore.instance.collection('chat_stamps').doc();
    final path = 'chat_stamps/${docRef.id}.$e';
    final storageRef = FirebaseStorage.instance.ref().child(path);
    await storageRef.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await storageRef.getDownloadURL();
    await docRef.set({
      'url': url,
      'path': path,
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// スタンプを削除（Firestore ルール上はスタッフ or 登録者のみ成功）。
  Future<void> deleteStamp(String id) async {
    final docRef = FirebaseFirestore.instance.collection('chat_stamps').doc(id);
    final snap = await docRef.get();
    final path = snap.data()?['path'] as String?;
    await docRef.delete();
    if (path != null && path.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref().child(path).delete();
      } catch (e) {
        debugPrint('[CustomStamps] storage delete failed: $e');
      }
    }
  }
}
