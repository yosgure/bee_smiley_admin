import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'app_theme.dart';
import 'notification_service.dart';

// ==========================================
// 1. メイン画面 (ChatListScreen)
// ==========================================

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String? _selectedRoomId;
  final currentUser = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot>? _roomsStream;
  String _myDisplayName = '';
  final Map<String, String> _drafts = {};

  StreamSubscription<String>? _pendingChatRoomSub;

  @override
  void initState() {
    super.initState();
    _initStream();
    _setupPendingChatRoomListener();
  }

  @override
  void dispose() {
    _pendingChatRoomSub?.cancel();
    super.dispose();
  }

  void _setupPendingChatRoomListener() {
    final service = NotificationService();
    // 既に保留の roomId があれば即座に開く
    final pending = service.pendingChatRoomId;
    if (pending != null && pending.isNotEmpty) {
      service.pendingChatRoomId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRoomFromNotification(pending);
      });
    }
    _pendingChatRoomSub = service.pendingChatRoomStream.listen((roomId) {
      if (!mounted) return;
      service.pendingChatRoomId = null;
      _openRoomFromNotification(roomId);
    });
  }

  Future<void> _openRoomFromNotification(String roomId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .get();
      if (!mounted || !doc.exists) return;

      final isWide =
          MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
      if (isWide) {
        setState(() => _selectedRoomId = roomId);
        return;
      }

      // ナロー: チャット詳細画面を直接 push
      final data = doc.data() as Map<String, dynamic>;
      String roomName = (data['groupName'] ?? '').toString().trim();
      final memberNames =
          Map<String, dynamic>.from(data['names'] ?? {});
      if (roomName.isEmpty) {
        final others = memberNames.entries
            .where((e) => e.key != currentUser?.uid)
            .map((e) => e.value.toString().trim())
            .toList();
        if (others.isNotEmpty) roomName = others.join(', ');
      }
      if (roomName.isEmpty) roomName = '名称未設定';
      final isGroup = ((data['members'] as List?) ?? []).length > 2 ||
          (data['groupName'] != null &&
              (data['groupName'] as String).isNotEmpty);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: SafeArea(
                child: _buildCommonHeader(
                  roomName,
                  showBackButton: true,
                  actions: [
                    _buildChatMenu(roomId, isGroup, memberNames, false),
                  ],
                ),
              ),
            ),
            body: ChatDetailView(
              roomId: roomId,
              roomName: roomName,
              isGroup: isGroup,
              memberNames: memberNames,
              showAppBar: false,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('通知からのチャット遷移失敗: $e');
    }
  }

  void _initStream() {
    if (currentUser != null) {
      _roomsStream = FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('members', arrayContains: currentUser!.uid)
          .orderBy('lastMessageTime', descending: true)
          .snapshots();
      _fetchMyName();
    }
  }

  Future<void> _fetchMyName() async {
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('staffs').where('uid', isEqualTo: currentUser!.uid).limit(1).get();
      if (doc.docs.isNotEmpty) {
        setState(() {
          _myDisplayName = doc.docs.first.data()['name'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error fetching my name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) return const Center(child: Text('ログインが必要です'));
    if (_roomsStream == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 800;
        if (isWideScreen) return _buildWideLayout();
        return _buildNarrowLayout();
      },
    );
  }

  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _buildCommonHeader('チャット一覧', isLeftPane: true),
                Expanded(child: _buildFirestoreRoomList(isWide: true)),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: _selectedRoomId == null
                ? Center(child: Text('チャットを選択してください', style: TextStyle(color: context.colors.textSecondary)))
                : _buildChatDetailWrapper(),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return Scaffold(
      body: Column(
        children: [
          SafeArea(bottom: false, child: _buildCommonHeader('チャット一覧', isLeftPane: true)),
          Expanded(child: _buildFirestoreRoomList(isWide: false)),
        ],
      ),
    );
  }

  Widget _buildCommonHeader(String title, {bool isLeftPane = false, List<Widget>? actions, bool showBackButton = false}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(bottom: BorderSide(color: context.colors.borderMedium, width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis)),
          if (showBackButton)
            Positioned(left: 0, child: IconButton(icon: Icon(Icons.arrow_back_ios, color: context.colors.textSecondary), onPressed: () => Navigator.pop(context))),
          Positioned(
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actions != null) ...actions,
                if (isLeftPane)
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.primary, size: 24),
                    tooltip: '新規チャット',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => NewChatDialog(
                        myUid: currentUser!.uid,
                        myName: _myDisplayName,
                        onStartChat: (roomId, name, isGroup, memberNames) {
                          if (MediaQuery.of(context).size.width >= AppBreakpoints.desktop) {
                            setState(() => _selectedRoomId = roomId);
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: PreferredSize(
                                  preferredSize: const Size.fromHeight(40),
                                  child: SafeArea(child: _buildCommonHeader(name, showBackButton: true, actions: [_buildChatMenu(roomId, isGroup, memberNames, false)])),
                                ),
                                body: ChatDetailView(roomId: roomId, roomName: name, isGroup: isGroup, memberNames: memberNames, showAppBar: false),
                              ),
                            ));
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatDetailWrapper() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_selectedRoomId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const Center(child: Text('チャットが存在しません'));

        String roomName = (data['groupName'] ?? '').toString().trim();
        if (roomName.isEmpty) {
          final names = Map<String, dynamic>.from(data['names'] ?? {});
          final otherNames = names.entries.where((e) => e.key != currentUser!.uid).map((e) => e.value.toString().trim().replaceAll(RegExp(r'\s+'), ' ')).toList();
          if (otherNames.isNotEmpty) roomName = otherNames.join(', ');
        }
        if (roomName.isEmpty) roomName = '名称未設定';

        final isGroup = (data['members'] as List).length > 2 || (data['groupName'] != null && data['groupName'].isNotEmpty);
        final memberNames = Map<String, dynamic>.from(data['names'] ?? {});

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _buildCommonHeader(roomName, actions: [_buildChatMenu(_selectedRoomId!, isGroup, memberNames, true)]),
          ),
          body: ChatDetailView(
            key: ValueKey(_selectedRoomId),
            roomId: _selectedRoomId!, roomName: roomName, isGroup: isGroup, memberNames: memberNames, showAppBar: false,
            initialDraft: _drafts[_selectedRoomId!] ?? '',
            onDraftChanged: (text) => _drafts[_selectedRoomId!] = text,
          ),
        );
      },
    );
  }

  Widget _buildChatMenu(String roomId, bool isGroup, Map<String, dynamic> memberNames, bool isWide) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: context.colors.textSecondary),
      onSelected: (value) {
        if (value == 'delete') _deleteChat(roomId, isWide);
        if (value == 'members') _showMemberList(memberNames);
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(value: 'members', child: Text('メンバー一覧')),
        const PopupMenuItem(value: 'delete', child: Text('チャットを削除', style: TextStyle(color: Colors.red))),
      ],
    );
  }

  void _deleteChat(String roomId, bool isWide) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('チャットを削除'),
        content: const Text('このチャットルームを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).delete();
              if (isWide) setState(() => _selectedRoomId = null);
              else Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showMemberList(Map<String, dynamic> names) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メンバー一覧'),
        content: SizedBox(
          width: 300, height: 300,
          child: ListView(
            children: names.entries.map((e) {
              final name = e.key == currentUser!.uid ? '${e.value} (自分)' : e.value;
              return ListTile(leading: const Icon(Icons.person), title: Text(name));
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
      ),
    );
  }

  Widget _buildFirestoreRoomList({required bool isWide}) {
    if (_roomsStream == null) return const Center(child: Text('ストリームが初期化されていません'));

    return StreamBuilder<QuerySnapshot>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('エラー: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('チャット履歴はありません'));

        final docs = snapshot.data!.docs;
        
        if (isWide && _selectedRoomId == null && docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedRoomId = docs.first.id);
            }
          });
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final roomDoc = docs[index];
            return _SwipeTile(
              key: ValueKey(roomDoc.id),
              roomId: roomDoc.id,
              onDelete: () async {
                await FirebaseFirestore.instance.collection('chat_rooms').doc(roomDoc.id).delete();
                if (isWide && _selectedRoomId == roomDoc.id) setState(() => _selectedRoomId = null);
              },
              child: _RoomListTile(
              roomDoc: roomDoc,
              myUid: currentUser!.uid,
              isSelected: isWide && roomDoc.id == _selectedRoomId,
              onTap: (roomId, roomName, isGroup, memberNames) {
                if (isWide) {
                  setState(() => _selectedRoomId = roomId);
                } else {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: PreferredSize(
                        preferredSize: const Size.fromHeight(40),
                        child: SafeArea(child: _buildCommonHeader(roomName, showBackButton: true, actions: [_buildChatMenu(roomId, isGroup, memberNames, false)])),
                      ),
                      body: ChatDetailView(roomId: roomId, roomName: roomName, isGroup: isGroup, memberNames: memberNames, showAppBar: false),
                    ),
                  ));
                }
              },
            ));
          },
        );
      },
    );
  }
}

// ==========================================
// スワイプ削除ラッパー
// ==========================================
class _SwipeTile extends StatefulWidget {
  final String roomId;
  final VoidCallback onDelete;
  final Widget child;
  const _SwipeTile({super.key, required this.roomId, required this.onDelete, required this.child});
  @override
  State<_SwipeTile> createState() => _SwipeTileState();
}

class _SwipeTileState extends State<_SwipeTile> with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _showButton = false;
  static const double _buttonWidth = 80;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(-_buttonWidth, 0);
      _showButton = _dragOffset < -20;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    setState(() {
      if (_dragOffset < -_buttonWidth / 2) {
        _dragOffset = -_buttonWidth;
        _showButton = true;
      } else {
        _dragOffset = 0;
        _showButton = false;
      }
    });
  }

  void _close() {
    setState(() { _dragOffset = 0; _showButton = false; });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: ClipRect(
        child: Stack(
          children: [
            // 削除ボタン（スワイプで露出する部分のみ）
            if (_showButton)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: _buttonWidth,
                child: GestureDetector(
                  onTap: () {
                    _close();
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('チャットを削除'),
                        content: const Text('このチャットルームを削除しますか？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                          TextButton(onPressed: () { Navigator.pop(ctx); widget.onDelete(); }, child: const Text('削除', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    color: Colors.red,
                    alignment: Alignment.center,
                    child: const Text('削除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            // メインのタイル（背景色付き）
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// リストアイテム
// ==========================================
class _RoomListTile extends StatefulWidget {
  final DocumentSnapshot roomDoc;
  final String myUid;
  final bool isSelected;
  final Function(String, String, bool, Map<String, dynamic>) onTap;

  const _RoomListTile({required this.roomDoc, required this.myUid, required this.isSelected, required this.onTap});

  @override
  State<_RoomListTile> createState() => _RoomListTileState();
}

class _RoomListTileState extends State<_RoomListTile> {
  Future<Map<String, dynamic>>? _peerInfoFuture;
  String? _cachedPeerId;

  Future<Map<String, dynamic>> _fetchPeerInfo(String peerId) async {
    var snap = await FirebaseFirestore.instance.collection('staffs').where('uid', isEqualTo: peerId).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first.data();
      return {'name': d['name'] ?? 'スタッフ', 'photoUrl': d['photoUrl'], 'isStaff': true};
    }
    snap = await FirebaseFirestore.instance.collection('families').where('uid', isEqualTo: peerId).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first.data();
      final lastName = (d['lastName'] ?? '').toString().trim();
      final firstName = (d['firstName'] ?? '').toString().trim();
      final fullName = '$lastName $firstName'.trim();
      String? childPhotoUrl;
      final children = List<Map<String, dynamic>>.from(d['children'] ?? []);
      if (children.isNotEmpty) childPhotoUrl = children.first['photoUrl'] as String?;
      return {'name': fullName.isNotEmpty ? fullName : '保護者', 'photoUrl': childPhotoUrl, 'isStaff': false};
    }
    return {'name': '不明', 'photoUrl': null, 'isStaff': false};
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDate = DateTime(date.year, date.month, date.day);
    return aDate == today ? DateFormat('HH:mm').format(date) : DateFormat('MM/dd').format(date);
  }

  Widget _buildTrailing(String roomId, String timeStr) {
    // 選択中（表示中）のルームは未読バッジを表示しない（ChatDetailViewが自動既読にするため点滅防止）
    if (widget.isSelected) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeStr, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
        ],
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').where('senderId', isNotEqualTo: widget.myUid).snapshots(),
      builder: (context, msgSnapshot) {
        int unreadCount = 0;
        if (msgSnapshot.hasData) {
          for (var doc in msgSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final readBy = List<String>.from(data['readBy'] ?? []);
            if (!readBy.contains(widget.myUid)) unreadCount++;
          }
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeStr, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 4), width: 20, height: 20,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Center(child: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.roomDoc.data() as Map<String, dynamic>;
    final roomId = widget.roomDoc.id;
    final isGroup = (room['members'] as List).length > 2 || (room['groupName'] != null && room['groupName'].isNotEmpty);
    final memberNames = Map<String, dynamic>.from(room['names'] ?? {});
    String timeStr = '';
    if (room['lastMessageTime'] != null) {
      final ts = room['lastMessageTime'] as Timestamp;
      timeStr = _formatTime(ts.toDate());
    }
    if (isGroup) {
      final groupName = (room['groupName'] ?? 'グループ').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
      final photoUrl = room['photoUrl'] as String?;
      return ListTile(
        selected: widget.isSelected, selectedTileColor: AppColors.primary.withOpacity(0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: (photoUrl == null || photoUrl.isEmpty) ? Text(groupName.isNotEmpty ? groupName[0] : 'G', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)) : null,
        ),
        title: Text(groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal, color: widget.isSelected ? AppColors.primary : context.colors.textPrimary)),
        subtitle: Text(room['lastMessage'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
        trailing: _buildTrailing(roomId, timeStr),
        onTap: () => widget.onTap(roomId, groupName, true, memberNames),
      );
    }
    final peerId = (room['members'] as List).firstWhere((id) => id != widget.myUid, orElse: () => '');
    if (peerId.isEmpty) return const SizedBox();
    // Futureをキャッシュして、リビルドごとに再フェッチしないようにする
    if (_peerInfoFuture == null || _cachedPeerId != peerId) {
      _cachedPeerId = peerId;
      _peerInfoFuture = _fetchPeerInfo(peerId).then((info) {
        // names mapの名前が古い場合、Firestoreを同期更新
        final currentName = memberNames[peerId]?.toString() ?? '';
        final fetchedName = info['name']?.toString() ?? '';
        if (fetchedName.isNotEmpty && currentName != fetchedName) {
          FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).update({'names.$peerId': fetchedName});
        }
        return info;
      });
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _peerInfoFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // フェッチ完了まではスケルトン表示（names mapの古いデータでチラつくのを防止）
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(backgroundColor: context.colors.borderLight),
            title: Container(height: 14, width: 80, decoration: BoxDecoration(color: context.colors.borderLight, borderRadius: BorderRadius.circular(4))),
            subtitle: Container(height: 10, width: 120, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(4))),
            trailing: _buildTrailing(roomId, timeStr),
          );
        }
        final peerData = snapshot.data!;
        final name = (peerData['name'] ?? '不明').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
        final photoUrl = peerData['photoUrl'] as String?;
        final isStaff = peerData['isStaff'] == true;
        return ListTile(
          selected: widget.isSelected, selectedTileColor: AppColors.primary.withOpacity(0.1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: isStaff ? AppColors.primary.withOpacity(0.15) : AppColors.accent.shade100,
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty) ? Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(color: isStaff ? AppColors.primary : AppColors.accent, fontWeight: FontWeight.bold)) : null,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal, color: widget.isSelected ? AppColors.primary : context.colors.textPrimary)),
          subtitle: Text(room['lastMessage'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
          trailing: _buildTrailing(roomId, timeStr),
          onTap: () => widget.onTap(roomId, name, false, memberNames),
        );
      },
    );
  }
}

// ==========================================
// 2. 新規チャット作成ダイアログ
// ==========================================

class NewChatDialog extends StatefulWidget {
  final String myUid;
  final String myName;
  final Function(String roomId, String roomName, bool isGroup, Map<String, dynamic> memberNames) onStartChat;
  const NewChatDialog({super.key, required this.myUid, required this.myName, required this.onStartChat});
  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _families = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _filteredFamilies = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  final Set<String> _selectedUids = {};
  bool _isGroupMode = false;
  bool _isLoading = true;
  Uint8List? _groupImageBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) setState(() { _selectedUids.clear(); _isGroupMode = false; _groupImageBytes = null; });
    });
    _fetchUsers();
  }

  @override
  void dispose() { _tabController?.dispose(); _groupNameController.dispose(); _searchController.dispose(); super.dispose(); }

  Future<void> _fetchUsers() async {
    try {
      final List<Map<String, dynamic>> tempFamilies = [];
      final List<Map<String, dynamic>> tempStaff = [];
      final familySnap = await FirebaseFirestore.instance.collection('families').get();
      for (var doc in familySnap.docs) {
        final d = doc.data();
        if (d['uid'] == widget.myUid) continue;
        final name = '${(d['lastName'] ?? '').toString().trim()} ${(d['firstName'] ?? '').toString().trim()}'.trim();
        final kana = '${(d['lastNameKana'] ?? '').toString().trim()} ${(d['firstNameKana'] ?? '').toString().trim()}'.trim();
        final children = List<Map<String, dynamic>>.from(d['children'] ?? []);
        String? classroom; String? childPhotoUrl;
        if (children.isNotEmpty) { classroom = children.first['classroom']; childPhotoUrl = children.first['photoUrl'] as String?; }
        tempFamilies.add({'uid': d['uid'] ?? doc.id, 'name': name.isEmpty ? '名称未設定' : name, 'kana': kana.isEmpty ? name : kana, 'photoUrl': childPhotoUrl, 'classroom': classroom});
      }
      final staffSnap = await FirebaseFirestore.instance.collection('staffs').get();
      for (var doc in staffSnap.docs) {
        final d = doc.data();
        final String uid = d['uid'] ?? doc.id;
        if (uid == widget.myUid) continue;
        String name = (d['name'] ?? '').toString().trim();
        if (name.isEmpty) name = '${(d['lastName'] ?? '').toString().trim()} ${(d['firstName'] ?? '').toString().trim()}'.trim();
        if (name.isEmpty) name = 'スタッフ (名称未設定)';
        String kana = d['furigana'] ?? '';
        if (kana.isEmpty) kana = name;
        tempStaff.add({'uid': uid, 'name': name, 'kana': kana, 'photoUrl': d['photoUrl'], 'classrooms': d['classrooms']});
      }
      tempFamilies.sort((a, b) => a['kana'].compareTo(b['kana']));
      tempStaff.sort((a, b) => a['kana'].compareTo(b['kana']));
      setState(() { _families = tempFamilies; _staff = tempStaff; _filteredFamilies = tempFamilies; _filteredStaff = tempStaff; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) { _filteredFamilies = _families; _filteredStaff = _staff; }
      else {
        _filteredFamilies = _families.where((u) => u['name'].contains(query) || u['kana'].contains(query)).toList();
        _filteredStaff = _staff.where((u) => u['name'].contains(query) || u['kana'].contains(query)).toList();
      }
    });
  }

  String _getIndexHeader(String kana) {
    if (kana.isEmpty) return '他';
    final firstChar = kana.substring(0, 1);
    if (firstChar.compareTo('あ') >= 0 && firstChar.compareTo('お') <= 0) return 'あ';
    if (firstChar.compareTo('か') >= 0 && firstChar.compareTo('こ') <= 0) return 'か';
    if (firstChar.compareTo('さ') >= 0 && firstChar.compareTo('そ') <= 0) return 'さ';
    if (firstChar.compareTo('た') >= 0 && firstChar.compareTo('と') <= 0) return 'た';
    if (firstChar.compareTo('な') >= 0 && firstChar.compareTo('の') <= 0) return 'な';
    if (firstChar.compareTo('は') >= 0 && firstChar.compareTo('ほ') <= 0) return 'は';
    if (firstChar.compareTo('ま') >= 0 && firstChar.compareTo('も') <= 0) return 'ま';
    if (firstChar.compareTo('や') >= 0 && firstChar.compareTo('よ') <= 0) return 'や';
    if (firstChar.compareTo('ら') >= 0 && firstChar.compareTo('ろ') <= 0) return 'ら';
    if (firstChar.compareTo('わ') >= 0 && firstChar.compareTo('ん') <= 0) return 'わ';
    return '他';
  }

  Widget _buildSectionedList(List<Map<String, dynamic>> users, bool isStaffTab) {
    if (users.isEmpty) return const Center(child: Text('ユーザーがいません'));
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var user in users) { final header = _getIndexHeader(user['kana']); if (!grouped.containsKey(header)) grouped[header] = []; grouped[header]!.add(user); }
    final headers = grouped.keys.toList()..sort();
    return ListView.builder(
      itemCount: headers.length,
      itemBuilder: (context, index) {
        final header = headers[index];
        final groupUsers = grouped[header]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), color: context.colors.cardBg, child: Text(header, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14))),
            Divider(height: 1, thickness: 1, color: context.colors.scaffoldBgAlt),
            ...groupUsers.map((user) {
              final uid = user['uid']; final isSelected = _selectedUids.contains(uid); final photoUrl = user['photoUrl']; final name = user['name'];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                leading: CircleAvatar(backgroundColor: isStaffTab ? AppColors.primary.withOpacity(0.15) : AppColors.accent.shade100, backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: (photoUrl == null || photoUrl.isEmpty) ? Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(color: isStaffTab ? AppColors.primary : AppColors.accent, fontWeight: FontWeight.bold)) : null),
                title: Text(name, style: TextStyle(fontSize: 16)),
                trailing: isStaffTab && _isGroupMode ? Checkbox(value: isSelected, activeColor: AppColors.primary, onChanged: (val) => _toggleSelection(uid)) : null,
                onTap: () { if (isStaffTab && _isGroupMode) _toggleSelection(uid); else if (isStaffTab) _startSingleChat(uid, user['name']); else _startFamilyChat(user); },
              );
            }),
          ],
        );
      },
    );
  }

  void _toggleSelection(String uid) { setState(() { if (_selectedUids.contains(uid)) _selectedUids.remove(uid); else _selectedUids.add(uid); }); }

  Future<void> _pickGroupImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) { final bytes = await picked.readAsBytes(); setState(() => _groupImageBytes = bytes); }
  }

  void _startSingleChat(String targetUid, String targetName) async {
    final memberIds = [widget.myUid, targetUid]..sort();
    final roomId = memberIds.join('_');
    final Map<String, String> namesMap = {widget.myUid: widget.myName.isEmpty ? '担当者' : widget.myName, targetUid: targetName};
    await _createRoomIfNeeded(roomId, memberIds, namesMap, null, null);
    if (mounted) { Navigator.pop(context); widget.onStartChat(roomId, targetName, false, namesMap); }
  }

  void _startFamilyChat(Map<String, dynamic> familyData) async {
    final familyUid = familyData['uid']; final familyName = familyData['name']; final classroom = familyData['classroom'];
    List<String> classroomStaffUids = [widget.myUid];
    Map<String, String> namesMap = {widget.myUid: widget.myName.isEmpty ? '担当者' : widget.myName, familyUid: familyName};
    if (classroom != null) {
      for (var staff in _staff) {
        if (staff['classrooms'] != null && (staff['classrooms'] as List).contains(classroom) && staff['uid'] != widget.myUid) { classroomStaffUids.add(staff['uid']); namesMap[staff['uid']] = staff['name']; }
      }
    }
    final List<String> memberIds = [familyUid, ...classroomStaffUids]..sort();
    final roomId = 'family_$familyUid';
    String? groupName; if (classroomStaffUids.length > 1) groupName = familyName;
    await _createRoomIfNeeded(roomId, memberIds, namesMap, groupName, null);
    if (mounted) { Navigator.pop(context); widget.onStartChat(roomId, groupName ?? familyName, classroomStaffUids.length > 1, namesMap); }
  }

  void _startGroupChat() async {
    if (_selectedUids.isEmpty) return;
    final roomId = FirebaseFirestore.instance.collection('chat_rooms').doc().id;
    final memberIds = [widget.myUid, ..._selectedUids]..sort();
    final Map<String, String> namesMap = {widget.myUid: widget.myName.isEmpty ? '担当者' : widget.myName};
    for (var uid in _selectedUids) { final user = _staff.firstWhere((u) => u['uid'] == uid, orElse: () => {'name': 'Unknown'}); namesMap[uid] = user['name']; }
    String groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) { groupName = namesMap.values.where((n) => n != widget.myName).take(3).join(', '); if (namesMap.length > 4) groupName += '...'; }
    String? photoUrl;
    if (_groupImageBytes != null) {
      try { final ref = FirebaseStorage.instance.ref().child('group_photos/$roomId.jpg'); await ref.putData(_groupImageBytes!, SettableMetadata(contentType: 'image/jpeg')); photoUrl = await ref.getDownloadURL(); } catch (e) { debugPrint('Error uploading group image: $e'); }
    }
    await _createRoomIfNeeded(roomId, memberIds, namesMap, groupName, photoUrl);
    if (mounted) { Navigator.pop(context); widget.onStartChat(roomId, groupName, true, namesMap); }
  }

  Future<void> _createRoomIfNeeded(String roomId, List<String> members, Map<String, String> names, String? groupName, String? photoUrl) async {
    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId);
    final doc = await roomRef.get();
    if (!doc.exists) {
      await roomRef.set({'roomId': roomId, 'members': members, 'names': names, 'groupName': groupName, 'photoUrl': photoUrl, 'lastMessage': groupName != null ? 'グループ作成' : 'チャット開始', 'lastMessageTime': FieldValue.serverTimestamp(), 'createdAt': FieldValue.serverTimestamp()});
    } else { final updateData = <String, dynamic>{'members': members, 'names': names}; if (groupName != null) updateData['groupName'] = groupName; await roomRef.update(updateData); }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 500.0;
    final dialogHeight = screenHeight < 700 ? screenHeight * 0.85 : 650.0;
    return AlertDialog(
      contentPadding: EdgeInsets.zero, backgroundColor: context.colors.cardBg, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: dialogWidth, height: dialogHeight,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('新規チャット', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: _searchController, decoration: const InputDecoration(hintText: '名前で検索...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true, filled: false), onChanged: _onSearch),
                  const SizedBox(height: 16),
                  TabBar(controller: _tabController, labelColor: AppColors.primary, unselectedLabelColor: Colors.grey, indicatorColor: AppColors.primary, indicatorSize: TabBarIndicatorSize.tab, labelStyle: const TextStyle(fontWeight: FontWeight.bold), tabs: const [Tab(text: '保護者'), Tab(text: 'スタッフ')]),
                  AnimatedBuilder(
                    animation: _tabController!,
                    builder: (context, _) {
                      if (_tabController!.index == 1) {
                        return Column(
                          children: [
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Text('グループ作成', style: TextStyle(fontSize: 14)), const SizedBox(width: 8), Switch(value: _isGroupMode, activeColor: AppColors.primary, onChanged: (val) => setState(() => _isGroupMode = val))]),
                            if (_isGroupMode) ...[
                              const SizedBox(height: 16),
                              Row(children: [
                                GestureDetector(onTap: _pickGroupImage, child: CircleAvatar(radius: 24, backgroundColor: context.colors.borderLight, backgroundImage: _groupImageBytes != null ? MemoryImage(_groupImageBytes!) : null, child: _groupImageBytes == null ? Icon(Icons.camera_alt, color: context.colors.textSecondary) : null)),
                                const SizedBox(width: 16),
                                Expanded(child: TextField(controller: _groupNameController, decoration: const InputDecoration(labelText: 'グループ名（任意）', border: OutlineInputBorder(), isDense: true))),
                              ]),
                            ]
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabController, children: [_buildSectionedList(_filteredFamilies, false), _buildSectionedList(_filteredStaff, true)])),
            if (_tabController!.index == 1 && _isGroupMode) Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _selectedUids.isEmpty ? null : _startGroupChat, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)), child: Text('選択した${_selectedUids.length}名でグループ作成')))) else const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. チャット詳細画面 (ChatDetailView)
// ==========================================

class ChatDetailView extends StatefulWidget {
  final String roomId;
  final String roomName;
  final bool showAppBar;
  final bool isGroup;
  final Map<String, dynamic> memberNames;
  final String initialDraft;
  final ValueChanged<String>? onDraftChanged;
  const ChatDetailView({super.key, required this.roomId, required this.roomName, required this.isGroup, required this.memberNames, this.showAppBar = true, this.initialDraft = '', this.onDraftChanged});
  @override
  State<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<ChatDetailView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _isUploading = false;
  // デフォルトで＋（折りたたみ）。タップすると展開して添付アイコンが出る
  bool _iconsExpanded = false;

  // 返信対象: {messageId, senderName, preview, type}
  Map<String, dynamic>? _replyTo;

  void _startReply(String msgId, String type, String text) {
    final senderId = _lastMessageCache[msgId]?['senderId'] as String?;
    final senderName = senderId == currentUser?.uid
        ? (_myNameCache ?? '自分')
        : (widget.memberNames[senderId] ?? '相手').toString();
    String preview;
    if (type == 'image') {
      preview = '📷 画像';
    } else if (type == 'file') {
      preview = '📎 ファイル';
    } else if (type == 'video') {
      preview = '🎬 動画';
    } else {
      preview = text;
    }
    setState(() {
      _replyTo = {
        'messageId': msgId,
        'senderName': senderName,
        'preview': preview,
        'type': type,
      };
    });
    // 入力欄にフォーカス
    FocusScope.of(context).requestFocus(_focusNode);
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  // 返信時の senderName 特定のためのキャッシュ
  final Map<String, Map<String, dynamic>> _lastMessageCache = {};
  String? _myNameCache;

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft.isNotEmpty) {
      _textController.text = widget.initialDraft;
    }
    _textController.addListener(() {
      // 文字を入力し始めたらアイコン群を自動で折りたたむ
      if (_iconsExpanded && _textController.text.isNotEmpty) {
        setState(() => _iconsExpanded = false);
      }
      widget.onDraftChanged?.call(_textController.text);
    });
  }

  @override
  void dispose() { _textController.dispose(); _scrollController.dispose(); _focusNode.dispose(); super.dispose(); }

  void _dismissKeyboard() { _focusNode.unfocus(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Column(
        children: [
          if (widget.showAppBar) ...[
            Container(
              height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: context.colors.cardBg, border: Border(bottom: BorderSide(color: context.colors.borderMedium, width: 1))),
              child: Row(children: [
                Expanded(child: Text(widget.roomName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: context.colors.textSecondary),
                  onSelected: (value) { if (value == 'delete') _deleteChat(); if (value == 'members') _showMembers(); },
                  itemBuilder: (context) => [if (widget.isGroup) const PopupMenuItem(value: 'members', child: Text('メンバー一覧')), const PopupMenuItem(value: 'delete', child: Text('チャットを削除', style: TextStyle(color: Colors.red)))],
                ),
              ]),
            ),
          ],
          Expanded(
            child: Container(
              color: context.colors.cardBg,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').orderBy('createdAt', descending: false).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final senderId = data['senderId'];
                    final readBy = List<String>.from(data['readBy'] ?? []);
                    if (currentUser != null && senderId != currentUser!.uid && !readBy.contains(currentUser!.uid)) {
                      FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(doc.id).update({'readBy': FieldValue.arrayUnion([currentUser!.uid])});
                    }
                  }
                  return ListView.builder(
                    controller: _scrollController, reverse: true, padding: const EdgeInsets.all(16), itemCount: docs.length, cacheExtent: 5000,
                    itemBuilder: (context, index) {
                      final reversedIndex = docs.length - 1 - index;
                      final msg = docs[reversedIndex].data() as Map<String, dynamic>;
                      final msgId = docs[reversedIndex].id;
                      Widget? dateSeparator;
                      if (msg['createdAt'] != null) {
                        final date = (msg['createdAt'] as Timestamp).toDate();
                        final dateStr = DateFormat('yyyy年M月d日 EEEE', 'ja').format(date);
                        bool showDate = true;
                        if (reversedIndex > 0) {
                          final prevMsg = docs[reversedIndex - 1].data() as Map<String, dynamic>;
                          if (prevMsg['createdAt'] != null) {
                            final prevDate = (prevMsg['createdAt'] as Timestamp).toDate();
                            if (DateFormat('yyyyMMdd').format(date) == DateFormat('yyyyMMdd').format(prevDate)) showDate = false;
                          }
                        }
                        if (showDate) {
                          dateSeparator = Center(child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(color: context.colors.borderLight, borderRadius: BorderRadius.circular(12)),
                            child: Text(dateStr, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
                          ));
                        }
                      }
                      return Column(children: [if (dateSeparator != null) dateSeparator, _buildMessageItem(msg, msgId)]);
                    },
                  );
                },
              ),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  void _deleteChat() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('チャットを削除'), content: const Text('このチャットルームを削除しますか？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')), TextButton(onPressed: () async { Navigator.pop(ctx); await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).delete(); }, child: const Text('削除', style: TextStyle(color: Colors.red)))],
    ));
  }

  void _showMembers() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('メンバー一覧'),
      content: SizedBox(width: 300, height: 300, child: ListView(children: widget.memberNames.entries.map((e) { final name = e.key == currentUser!.uid ? '${e.value} (自分)' : e.value; return ListTile(leading: const Icon(Icons.person), title: Text(name)); }).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
    ));
  }

  Widget _buildInputArea() {
    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Container(
        color: context.colors.cardBg,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
            if (_replyTo != null) _buildReplyPreviewBar(),
            // 入力エリア全体を角丸コンテナで囲む
            Container(
              decoration: BoxDecoration(
                color: context.colors.chipBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // テキスト入力エリア
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: Focus(
                        onKeyEvent: (node, event) {
                          if (_textController.value.composing.isValid) return KeyEventResult.ignored;
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) { _sendMessage(); return KeyEventResult.handled; }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _textController, focusNode: _focusNode,
                          maxLines: null, minLines: 3, keyboardType: TextInputType.multiline,
                          style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']),
                          decoration: InputDecoration(
                            hintText: 'メッセージを入力してください。(Enterで送信 / Shift + Enterで改行)',
                            hintStyle: TextStyle(fontSize: 14, color: context.colors.iconMuted),
                            border: InputBorder.none,
                            filled: true,
                            fillColor: context.colors.chipBg,
                            hoverColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  // アイコンバー
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.attach_file, color: _isUploading ? context.colors.borderMedium : context.colors.textSecondary, size: 22),
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: 'ファイルを添付',
                          onPressed: _isUploading ? null : _pickAndUploadFile,
                        ),
                        IconButton(
                          icon: Icon(Icons.image_outlined, color: _isUploading ? context.colors.borderMedium : context.colors.textSecondary, size: 22),
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: '画像を送信',
                          onPressed: _isUploading ? null : _pickAndUploadImage,
                        ),
                        IconButton(
                          icon: Icon(Icons.videocam_outlined, color: _isUploading ? context.colors.borderMedium : context.colors.textSecondary, size: 22),
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: '動画を送信',
                          onPressed: _isUploading ? null : _pickAndUploadVideo,
                        ),
                        const Spacer(),
                        // 送信ボタン（青丸）
                        GestureDetector(
                          onTap: _sendMessage,
                          child: Container(
                            width: 36, height: 36,
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.send, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), color: context.colors.cardBg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildReplyPreviewBar(),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            if (!_iconsExpanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _iconsExpanded = true),
                  child: Container(
                    width: 28, height: 28, margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: context.colors.borderLight, shape: BoxShape.circle),
                    child: Icon(Icons.add, color: context.colors.textSecondary, size: 18),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: IconButton(icon: Icon(Icons.attach_file, color: context.colors.textSecondary, size: 20), constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: EdgeInsets.zero, onPressed: _isUploading ? null : _pickAndUploadFile),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: IconButton(icon: Icon(Icons.image, color: context.colors.textSecondary, size: 20), constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: EdgeInsets.zero, onPressed: _isUploading ? null : _pickAndUploadImage),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: IconButton(icon: Icon(Icons.videocam, color: context.colors.textSecondary, size: 20), constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: EdgeInsets.zero, onPressed: _isUploading ? null : _pickAndUploadVideo),
              ),
            ],
            const SizedBox(width: 4),
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (_textController.value.composing.isValid) return KeyEventResult.ignored;
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) { _sendMessage(); return KeyEventResult.handled; }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _textController, focusNode: _focusNode, maxLines: null, minLines: 1, keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']),
                  decoration: InputDecoration(hintText: 'メッセージを入力', filled: true, fillColor: context.colors.chipBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: GestureDetector(onTap: _sendMessage, child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.send, color: Colors.white, size: 20))),
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreviewBar() {
    final senderName = (_replyTo?['senderName'] ?? '') as String;
    final preview = (_replyTo?['preview'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.reply, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$senderName への返信',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _cancelReply,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: context.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _chatTextStyleOf(BuildContext context) => TextStyle(fontSize: 15, height: 1.5, color: context.colors.textPrimary, fontFamily: 'NotoSansJP', fontFamilyFallback: const ['Hiragino Sans', 'Roboto', 'sans-serif']);
  static const _chatLinkStyle = TextStyle(fontSize: 15, height: 1.5, color: Colors.blue, decoration: TextDecoration.underline, decorationColor: Colors.blue, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']);

  List<InlineSpan> _buildTextSpansWithLinks(String text, {BuildContext? ctx}) {
    final textStyle = ctx != null ? _chatTextStyleOf(ctx) : const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']);
    final urlPattern = RegExp(r'https?://[^\s\u3000]+', caseSensitive: false);
    final spans = <InlineSpan>[]; int lastEnd = 0;
    for (final match in urlPattern.allMatches(text)) {
      if (match.start > lastEnd) spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: textStyle));
      final url = match.group(0)!;
      spans.add(TextSpan(text: url, style: _chatLinkStyle, recognizer: TapGestureRecognizer()..onTap = () async { final uri = Uri.tryParse(url); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) spans.add(TextSpan(text: text.substring(lastEnd), style: textStyle));
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: textStyle));
    return spans;
  }

  Widget _buildReplyQuote(Map<String, dynamic> replyTo, bool isMe) {
    final senderName = (replyTo['senderName'] ?? '') as String;
    final preview = (replyTo['preview'] ?? '') as String;
    final bgColor =
        isMe ? context.colors.cardBg.withOpacity(0.5) : context.colors.cardBg.withOpacity(0.7);
    final accentColor = isMe ? AppColors.primary : context.colors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg, String msgId) {
    // キャッシュ（返信時の senderName 取得用）
    _lastMessageCache[msgId] = msg;
    final isMe = msg['senderId'] == currentUser?.uid;
    if (isMe && _myNameCache == null) {
      _myNameCache = widget.memberNames[currentUser?.uid] as String?;
    }
    final String text = msg['text'] ?? '';
    final String type = msg['type'] ?? 'text';
    final stamps = Map<String, dynamic>.from(msg['stamps'] ?? {});
    final readBy = List<String>.from(msg['readBy'] ?? []);
    final readCount = readBy.where((uid) => uid != currentUser!.uid).length;
    final isRead = isMe && readCount > 0;
    final totalMembers = widget.memberNames.length - 1;
    String timeStr = '';
    if (msg['createdAt'] != null) { final ts = msg['createdAt'] as Timestamp; timeStr = DateFormat('HH:mm').format(ts.toDate()); }
    String senderName = '';
    if (widget.isGroup && !isMe) senderName = widget.memberNames[msg['senderId']] ?? '不明';
    final Map<String, dynamic>? replyTo =
        msg['replyTo'] is Map ? Map<String, dynamic>.from(msg['replyTo']) : null;

    Widget content;
    final bool isImageOnly = (type == 'image' || type == 'video') && text.isEmpty;
    if (type == 'image') {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(onTap: () => _showImagePreview(msg['url']), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: msg['url'], width: 200, fit: BoxFit.cover, placeholder: (c, u) => Container(width: 200, height: 150, decoration: BoxDecoration(color: context.colors.borderLight, borderRadius: BorderRadius.circular(12)), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))), errorWidget: (c, u, e) => Icon(Icons.broken_image)))),
        if (text.isNotEmpty) ...[const SizedBox(height: 8), Text.rich(TextSpan(children: _buildTextSpansWithLinks(text, ctx: context)))]
      ]);
    } else if (type == 'video') {
      final vUrl = (msg['url'] ?? '') as String;
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _showVideoPlayer(vUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 220,
              height: 140,
              color: Colors.black,
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.videocam, color: Colors.white24, size: 56),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white70,
                    child: Icon(Icons.play_arrow, color: Colors.black, size: 32),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (text.isNotEmpty) ...[const SizedBox(height: 8), Text.rich(TextSpan(children: _buildTextSpansWithLinks(text, ctx: context)))]
      ]);
    } else if (type == 'file') {
      final String fName = msg['fileName'] ?? 'ファイル';
      final int? fSize = msg['fileSize'] is int ? msg['fileSize'] : null;
      final String fUrl = msg['url'] ?? '';
      final Timestamp? createdAt = msg['createdAt'] as Timestamp?;
      String expiryText = '';
      if (createdAt != null) {
        final expiry = createdAt.toDate().add(const Duration(days: 365));
        expiryText = '期間: ~${DateFormat('yyyy/MM/dd HH:mm').format(expiry)}';
      }
      final sizeText = _formatFileSize(fSize);

      final fExt = fName.split('.').last.toLowerCase();
      IconData fIcon;
      Color fIconBg;
      if (fExt == 'pdf') { fIcon = Icons.picture_as_pdf; fIconBg = Colors.red.shade400; }
      else if (['doc', 'docx'].contains(fExt)) { fIcon = Icons.description; fIconBg = Colors.blue.shade600; }
      else if (['xls', 'xlsx', 'csv'].contains(fExt)) { fIcon = Icons.table_chart; fIconBg = Colors.green.shade600; }
      else if (['ppt', 'pptx'].contains(fExt)) { fIcon = Icons.slideshow; fIconBg = Colors.orange.shade600; }
      else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(fExt)) { fIcon = Icons.image; fIconBg = Colors.teal; }
      else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(fExt)) { fIcon = Icons.folder_zip; fIconBg = Colors.amber.shade700; }
      else { fIcon = Icons.insert_drive_file; fIconBg = context.colors.textSecondary; }

      content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _showFilePreview(fUrl, fName),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: fIconBg, borderRadius: BorderRadius.circular(6)),
                    child: Icon(fIcon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2),
                        if (expiryText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(expiryText, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                        ],
                        if (sizeText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('サイズ: $sizeText', style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (text.isNotEmpty) ...[const SizedBox(height: 8), Text.rich(TextSpan(children: _buildTextSpansWithLinks(text, ctx: context)))],
            const SizedBox(height: 6),
            Divider(height: 1, color: context.colors.borderMedium),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse(fUrl);
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text('保存', style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else { content = Text.rich(TextSpan(children: _buildTextSpansWithLinks(text, ctx: context))); }

    String readText = '';
    if (isMe && isRead) {
      if (widget.isGroup && totalMembers > 1) { readText = readCount >= totalMembers ? '全員既読' : '既読 $readCount'; }
      else { readText = '既読'; }
    }

    final isDesktop = kIsWeb && MediaQuery.of(context).size.width >= AppBreakpoints.desktop;

    Widget menuButton(bool visible) {
      if (!visible) return const SizedBox(width: 24, height: 24);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTapDown: (details) {
            if (isDesktop) {
              _showPopupMenu(details.globalPosition, msgId, isMe, type, text);
            } else {
              _showActionSheet(msgId, isMe, type, text);
            }
          },
          child: Container(width: 24, height: 24, alignment: Alignment.center, child: Icon(Icons.more_vert, size: 18, color: context.colors.textSecondary)),
        ),
      );
    }

    return _HoverableMessageRow(
      isDesktop: isDesktop,
      hasImage: type == 'image',
      onLongPress: () => _showActionSheet(msgId, isMe, type, text),
      builder: (isHovering) => Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (senderName.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8, bottom: 2), child: Text(senderName, style: TextStyle(fontSize: 11, color: context.colors.textSecondary))),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isMe) ...[
                    if (isDesktop) menuButton(isHovering),
                    if (isDesktop) const SizedBox(width: 4),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [if (readText.isNotEmpty) Text(readText, style: TextStyle(fontSize: 10, color: context.colors.textSecondary)), Text(timeStr, style: TextStyle(fontSize: 10, color: context.colors.textSecondary))]),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: isImageOnly && replyTo == null ? content : Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), decoration: BoxDecoration(color: isMe ? context.colors.chatMyBubble : context.colors.chatOtherBubble, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [if (replyTo != null) _buildReplyQuote(replyTo, isMe), content]))),
                  if (!isMe) ...[
                    const SizedBox(width: 8),
                    Text(timeStr, style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                    if (isDesktop) const SizedBox(width: 4),
                    if (isDesktop) menuButton(isHovering),
                  ],
                ],
              ),
              if (stamps.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8, left: isMe ? 0 : 8, right: isMe ? 8 : 0), child: Wrap(spacing: 8, children: stamps.entries.map((entry) => _buildReactionChip(msgId, entry.key, entry.value, isMe)).toList())),
            ],
          ),
        ),
      ),
    );
  }

  void _showPopupMenu(Offset position, String msgId, bool isMe, String type, String text) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, overlay.size.width - position.dx, overlay.size.height - position.dy),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        const PopupMenuItem(value: 'stamp', height: 36, padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.emoji_emotions_outlined, size: 18), SizedBox(width: 8), Text('スタンプ', style: TextStyle(fontSize: 14))])),
        const PopupMenuItem(value: 'reply', height: 36, padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.reply, size: 18), SizedBox(width: 8), Text('返信', style: TextStyle(fontSize: 14))])),
        if (isMe && type == 'text') const PopupMenuItem(value: 'edit', height: 36, padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('編集', style: TextStyle(fontSize: 14))])),
        if (isMe) const PopupMenuItem(value: 'delete', height: 36, padding: EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('削除', style: TextStyle(fontSize: 14, color: Colors.red))])),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'stamp': _showEmojiPicker(msgId); break;
        case 'reply': _startReply(msgId, type, text); break;
        case 'edit': _showEditDialog(msgId, text); break;
        case 'delete': _deleteMessage(msgId); break;
      }
    });
  }

  void _showActionSheet(String msgId, bool isMe, String type, String text) {
    showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        message: _buildQuickReactionBar(sheetContext, msgId),
        actions: [
          if (type == 'text' && text.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('コピーしました'),
                      duration: Duration(seconds: 1)),
                );
              },
              child: const Text('コピー'),
            ),
          if (type == 'text' && text.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showPartialCopyDialog(text);
              },
              child: const Text('部分コピー'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              _startReply(msgId, type, text);
            },
            child: const Text('返信'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              _showEmojiPicker(msgId);
            },
            child: const Text('他のスタンプ…'),
          ),
          if (isMe && type == 'text')
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _showEditDialog(msgId, text);
              },
              child: const Text('編集'),
            ),
          if (isMe)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                _deleteMessage(msgId);
              },
              child: const Text('削除'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('キャンセル'),
        ),
      ),
    );
  }

  // クイックスタンプバー: よく使うスタンプをワンタップで送信
  Widget _buildQuickReactionBar(BuildContext sheetContext, String msgId) {
    const quickEmojis = ['👍', '❤️', '😄', '🎉', '🙏', '🆗'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in quickEmojis)
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleReaction(msgId, e);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Text(e, style: TextStyle(fontSize: 26)),
              ),
            ),
        ],
      ),
    );
  }

  // 部分コピー: SelectableText で範囲選択させてネイティブのコピー操作を使わせる
  void _showPartialCopyDialog(String text) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('部分コピー', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'NotoSansJP',
                fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif'],
              ),
              contextMenuBuilder: (context, editableTextState) {
                return AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionChip(String msgId, String emoji, dynamic users, bool isMe) {
    final List<String> userList = users is List ? List<String>.from(users) : [];
    final int count = users is List ? users.length : (users is int ? users : 1);
    final bool alreadyReacted = userList.contains(currentUser?.uid);
    return GestureDetector(
      onTap: () => _toggleReaction(msgId, emoji),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: alreadyReacted ? AppColors.primary.withOpacity(0.2) : (isMe ? AppColors.primary.withOpacity(0.1) : context.colors.tagBg), borderRadius: BorderRadius.circular(16), border: Border.all(color: alreadyReacted ? AppColors.primary : context.colors.borderMedium)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji, style: TextStyle(fontSize: 14)), if (count > 1) ...[SizedBox(width: 4), Text('$count', style: TextStyle(fontSize: 12, color: context.colors.textSecondary))]])));
  }

  Future<void> _pickAndUploadImage() async {
    _dismissKeyboard();
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _isUploading = true);
    try {
      final Uint8List fileBytes = await image.readAsBytes();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final ref = FirebaseStorage.instance.ref().child('chat_uploads/${widget.roomId}/$fileName');
      await ref.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await _sendMessage(type: 'image', url: url, text: _textController.text);
      _textController.clear();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e'))); }
    finally { setState(() => _isUploading = false); }
  }

  Future<void> _pickAndUploadVideo() async {
    _dismissKeyboard();
    final picker = ImagePicker();
    final XFile? video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (video == null) return;
    setState(() => _isUploading = true);
    try {
      final Uint8List bytes = await video.readAsBytes();
      // 50MB 制限
      if (bytes.length > 50 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('動画サイズが大きすぎます (50MBまで)')),
          );
        }
        return;
      }
      final String ext = video.name.split('.').last.toLowerCase();
      final String contentType =
          ext == 'mov' ? 'video/quicktime' : 'video/mp4';
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${video.name}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_uploads/${widget.roomId}/$fileName');
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      await _sendMessage(
        type: 'video',
        url: url,
        fileName: video.name,
        text: _textController.text,
        fileSize: bytes.length,
      );
      _textController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('動画アップロード失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndUploadFile() async {
    _dismissKeyboard();
    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null) return;
    setState(() => _isUploading = true);
    try {
      final PlatformFile file = result.files.first;
      final Uint8List? fileBytes = file.bytes;
      if (fileBytes == null) throw Exception('データ取得失敗');
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('chat_uploads/${widget.roomId}/$fileName');
      await ref.putData(fileBytes);
      final url = await ref.getDownloadURL();
      await _sendMessage(type: 'file', url: url, fileName: file.name, text: _textController.text, fileSize: file.size);
      _textController.clear();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e'))); }
    finally { setState(() => _isUploading = false); }
  }

  Future<void> _sendMessage({String type = 'text', String? url, String? fileName, String? text, int? fileSize, String? thumbnailUrl, int? durationMs}) async {
    final msgText = text ?? _textController.text;
    if (msgText.trim().isEmpty && type == 'text') return;
    _dismissKeyboard();
    if (type == 'text') _textController.clear();
    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
    final data = <String, dynamic>{
      'senderId': currentUser!.uid,
      'text': msgText,
      'type': type,
      'url': url,
      'fileName': fileName,
      'fileSize': fileSize,
      'stamps': {},
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': [currentUser!.uid],
    };
    if (thumbnailUrl != null) data['thumbnailUrl'] = thumbnailUrl;
    if (durationMs != null) data['durationMs'] = durationMs;
    if (_replyTo != null) data['replyTo'] = _replyTo;
    await roomRef.collection('messages').add(data);
    String lastMsg = msgText;
    if (type == 'image') lastMsg = '画像を送信しました';
    if (type == 'file') lastMsg = 'ファイルを送信しました';
    if (type == 'video') lastMsg = '動画を送信しました';
    await roomRef.update({'lastMessage': lastMsg, 'lastMessageTime': FieldValue.serverTimestamp()});
    // 返信状態をクリア
    if (_replyTo != null) setState(() => _replyTo = null);
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    final msgRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(msgId);
    final uid = currentUser!.uid;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(msgRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final stamps = Map<String, dynamic>.from(data['stamps'] ?? {});
      List<String> userList = [];
      if (stamps[emoji] is List) userList = List<String>.from(stamps[emoji]);
      else if (stamps[emoji] is int) userList = [];
      if (userList.contains(uid)) { userList.remove(uid); if (userList.isEmpty) stamps.remove(emoji); else stamps[emoji] = userList; }
      else { userList.add(uid); stamps[emoji] = userList; }
      transaction.update(msgRef, {'stamps': stamps});
    });
  }

  void _showEmojiPicker(String msgId) {
    final emojis = ['👍', '❤️', '😄', '🎉', '🙏', '🆗', '😂', '😢', '✨', '🤔'];
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('スタンプを選択'),
      content: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: emojis.map((e) => GestureDetector(onTap: () { _toggleReaction(msgId, e); Navigator.of(dialogContext).pop(); }, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Text(e, style: TextStyle(fontSize: 28))))).toList()),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('キャンセル'))],
    ));
  }

  void _deleteMessage(String msgId) {
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('メッセージを削除'), content: const Text('このメッセージを削除しますか？'),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('キャンセル')), TextButton(onPressed: () async {
        final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
        await roomRef.collection('messages').doc(msgId).delete();
        final latest = await roomRef.collection('messages').orderBy('createdAt', descending: true).limit(1).get();
        if (latest.docs.isNotEmpty) {
          final d = latest.docs.first.data();
          String lastMsg = d['text'] ?? '';
          if (d['type'] == 'image') lastMsg = '画像を送信しました';
          if (d['type'] == 'file') lastMsg = 'ファイルを送信しました';
          if (d['type'] == 'video') lastMsg = '動画を送信しました';
          await roomRef.update({'lastMessage': lastMsg, 'lastMessageTime': d['createdAt']});
        } else {
          await roomRef.update({'lastMessage': '', 'lastMessageTime': FieldValue.serverTimestamp()});
        }
        Navigator.of(dialogContext).pop();
      }, child: const Text('削除', style: TextStyle(color: Colors.red)))],
    ));
  }

  void _showEditDialog(String msgId, String currentText) {
    final ctrl = TextEditingController(text: currentText);
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('メッセージを編集'),
      content: TextField(controller: ctrl, maxLines: 3, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'メッセージを入力')),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('キャンセル')), ElevatedButton(onPressed: () async { await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(msgId).update({'text': ctrl.text}); Navigator.of(dialogContext).pop(); }, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white), child: const Text('保存'))],
    ));
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      barrierColor: context.colors.textPrimary,
      builder: (_) => Stack(
        children: [
          // 画像表示エリア
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (c, u) => Center(child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (c, u, e) => const Icon(Icons.broken_image, color: Colors.white, size: 48),
              ),
            ),
          ),
          // 上部バー（閉じる・ダウンロード）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 28),
                      tooltip: 'ダウンロード',
                      onPressed: () async {
                        try {
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        } catch (e) {
                          debugPrint('Download error: $e');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showVideoPlayer(String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => VideoPlayerDialog(url: url),
    );
  }

  void _showFilePreview(String url, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isPdf = ext == 'pdf';

    if (!isImage && !isPdf) {
      launchUrl(Uri.parse(url));
      return;
    }

    if (isImage) {
      _showImagePreview(url);
      return;
    }

    // PDFはブラウザで開く（Web/Android共通）
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ==========================================
// 4. ホバー対応メッセージ行ラッパー
// ==========================================

class _HoverableMessageRow extends StatefulWidget {
  final bool isDesktop;
  final VoidCallback onLongPress;
  final Widget Function(bool isHovering) builder;
  final bool hasImage;

  const _HoverableMessageRow({
    required this.isDesktop,
    required this.onLongPress,
    required this.builder,
    this.hasImage = false,
  });

  @override
  State<_HoverableMessageRow> createState() => _HoverableMessageRowState();
}

class _HoverableMessageRowState extends State<_HoverableMessageRow> with AutomaticKeepAliveClientMixin {
  bool _isHovering = false;

  @override
  bool get wantKeepAlive => widget.hasImage;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // スマホの場合は長押しでメニュー
    if (!widget.isDesktop) {
      return GestureDetector(
        onLongPress: widget.onLongPress,
        child: widget.builder(false),
      );
    }

    // PCの場合はホバーで「⋮」表示（行全体がホバー範囲）
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: widget.builder(_isHovering),
    );
  }
}

// ==========================================
// 動画再生ダイアログ
// ==========================================
class VideoPlayerDialog extends StatefulWidget {
  final String url;
  const VideoPlayerDialog({super.key, required this.url});

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initialized = true;
      });
      c.play();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Center(
            child: _error != null
                ? Text('再生できません: $_error',
                    style: const TextStyle(color: Colors.white))
                : !_initialized || _controller == null
                    ? CircularProgressIndicator(color: context.colors.cardBg)
                    : AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_controller!.value.isPlaying) {
                                    _controller!.pause();
                                  } else {
                                    _controller!.play();
                                  }
                                });
                              },
                              child: VideoPlayer(_controller!),
                            ),
                            // コントロール
                            Container(
                              color: Colors.black45,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        if (_controller!.value.isPlaying) {
                                          _controller!.pause();
                                        } else {
                                          _controller!.play();
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      _controller!.value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: context.colors.cardBg,
                                    ),
                                  ),
                                  Expanded(
                                    child: ValueListenableBuilder<
                                        VideoPlayerValue>(
                                      valueListenable: _controller!,
                                      builder: (_, value, __) {
                                        final total = value.duration;
                                        final pos = value.position;
                                        return Row(
                                          children: [
                                            Text(
                                              _fmtDuration(pos),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12),
                                            ),
                                            Expanded(
                                              child: Slider(
                                                value: pos.inMilliseconds
                                                    .toDouble()
                                                    .clamp(
                                                        0,
                                                        total.inMilliseconds
                                                            .toDouble()),
                                                max: total.inMilliseconds
                                                    .toDouble()
                                                    .clamp(1, double.infinity),
                                                onChanged: (v) {
                                                  _controller!.seekTo(Duration(
                                                      milliseconds:
                                                          v.toInt()));
                                                },
                                                activeColor: Colors.white,
                                                inactiveColor: Colors.white24,
                                              ),
                                            ),
                                            Text(
                                              _fmtDuration(total),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}