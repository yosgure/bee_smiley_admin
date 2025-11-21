import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';

// 各画面のインポート
import 'calendar_screen.dart';
import 'assessment_screen.dart';
import 'chat_screen.dart';
import 'notification_screen.dart';
import 'event_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';

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
      title: 'Bee Smiley Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
        fontFamily: 'Noto Sans JP',
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      locale: const Locale('ja', 'JP'),
      
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return const AdminShell();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const CalendarScreen(),      // 0: 予定
    const AssessmentScreen(),    // 1: 記録
    const ChatListScreen(),      // 2: チャット
    const NotificationScreen(),  // 3: お知らせ
    const EventScreen(),         // 4: 企画
    const AdminScreen(),         // 5: 管理
  ];

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWebLayout = width >= 600;

    return Scaffold(
      body: Row(
        children: [
          if (isWebLayout)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              
              // ★ここを変更: アイコンではなく画像を表示
              leading: Padding(
                padding: const EdgeInsets.all(12.0), // 少し余白を調整
                child: Image.asset(
                  'assets/logo_beesmileymark.png',
                  width: 50, // サイズはお好みで調整してください
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
                NavigationRailDestination(icon: Icon(Icons.event), label: Text('企画')),
                NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
              ],
            ),
          if (isWebLayout) const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: isWebLayout
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (int index) => setState(() => _selectedIndex = index),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Colors.orange,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '予定'),
                BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '記録'),
                BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'チャット'),
                BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
                BottomNavigationBarItem(icon: Icon(Icons.event), label: '企画'),
                BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
              ],
            ),
    );
  }
}