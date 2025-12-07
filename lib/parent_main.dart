import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // 追加
import 'parent_chat_screen.dart';
import 'parent_assessment_screen.dart';
import 'parent_notification_screen.dart';
import 'parent_event_screen.dart';
import 'parent_settings_screen.dart';
import 'app_theme.dart';
import 'notification_service.dart'; // 追加

class ParentMainScreen extends StatefulWidget {
  const ParentMainScreen({super.key});

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  // 初期値を0（記録/アセスメント）に設定
  int _selectedIndex = 0;
  
  // バッジ用フラグ
  bool _hasUnreadRecord = false; // 記録
  bool _hasUnreadChat = false;   // チャット
  bool _hasUnreadInfo = false;   // お知らせ
  bool _hasUnreadEvent = false;  // イベント

  // 家族情報
  Map<String, dynamic>? _familyData;
  List<Map<String, dynamic>> _children = [];
  int _selectedChildIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFamilyData();
    _setupNotificationListener(); // バッジ用
    _setupNavigationListener();   // 遷移用
  }

  // バッジ表示用リスナー
  void _setupNotificationListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final type = message.data['type'];
      if (!mounted) return;
      setState(() {
        switch (type) {
          case 'record':
          case 'assessment':
            _hasUnreadRecord = true;
            break;
          case 'chat':
            _hasUnreadChat = true;
            break;
          case 'info':
          case 'notification':
            _hasUnreadInfo = true;
            break;
          case 'event':
            _hasUnreadEvent = true;
            break;
        }
      });
    });
  }

  // 画面遷移用リスナー
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

  // タブ切り替えロジック
  void _navigateByType(String type) {
    int newIndex = _selectedIndex;

    switch (type) {
      case 'record':
      case 'assessment':
        newIndex = 0; // 記録
        break;
      case 'chat':
        newIndex = 1; // チャット
        break;
      case 'info':
      case 'notification':
        newIndex = 2; // お知らせ
        break;
      case 'event':
        newIndex = 3; // イベント
        break;
    }

    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
        // 遷移したらバッジを消す
        if (type == 'chat') _hasUnreadChat = false;
        if (type == 'record') _hasUnreadRecord = false;
        if (type == 'info') _hasUnreadInfo = false;
        if (type == 'event') _hasUnreadEvent = false;
      });
    }
  }

  Future<void> _fetchFamilyData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final query = await FirebaseFirestore.instance
          .collection('families')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
        
        setState(() {
          _familyData = data;
          _children = children;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching family data: $e');
      setState(() => _isLoading = false);
    }
  }

  // 現在選択中の子どもの情報
  Map<String, dynamic>? get _currentChild {
    if (_children.isEmpty) return null;
    return _children[_selectedChildIndex];
  }

  // 子どものID（親のuid_子どもの名前）
  String? get _currentChildId {
    if (_currentChild == null || _familyData == null) return null;
    final uid = _familyData!['uid'];
    final firstName = _currentChild!['firstName'] ?? '';
    return '${uid}_$firstName';
  }

  // 子どもの表示名（名前のみ）
  String get _currentChildFirstName {
    if (_currentChild == null) return '';
    return _currentChild!['firstName'] ?? '';
  }

  // 子どもの顔写真URL
  String? get _currentChildPhotoUrl {
    if (_currentChild == null) return null;
    return _currentChild!['photoUrl'];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 順序: 記録、チャット、お知らせ、イベント、設定
    final List<Widget> screens = [
      // 0: アセスメント
      ParentAssessmentScreen(
        childId: _currentChildId,
        childName: _currentChildFirstName,
        childPhotoUrl: _currentChildPhotoUrl,
        allChildren: _children,
        selectedChildIndex: _selectedChildIndex,
        onChildChanged: (index) {
          setState(() => _selectedChildIndex = index);
        },
      ),
      // 1: チャット
      ParentChatScreen(familyData: _familyData),
      // 2: お知らせ
      const ParentNotificationScreen(),
      // 3: イベント
      ParentEventScreen(
        childId: _currentChildId,
        classroom: _currentChild?['classroom'],
      ),
      // 4: 設定
      ParentSettingsScreen(
        familyData: _familyData,
        children: _children,
        selectedChildIndex: _selectedChildIndex,
        onChildChanged: (index) {
          setState(() => _selectedChildIndex = index);
        },
        onFamilyUpdated: _fetchFamilyData,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: screens[_selectedIndex],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
              // タップしたらバッジを消す
              if (index == 0) _hasUnreadRecord = false;
              if (index == 1) _hasUnreadChat = false;
              if (index == 2) _hasUnreadInfo = false;
              if (index == 3) _hasUnreadEvent = false;
            });
          },
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          // 順序: 記録、チャット、お知らせ、イベント、設定
          items: [
            BottomNavigationBarItem(
              icon: Badge(isLabelVisible: _hasUnreadRecord, child: const Icon(Icons.assignment_outlined)),
              activeIcon: Badge(isLabelVisible: _hasUnreadRecord, child: const Icon(Icons.assignment)),
              label: '記録',
            ),
            BottomNavigationBarItem(
              icon: Badge(isLabelVisible: _hasUnreadChat, child: const Icon(Icons.chat_bubble_outline)),
              activeIcon: Badge(isLabelVisible: _hasUnreadChat, child: const Icon(Icons.chat_bubble)),
              label: 'チャット',
            ),
            BottomNavigationBarItem(
              icon: Badge(isLabelVisible: _hasUnreadInfo, child: const Icon(Icons.notifications_outlined)),
              activeIcon: Badge(isLabelVisible: _hasUnreadInfo, child: const Icon(Icons.notifications)),
              label: 'お知らせ',
            ),
            BottomNavigationBarItem(
              icon: Badge(isLabelVisible: _hasUnreadEvent, child: const Icon(Icons.event_outlined)),
              activeIcon: Badge(isLabelVisible: _hasUnreadEvent, child: const Icon(Icons.event)),
              label: 'イベント',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: '設定',
            ),
          ],
        ),
      ),
    );
  }
}