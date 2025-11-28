import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'app_theme.dart';

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
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      locale: const Locale('ja', 'JP'),
      
      home: const AuthCheckWrapper(),
    );
  }
}

/// ユーザー種別
enum UserType {
  staff,    // スタッフ/管理者
  parent,   // 保護者
  unknown,  // 不明（該当なし）
}

/// ユーザーステータス情報
class UserStatus {
  final UserType type;
  final bool isInitialPassword;

  const UserStatus({
    required this.type,
    required this.isInitialPassword,
  });

  static const unknown = UserStatus(type: UserType.unknown, isInitialPassword: false);
}

class AuthCheckWrapper extends StatelessWidget {
  const AuthCheckWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 接続待ち
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        
        // ログイン済み
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<UserStatus>(
            future: _checkUserStatus(snapshot.data!.uid),
            builder: (context, statusSnapshot) {
              if (statusSnapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingScreen();
              }
              
              final status = statusSnapshot.data ?? UserStatus.unknown;
              
              debugPrint('🎯 Final status: type=${status.type}, isInitialPassword=${status.isInitialPassword}');
              
              // ユーザーが見つからない場合は強制ログアウト
              if (status.type == UserType.unknown) {
                return const _ForceLogout();
              }
              
              // 初回パスワード変更が必要
              if (status.isInitialPassword) {
                return const ForceChangePasswordScreen();
              }
              
              // ユーザー種別に応じて画面を切り替え
              switch (status.type) {
                case UserType.staff:
                  debugPrint('🏢 Navigating to AdminShell');
                  return const AdminShell();
                case UserType.parent:
                  debugPrint('👨‍👩‍👧 Navigating to ParentMainScreen');
                  return const ParentMainScreen();
                default:
                  return const _ForceLogout();
              }
            },
          );
        }
        
        // 未ログイン
        return const LoginScreen();
      },
    );
  }

  /// ユーザーのステータスを確認
  Future<UserStatus> _checkUserStatus(String uid) async {
    try {
      debugPrint('🔍 Checking user status for uid: $uid');
      
      // staffsコレクションを確認
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      debugPrint('📋 staffs docs count: ${staffSnap.docs.length}');
      
      if (staffSnap.docs.isNotEmpty) {
        final data = staffSnap.docs.first.data();
        debugPrint('👨‍💼 Found in staffs: ${data['loginId']}');
        return UserStatus(
          type: UserType.staff,
          isInitialPassword: data['isInitialPassword'] == true,
        );
      }

      // familiesコレクションを確認
      final familySnap = await FirebaseFirestore.instance
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      debugPrint('👨‍👩‍👧 families docs count: ${familySnap.docs.length}');
      
      if (familySnap.docs.isNotEmpty) {
        final data = familySnap.docs.first.data();
        debugPrint('👨‍👩‍👧 Found in families: ${data['loginId']}');
        return UserStatus(
          type: UserType.parent,
          isInitialPassword: data['isInitialPassword'] == true,
        );
      }
      
      debugPrint('❌ User not found in any collection');
      return UserStatus.unknown;
    } catch (e) {
      debugPrint('❌ Error checking user status: $e');
      return UserStatus.unknown;
    }
  }
}

/// ローディング画面
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
            Image.asset(
              'assets/logo_beesmiley.png',
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// 強制ログアウト（ユーザー情報が見つからない場合）
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウント情報が見つかりません。管理者にお問い合わせください。'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ============================================================
// 管理者/スタッフ用シェル
// ============================================================

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    CalendarScreen(),      // 0: 予定
    AssessmentScreen(),    // 1: 記録
    ChatListScreen(),      // 2: チャット
    NotificationScreen(),  // 3: お知らせ
    EventScreen(),         // 4: イベント
    AdminScreen(),         // 5: 管理
  ];

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWebLayout = width >= 600;

    return Scaffold(
      body: Row(
        children: [
          // サイドナビゲーション（PC）
          if (isWebLayout)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.primary.withOpacity(0.2),
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              
              leading: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.asset(
                  'assets/logo_beesmileymark.png',
                  width: 50,
                  height: 50,
                  fit: BoxFit.contain,
                ),
              ),
              
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: IconButton(
                      icon: const Icon(Icons.logout, color: Colors.grey),
                      onPressed: _logout,
                      tooltip: 'ログアウト',
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.calendar_month), label: Text('予定')),
                NavigationRailDestination(icon: Icon(Icons.edit_note), label: Text('記録')),
                NavigationRailDestination(icon: Icon(Icons.chat), label: Text('チャット')),
                NavigationRailDestination(icon: Icon(Icons.notifications), label: Text('お知らせ')),
                NavigationRailDestination(icon: Icon(Icons.event), label: Text('イベント')),
                NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
              ],
            ),
          if (isWebLayout) const VerticalDivider(thickness: 1, width: 1),
          
          // メインコンテンツ
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      // ボトムナビゲーション（スマホ）
      bottomNavigationBar: isWebLayout
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (int index) => setState(() => _selectedIndex = index),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.primary,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '予定'),
                BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '記録'),
                BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'チャット'),
                BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
                BottomNavigationBarItem(icon: Icon(Icons.event), label: 'イベント'),
                BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
              ],
            ),
    );
  }
}