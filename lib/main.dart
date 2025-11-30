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
  const UserStatus({required this.type, required this.isInitialPassword});
  static const unknown = UserStatus(type: UserType.unknown, isInitialPassword: false);
}

class AuthCheckWrapper extends StatefulWidget {
  const AuthCheckWrapper({super.key});
  @override
  State<AuthCheckWrapper> createState() => _AuthCheckWrapperState();
}

class _AuthCheckWrapperState extends State<AuthCheckWrapper> {
  UserStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final status = await _checkUserStatus(user.uid);
      if (mounted) setState(() { _status = status; _loading = false; });
    } else {
      if (mounted) setState(() { _status = null; _loading = false; });
    }
    
    // Authの変更を監視
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final status = await _checkUserStatus(user.uid);
        if (mounted) setState(() { _status = status; });
      } else {
        if (mounted) setState(() { _status = null; });
      }
    });
  }

  Future<UserStatus> _checkUserStatus(String uid) async {
    try {
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs').where('uid', isEqualTo: uid).limit(1).get();
      if (staffSnap.docs.isNotEmpty) {
        final data = staffSnap.docs.first.data();
        return UserStatus(type: UserType.staff, isInitialPassword: data['isInitialPassword'] == true);
      }
      final familySnap = await FirebaseFirestore.instance
          .collection('families').where('uid', isEqualTo: uid).limit(1).get();
      if (familySnap.docs.isNotEmpty) {
        final data = familySnap.docs.first.data();
        return UserStatus(type: UserType.parent, isInitialPassword: data['isInitialPassword'] == true);
      }
      return UserStatus.unknown;
    } catch (e) {
      debugPrint('Error: $e');
      return UserStatus.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
    if (_status == null) return const LoginScreen();
    if (_status!.type == UserType.unknown) return const _ForceLogout();
    if (_status!.isInitialPassword) return const ForceChangePasswordScreen();
    if (_status!.type == UserType.staff) return const AdminShell();
    if (_status!.type == UserType.parent) return const ParentMainScreen();
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
  final List<Widget> _screens = const [
    CalendarScreen(), AssessmentScreen(), ChatListScreen(),
    NotificationScreen(), EventScreen(), AdminScreen(),
  ];

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ログアウト', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final isWebLayout = MediaQuery.of(context).size.width >= 600;
    return Scaffold(
      body: Row(
        children: [
          if (isWebLayout) NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.primary.withOpacity(0.2),
            selectedIconTheme: const IconThemeData(color: AppColors.primary),
            selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            leading: Padding(padding: const EdgeInsets.all(12), child: Image.asset('assets/logo_beesmileymark.png', width: 50, height: 50)),
            trailing: Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 20), child: IconButton(icon: const Icon(Icons.logout, color: Colors.grey), onPressed: _logout)))),
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
          Expanded(child: IndexedStack(index: _selectedIndex, children: _screens)),
        ],
      ),
      bottomNavigationBar: isWebLayout ? null : BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
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
