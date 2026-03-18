import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

// バックグラウンドメッセージハンドラ（トップレベル関数である必要がある）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンドメッセージ受信
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Web用のVAPIDキー（--dart-define=VAPID_KEY=... でビルド時に注入）
  static const String _vapidKey = String.fromEnvironment('VAPID_KEY');
  
  bool _initialized = false;

  // 画面遷移の命令を送るための「放送局」
  final _navigationController = StreamController<String>.broadcast();
  Stream<String> get navigationStream => _navigationController.stream;

  // アプリ起動時に「どの画面を開くか」を一時保存する変数
  String? initialRoute;

  /// 通知サービスの初期化
  Future<void> initialize() async {
    if (_initialized) return;
    
    // 権限リクエスト
    await _requestPermission();

    // iOSフォアグラウンド通知表示設定
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    
    // ローカル通知の初期化（フォアグラウンド表示用）- モバイルのみ
    if (!kIsWeb) {
      await _initLocalNotifications();
    }
    
    // フォアグラウンドメッセージのリスナー設定
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // 通知タップ時のハンドラ（バックグラウンドからの復帰）
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    
    // アプリが終了状態から通知タップで起動した場合
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
    
    // アプリ起動時にバッジをクリア
    await clearBadge();
    
    _initialized = true;
  }

  /// 権限リクエスト
  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  /// ローカル通知の初期化
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // ローカル通知タップ時も画面遷移処理へ回す
        if (response.payload != null) {
           _navigationController.add(response.payload!);
        }
        // 通知タップ時にバッジをクリア
        clearBadge();
      },
    );

    // Androidの通知チャンネル作成
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );
      
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // iOSはsetForegroundNotificationPresentationOptionsで自動表示される
    // Androidもシステム通知で表示される
    // ローカル通知を重複して表示しないようにreturn
    return;
  }

  /// 通知タップ時の処理
  void _handleNotificationTap(RemoteMessage message) {
    // バッジをクリア
    clearBadge();
    
    final type = message.data['type'];
    if (type != null) {
      initialRoute = type;
      _navigationController.add(type);
    }
  }

  /// バッジをクリア
  Future<void> clearBadge() async {
    try {
      if (!kIsWeb) {
        final isSupported = await FlutterAppBadger.isAppBadgeSupported();
        if (isSupported) {
          await FlutterAppBadger.removeBadge();
        }
      }
    } catch (e) {
      // エラー時は何もしない
    }
  }

  /// バッジを設定
  Future<void> setBadge(int count) async {
    try {
      if (!kIsWeb) {
        final isSupported = await FlutterAppBadger.isAppBadgeSupported();
        if (isSupported) {
          await FlutterAppBadger.updateBadgeCount(count);
        }
      }
    } catch (e) {
      // エラー時は何もしない
    }
  }

  /// FCMトークンを取得してFirestoreに保存
  Future<void> saveTokenToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      String? token;
      
      if (kIsWeb) {
        // WebではVAPIDキーが必要
        token = await _messaging.getToken(vapidKey: _vapidKey);
      } else {
        if (Platform.isIOS) {
          String? apnsToken = await _messaging.getAPNSToken();
          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 3));
            apnsToken = await _messaging.getAPNSToken();
          }
          if (apnsToken == null) {
            return;
          }
        }
        token = await _messaging.getToken();
      }
      
      if (token == null) {
        return;
      }
      
      await _saveTokenForUser(user.uid, token);
      
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenForUser(user.uid, newToken);
      });
      
    } catch (e) {
      // エラー時は何もしない
    }
  }

  /// ユーザーのトークンを保存
  Future<void> _saveTokenForUser(String uid, String token) async {
    final firestore = FirebaseFirestore.instance;
    
    final staffSnap = await firestore
        .collection('staffs')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    
    if (staffSnap.docs.isNotEmpty) {
      await staffSnap.docs.first.reference.update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      return;
    }
    
    final familySnap = await firestore
        .collection('families')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    
    if (familySnap.docs.isNotEmpty) {
      await familySnap.docs.first.reference.update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      return;
    }
  }

  /// トークンを削除（ログアウト時）
  Future<void> removeToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      String? token;
      if (kIsWeb) {
        token = await _messaging.getToken(vapidKey: _vapidKey);
      } else {
        token = await _messaging.getToken();
      }
      if (token == null) return;
      
      final firestore = FirebaseFirestore.instance;
      
      final staffSnap = await firestore
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      if (staffSnap.docs.isNotEmpty) {
        await staffSnap.docs.first.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      
      final familySnap = await firestore
          .collection('families')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      if (familySnap.docs.isNotEmpty) {
        await familySnap.docs.first.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      
      // バッジもクリア
      await clearBadge();
      
    } catch (e) {
      // エラー時は何もしない
    }
  }

  /// 通知設定を取得
  Future<Map<String, bool>> getNotificationSettings(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      final staffSnap = await firestore
          .collection('staffs')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (staffSnap.docs.isNotEmpty) {
        final data = staffSnap.docs.first.data();
        return {
          'chat': data['notifyChat'] ?? true,
          'announcement': data['notifyAnnouncement'] ?? true,
          'event': data['notifyEvent'] ?? true,
          'assessment': data['notifyAssessment'] ?? true,
        };
      }
      
      final familySnap = await firestore
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (familySnap.docs.isNotEmpty) {
        final data = familySnap.docs.first.data();
        return {
          'chat': data['notifyChat'] ?? true,
          'announcement': data['notifyAnnouncement'] ?? true,
          'event': data['notifyEvent'] ?? true,
          'assessment': data['notifyAssessment'] ?? true,
        };
      }
    } catch (e) {
      // エラー時はデフォルト値を返す
    }
    
    return {
      'chat': true,
      'announcement': true,
      'event': true,
      'assessment': true,
    };
  }

  /// 通知設定を保存
  Future<void> saveNotificationSettings(String uid, Map<String, bool> settings) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      final updateData = {
        'notifyChat': settings['chat'] ?? true,
        'notifyAnnouncement': settings['announcement'] ?? true,
        'notifyEvent': settings['event'] ?? true,
        'notifyAssessment': settings['assessment'] ?? true,
      };
      
      final staffSnap = await firestore
          .collection('staffs')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (staffSnap.docs.isNotEmpty) {
        await staffSnap.docs.first.reference.update(updateData);
        return;
      }
      
      final familySnap = await firestore
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (familySnap.docs.isNotEmpty) {
        await familySnap.docs.first.reference.update(updateData);
        return;
      }
    } catch (e) {
      // エラー時は何もしない
    }
  }
}