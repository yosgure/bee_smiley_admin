import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) return const Center(child: Text('ログインが必要です'));

    return LayoutBuilder(
      builder: (context, constraints) {
        // 横幅が800px以上なら2ペイン表示（PC/タブレット用）
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
                _buildListHeader(),
                const Divider(height: 1),
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
          _buildListHeader(),
          const Divider(height: 1),
          Expanded(child: _buildFirestoreRoomList(isWide: false)),
        ],
      ),
    );
  }

  Widget _buildChatDetailWrapper() {
    // 選択中のルーム情報をリアルタイム取得して詳細画面を表示
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_selectedRoomId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const Center(child: Text('チャットが存在しません'));

        // ルーム名の特定（グループ名 または 相手の名前）
        String roomName = data['groupName'] ?? '';
        if (roomName.isEmpty) {
          final names = Map<String, dynamic>.from(data['names'] ?? {});
          names.forEach((uid, name) {
            if (uid != currentUser!.uid) roomName = name;
          });
        }
        if (roomName.isEmpty) roomName = '名称未設定';

        return ChatDetailView(
          roomId: _selectedRoomId!,
          roomName: roomName,
          showAppBar: true,
        );
      },
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('チャット一覧', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.edit_square, color: Colors.black54),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => NewChatDialog(
                  myUid: currentUser!.uid,
                  onStartChat: (roomId, name) {
                    if (MediaQuery.of(context).size.width >= 800) {
                      setState(() => _selectedRoomId = roomId);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(name)),
                            body: ChatDetailView(roomId: roomId, roomName: name, showAppBar: false),
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
    );
  }

  Widget _buildFirestoreRoomList({required bool isWide}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('members', arrayContains: currentUser!.uid)
          .orderBy('lastMessageTime', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('チャット履歴はありません', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final room = docs[index].data() as Map<String, dynamic>;
            final roomId = docs[index].id;
            final isSelected = isWide && roomId == _selectedRoomId;
            
            String roomName = room['groupName'] ?? '';
            if (roomName.isEmpty) {
              final names = Map<String, dynamic>.from(room['names'] ?? {});
              names.forEach((uid, name) {
                if (uid != currentUser!.uid) roomName = name;
              });
            }
            if (roomName.isEmpty) roomName = '名称未設定';

            String timeStr = '';
            if (room['lastMessageTime'] != null) {
              final ts = room['lastMessageTime'] as Timestamp;
              timeStr = DateFormat('MM/dd HH:mm').format(ts.toDate());
            }

            final isGroup = (room['members'] as List).length > 2 || (room['groupName'] != null && room['groupName'].isNotEmpty);

            return ListTile(
              selected: isSelected,
              selectedTileColor: Colors.orange.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: isGroup ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                child: Icon(isGroup ? Icons.groups : Icons.person, color: isGroup ? Colors.blue : Colors.orange),
              ),
              title: Text(
                roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              ),
              subtitle: Text(
                room['lastMessage'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () {
                if (isWide) {
                  setState(() => _selectedRoomId = roomId);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: Text(roomName)),
                        body: ChatDetailView(roomId: roomId, roomName: roomName, showAppBar: false),
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

// ==========================================
// 2. 新規チャット作成ダイアログ (NewChatDialog)
// ==========================================

class NewChatDialog extends StatefulWidget {
  final String myUid;
  final Function(String roomId, String roomName) onStartChat;

  const NewChatDialog({super.key, required this.myUid, required this.onStartChat});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // タブ切り替え時に選択をリセット
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() {
          _selectedUids.clear();
          _isGroupMode = false;
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

      // 1. 保護者取得
      final familySnap = await FirebaseFirestore.instance.collection('families').get();
      for (var doc in familySnap.docs) {
        final d = doc.data();
        if (d['uid'] == widget.myUid) continue;
        
        final name = '${d['lastName'] ?? ''} ${d['firstName'] ?? ''}'.trim();
        final kana = '${d['lastNameKana'] ?? ''} ${d['firstNameKana'] ?? ''}'.trim();
        
        tempFamilies.add({
          'uid': d['uid'],
          'name': name.isEmpty ? '名称未設定' : name,
          'kana': kana.isEmpty ? name : kana,
        });
      }

      // 2. スタッフ取得
      final staffSnap = await FirebaseFirestore.instance.collection('staff').get();
      for (var doc in staffSnap.docs) {
        final d = doc.data();
        if (d['uid'] == widget.myUid) continue;

        // スタッフ名の取得ロジック改善
        String name = d['name'] ?? '';
        if (name.isEmpty) {
          name = '${d['lastName'] ?? ''} ${d['firstName'] ?? ''}'.trim();
        }
        String kana = d['furigana'] ?? name; 

        tempStaff.add({
          'uid': d['uid'],
          'name': name.isEmpty ? 'スタッフ' : name,
          'kana': kana,
        });
      }

      // ソート
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

  // あいうえお順のヘッダー判定
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

  // セクション付きリストの構築
  Widget _buildSectionedList(List<Map<String, dynamic>> users, bool isStaffTab) {
    if (users.isEmpty) return const Center(child: Text('ユーザーがいません'));

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var user in users) {
      final header = _getIndexHeader(user['kana']);
      if (!grouped.containsKey(header)) {
        grouped[header] = [];
      }
      grouped[header]!.add(user);
    }

    final headers = grouped.keys.toList()..sort();

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade100,
              child: Text(
                header,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
              ),
            ),
            ...groupUsers.map((user) {
              final uid = user['uid'];
              final isSelected = _selectedUids.contains(uid);

              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isStaffTab ? Colors.blue.shade100 : Colors.orange.shade100,
                      child: Icon(Icons.person, color: isStaffTab ? Colors.blue : Colors.orange),
                    ),
                    title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    // スタッフのみチェックボックス表示
                    trailing: isStaffTab && _isGroupMode
                        ? Checkbox(
                            value: isSelected,
                            activeColor: Colors.blue,
                            onChanged: (val) => _toggleSelection(uid),
                          )
                        : null,
                    onTap: () {
                      if (isStaffTab && _isGroupMode) {
                        _toggleSelection(uid);
                      } else {
                        // 1対1チャット開始
                        _startSingleChat(uid, user['name']);
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 70),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  void _startSingleChat(String targetUid, String targetName) async {
    final memberIds = [widget.myUid, targetUid]..sort();
    final roomId = memberIds.join('_');
    
    final Map<String, String> namesMap = {
      widget.myUid: '自分',
      targetUid: targetName,
    };

    await _createRoomIfNeeded(roomId, memberIds, namesMap, null);
    
    if (mounted) {
      Navigator.pop(context);
      widget.onStartChat(roomId, targetName);
    }
  }

  void _startGroupChat() async {
    if (_selectedUids.isEmpty) return;

    final roomId = FirebaseFirestore.instance.collection('chat_rooms').doc().id;
    final memberIds = [widget.myUid, ..._selectedUids]..sort();
    
    final Map<String, String> namesMap = {widget.myUid: '自分'};
    for (var uid in _selectedUids) {
      final user = _staff.firstWhere((u) => u['uid'] == uid, orElse: () => {'name': 'Unknown'});
      namesMap[uid] = user['name'];
    }

    String groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      groupName = namesMap.values.where((n) => n != '自分').take(3).join(', ');
      if (namesMap.length > 4) groupName += '...';
    }

    await _createRoomIfNeeded(roomId, memberIds, namesMap, groupName);

    if (mounted) {
      Navigator.pop(context);
      widget.onStartChat(roomId, groupName);
    }
  }

  Future<void> _createRoomIfNeeded(String roomId, List<String> members, Map<String, String> names, String? groupName) async {
    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId);
    final doc = await roomRef.get();

    if (!doc.exists) {
      await roomRef.set({
        'roomId': roomId,
        'members': members,
        'names': names,
        'groupName': groupName,
        'lastMessage': groupName != null ? 'グループが作成されました' : 'チャットを開始しました',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 安全策：コントローラー初期化前なら何も表示しない
    if (_tabController == null) return const SizedBox.shrink();

    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 500,
        height: 650,
        child: Column(
          children: [
            // ヘッダー
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const Text('新規チャット', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  // 検索バー
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: _onSearch,
                  ),
                  const SizedBox(height: 16),

                  // タブ
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2)],
                      ),
                      labelColor: Colors.black87,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [Tab(text: '保護者'), Tab(text: 'スタッフ')],
                    ),
                  ),
                  
                  // グループ作成スイッチ (スタッフタブのみ)
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
                                const Text('グループ作成', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _isGroupMode,
                                  activeColor: Colors.blue,
                                  onChanged: (val) => setState(() => _isGroupMode = val),
                                ),
                              ],
                            ),
                            if (_isGroupMode)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextField(
                                  controller: _groupNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'グループ名（任意）',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.groups),
                                    isDense: true,
                                  ),
                                ),
                              ),
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

            // ユーザーリスト
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSectionedList(_filteredFamilies, false),
                        _buildSectionedList(_filteredStaff, true),
                      ],
                    ),
            ),

            // フッターボタン (グループ作成時のみ)
            if (_tabController!.index == 1 && _isGroupMode)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedUids.isEmpty ? null : _startGroupChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('選択した${_selectedUids.length}名でグループ作成'),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
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

  const ChatDetailView({
    super.key,
    required this.roomId,
    required this.roomName,
    this.showAppBar = true,
  });

  @override
  State<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<ChatDetailView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;

  // ignore: unused_field
  int? _hoveringMessageIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ヘッダー（必要な場合のみ表示）
        if (widget.showAppBar) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
            child: Row(children: [
              Expanded(child: Text(widget.roomName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
        
        // メッセージリスト
        Expanded(
          child: Container(
            color: const Color(0xFFF2F2F7),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(widget.roomId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
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
        
        // 入力エリア
        _buildInputArea(),
      ],
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
            IconButton(icon: const Icon(Icons.add, color: Colors.grey), onPressed: () {}),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: 'メッセージを入力',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _sendMessage,
              mini: true,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(int index, Map<String, dynamic> msg, String msgId) {
    final isMe = msg['senderId'] == currentUser?.uid;
    final text = msg['text'] ?? '';
    final stamps = Map<String, dynamic>.from(msg['stamps'] ?? {});

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isMe) ...[
                  Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.orange.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
                    ),
                    child: SelectableText(text, style: const TextStyle(fontSize: 15)),
                  ),
                ),
                if (!isMe) ...[
                  const SizedBox(width: 8),
                  Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ],
            ),
            // スタンプ表示
            if (stamps.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8, left: isMe ? 0 : 8, right: isMe ? 8 : 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
                  children: stamps.entries.map((entry) {
                    return _buildReactionChip(msgId, entry.key, entry.value, isMe);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionChip(String msgId, String emoji, dynamic count, bool isMe) {
    final int c = count is int ? count : 1;
    return GestureDetector(
      onTap: () => _toggleReaction(msgId, emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMe ? Colors.orange.shade50 : Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (c > 1) ...[
              const SizedBox(width: 4),
              Text('$c', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;
    final text = _textController.text;
    _textController.clear();

    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
    
    await roomRef.collection('messages').add({
      'senderId': currentUser!.uid,
      'text': text,
      'stamps': {},
      'createdAt': FieldValue.serverTimestamp(),
    });

    await roomRef.update({
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    final msgRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .doc(msgId);

    FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(msgRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final stamps = Map<String, dynamic>.from(data['stamps'] ?? {});
      if (stamps.containsKey(emoji)) {
        stamps[emoji] = (stamps[emoji] as int) + 1;
      } else {
        stamps[emoji] = 1;
      }
      transaction.update(msgRef, {'stamps': stamps});
    });
  }
}