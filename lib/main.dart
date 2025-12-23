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
import 'parent_main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

class _AuthCheckWrapperState extends State<AuthCheckWrapper> with WidgetsBindingObserver {
  UserStatus? _status;
  bool _loading = true;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().clearBadge();
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
      NotificationService().clearBadge();
    }
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      setState(() => _loading = true);
      
      if (user != null) {
        final status = await _checkUserStatus(user.uid);
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
    try {
      final staffSnap = await FirebaseFirestore.instance
          .collection('staffs').where('uid', isEqualTo: uid).limit(1).get();
      if (staffSnap.docs.isNotEmpty) {
        final data = staffSnap.docs.first.data();
        return UserStatus(type: UserType.staff, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
      }
      final familySnap = await FirebaseFirestore.instance
          .collection('families').where('uid', isEqualTo: uid).limit(1).get();
      if (familySnap.docs.isNotEmpty) {
        final data = familySnap.docs.first.data();
        return UserStatus(type: UserType.parent, isInitialPassword: data['isInitialPassword'] == true, uid: uid);
      }
      return UserStatus.unknown;
    } catch (e) {
      return UserStatus.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();
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

enum StaffType { both, beesmiley, plusOnly, loading }

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  bool _hasUnreadSchedule = false;
  bool _hasUnreadChat = false;
  StaffType _staffType = StaffType.loading;
  
  // Web版で右側に表示する管理詳細画面を保持する変数
  Widget? _adminDetailScreen;
  
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
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const PlusScheduleScreen();
          case 2: return const ChatListScreen();
          case 3: return const NotificationScreen();
          case 4: return buildAdminScreen();
          default: return const CalendarScreen();
        }
      case StaffType.beesmiley:
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const AssessmentScreen();
          case 2: return const ChatListScreen();
          case 3: return const NotificationScreen();
          case 4: return const EventScreen();
          case 5: return buildAdminScreen();
          default: return const CalendarScreen();
        }
      case StaffType.both:
      case StaffType.loading:
      default:
        switch (index) {
          case 0: return const CalendarScreen();
          case 1: return const PlusScheduleScreen();
          case 2: return const AssessmentScreen();
          case 3: return const ChatListScreen();
          case 4: return const NotificationScreen();
          case 5: return const EventScreen();
          case 6: return buildAdminScreen();
          default: return const CalendarScreen();
        }
    }
  }
  
  int get _screenCount {
    switch (_staffType) {
      case StaffType.plusOnly: return 5;
      case StaffType.beesmiley: return 6;
      default: return 7;
    }
  }
  
  List<NavigationRailDestination> get _railDestinations {
    switch (_staffType) {
      case StaffType.plusOnly:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          const NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text('プラス')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          const NavigationRailDestination(icon: Icon(Icons.notifications), label: Text('お知らせ')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
      case StaffType.beesmiley:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          const NavigationRailDestination(icon: Icon(Icons.edit_note), label: Text('記録')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          const NavigationRailDestination(icon: Icon(Icons.notifications), label: Text('お知らせ')),
          const NavigationRailDestination(icon: Icon(Icons.event), label: Text('イベント')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
      case StaffType.both:
      case StaffType.loading:
      default:
        return [
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: const Text('予定')),
          const NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text('プラス')),
          const NavigationRailDestination(icon: Icon(Icons.edit_note), label: Text('記録')),
          NavigationRailDestination(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: const Text('チャット')),
          const NavigationRailDestination(icon: Icon(Icons.notifications), label: Text('お知らせ')),
          const NavigationRailDestination(icon: Icon(Icons.event), label: Text('イベント')),
          const NavigationRailDestination(icon: Icon(Icons.manage_accounts), label: Text('管理')),
        ];
    }
  }
  
  List<BottomNavigationBarItem> get _bottomNavItems {
    switch (_staffType) {
      case StaffType.plusOnly:
        return [
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'プラス'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
          const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
          const BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
        ];
      case StaffType.beesmiley:
        return [
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          const BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '記録'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
          const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
          const BottomNavigationBarItem(icon: Icon(Icons.event), label: 'イベント'),
          const BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
        ];
      case StaffType.both:
      case StaffType.loading:
      default:
        return [
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.calendar_month, _hasUnreadSchedule), label: '予定'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'プラス'),
          const BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '記録'),
          BottomNavigationBarItem(icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat), label: 'チャット'),
          const BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'お知らせ'),
          const BottomNavigationBarItem(icon: Icon(Icons.event), label: 'イベント'),
          const BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: '管理'),
        ];
    }
  }

  void _setupNotificationListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final type = message.data['type'];
      if (!mounted) return;
      setState(() {
        if (type == 'schedule') {
          _hasUnreadSchedule = true;
        }
      });
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
      case StaffType.plusOnly:
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'chat': newIndex = 2; break;
          case 'info': newIndex = 3; break;
        }
        break;
      case StaffType.beesmiley:
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'record': newIndex = 1; break;
          case 'chat': newIndex = 2; break;
          case 'info': newIndex = 3; break;
          case 'event': newIndex = 4; break;
        }
        break;
      case StaffType.both:
      case StaffType.loading:
      default:
        switch (type) {
          case 'schedule': newIndex = 0; break;
          case 'record': newIndex = 2; break;
          case 'chat': newIndex = 3; break;
          case 'info': newIndex = 4; break;
          case 'event': newIndex = 5; break;
        }
        break;
    }

    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
        // 画面遷移時は詳細画面を閉じる
        _adminDetailScreen = null;
        if (type == 'schedule') _hasUnreadSchedule = false;
      });
      _saveIndex(newIndex); // 保存
    }
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
    final isWebLayout = MediaQuery.of(context).size.width >= 600;
    
    if (_staffType == StaffType.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                if (i == 0) _hasUnreadSchedule = false;
              });
              _saveIndex(i); // 保存
            },
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.primary.withOpacity(0.2),
            selectedIconTheme: const IconThemeData(color: AppColors.primary),
            selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            unselectedIconTheme: IconThemeData(color: Colors.grey.shade600),
            unselectedLabelTextStyle: TextStyle(color: Colors.grey.shade600),
            leading: Padding(padding: const EdgeInsets.all(12), child: Image.asset('assets/logo_beesmileymark.png', width: 50, height: 50)),
            destinations: _railDestinations,
          ),
          if (isWebLayout) const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: AnimatedSwitcher(
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
        currentIndex: safeIndex,
        onTap: (i) {
          setState(() {
            _selectedIndex = i;
            _adminDetailScreen = null;
            if (i == 0) _hasUnreadSchedule = false;
          });
          _saveIndex(i); // 保存
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        items: _bottomNavItems,
      ),
    );
  }
}