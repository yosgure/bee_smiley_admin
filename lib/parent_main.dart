import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'parent_chat_screen.dart';
import 'parent_assessment_screen.dart';
import 'parent_notification_screen.dart';
import 'parent_event_screen.dart';
import 'parent_settings_screen.dart';
import 'app_theme.dart';
import 'notification_service.dart';

class ParentMainScreen extends StatefulWidget {
  const ParentMainScreen({super.key});

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  int _selectedIndex = 0;
  
  // バッジ用フラグ
  bool _hasUnreadRecord = false;
  bool _hasUnreadChat = false;
  bool _hasUnreadInfo = false;
  bool _hasUnreadEvent = false;

  // 家族情報
  Map<String, dynamic>? _familyData;
  List<Map<String, dynamic>> _children = [];
  int _selectedChildIndex = 0;
  bool _isLoading = true;

  // チャット未読監視用
  StreamSubscription<QuerySnapshot>? _chatRoomSubscription;
  StreamSubscription<QuerySnapshot>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _fetchFamilyData();
    _setupNotificationListener();
    _setupNavigationListener();
    _setupChatUnreadListener();
  }

  @override
  void dispose() {
    _chatRoomSubscription?.cancel();
    _messageSubscription?.cancel();
    super.dispose();
  }

  // チャット未読監視（Firestoreベース・最新50件のみ監視）
  void _setupChatUnreadListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final familyRoomId = 'family_${user.uid}';

    _messageSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(familyRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((msgSnapshot) {
      bool hasUnread = false;
      for (var doc in msgSnapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'];
        if (senderId == user.uid) continue;
        final readBy = List<String>.from(data['readBy'] ?? []);
        if (!readBy.contains(user.uid)) {
          hasUnread = true;
          break;
        }
      }

      if (mounted) {
        setState(() => _hasUnreadChat = hasUnread);
      }
      // アプリアイコンのバッジを未読状態で更新
      NotificationService().setBadge(hasUnread ? 1 : 0);
    });
  }

  // バッジ表示用リスナー（チャット以外）
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
    });
  }

  // 画面遷移用リスナー
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

    switch (type) {
      case 'record':
      case 'assessment':
        newIndex = 0;
        break;
      case 'chat':
        newIndex = 1;
        break;
      case 'info':
      case 'notification':
      case 'announcement':
        newIndex = 2;
        break;
      case 'event':
        newIndex = 3;
        break;
    }

    setState(() {
      _selectedIndex = newIndex;
      if (type == 'record' || type == 'assessment') _hasUnreadRecord = false;
      if (type == 'info' || type == 'notification' || type == 'announcement') _hasUnreadInfo = false;
      if (type == 'event') _hasUnreadEvent = false;
    });
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
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching family data: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? get _currentChild {
    if (_children.isEmpty) return null;
    return _children[_selectedChildIndex];
  }

  String? get _currentChildId {
    if (_currentChild == null || _familyData == null) return null;
    final uid = _familyData!['uid'];
    final firstName = _currentChild!['firstName'] ?? '';
    return '${uid}_$firstName';
  }

  String get _currentChildFirstName {
    if (_currentChild == null) return '';
    return _currentChild!['firstName'] ?? '';
  }

  String? get _currentChildPhotoUrl {
    if (_currentChild == null) return null;
    return _currentChild!['photoUrl'];
  }

  // バッジ付きアイコンを作成するヘルパー（スタッフ用と同じ）
  Widget _buildBadgedIcon(IconData icon, bool showBadge) {
    return Badge(
      isLabelVisible: showBadge,
      smallSize: 10,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    final List<Widget> screens = [
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
      ParentChatScreen(familyData: _familyData),
      const ParentNotificationScreen(),
      ParentEventScreen(
        childId: _currentChildId,
        classroom: _currentChild?['classroom'],
      ),
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
              if (index == 0) _hasUnreadRecord = false;
              if (index == 2) _hasUnreadInfo = false;
              if (index == 3) _hasUnreadEvent = false;
            });
          },
          selectedItemColor: AppColors.primary,
          unselectedItemColor: context.colors.textSecondary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: [
            BottomNavigationBarItem(
              icon: _buildBadgedIcon(Icons.edit_note, _hasUnreadRecord),
              label: '記録',
            ),
            BottomNavigationBarItem(
              icon: _buildBadgedIcon(Icons.chat, _hasUnreadChat),
              label: 'チャット',
            ),
            BottomNavigationBarItem(
              icon: _buildBadgedIcon(Icons.notifications, _hasUnreadInfo),
              label: 'お知らせ',
            ),
            BottomNavigationBarItem(
              icon: _buildBadgedIcon(Icons.event, _hasUnreadEvent),
              label: 'イベント',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: '設定',
            ),
          ],
        ),
      ),
    );
  }
}