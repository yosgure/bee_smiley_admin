import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'app_theme.dart';
import 'notification_service.dart';

// 管理者用画面のインポート
import 'calendar_screen.dart';
import 'assessment_screen.dart';
import 'chat_screen.dart';
import 'notification_screen.dart';
import 'event_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import 'force_change_password_screen.dart';

// 保護者用画面のインポート
import 'parent_main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // バックグラウンドメッセージハンドラの設定
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const BeeSmileyApp());
}

class BeeSmileyApp extends StatelessWidget {
  const BeeSmileyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bee Smiley',
      debugShowCheckedModeBanner: false,
      theme: getAppTheme(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP')],
      locale: const Locale('ja', 'JP'),
      home: const AuthCheckWrapper(),
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

class _AuthCheckWrapperState extends State<AuthCheckWrapper> {
  UserStatus? _status;
  bool _loading = true;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      debugPrint("🔄 Auth state changed: ${user?.uid}");
      
      if (!mounted) return;
      setState(() => _loading = true);
      
      if (user != null) {
        final status = await _checkUserStatus(user.uid);
        debugPrint("📋 New status for ${user.uid}: ${status.type}");
        
        // 通知サービスの初期化とトークン保存
        if (status.type != UserType.unknown) {
          final notificationService = NotificationService();
          await notificationService.initialize();
          await notificationService.saveTokenToFirestore();
        }
        
        if (mounted) {
          setState(() {
            _status = status;
            _loading = false;
          });
        }
      } else {
        debugPrint("🚪 User logged out - clearing status");
        if (mounted) {
          setState(() {
            _status = null;
            _loading = false;
          });
        }
      }
    });
  }

  Future<UserStatus> _checkUserStatus(String uid) async {
    debugPrint("🔍 Checking user status for uid: $uid");
    try {
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs').where('uid', isEqualTo: uid).limit(1).get();
      if (staffSnap.docs.isNotEmpty) {
        debugPrint("✅ Found in staffs collection");
        final data = staffSnap.docs.first.data();
        return UserStatus(type: UserType.staff, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
      }
      final familySnap = await FirebaseFirestore.instance
          .collection('families').where('uid', isEqualTo: uid).limit(1).get();
      if (familySnap.docs.isNotEmpty) {
        debugPrint("✅ Found in families collection");
        final data = familySnap.docs.first.data();
        return UserStatus(type: UserType.parent, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
      }
      debugPrint("❌ User not found in any collection");
      return UserStatus.unknown;
    } catch (e) {
      debugPrint('Error: $e');
      return UserStatus.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🏗️ AuthCheckWrapper build: loading=$_loading, type=${_status?.type}, uid=${_status?.uid}");
    
    if (_loading) return const _LoadingScreen();
    if (_status == null) return const LoginScreen();
    if (_status!.type == UserType.unknown) return const _ForceLogout();
    if (_status!.isInitialPassword) return const ForceChangePasswordScreen();
    
    // 重要: KeyにユーザーUIDを使用して、ユーザーが変わったときにウィジェットを完全に再作成
    if (_status!.type == UserType.staff) {
      debugPrint("🔵 Returning AdminShell for uid: ${_status!.uid}");
      return AdminShell(key: ValueKey('admin_${_status!.uid}'));
    }
    if (_status!.type == UserType.parent) {
      debugPrint("🟢 Returning ParentMainScreen for uid: ${_status!.uid}");
      return ParentMainScreen(key: ValueKey('parent_${_status!.uid}'));
    }
    return const LoginScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo_beesmiley.png', height: 80, fit: BoxFit.contain),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
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
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  // 通知バッジ用の状態変数
  bool _hasUnreadSchedule = false; // 予定
  bool _hasUnreadChat = false;     // チャット

  final List<Widget> _screens = const [
    CalendarScreen(), AssessmentScreen(), ChatListScreen(),
    NotificationScreen(), EventScreen(), AdminScreen(),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint("🔵 AdminShell initState called");
    _setupNotificationListener(); // バッジ表示用
    _setupNavigationListener();   // 画面遷移用
  }

  // バッジ表示用のリスナー
  void _setupNotificationListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final type = message.data['type'];
      if (!mounted) return;
      setState(() {
        if (type == 'chat') {
          _hasUnreadChat = true;
        } else if (type == 'schedule') {
          _hasUnreadSchedule = true;
        }
      });
    });
  }

  // 画面遷移用のリスナー
  void _setupNavigationListener() {
    final service = NotificationService();

    // 1. アプリ起動時のチェック
    if (service.initialRoute != null) {
      _navigateByType(service.initialRoute!);
      service.initialRoute = null;
    }

    // 2. 起動中の監視
    service.navigationStream.listen((type) {
      if (!mounted) return;
      _navigateByType(type);
    });
  }

  // タイプに応じてタブを切り替える共通処理
  void _navigateByType(String type) {
    int newIndex = _selectedIndex;

    switch (type) {
      case 'schedule':
        newIndex = 0; // 予定タブ
        break;
      case 'record':
        newIndex = 1; // 記録タブ
        break;
      case 'chat':
        newIndex = 2; // チャットタブ
        break;
      case 'info':
        newIndex = 3; // お知らせタブ
        break;
      case 'event':
        newIndex = 4; // イベントタブ
        break;
    }

    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
        // 遷移したらそのタブのバッジを消す
        if (type == 'chat') _hasUnreadChat = false;
        if (type == 'schedule') _hasUnreadSchedule = false;
      });
    }
  }

  // バッジ付きアイコンを作成するヘルパー
  Widget _buildBadgedIcon(IconData icon, bool showBadge) {
    return Badge(
      isLabelVisible: showBadge,
      smallSize: 10,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🔵 AdminShell build called");
    final isWebLayout = MediaQuery.of(context).size.width >= 600;
    
    return Scaffold(
      body: Row(
        children: [
          if (isWebLayout) NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              setState(() {
                _selectedIndex = i;
                if (i == 0) _hasUnreadSchedule = false;
                if (i == 2) _hasUnreadChat = false;
              });
            },
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.primary.withOpacity(0.2),
            selectedIconTheme: const IconThemeData(color: AppColors.primary),
            selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            leading: Padding(padding: const EdgeInsets.all(12), child: Image.asset('assets/logo_beesmileymark.png', width: 50, height: 50)),
            destinations: [
              NavigationRailDestination(
                icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule),
                label: const Text('予定'),
              ),
              const NavigationRailDestination(icon: Icon(Icons.edit_note), label: Text('記録')),
              NavigationRailDestination(
                icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat),
                label: const Text('チャット'),
              ),
              const NavigationRailDestination(icon: Icon(Icons.notifications), label: Text('お知らせ')),
              const NavigationRailDestination(icon: Icon(Icons.event), label: Text('イベント')),
              const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
            ],
          ),
          if (isWebLayout) const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: IndexedStack(index: _selectedIndex, children: _screens)),
        ],
      ),
      bottomNavigationBar: isWebLayout ? null : BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) {
          setState(() {
            _selectedIndex = i;
            if (i == 0) _hasUnreadSchedule = false;
            if (i == 2) _hasUnreadChat = false;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        items: [
          BottomNavigationBarItem(
            icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule),
            label: '予定',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '記録'),
          BottomNavigationBarItem(
            icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat),
            label: 'チャット',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
          const BottomNavigationBarItem(icon: Icon(Icons.event), label: 'イベント'),
          const BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
        ],
      ),
    );
  }
}