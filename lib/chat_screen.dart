import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart'; // テーマ定義

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
  
  Stream<QuerySnapshot>? _roomsStream; // ★修正: nullableに変更
  String _myDisplayName = '';

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    if (currentUser != null) {
      debugPrint('=== ChatListScreen: Initializing stream for user: ${currentUser!.uid}');
      try {
        _roomsStream = FirebaseFirestore.instance
            .collection('chat_rooms')
            .where('members', arrayContains: currentUser!.uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots();
        debugPrint('=== ChatListScreen: Stream created successfully');
      } catch (e) {
        debugPrint('=== ChatListScreen: Error creating stream: $e');
      }
      
      _fetchMyName();
    } else {
      debugPrint('=== ChatListScreen: currentUser is null');
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
    
    // ★修正: ストリームがnullの場合はローディング表示
    if (_roomsStream == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 800;
        if (isWideScreen) {
          return _buildWideLayout();
        } else {
          return _buildNarrowLayout();
        }
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
                ? const Center(child: Text('チャットを選択してください', style: TextStyle(color: Colors.grey)))
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
          // ★修正: SafeAreaを追加
          SafeArea(
            bottom: false,
            child: _buildCommonHeader('チャット一覧', isLeftPane: true),
          ),
          Expanded(child: _buildFirestoreRoomList(isWide: false)),
        ],
      ),
    );
  }

  Widget _buildCommonHeader(String title, {bool isLeftPane = false, List<Widget>? actions, bool showBackButton = false}) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 中央のタイトル
          Center(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 左側：戻るボタン
          if (showBackButton)
            Positioned(
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          // 右側：アクションボタン
          Positioned(
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actions != null) ...actions,
                if (isLeftPane)
                  IconButton(
                    icon: const Icon(Icons.add_comment_rounded, color: AppColors.primary, size: 28),
                    tooltip: '新規チャット',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => NewChatDialog(
                        myUid: currentUser!.uid,
                        myName: _myDisplayName, 
                        onStartChat: (roomId, name, isGroup, memberNames) {
                          if (MediaQuery.of(context).size.width >= 800) {
                            setState(() => _selectedRoomId = roomId);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: PreferredSize(
                                    preferredSize: const Size.fromHeight(60),
                                    child: SafeArea(
                                      child: _buildCommonHeader(name, showBackButton: true, actions: [
                                        _buildChatMenu(roomId, isGroup, memberNames, false),
                                      ]),
                                    ),
                                  ),
                                  body: ChatDetailView(
                                    roomId: roomId,
                                    roomName: name,
                                    isGroup: isGroup,
                                    memberNames: memberNames,
                                    showAppBar: false,
                                  ),
                                ),
                              ),
                            );
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

        String roomName = data['groupName'] ?? '';
        if (roomName.isEmpty) {
          final names = Map<String, dynamic>.from(data['names'] ?? {});
          final otherNames = names.entries
              .where((e) => e.key != currentUser!.uid)
              .map((e) => e.value)
              .toList();
          if (otherNames.isNotEmpty) {
            roomName = otherNames.join(', ');
          }
        }
        if (roomName.isEmpty) roomName = '名称未設定';

        final isGroup = (data['members'] as List).length > 2 || (data['groupName'] != null && data['groupName'].isNotEmpty);
        final memberNames = Map<String, dynamic>.from(data['names'] ?? {});

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: _buildCommonHeader(roomName, actions: [
              _buildChatMenu(_selectedRoomId!, isGroup, memberNames, true),
            ]),
          ),
          body: ChatDetailView(
            roomId: _selectedRoomId!,
            roomName: roomName,
            isGroup: isGroup,
            memberNames: memberNames,
            showAppBar: false,
          ),
        );
      },
    );
  }

  Widget _buildChatMenu(String roomId, bool isGroup, Map<String, dynamic> memberNames, bool isWide) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
      onSelected: (value) {
        if (value == 'delete') _deleteChat(roomId, isWide);
        if (value == 'members') _showMemberList(memberNames);
      },
      itemBuilder: (BuildContext context) {
        return [
          const PopupMenuItem(value: 'members', child: Text('メンバー一覧')),
          const PopupMenuItem(value: 'delete', child: Text('チャットを削除', style: TextStyle(color: Colors.red))),
        ];
      },
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

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDate = DateTime(date.year, date.month, date.day);
    return aDate == today ? DateFormat('HH:mm').format(date) : DateFormat('MM/dd').format(date);
  }

  Widget _buildFirestoreRoomList({required bool isWide}) {
    // ★修正: nullチェックを追加
    if (_roomsStream == null) {
      debugPrint('=== _buildFirestoreRoomList: _roomsStream is null');
      return const Center(child: Text('ストリームが初期化されていません'));
    }
    
    debugPrint('=== _buildFirestoreRoomList: Building StreamBuilder');
    
    return StreamBuilder<QuerySnapshot>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        debugPrint('=== StreamBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');
        
        if (snapshot.hasError) {
          debugPrint('=== Firestore error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('エラーが発生しました', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${snapshot.error}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('=== StreamBuilder: waiting...');
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          debugPrint('=== StreamBuilder: no data or empty');
          return const Center(child: Text('チャット履歴はありません'));
        }

        debugPrint('=== StreamBuilder: Got ${snapshot.data!.docs.length} docs');
        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final roomDoc = docs[index];
            return _RoomListTile(
              roomDoc: roomDoc,
              myUid: currentUser!.uid,
              isSelected: isWide && roomDoc.id == _selectedRoomId,
              onTap: (roomId, roomName, isGroup, memberNames) {
                if (isWide) {
                  setState(() => _selectedRoomId = roomId);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: PreferredSize(
                          preferredSize: const Size.fromHeight(60),
                          child: SafeArea(child: _buildCommonHeader(roomName, showBackButton: true, actions: [
                            _buildChatMenu(roomId, isGroup, memberNames, false)
                          ])),
                        ),
                        body: ChatDetailView(roomId: roomId, roomName: roomName, isGroup: isGroup, memberNames: memberNames, showAppBar: false),
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

// リストアイテム
class _RoomListTile extends StatelessWidget {
  final DocumentSnapshot roomDoc;
  final String myUid;
  final bool isSelected;
  final Function(String, String, bool, Map<String, dynamic>) onTap;

  const _RoomListTile({
    required this.roomDoc,
    required this.myUid,
    required this.isSelected,
    required this.onTap,
  });

  Future<Map<String, dynamic>> _fetchPeerInfo(String peerId) async {
    var snap = await FirebaseFirestore.instance.collection('staffs').where('uid', isEqualTo: peerId).limit(1).get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.data();
    }
    snap = await FirebaseFirestore.instance.collection('families').where('uid', isEqualTo: peerId).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final d = snap.docs.first.data();
      final lastName = d['lastName'] ?? '';
      final firstName = d['firstName'] ?? ''; 
      final fullName = '$lastName $firstName'.trim();
      return {
        'name': fullName.isNotEmpty ? fullName : '保護者',
        'photoUrl': null,
      };
    }
    return {'name': '不明', 'photoUrl': null};
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDate = DateTime(date.year, date.month, date.day);
    return aDate == today ? DateFormat('HH:mm').format(date) : DateFormat('MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final room = roomDoc.data() as Map<String, dynamic>;
    final roomId = roomDoc.id;
    final isGroup = (room['members'] as List).length > 2 || (room['groupName'] != null && room['groupName'].isNotEmpty);
    final memberNames = Map<String, dynamic>.from(room['names'] ?? {});

    String timeStr = '';
    if (room['lastMessageTime'] != null) {
      final ts = room['lastMessageTime'] as Timestamp;
      timeStr = _formatTime(ts.toDate());
    }

    if (isGroup) {
      final groupName = room['groupName'] ?? 'グループ';
      final photoUrl = room['photoUrl'] as String?;

      return ListTile(
        selected: isSelected,
        selectedTileColor: Colors.orange.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: (photoUrl == null || photoUrl.isEmpty)
              ? Text(groupName.isNotEmpty ? groupName[0] : 'G', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
              : null,
        ),
        title: Text(groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(room['lastMessage'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        onTap: () => onTap(roomId, groupName, true, memberNames),
      );
    }

    final peerId = (room['members'] as List).firstWhere((id) => id != myUid, orElse: () => '');
    
    if (peerId.isEmpty) {
      return const SizedBox();
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchPeerInfo(peerId),
      builder: (context, snapshot) {
        final peerData = snapshot.data;
        final name = peerData?['name'] ?? memberNames[peerId] ?? '読み込み中...';
        final photoUrl = peerData?['photoUrl'] as String?;
        
        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.orange.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: Colors.orange.shade100,
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0] : '?', 
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)
                  )
                : null,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          subtitle: Text(room['lastMessage'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          onTap: () => onTap(roomId, name, false, memberNames),
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
      if (!_tabController!.indexIsChanging) {
        setState(() {
          _selectedUids.clear();
          _isGroupMode = false;
          _groupImageBytes = null;
        });
      }
    });
    _fetchUsers();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    try {
      final List<Map<String, dynamic>> tempFamilies = [];
      final List<Map<String, dynamic>> tempStaff = [];

      final familySnap = await FirebaseFirestore.instance.collection('families').get();
      for (var doc in familySnap.docs) {
        final d = doc.data();
        if (d['uid'] == widget.myUid) continue;
        final name = '${d['lastName'] ?? ''} ${d['firstName'] ?? ''}'.trim();
        final kana = '${d['lastNameKana'] ?? ''} ${d['firstNameKana'] ?? ''}'.trim();
        tempFamilies.add({
          'uid': d['uid'] ?? doc.id,
          'name': name.isEmpty ? '名称未設定' : name,
          'kana': kana.isEmpty ? name : kana,
          'photoUrl': null,
        });
      }

      final staffSnap = await FirebaseFirestore.instance.collection('staffs').get();
      for (var doc in staffSnap.docs) {
        final d = doc.data();
        final String uid = d['uid'] ?? doc.id;
        if (uid == widget.myUid) continue;
        String name = d['name'] ?? '';
        if (name.isEmpty) {
          name = '${d['lastName'] ?? ''} ${d['firstName'] ?? ''}'.trim();
        }
        if (name.isEmpty) name = 'スタッフ (名称未設定)';
        String kana = d['furigana'] ?? '';
        if (kana.isEmpty) kana = name; 
        tempStaff.add({
          'uid': uid,
          'name': name,
          'kana': kana,
          'photoUrl': d['photoUrl'],
        });
      }

      tempFamilies.sort((a, b) => a['kana'].compareTo(b['kana']));
      tempStaff.sort((a, b) => a['kana'].compareTo(b['kana']));

      setState(() {
        _families = tempFamilies;
        _staff = tempStaff;
        _filteredFamilies = tempFamilies;
        _filteredStaff = tempStaff;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredFamilies = _families;
        _filteredStaff = _staff;
      } else {
        _filteredFamilies = _families.where((u) => u['name'].contains(query) || u['kana'].contains(query)).toList();
        _filteredStaff = _staff.where((u) => u['name'].contains(query) || u['kana'].contains(query)).toList();
      }
    });
  }

  // ★修正: 「行」を削除して「あ」「か」のみにする
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
    for (var user in users) {
      final header = _getIndexHeader(user['kana']);
      if (!grouped.containsKey(header)) grouped[header] = [];
      grouped[header]!.add(user);
    }

    final headers = grouped.keys.toList()..sort();

    // ★修正: ListViewに戻し、ヘッダー背景を白に統一
    return ListView.builder(
      itemCount: headers.length,
      itemBuilder: (context, index) {
        final header = headers[index];
        final groupUsers = grouped[header]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Colors.white, // ★背景白
              child: Text(
                header,
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF2F2F7)),
            ...groupUsers.map((user) {
              final uid = user['uid'];
              final isSelected = _selectedUids.contains(uid);
              final photoUrl = user['photoUrl'];
              final name = user['name'];

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                leading: CircleAvatar(
                  backgroundColor: isStaffTab ? Colors.blue.shade100 : Colors.orange.shade100,
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(color: isStaffTab ? Colors.blue : Colors.orange, fontWeight: FontWeight.bold))
                      : null,
                ),
                title: Text(name, style: const TextStyle(fontSize: 16)),
                trailing: isStaffTab && _isGroupMode
                    ? Checkbox(value: isSelected, activeColor: AppColors.primary, onChanged: (val) => _toggleSelection(uid))
                    : null,
                onTap: () {
                  if (isStaffTab && _isGroupMode) _toggleSelection(uid);
                  else _startSingleChat(uid, user['name']);
                },
              );
            }),
          ],
        );
      },
    );
  }

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedUids.contains(uid)) _selectedUids.remove(uid);
      else _selectedUids.add(uid);
    });
  }

  Future<void> _pickGroupImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _groupImageBytes = bytes;
      });
    }
  }

  void _startSingleChat(String targetUid, String targetName) async {
    final memberIds = [widget.myUid, targetUid]..sort();
    final roomId = memberIds.join('_');
    final Map<String, String> namesMap = {
      widget.myUid: widget.myName.isEmpty ? '担当者' : widget.myName,
      targetUid: targetName
    };
    await _createRoomIfNeeded(roomId, memberIds, namesMap, null, null);
    if (mounted) {
      Navigator.pop(context);
      widget.onStartChat(roomId, targetName, false, namesMap);
    }
  }

  void _startGroupChat() async {
    if (_selectedUids.isEmpty) return;
    final roomId = FirebaseFirestore.instance.collection('chat_rooms').doc().id;
    final memberIds = [widget.myUid, ..._selectedUids]..sort();
    final Map<String, String> namesMap = {
      widget.myUid: widget.myName.isEmpty ? '担当者' : widget.myName
    };
    for (var uid in _selectedUids) {
      final user = _staff.firstWhere((u) => u['uid'] == uid, orElse: () => {'name': 'Unknown'});
      namesMap[uid] = user['name'];
    }
    String groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      groupName = namesMap.values.where((n) => n != widget.myName).take(3).join(', ');
      if (namesMap.length > 4) groupName += '...';
    }
    
    String? photoUrl;
    if (_groupImageBytes != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child('group_photos/$roomId.jpg');
        await ref.putData(_groupImageBytes!, SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Error uploading group image: $e');
      }
    }

    await _createRoomIfNeeded(roomId, memberIds, namesMap, groupName, photoUrl);
    if (mounted) {
      Navigator.pop(context);
      widget.onStartChat(roomId, groupName, true, namesMap);
    }
  }

  Future<void> _createRoomIfNeeded(String roomId, List<String> members, Map<String, String> names, String? groupName, String? photoUrl) async {
    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId);
    final doc = await roomRef.get();
    
    if (!doc.exists) {
      await roomRef.set({
        'roomId': roomId, 'members': members, 'names': names, 'groupName': groupName,
        'photoUrl': photoUrl,
        'lastMessage': groupName != null ? 'グループ作成' : 'チャット開始',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await roomRef.update({'names': names});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) return const SizedBox.shrink();
    
    // ★修正: スマホ対応のダイアログサイズ
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 500.0;
    final dialogHeight = screenHeight < 700 ? screenHeight * 0.85 : 650.0;
    
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      // ★修正: ダイアログ全体の背景を白に
      backgroundColor: Colors.white, 
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: dialogWidth, 
        height: dialogHeight,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('新規チャット', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(hintText: '名前で検索...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true, filled: false),
                    onChanged: _onSearch,
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppColors.primary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [Tab(text: '保護者'), Tab(text: 'スタッフ')],
                  ),
                  AnimatedBuilder(
                    animation: _tabController!,
                    builder: (context, _) {
                      if (_tabController!.index == 1) {
                        return Column(
                          children: [
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text('グループ作成', style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 8),
                                Switch(value: _isGroupMode, activeColor: AppColors.primary, onChanged: (val) => setState(() => _isGroupMode = val)),
                              ],
                            ),
                            if (_isGroupMode) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: _pickGroupImage,
                                    child: CircleAvatar(
                                      radius: 24,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: _groupImageBytes != null ? MemoryImage(_groupImageBytes!) : null,
                                      child: _groupImageBytes == null ? const Icon(Icons.camera_alt, color: Colors.grey) : null,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(controller: _groupNameController, decoration: const InputDecoration(labelText: 'グループ名（任意）', border: OutlineInputBorder(), isDense: true)),
                                  ),
                                ],
                              ),
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
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabController, children: [
                _buildSectionedList(_filteredFamilies, false), 
                _buildSectionedList(_filteredStaff, true)
              ]),
            ),
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

  const ChatDetailView({super.key, required this.roomId, required this.roomName, required this.isGroup, required this.memberNames, this.showAppBar = true});

  @override
  State<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<ChatDetailView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;
  String? _hoveringMessageId;
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showAppBar) ...[
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1))),
            child: Row(
              children: [
                Expanded(child: Text(widget.roomName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'delete') _deleteChat();
                    if (value == 'members') _showMembers();
                  },
                  itemBuilder: (context) => [
                    if (widget.isGroup) const PopupMenuItem(value: 'members', child: Text('メンバー一覧')),
                    const PopupMenuItem(value: 'delete', child: Text('チャットを削除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
          ),
        ],
        Expanded(
          child: Container(
            color: const Color(0xFFF2F2F7),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').orderBy('createdAt', descending: false).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                });

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final senderId = data['senderId'];
                  final readBy = List<String>.from(data['readBy'] ?? []);
                  
                  if (currentUser != null && senderId != currentUser!.uid && !readBy.contains(currentUser!.uid)) {
                    FirebaseFirestore.instance
                        .collection('chat_rooms')
                        .doc(widget.roomId)
                        .collection('messages')
                        .doc(doc.id)
                        .update({
                      'readBy': FieldValue.arrayUnion([currentUser!.uid])
                    });
                  }
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final msg = docs[index].data() as Map<String, dynamic>;
                    final msgId = docs[index].id;
                    return _buildMessageItem(index, msg, msgId);
                  },
                );
              },
            ),
          ),
        ),
        if (_isUploading) const LinearProgressIndicator(),
        _buildInputArea(),
      ],
    );
  }

  void _deleteChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('チャットを削除'),
        content: const Text('このチャットルームを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).delete();
          }, child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _showMembers() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メンバー一覧'),
        content: SizedBox(width: 300, height: 300, child: ListView(children: widget.memberNames.entries.map((e) {
          final name = e.key == currentUser!.uid ? '${e.value} (自分)' : e.value;
          return ListTile(leading: const Icon(Icons.person), title: Text(name));
        }).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: _isUploading ? null : _pickAndUploadFile),
            IconButton(icon: const Icon(Icons.image, color: Colors.grey), onPressed: _isUploading ? null : _pickAndUploadImage),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null, minLines: 1,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(hintText: 'メッセージを入力', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(onPressed: _sendMessage, mini: true, backgroundColor: AppColors.primary, child: const Icon(Icons.send, color: Colors.white, size: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(int index, Map<String, dynamic> msg, String msgId) {
    final isMe = msg['senderId'] == currentUser?.uid;
    final String text = msg['text'] ?? '';
    final String type = msg['type'] ?? 'text'; 
    final stamps = Map<String, dynamic>.from(msg['stamps'] ?? {});
    final isHovering = _hoveringMessageId == msgId;
    final readBy = List<String>.from(msg['readBy'] ?? []);
    final isRead = isMe && readBy.any((uid) => uid != currentUser!.uid);

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }
    
    String senderName = '';
    if (widget.isGroup && !isMe) {
      senderName = widget.memberNames[msg['senderId']] ?? '不明';
    }

    Widget content;
    if (type == 'image') {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(onTap: () => _showImagePreview(msg['url']), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(msg['url'], width: 200, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.broken_image)))),
        if (text.isNotEmpty) ...[const SizedBox(height: 4), SelectableText(text, style: const TextStyle(fontSize: 15))]
      ]);
    } else if (type == 'file') {
      content = InkWell(onTap: () async { final Uri url = Uri.parse(msg['url']); if (await canLaunchUrl(url)) await launchUrl(url); }, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description, color: AppColors.primary), const SizedBox(width: 8), Flexible(child: Text(msg['fileName'] ?? 'ファイル', style: const TextStyle(fontSize: 14, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis))])));
    } else {
      content = SelectableText(text, style: const TextStyle(fontSize: 15));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveringMessageId = msgId),
      onExit: (_) => setState(() => _hoveringMessageId = null),
      child: GestureDetector(
        onLongPress: () => setState(() => _hoveringMessageId = msgId),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.only(top: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (senderName.isNotEmpty)
                       Padding(
                         padding: const EdgeInsets.only(left: 8, bottom: 2),
                         child: Text(senderName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                       ),

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isMe) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isRead) const Text('既読', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ), 
                          const SizedBox(width: 8)
                        ],
                        Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: isMe ? AppColors.primary.withOpacity(0.2) : Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]), child: content)),
                        if (!isMe) ...[const SizedBox(width: 8), Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey))],
                      ],
                    ),
                    if (stamps.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8, left: isMe ? 0 : 8, right: isMe ? 8 : 0), child: Wrap(spacing: 8, children: stamps.entries.map((entry) => _buildReactionChip(msgId, entry.key, entry.value, isMe)).toList())),
                  ],
                ),
                
                if (isHovering)
                  Positioned(
                    top: -16,
                    right: isMe ? 0 : null,
                    left: isMe ? null : 0,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)], border: Border.all(color: Colors.grey.shade200)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHoverIcon(Icons.emoji_emotions_outlined, () => _showEmojiPickerForReaction(context, msgId)),
                          const SizedBox(width: 8),
                          _buildHoverIcon(Icons.reply, () {
                            String preview = type == 'image' ? '📷 画像' : (type == 'file' ? '📎 ${msg['fileName']}' : text);
                            _textController.text = '> $preview\n';
                            setState(() => _hoveringMessageId = null);
                          }),
                          if (isMe && type == 'text') ...[const SizedBox(width: 8), _buildHoverIcon(Icons.edit, () { _showEditDialog(msgId, text); setState(() => _hoveringMessageId = null); })],
                          if (isMe) ...[const SizedBox(width: 8), _buildHoverIcon(Icons.delete, () { _deleteMessage(msgId); setState(() => _hoveringMessageId = null); }, color: Colors.red)],
                          if (!kIsWeb) ...[const SizedBox(width: 8), _buildHoverIcon(Icons.close, () => setState(() => _hoveringMessageId = null))],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoverIcon(IconData icon, VoidCallback onTap, {Color color = Colors.grey}) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(icon, size: 20, color: color)));
  }

  Widget _buildReactionChip(String msgId, String emoji, dynamic count, bool isMe) {
    final int c = count is int ? count : 1;
    return GestureDetector(onTap: () => _toggleReaction(msgId, emoji), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: isMe ? AppColors.primary.withOpacity(0.1) : Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(emoji, style: const TextStyle(fontSize: 14)), if (c > 1) ...[const SizedBox(width: 4), Text('$c', style: const TextStyle(fontSize: 12, color: Colors.grey))]])));
  }

  Future<void> _pickAndUploadImage() async {
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
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e'))); } finally { setState(() => _isUploading = false); }
  }

  Future<void> _pickAndUploadFile() async {
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
      await _sendMessage(type: 'file', url: url, fileName: file.name, text: _textController.text);
      _textController.clear();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e'))); } finally { setState(() => _isUploading = false); }
  }

  Future<void> _sendMessage({String type = 'text', String? url, String? fileName, String? text}) async {
    final msgText = text ?? _textController.text;
    if (msgText.trim().isEmpty && type == 'text') return;
    if (type == 'text') _textController.clear();
    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
    await roomRef.collection('messages').add({
      'senderId': currentUser!.uid, 'text': msgText, 'type': type, 'url': url, 'fileName': fileName, 'stamps': {}, 'createdAt': FieldValue.serverTimestamp(),
      'readBy': [currentUser!.uid],
    });
    String lastMsg = msgText;
    if (type == 'image') lastMsg = '画像を送信しました';
    if (type == 'file') lastMsg = 'ファイルを送信しました';
    await roomRef.update({'lastMessage': lastMsg, 'lastMessageTime': FieldValue.serverTimestamp()});
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    final msgRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(msgId);
    FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(msgRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final stamps = Map<String, dynamic>.from(data['stamps'] ?? {});
      if (stamps.containsKey(emoji)) stamps[emoji] = (stamps[emoji] as int) + 1; else stamps[emoji] = 1;
      transaction.update(msgRef, {'stamps': stamps});
    });
  }

  void _showEmojiPickerForReaction(BuildContext buttonContext, String msgId) {
    final emojis = ['👍', '❤️', '😄', '🎉', '🙏', '🆗', '😂', '😢', '✨', '🤔'];
    showDialog(context: context, builder: (_) => SimpleDialog(title: const Text('リアクション'), children: [Wrap(alignment: WrapAlignment.center, children: emojis.map((e) => IconButton(icon: Text(e, style: const TextStyle(fontSize: 24)), onPressed: () { _toggleReaction(msgId, e); Navigator.pop(context); setState(() => _hoveringMessageId = null); })).toList())]));
  }

  void _deleteMessage(String msgId) {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('削除'), content: const Text('このメッセージを削除しますか？'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')), TextButton(onPressed: () async { await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(msgId).delete(); Navigator.pop(context); setState(() => _hoveringMessageId = null); }, child: const Text('削除', style: TextStyle(color: Colors.red)))]));
  }

  void _showEditDialog(String msgId, String currentText) {
    final ctrl = TextEditingController(text: currentText);
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('編集'), content: TextField(controller: ctrl, maxLines: 3), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')), ElevatedButton(onPressed: () async { await FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId).collection('messages').doc(msgId).update({'text': ctrl.text}); Navigator.pop(context); }, child: const Text('保存'))]));
  }

  void _showImagePreview(String url) {
    showDialog(context: context, builder: (_) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Image.network(url)), TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])));
  }
}