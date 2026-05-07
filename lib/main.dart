import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'app_theme.dart';
import 'notification_service.dart';

import 'calendar_screen.dart';
import 'assessment_screen.dart';
import 'chat_screen.dart';
import 'notification_screen.dart';
import 'event_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import 'force_change_password_screen.dart';
import 'plus_schedule_screen.dart';
import 'crm_lead_screen.dart';
import 'parent_main.dart';
import 'ai_chat_main_screen.dart';

// テーマモード管理（グローバル）
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

Future<void> _loadThemePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('themeMode') ?? 'system';
  switch (mode) {
    case 'light':
      themeNotifier.value = ThemeMode.light;
    case 'dark':
      themeNotifier.value = ThemeMode.dark;
    default:
      themeNotifier.value = ThemeMode.system;
  }
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  switch (mode) {
    case ThemeMode.light:
      await prefs.setString('themeMode', 'light');
    case ThemeMode.dark:
      await prefs.setString('themeMode', 'dark');
    case ThemeMode.system:
      await prefs.setString('themeMode', 'system');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await _loadThemePreference();
  runApp(const BeeSmileyApp());
}

class BeeSmileyApp extends StatelessWidget {
  const BeeSmileyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Bee Smiley',
          debugShowCheckedModeBanner: false,
          theme: getAppTheme(),
          darkTheme: getDarkTheme(),
          themeMode: mode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ja', 'JP')],
          locale: const Locale('ja', 'JP'),
          home: const AuthCheckWrapper(),
        );
      },
    );
  }
}

enum UserType { staff, parent, unknown }

class UserStatus {
  final UserType type;
  final bool isInitialPassword;
  final String uid;
  const UserStatus({required this.type, required this.isInitialPassword, required this.uid});
  static const unknown = UserStatus(type: UserType.unknown, isInitialPassword: false, uid: '');
}

class AuthCheckWrapper extends StatefulWidget {
  const AuthCheckWrapper({super.key});
  @override
  State<AuthCheckWrapper> createState() => _AuthCheckWrapperState();
}

class _AuthCheckWrapperState extends State<AuthCheckWrapper> with WidgetsBindingObserver {
  UserStatus? _status;
  bool _loading = true;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // バッジは各画面の未読リスナーが正確な未読数で管理する
    _setupAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // バッジは各画面(AdminShell/ParentMainScreen)の未読リスナーが
      // 正確な未読数で更新するため、ここでは全クリアしない
    }
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      setState(() => _loading = true);
      
      if (user != null) {
        final status = await _checkUserStatus(user.uid);
        if (mounted) {
          setState(() {
            _status = status;
            _loading = false;
          });
        }
        // 通知初期化はバックグラウンドで実行（UIをブロックしない）
        if (status.type != UserType.unknown) {
          unawaited(_initNotificationsInBackground());
        }
      } else {
        if (mounted) {
          setState(() {
            _status = null;
            _loading = false;
          });
        }
      }
    });
  }

  Future<void> _initNotificationsInBackground() async {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize().timeout(const Duration(seconds: 10));
      await notificationService.saveTokenToFirestore().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Notification init skipped: $e');
    }
  }

  Future<UserStatus> _checkUserStatus(String uid) async {
    try {
      debugPrint('🔍 _checkUserStatus called with uid: $uid');
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs').where('uid', isEqualTo: uid).limit(1).get();
      debugPrint('🔍 staffs query result: ${staffSnap.docs.length} docs');
      if (staffSnap.docs.isNotEmpty) {
        final data = staffSnap.docs.first.data();
        // Custom Claims を反映するためトークンをリフレッシュ
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        return UserStatus(type: UserType.staff, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
      }
      // 保護者は families（通常）と plus_families（プラス）両方を確認
      for (final coll in const ['families', 'plus_families']) {
        final familySnap = await FirebaseFirestore.instance
            .collection(coll).where('uid', isEqualTo: uid).limit(1).get();
        debugPrint('🔍 $coll query result: ${familySnap.docs.length} docs');
        if (familySnap.docs.isNotEmpty) {
          final data = familySnap.docs.first.data();
          debugPrint('🔍 family data ($coll): $data');
          // Custom Claims を反映するためトークンをリフレッシュ
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          return UserStatus(type: UserType.parent, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
        }
      }
      debugPrint('⚠️ uid $uid not found in staffs / families / plus_families → unknown');
      return UserStatus.unknown;
    } catch (e) {
      debugPrint('❌ _checkUserStatus error: $e');
      return UserStatus.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Center(
          child: Image.asset(
            'assets/logo_beesmiley.png',
            height: 120,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    if (_status == null) return const LoginScreen();
    if (_status!.type == UserType.unknown) return const _ForceLogout();
    if (_status!.isInitialPassword) return const ForceChangePasswordScreen();
    
    if (_status!.type == UserType.staff) {
      return AdminShell(key: ValueKey('admin_${_status!.uid}'));
    }
    if (_status!.type == UserType.parent) {
      return ParentMainScreen(key: ValueKey('parent_${_status!.uid}'));
    }
    return const LoginScreen();
  }
}

class _ForceLogout extends StatefulWidget {
  const _ForceLogout();
  @override
  State<_ForceLogout> createState() => _ForceLogoutState();
}

class _ForceLogoutState extends State<_ForceLogout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FirebaseAuth.instance.signOut();
    });
  }
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  /// コンテンツエリア内にオーバーレイ画面を表示（サイドバーを残す）
  static void showOverlay(BuildContext context, Widget screen) {
    final state = context.findAncestorStateOfType<_AdminShellState>();
    state?.setState(() => state._contentOverlay = screen);
  }

  /// オーバーレイ画面を閉じる
  static void hideOverlay(BuildContext context) {
    final state = context.findAncestorStateOfType<_AdminShellState>();
    state?.setState(() => state._contentOverlay = null);
  }

  /// AI相談タブに遷移して生徒を選択
  static void navigateToAiChat(BuildContext context, {
    required String studentId,
    required String studentName,
    Map<String, dynamic>? studentInfo,
  }) {
    final state = context.findAncestorStateOfType<_AdminShellState>();
    state?.navigateToAiChat(
      studentId: studentId,
      studentName: studentName,
      studentInfo: studentInfo,
    );
  }

  @override
  State<AdminShell> createState() => _AdminShellState();
}

enum StaffType { both, beesmiley, plusOnly, loading }

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  bool _hasUnreadSchedule = false;
  bool _hasUnreadChat = false;
  bool _hasUnreadInfo = false;
  bool _hasUnreadEvent = false;
  bool _hasUnreadRecord = false;
  StaffType _staffType = StaffType.loading;

  // アプリアイコンバッジ：いずれかの種類で未読があれば 1、無ければ 0（運用案A）
  void _updateAppBadge() {
    final hasAny = _hasUnreadChat ||
        _hasUnreadSchedule ||
        _hasUnreadInfo ||
        _hasUnreadEvent ||
        _hasUnreadRecord;
    NotificationService().setBadge(hasAny ? 1 : 0);
  }

  // タブ index → 種類文字列。タップ時に該当バッジをクリアするのに使う。
  String? _navTypeForIndex(int i) {
    switch (_staffType) {
      case StaffType.plusOnly:
        // 0:予定, 1:プラス, 2:AI相談, 3:チャット, 4:お知らせ, 5:管理
        if (i == 0) return 'schedule';
        if (i == 4) return 'info';
        return null;
      case StaffType.beesmiley:
        // 0:予定, 1:記録, 2:AI相談, 3:チャット, 4:お知らせ, 5:イベント, 6:管理
        if (i == 0) return 'schedule';
        if (i == 1) return 'record';
        if (i == 4) return 'info';
        if (i == 5) return 'event';
        return null;
      case StaffType.both:
      case StaffType.loading:
      default:
        // 0:予定, 1:プラス, 2:記録, 3:AI相談, 4:チャット, 5:お知らせ, 6:イベント, 7:管理
        if (i == 0) return 'schedule';
        if (i == 2) return 'record';
        if (i == 5) return 'info';
        if (i == 6) return 'event';
        return null;
    }
  }

  void _clearUnreadOnTap(int index) {
    final type = _navTypeForIndex(index);
    if (type == null) return;
    setState(() {
      switch (type) {
        case 'schedule':
          _hasUnreadSchedule = false;
          break;
        case 'record':
          _hasUnreadRecord = false;
          break;
        case 'info':
          _hasUnreadInfo = false;
          break;
        case 'event':
          _hasUnreadEvent = false;
          break;
      }
    });
    _updateAppBadge();
  }
  
  // Web版で右側に表示する管理詳細画面を保持する変数
  Widget? _adminDetailScreen;

  // コンテンツエリア内のオーバーレイ画面（サイドバーを残して表示）
  Widget? _contentOverlay;

  // AI相談に生徒情報付きでジャンプする用
  Map<String, dynamic>? _pendingAiChatStudent;
  
  StreamSubscription<QuerySnapshot>? _chatRoomsSubscription;
  final Map<String, StreamSubscription<QuerySnapshot>> _messageSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadSavedIndex(); // 保存されたタブインデックスを読み込む
    _loadStaffClassrooms();
    _setupNotificationListener();
    _setupNavigationListener();
    _setupChatUnreadListener();
  }
  
  @override
  void dispose() {
    _chatRoomsSubscription?.cancel();
    for (var sub in _messageSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  // 保存されたページインデックスを読み込む
  Future<void> _loadSavedIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt('selectedTabIndex') ?? 0;
      if (mounted) {
        setState(() {
          // _screenCountはまだ確定していないので、一旦保存して後で検証
          _selectedIndex = savedIndex;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved index: $e');
    }
  }

  // ページインデックスを保存
  Future<void> _saveIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('selectedTabIndex', index);
    } catch (e) {
      debugPrint('Error saving index: $e');
    }
  }
  
  void _setupChatUnreadListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    _chatRoomsSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('members', arrayContains: user.uid)
        .snapshots()
        .listen((roomsSnapshot) {
      _updateUnreadStatus(roomsSnapshot.docs, user.uid);
    });
  }
  
  void _updateUnreadStatus(List<DocumentSnapshot> roomDocs, String myUid) {
    for (var sub in _messageSubscriptions.values) {
      sub.cancel();
    }
    _messageSubscriptions.clear();

    if (roomDocs.isEmpty) {
      if (mounted) setState(() => _hasUnreadChat = false);
      _updateAppBadge();
      return;
    }

    final Map<String, bool> roomUnreadStatus = {};

    for (var roomDoc in roomDocs) {
      final roomId = roomDoc.id;
      roomUnreadStatus[roomId] = false;

      final sub = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .where('senderId', isNotEqualTo: myUid)
          .snapshots()
          .listen((msgSnapshot) {
        bool hasUnread = false;
        for (var doc in msgSnapshot.docs) {
          final data = doc.data();
          final readBy = List<String>.from(data['readBy'] ?? []);
          if (!readBy.contains(myUid)) {
            hasUnread = true;
            break;
          }
        }

        roomUnreadStatus[roomId] = hasUnread;
        final totalHasUnread = roomUnreadStatus.values.any((v) => v);

        if (mounted) {
          setState(() => _hasUnreadChat = totalHasUnread);
        }
        // アプリアイコンバッジは全種類合算（運用案A：未読の有無のみ）
        _updateAppBadge();
      });

      _messageSubscriptions[roomId] = sub;
    }
  }
  
  Future<void> _loadStaffClassrooms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _staffType = StaffType.both);
        return;
      }
      
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      if (staffSnap.docs.isEmpty) {
        setState(() => _staffType = StaffType.both);
        return;
      }
      
      final classrooms = List<String>.from(staffSnap.docs.first.data()['classrooms'] ?? []);
      final hasPlus = classrooms.any((c) => c.contains('プラス'));
      final hasBeesmiley = classrooms.any((c) => !c.contains('プラス') && c.contains('ビースマイリー'));
      
      setState(() {
        if (hasPlus && hasBeesmiley) {
          _staffType = StaffType.both;
        } else if (hasPlus) {
          _staffType = StaffType.plusOnly;
        } else {
          _staffType = StaffType.beesmiley;
        }
        
        // staffTypeが確定した後、保存されたインデックスが有効か検証
        if (_selectedIndex >= _screenCount) {
          _selectedIndex = 0;
        }
      });
    } catch (e) {
      setState(() => _staffType = StaffType.both);
    }
  }
  
  Widget _getScreen(int index) {
    // 管理画面の構築ロジックを一元化
    Widget buildAdminScreen() {
      // 詳細画面が指定されている場合（Web版でサブ画面を開いている場合）
      if (_adminDetailScreen != null) {
        return _adminDetailScreen!;
      }
      // 通常の管理メニュー画面（コールバックを渡す）
      return AdminScreen(
        onOpenWebScreen: (screen) {
          setState(() => _adminDetailScreen = screen);
        },
        onCloseWebScreen: () {
          setState(() => _adminDetailScreen = null);
        },
      );
    }

    switch (_staffType) {
      case StaffType.plusOnly:
        // 0:予定 1:プラス 2:AI相談 3:チャット 4:CRM 5:お知らせ 6:管理
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const PlusScheduleScreen();
          case 2: return _buildAiChatScreen();
          case 3: return const ChatListScreen();
          case 4: return const CrmLeadScreen();
          case 5: return const NotificationScreen();
          case 6: return buildAdminScreen();
          default: return const CalendarScreen();
        }
      case StaffType.beesmiley:
        // 0:予定 1:記録 2:AI相談 3:チャット 4:CRM 5:お知らせ 6:イベント 7:管理
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const AssessmentScreen();
          case 2: return _buildAiChatScreen();
          case 3: return const ChatListScreen();
          case 4: return const CrmLeadScreen();
          case 5: return const NotificationScreen();
          case 6: return const EventScreen();
          case 7: return buildAdminScreen();
          default: return const CalendarScreen();
        }
      case StaffType.both:
      case StaffType.loading:
      default:
        // 0:予定 1:プラス 2:記録 3:AI相談 4:チャット 5:CRM 6:お知らせ 7:イベント 8:管理
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const PlusScheduleScreen();
          case 2: return const AssessmentScreen();
          case 3: return _buildAiChatScreen();
          case 4: return const ChatListScreen();
          case 5: return const CrmLeadScreen();
          case 6: return const NotificationScreen();
          case 7: return const EventScreen();
          case 8: return buildAdminScreen();
          default: return const CalendarScreen();
        }
    }
  }

  int get _screenCount {
    switch (_staffType) {
      case StaffType.plusOnly: return 7;
      case StaffType.beesmiley: return 8;
      default: return 9;
    }
  }
  
  List<NavigationRailDestination> get _railDestinations {
    const crmRail = NavigationRailDestination(
        icon: Icon(Icons.support_agent), label: Text('CRM'));
    switch (_staffType) {
      case StaffType.plusOnly:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          const NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text('プラス')),
          const NavigationRailDestination(icon: Icon(Icons.psychology), label: Text('AI相談')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          crmRail,
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.notifications, _hasUnreadInfo), label: const Text('お知らせ')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
      case StaffType.beesmiley:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.edit_note, _hasUnreadRecord), label: const Text('記録')),
          const NavigationRailDestination(icon: Icon(Icons.psychology), label: Text('AI相談')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          crmRail,
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.notifications, _hasUnreadInfo), label: const Text('お知らせ')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.event, _hasUnreadEvent), label: const Text('イベント')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
      case StaffType.both:
      case StaffType.loading:
      default:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          const NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text('プラス')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.edit_note, _hasUnreadRecord), label: const Text('記録')),
          const NavigationRailDestination(icon: Icon(Icons.psychology), label: Text('AI相談')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          crmRail,
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.notifications, _hasUnreadInfo), label: const Text('お知らせ')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.event, _hasUnreadEvent), label: const Text('イベント')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
    }
  }
  
  /// モバイル: 直接表示する index 数（残りは「…」メニュー内）。
  /// プラス/記録/AI相談/チャット までを表に出し、CRM/お知らせ/イベント/管理 は ... に格納。
  int get _visibleBottomCount {
    switch (_staffType) {
      case StaffType.plusOnly: return 4;  // 予定/プラス/AI相談/チャット
      case StaffType.beesmiley: return 4; // 予定/記録/AI相談/チャット
      default: return 5;                  // 予定/プラス/記録/AI相談/チャット
    }
  }

  /// 「…」内に出す index 範囲（visible 以降すべて）
  List<({int index, IconData icon, String label})> get _moreMenuItems {
    final items = <({int index, IconData icon, String label})>[];
    switch (_staffType) {
      case StaffType.plusOnly:
        // 4:CRM 5:お知らせ 6:管理
        items.add((index: 4, icon: Icons.support_agent, label: 'CRM'));
        items.add((index: 5, icon: Icons.notifications, label: 'お知らせ'));
        items.add((index: 6, icon: Icons.manage_accounts, label: '管理'));
      case StaffType.beesmiley:
        // 4:CRM 5:お知らせ 6:イベント 7:管理
        items.add((index: 4, icon: Icons.support_agent, label: 'CRM'));
        items.add((index: 5, icon: Icons.notifications, label: 'お知らせ'));
        items.add((index: 6, icon: Icons.event, label: 'イベント'));
        items.add((index: 7, icon: Icons.manage_accounts, label: '管理'));
      case StaffType.both:
      case StaffType.loading:
        // 5:CRM 6:お知らせ 7:イベント 8:管理
        items.add((index: 5, icon: Icons.support_agent, label: 'CRM'));
        items.add((index: 6, icon: Icons.notifications, label: 'お知らせ'));
        items.add((index: 7, icon: Icons.event, label: 'イベント'));
        items.add((index: 8, icon: Icons.manage_accounts, label: '管理'));
    }
    return items;
  }

  List<BottomNavigationBarItem> get _bottomNavItems {
    final visible = <BottomNavigationBarItem>[];
    switch (_staffType) {
      case StaffType.plusOnly:
        visible.addAll([
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'プラス'),
          const BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI相談'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
        ]);
      case StaffType.beesmiley:
        visible.addAll([
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.edit_note, _hasUnreadRecord), label: '記録'),
          const BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI相談'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
        ]);
      case StaffType.both:
      case StaffType.loading:
        visible.addAll([
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'プラス'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.edit_note, _hasUnreadRecord), label: '記録'),
          const BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI相談'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
        ]);
    }
    visible.add(const BottomNavigationBarItem(
        icon: Icon(Icons.more_horiz), label: 'その他'));
    return visible;
  }

  /// モバイル: ... メニューを開いて選択させる
  Future<void> _showMoreMenu() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in _moreMenuItems)
              ListTile(
                leading: Icon(m.icon),
                title: Text(m.label),
                selected: _selectedIndex == m.index,
                onTap: () => Navigator.pop(ctx, m.index),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedIndex = picked;
        _adminDetailScreen = null;
      });
      _clearUnreadOnTap(picked);
      _saveIndex(picked);
    }
  }

  void _setupNotificationListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final type = message.data['type'];
      if (!mounted) return;
      setState(() {
        switch (type) {
          case 'schedule':
            _hasUnreadSchedule = true;
            break;
          case 'record':
          case 'assessment':
            _hasUnreadRecord = true;
            break;
          case 'info':
          case 'notification':
          case 'announcement':
            _hasUnreadInfo = true;
            break;
          case 'event':
            _hasUnreadEvent = true;
            break;
        }
      });
      _updateAppBadge();
    });
  }

  void _setupNavigationListener() {
    final service = NotificationService();

    if (service.initialRoute != null) {
      _navigateByType(service.initialRoute!);
      service.initialRoute = null;
    }

    service.navigationStream.listen((type) {
      if (!mounted) return;
      _navigateByType(type);
    });
  }

  void _navigateByType(String type) {
    int newIndex = _selectedIndex;

    switch (_staffType) {
      // インデックスは _getScreen() のcase番号と一致させること（CRM 追加で +1）
      case StaffType.plusOnly:
        // 0:予定, 1:プラス, 2:AI相談, 3:チャット, 4:CRM, 5:お知らせ, 6:管理
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'chat': newIndex = 3; break;
          case 'crm': newIndex = 4; break;
          case 'info': newIndex = 5; break;
        }
        break;
      case StaffType.beesmiley:
        // 0:予定, 1:記録, 2:AI相談, 3:チャット, 4:CRM, 5:お知らせ, 6:イベント, 7:管理
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'record': newIndex = 1; break;
          case 'chat': newIndex = 3; break;
          case 'crm': newIndex = 4; break;
          case 'info': newIndex = 5; break;
          case 'event': newIndex = 6; break;
        }
        break;
      case StaffType.both:
      case StaffType.loading:
      default:
        // 0:予定, 1:プラス, 2:記録, 3:AI相談, 4:チャット, 5:CRM, 6:お知らせ, 7:イベント, 8:管理
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'record': newIndex = 2; break;
          case 'chat': newIndex = 4; break;
          case 'crm': newIndex = 5; break;
          case 'info': newIndex = 6; break;
          case 'event': newIndex = 7; break;
        }
        break;
    }

    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
        // 画面遷移時は詳細画面を閉じる
        _adminDetailScreen = null;
        switch (type) {
          case 'schedule':
            _hasUnreadSchedule = false;
            break;
          case 'record':
          case 'assessment':
            _hasUnreadRecord = false;
            break;
          case 'info':
          case 'notification':
          case 'announcement':
            _hasUnreadInfo = false;
            break;
          case 'event':
            _hasUnreadEvent = false;
            break;
        }
      });
      _updateAppBadge();
      _saveIndex(newIndex); // 保存
    }
  }

  Widget _buildAiChatScreen() {
    final student = _pendingAiChatStudent;
    _pendingAiChatStudent = null; // 一度だけ使用
    if (student != null) {
      return AiChatMainScreen(initialStudent: student);
    }
    return const AiChatMainScreen();
  }

  int get _aiChatTabIndex {
    switch (_staffType) {
      case StaffType.plusOnly: return 2;
      case StaffType.beesmiley: return 2;
      case StaffType.both:
      case StaffType.loading:
      default: return 3;
    }
  }

  /// AI相談タブに遷移し、指定の生徒を選択状態にする
  void navigateToAiChat({
    required String studentId,
    required String studentName,
    Map<String, dynamic>? studentInfo,
  }) {
    setState(() {
      _pendingAiChatStudent = {
        'studentId': studentId,
        'studentName': studentName,
        'studentInfo': studentInfo,
      };
      _selectedIndex = _aiChatTabIndex;
      _adminDetailScreen = null;
    });
    _saveIndex(_selectedIndex);
  }

  Widget _buildBadgedIcon(IconData icon, bool showBadge) {
    return Badge(
      isLabelVisible: showBadge,
      smallSize: 10,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWebLayout = MediaQuery.of(context).size.width >= AppBreakpoints.tablet;
    
    if (_staffType == StaffType.loading) {
      return Scaffold(backgroundColor: context.colors.scaffoldBg, body: const SizedBox.shrink());
    }
    
    final safeIndex = _selectedIndex < _screenCount ? _selectedIndex : 0;
    
    return Scaffold(
      body: Row(
        children: [
          if (isWebLayout) NavigationRail(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) {
              setState(() {
                _selectedIndex = i;
                _adminDetailScreen = null;
                _contentOverlay = null;
              });
              _clearUnreadOnTap(i);
              _saveIndex(i); // 保存
            },
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.primary.withOpacity(0.2),
            selectedIconTheme: const IconThemeData(color: AppColors.primary),
            selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            unselectedIconTheme: IconThemeData(color: context.colors.textSecondary),
            unselectedLabelTextStyle: TextStyle(color: context.colors.textSecondary),
            leading: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.transparent : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: context.isDark
                      ? []
                      : [],
                ),
                padding: const EdgeInsets.all(4),
                child: Image.asset('assets/logo_beesmileymark.png', width: 42, height: 42),
              ),
            ),
            destinations: _railDestinations,
          ),
          if (isWebLayout) const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _contentOverlay != null
              ? Navigator(
                  key: ValueKey('overlay_${_contentOverlay.hashCode}'),
                  onGenerateRoute: (_) => MaterialPageRoute(
                    builder: (_) => _contentOverlay!,
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey('$_selectedIndex${_adminDetailScreen?.runtimeType}'),
                    child: _getScreen(safeIndex),
                  ),
                ),
          ),
        ],
      ),
      bottomNavigationBar: isWebLayout ? null : BottomNavigationBar(
        // 末尾は「…」（その他）。隠れた画面（CRM/お知らせ/イベント/管理）が
        // アクティブな場合は「…」を選択中として表示する。
        currentIndex: safeIndex >= _visibleBottomCount
            ? _bottomNavItems.length - 1
            : safeIndex,
        onTap: (i) {
          if (i == _bottomNavItems.length - 1) {
            _showMoreMenu();
            return;
          }
          setState(() {
            _selectedIndex = i;
            _adminDetailScreen = null;
          });
          _clearUnreadOnTap(i);
          _saveIndex(i);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: _bottomNavItems,
      ),
    );
  }
}