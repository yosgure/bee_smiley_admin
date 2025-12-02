import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// バックグラウンドメッセージハンドラ（トップレベル関数である必要がある）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 バックグラウンドメッセージ受信: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;

  /// 通知サービスの初期化
  Future<void> initialize() async {
    if (_initialized) return;
    
    // 権限リクエスト
    await _requestPermission();
    
    // ローカル通知の初期化（フォアグラウンド表示用）
    await _initLocalNotifications();
    
    // フォアグラウンドメッセージのリスナー設定
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // 通知タップ時のハンドラ
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    
    // アプリが終了状態から通知タップで起動した場合
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
    
    _initialized = true;
    debugPrint('✅ NotificationService 初期化完了');
  }

  /// 権限リクエスト
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    debugPrint('📱 通知権限: ${settings.authorizationStatus}');
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
        debugPrint('🔔 ローカル通知タップ: ${response.payload}');
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

  /// フォアグラウンドメッセージの処理
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📩 フォアグラウンドメッセージ: ${message.notification?.title}');
    
    final notification = message.notification;
    if (notification == null) return;
    
    // ローカル通知として表示
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'This channel is used for important notifications.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['type'],
    );
  }

  /// 通知タップ時の処理
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('👆 通知タップ: ${message.data}');
    // TODO: 画面遷移などの処理
  }

  /// FCMトークンを取得してFirestoreに保存
  Future<void> saveTokenToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      String? token;
      
      if (kIsWeb) {
        // Web用のVAPIDキーが必要な場合はここで設定
        // token = await _messaging.getToken(vapidKey: 'YOUR_VAPID_KEY');
        token = await _messaging.getToken();
      } else {
        // iOSではAPNsトークンを先に取得する必要がある
        String? apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          // APNsトークンがまだない場合は少し待つ
          await Future.delayed(const Duration(seconds: 3));
          apnsToken = await _messaging.getAPNSToken();
        }
        if (apnsToken == null) {
          debugPrint('⚠️ APNsトークンを取得できませんでした');
          return;
        }
        token = await _messaging.getToken();
      }
      
      if (token == null) {
        debugPrint('⚠️ FCMトークンを取得できませんでした');
        return;
      }
      
      debugPrint('🔑 FCMトークン: ${token.substring(0, 20)}...');
      
      // スタッフか保護者かを判定してトークンを保存
      await _saveTokenForUser(user.uid, token);
      
      // トークンのリフレッシュを監視
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenForUser(user.uid, newToken);
      });
      
    } catch (e) {
      debugPrint('❌ トークン保存エラー: $e');
    }
  }

  /// ユーザーのトークンを保存
  Future<void> _saveTokenForUser(String uid, String token) async {
    final firestore = FirebaseFirestore.instance;
    
    // スタッフコレクションを確認
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
      debugPrint('✅ スタッフのFCMトークンを保存しました');
      return;
    }
    
    // 保護者コレクションを確認
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
      debugPrint('✅ 保護者のFCMトークンを保存しました');
      return;
    }
    
    debugPrint('⚠️ ユーザードキュメントが見つかりません');
  }

  /// トークンを削除（ログアウト時）
  Future<void> removeToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final token = await _messaging.getToken();
      if (token == null) return;
      
      final firestore = FirebaseFirestore.instance;
      
      // スタッフから削除
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
      
      // 保護者から削除
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
      
      debugPrint('✅ FCMトークンを削除しました');
    } catch (e) {
      debugPrint('❌ トークン削除エラー: $e');
    }
  }

  /// 通知設定を取得
  Future<Map<String, bool>> getNotificationSettings(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // スタッフを確認
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
      
      // 保護者を確認
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
      debugPrint('❌ 通知設定取得エラー: $e');
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
      
      // スタッフを確認
      final staffSnap = await firestore
          .collection('staffs')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (staffSnap.docs.isNotEmpty) {
        await staffSnap.docs.first.reference.update(updateData);
        debugPrint('✅ スタッフの通知設定を保存しました');
        return;
      }
      
      // 保護者を確認
      final familySnap = await firestore
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (familySnap.docs.isNotEmpty) {
        await familySnap.docs.first.reference.update(updateData);
        debugPrint('✅ 保護者の通知設定を保存しました');
        return;
      }
    } catch (e) {
      debugPrint('❌ 通知設定保存エラー: $e');
    }
  }
}