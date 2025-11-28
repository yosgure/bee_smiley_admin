import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';

class ParentChatScreen extends StatefulWidget {
  final Map<String, dynamic>? familyData;

  const ParentChatScreen({super.key, this.familyData});

  @override
  State<ParentChatScreen> createState() => _ParentChatScreenState();
}

class _ParentChatScreenState extends State<ParentChatScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  String _myDisplayName = '';
  
  // チャットルーム情報
  String? _roomId;
  String _teacherName = '先生';
  bool _isLoading = true;
  bool _noRoom = false;

  @override
  void initState() {
    super.initState();
    _setDisplayName();
    _findOrCreateChatRoom();
  }

  void _setDisplayName() {
    if (widget.familyData != null) {
      final lastName = widget.familyData!['lastName'] ?? '';
      final firstName = widget.familyData!['firstName'] ?? '';
      _myDisplayName = '$lastName $firstName'.trim();
      if (_myDisplayName.isEmpty) _myDisplayName = '保護者';
    }
  }

  /// チャットルームを検索
  Future<void> _findOrCreateChatRoom() async {
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // 既存のチャットルームを検索
      final roomQuery = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('members', arrayContains: currentUser!.uid)
          .limit(1)
          .get();

      if (roomQuery.docs.isNotEmpty) {
        // 既存のルームがある
        final roomDoc = roomQuery.docs.first;
        final room = roomDoc.data();
        
        setState(() {
          _roomId = roomDoc.id;
          _noRoom = false;
        });
        
        // 先生の名前を取得
        await _loadTeacherName(room);
      } else {
        // チャットルームがない
        setState(() {
          _isLoading = false;
          _noRoom = true;
        });
      }
    } catch (e) {
      debugPrint('Error finding chat room: $e');
      setState(() {
        _isLoading = false;
        _noRoom = true;
      });
    }
  }

  /// チャットルームを作成
  Future<void> _createChatRoom() async {
    if (currentUser == null || widget.familyData == null) return;

    setState(() => _isLoading = true);

    try {
      // 子どもの教室を取得
      final children = List<Map<String, dynamic>>.from(widget.familyData!['children'] ?? []);
      String? classroom;
      if (children.isNotEmpty) {
        classroom = children.first['classroom'];
      }

      // その教室の担当先生を検索
      String? teacherUid;
      String teacherName = '先生';
      
      if (classroom != null) {
        final staffQuery = await FirebaseFirestore.instance
            .collection('staffs')
            .where('classroom', isEqualTo: classroom)
            .limit(1)
            .get();
        
        if (staffQuery.docs.isNotEmpty) {
          final staffData = staffQuery.docs.first.data();
          teacherUid = staffData['uid'];
          final lastName = staffData['lastName'] ?? '';
          final firstName = staffData['firstName'] ?? '';
          teacherName = '$lastName $firstName'.trim();
          if (teacherName.isEmpty) teacherName = '先生';
        }
      }

      // 先生が見つからない場合は最初のスタッフを使用
      if (teacherUid == null) {
        final anyStaffQuery = await FirebaseFirestore.instance
            .collection('staffs')
            .limit(1)
            .get();
        
        if (anyStaffQuery.docs.isNotEmpty) {
          final staffData = anyStaffQuery.docs.first.data();
          teacherUid = staffData['uid'];
          final lastName = staffData['lastName'] ?? '';
          final firstName = staffData['firstName'] ?? '';
          teacherName = '$lastName $firstName'.trim();
          if (teacherName.isEmpty) teacherName = '先生';
        }
      }

      if (teacherUid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('先生が登録されていません')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // チャットルームを作成
      final roomRef = await FirebaseFirestore.instance.collection('chat_rooms').add({
        'members': [currentUser!.uid, teacherUid],
        'names': {
          currentUser!.uid: _myDisplayName,
          teacherUid: teacherName,
        },
        'lastMessage': 'チャットを開始しました',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _roomId = roomRef.id;
        _teacherName = teacherName;
        _noRoom = false;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error creating chat room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('チャットルームの作成に失敗しました: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  /// 先生の名前を取得
  Future<void> _loadTeacherName(Map<String, dynamic> room) async {
    final members = List<String>.from(room['members'] ?? []);
    final names = Map<String, dynamic>.from(room['names'] ?? {});
    
    // namesに相手の名前がある場合
    for (final entry in names.entries) {
      if (entry.key != currentUser!.uid) {
        setState(() {
          _teacherName = entry.value.toString();
          _isLoading = false;
        });
        return;
      }
    }
    
    // namesにない場合、staffsコレクションから取得
    for (final memberId in members) {
      if (memberId != currentUser!.uid) {
        try {
          final staffQuery = await FirebaseFirestore.instance
              .collection('staffs')
              .where('uid', isEqualTo: memberId)
              .limit(1)
              .get();
          
          if (staffQuery.docs.isNotEmpty) {
            final staffData = staffQuery.docs.first.data();
            final lastName = staffData['lastName'] ?? '';
            final firstName = staffData['firstName'] ?? '';
            final name = '$lastName $firstName'.trim();
            if (name.isNotEmpty) {
              setState(() {
                _teacherName = name;
                _isLoading = false;
              });
              return;
            }
          }
        } catch (e) {
          debugPrint('Error fetching staff name: $e');
        }
      }
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    // ローディング中
    if (_isLoading) {
      return Column(
        children: [
          _buildHeader('チャット'),
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    // チャットルームがない場合 → 作成ボタンを表示
    if (_noRoom || _roomId == null) {
      return Column(
        children: [
          _buildHeader('チャット'),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'まだチャットがありません',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _createChatRoom,
                    icon: const Icon(Icons.add_comment),
                    label: const Text('先生とチャットを始める'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // チャット画面を直接表示
    return Column(
      children: [
        _buildHeader('チャット'),
        Expanded(child: _ChatMessageList(roomId: _roomId!)),
        _ChatInputArea(roomId: _roomId!, myName: _myDisplayName),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
        ),
      ),
    );
  }
}

// メッセージリスト
class _ChatMessageList extends StatefulWidget {
  final String roomId;

  const _ChatMessageList({required this.roomId});

  @override
  State<_ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<_ChatMessageList> {
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F2F7),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(widget.roomId)
            .collection('messages')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final messages = snapshot.data!.docs;

          if (messages.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('メッセージを送信してみましょう', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          // 既読処理
          _markAsRead(messages);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              return _buildMessageBubble(msg, messages[index].id);
            },
          );
        },
      ),
    );
  }

  void _markAsRead(List<QueryDocumentSnapshot> messages) async {
    for (final doc in messages) {
      final data = doc.data() as Map<String, dynamic>;
      final readBy = List<String>.from(data['readBy'] ?? []);
      if (!readBy.contains(currentUser!.uid)) {
        await doc.reference.update({
          'readBy': FieldValue.arrayUnion([currentUser!.uid]),
        });
      }
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, String msgId) {
    final bool isMe = msg['senderId'] == currentUser!.uid;
    final String text = msg['text'] ?? '';
    final String type = msg['type'] ?? 'text';
    final readBy = List<String>.from(msg['readBy'] ?? []);
    final isRead = isMe && readBy.any((uid) => uid != currentUser!.uid);

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    Widget content;
    if (type == 'image') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(msg['url']),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                msg['url'],
                width: 200,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 15)),
          ],
        ],
      );
    } else if (type == 'file') {
      content = InkWell(
        onTap: () async {
          final Uri url = Uri.parse(msg['url']);
          if (await canLaunchUrl(url)) await launchUrl(url);
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg['fileName'] ?? 'ファイル',
                  style: const TextStyle(fontSize: 14, decoration: TextDecoration.underline),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      content = Text(text, style: const TextStyle(fontSize: 15));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
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
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary.withOpacity(0.2) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: content,
                  ),
                ),
                if (!isMe) ...[
                  const SizedBox(width: 8),
                  Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Image.network(url)),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }
}

// 入力エリア
class _ChatInputArea extends StatefulWidget {
  final String roomId;
  final String myName;

  const _ChatInputArea({required this.roomId, required this.myName});

  @override
  State<_ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<_ChatInputArea> {
  final TextEditingController _textController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading) const LinearProgressIndicator(),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image, color: Colors.grey),
                  onPressed: _isUploading ? null : _pickAndUploadImage,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'メッセージを入力',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  mini: true,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage({String type = 'text', String? url, String? fileName}) async {
    final text = _textController.text.trim();
    if (text.isEmpty && type == 'text') return;

    if (type == 'text') _textController.clear();

    final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
    await roomRef.collection('messages').add({
      'senderId': currentUser!.uid,
      'text': text,
      'type': type,
      'url': url,
      'fileName': fileName,
      'stamps': {},
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': [currentUser!.uid],
    });

    String lastMsg = text;
    if (type == 'image') lastMsg = '画像を送信しました';
    if (type == 'file') lastMsg = 'ファイルを送信しました';
    await roomRef.update({
      'lastMessage': lastMsg,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
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
      await _sendMessage(type: 'image', url: url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}