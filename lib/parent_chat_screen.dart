import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'app_theme.dart';
import 'skeleton_loading.dart';

class ParentChatScreen extends StatefulWidget {
  final Map<String, dynamic>? familyData;

  const ParentChatScreen({super.key, this.familyData});

  @override
  State<ParentChatScreen> createState() => _ParentChatScreenState();
}

class _ParentChatScreenState extends State<ParentChatScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  String _myDisplayName = '';
  
  String? _roomId;
  String _roomName = '先生';
  bool _isLoading = true;
  bool _noRoom = false;
  bool _isGroup = false;
  Map<String, dynamic> _memberNames = {};

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

  Future<void> _findOrCreateChatRoom() async {
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 保護者専用のルームIDを使用
      final familyRoomId = 'family_${currentUser!.uid}';
      
      // 既存のルームを確認
      final roomDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(familyRoomId)
          .get();

      if (roomDoc.exists) {
        final room = roomDoc.data()!;
        final names = Map<String, dynamic>.from(room['names'] ?? {});
        final members = List<String>.from(room['members'] ?? []);
        
        // ルーム名を設定（自分以外のメンバー名）
        String roomName = room['groupName'] ?? '';
        if (roomName.isEmpty) {
          final otherNames = names.entries
              .where((e) => e.key != currentUser!.uid)
              .map((e) => e.value)
              .toList();
          roomName = otherNames.isNotEmpty ? otherNames.join(', ') : '先生';
        }
        
        setState(() {
          _roomId = familyRoomId;
          _roomName = roomName;
          _isGroup = members.length > 2;
          _memberNames = names;
          _noRoom = false;
          _isLoading = false;
        });
      } else {
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

  Future<void> _createChatRoom() async {
    if (currentUser == null || widget.familyData == null) return;

    setState(() => _isLoading = true);

    try {
      // 子供の教室を取得
      final children = List<Map<String, dynamic>>.from(widget.familyData!['children'] ?? []);
      Set<String> classrooms = {};
      for (var child in children) {
        if (child['classroom'] != null && child['classroom'].toString().isNotEmpty) {
          classrooms.add(child['classroom']);
        }
      }

      // 該当教室を担当する全スタッフを取得
      List<String> staffUids = [];
      Map<String, String> staffNames = {};

      if (classrooms.isNotEmpty) {
        final staffQuery = await FirebaseFirestore.instance
            .collection('staffs')
            .get();

        for (var doc in staffQuery.docs) {
          final staffData = doc.data();
          final staffClassrooms = List<String>.from(staffData['classrooms'] ?? []);
          final staffUid = staffData['uid'] as String?;
          
          if (staffUid == null) continue;
          
          // スタッフが担当する教室と子供の教室が一致するか確認
          final hasMatchingClassroom = staffClassrooms.any((sc) => classrooms.contains(sc));
          
          if (hasMatchingClassroom) {
            staffUids.add(staffUid);
            final name = staffData['name'] ?? 
                '${staffData['lastName'] ?? ''} ${staffData['firstName'] ?? ''}'.trim();
            staffNames[staffUid] = name.isNotEmpty ? name : '先生';
          }
        }
      }

      // スタッフが見つからない場合、全スタッフから1人を選択
      if (staffUids.isEmpty) {
        final anyStaffQuery = await FirebaseFirestore.instance
            .collection('staffs')
            .limit(1)
            .get();
        
        if (anyStaffQuery.docs.isNotEmpty) {
          final staffData = anyStaffQuery.docs.first.data();
          final staffUid = staffData['uid'] as String?;
          if (staffUid != null) {
            staffUids.add(staffUid);
            final name = staffData['name'] ?? 
                '${staffData['lastName'] ?? ''} ${staffData['firstName'] ?? ''}'.trim();
            staffNames[staffUid] = name.isNotEmpty ? name : '先生';
          }
        }
      }

      if (staffUids.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('先生が登録されていません')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // ルーム作成
      final familyRoomId = 'family_${currentUser!.uid}';
      final List<String> members = [currentUser!.uid, ...staffUids];
      final Map<String, String> names = {
        currentUser!.uid: _myDisplayName,
        ...staffNames,
      };

      // グループ名（複数スタッフの場合は保護者名をグループ名に）
      String? groupName;
      if (staffUids.length > 1) {
        groupName = _myDisplayName;
      }

      final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(familyRoomId);
      await roomRef.set({
        'roomId': familyRoomId,
        'members': members,
        'names': names,
        'groupName': groupName,
        'lastMessage': 'チャットを開始しました',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ルーム名を設定
      String roomName = groupName ?? staffNames.values.firstOrNull ?? '先生';

      setState(() {
        _roomId = familyRoomId;
        _roomName = roomName;
        _isGroup = staffUids.length > 1;
        _memberNames = names;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Column(
        children: [
          _buildHeader('チャット'),
          const Expanded(child: ChatListSkeleton()),
        ],
      );
    }

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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          _buildHeader('チャット'),
          Expanded(
            child: _ChatMessageList(
              roomId: _roomId!,
              myUid: currentUser!.uid,
              isGroup: _isGroup,
              memberNames: _memberNames,
            ),
          ),
          _ChatInputArea(roomId: _roomId!, myName: _myDisplayName),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      height: 40,
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

// ==========================================
// メッセージリスト
// ==========================================
class _ChatMessageList extends StatefulWidget {
  final String roomId;
  final String myUid;
  final bool isGroup;
  final Map<String, dynamic> memberNames;

  const _ChatMessageList({
    required this.roomId,
    required this.myUid,
    required this.isGroup,
    required this.memberNames,
  });

  @override
  State<_ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<_ChatMessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _isFirstLoad = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
            return const ChatListSkeleton();
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

          _markAsRead(messages);

          if (_isFirstLoad) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
              }
              _isFirstLoad = false;
            });
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              final msgId = messages[index].id;
              return _buildMessageBubble(msg, msgId);
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
      if (!readBy.contains(widget.myUid)) {
        await doc.reference.update({
          'readBy': FieldValue.arrayUnion([widget.myUid]),
        });
      }
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, String msgId) {
    final bool isMe = msg['senderId'] == widget.myUid;
    final String text = msg['text'] ?? '';
    final String type = msg['type'] ?? 'text';
    final readBy = List<String>.from(msg['readBy'] ?? []);
    final isRead = isMe && readBy.any((uid) => uid != widget.myUid);
    final stamps = Map<String, dynamic>.from(msg['stamps'] ?? {});

    String timeStr = '';
    if (msg['createdAt'] != null) {
      final ts = msg['createdAt'] as Timestamp;
      timeStr = DateFormat('HH:mm').format(ts.toDate());
    }

    // グループチャットの場合、送信者名を表示
    String senderName = '';
    if (widget.isGroup && !isMe) {
      senderName = widget.memberNames[msg['senderId']]?.toString() ?? '不明';
    }

    Widget content;
    final bool isImageOnly = type == 'image' && text.isEmpty;

    if (type == 'image') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(msg['url']),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                msg['url'],
                width: 200,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
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

    return GestureDetector(
      onLongPress: () => _showActionSheet(msgId, isMe, type, text),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
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
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: isImageOnly
                        ? content
                        : Container(
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
              if (stamps.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 4, left: isMe ? 0 : 8, right: isMe ? 8 : 0),
                  child: Wrap(
                    spacing: 4,
                    children: stamps.entries.map((e) => _buildStampChip(msgId, e.key, e.value, isMe)).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStampChip(String msgId, String emoji, dynamic count, bool isMe) {
    final int c = count is int ? count : (count is List ? count.length : 1);
    return GestureDetector(
      onTap: () => _toggleStamp(msgId, emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            if (c > 1) ...[
              const SizedBox(width: 2),
              Text('$c', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  void _showActionSheet(String msgId, bool isMe, String type, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text("スタンプを追加"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEmojiPicker(msgId);
                },
              ),
              if (isMe && type == "text")
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text("編集"),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditDialog(msgId, text);
                  },
                ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text("削除", style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteMessage(msgId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text("キャンセル"),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmojiPicker(String msgId) {
    final emojis = ['👍', '❤️', '😄', '🎉', '🙏', '🆗', '😂', '😢', '✨', '🤔'];
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('スタンプを選択'),
        content: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: emojis.map((e) => GestureDetector(
            onTap: () {
              _toggleStamp(msgId, e);
              Navigator.of(dialogContext).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(e, style: const TextStyle(fontSize: 28)),
            ),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStamp(String msgId, String emoji) async {
    final msgRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .doc(msgId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(msgRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;
        final stamps = Map<String, dynamic>.from(data['stamps'] ?? {});
        
        List<String> userList = [];
        if (stamps[emoji] is List) {
          userList = List<String>.from(stamps[emoji]);
        }
        
        if (userList.contains(widget.myUid)) {
          userList.remove(widget.myUid);
          if (userList.isEmpty) {
            stamps.remove(emoji);
          } else {
            stamps[emoji] = userList;
          }
        } else {
          userList.add(widget.myUid);
          stamps[emoji] = userList;
        }
        
        transaction.update(msgRef, {'stamps': stamps});
      });
    } catch (e) {
      debugPrint('スタンプ追加エラー: $e');
    }
  }

  void _showEditDialog(String msgId, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('メッセージを編集'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'メッセージを入力',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(widget.roomId)
                    .collection('messages')
                    .doc(msgId)
                    .update({'text': controller.text});
              } catch (e) {
                debugPrint('編集エラー: $e');
              }
              Navigator.of(dialogContext).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteMessage(String msgId) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('メッセージを削除'),
        content: const Text('このメッセージを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(widget.roomId)
                    .collection('messages')
                    .doc(msgId)
                    .delete();
              } catch (e) {
                debugPrint('削除エラー: $e');
              }
              Navigator.of(dialogContext).pop();
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(url),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setDialogState(() => isSaving = true);
                                await _saveImageToGallery(url, dialogContext);
                                setDialogState(() => isSaving = false);
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(isSaving ? '保存中...' : '保存'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade600,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveImageToGallery(String url, BuildContext dialogContext) async {
    try {
      if (kIsWeb) {
        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Web版では保存できません'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('写真へのアクセス許可が必要です'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception('ダウンロード失敗');

      final tempDir = await getTemporaryDirectory();
      final fileName = 'beesmiley_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      await Gal.putImage(file.path, album: 'Beesmiley');

      await file.delete();

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('写真を保存しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ==========================================
// 入力エリア
// ==========================================
class _ChatInputArea extends StatefulWidget {
  final String roomId;
  final String myName;

  const _ChatInputArea({required this.roomId, required this.myName});

  @override
  State<_ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<_ChatInputArea> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _isUploading = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading) const LinearProgressIndicator(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    child: Icon(
                      Icons.image,
                      color: _isUploading ? Colors.grey.shade400 : Colors.grey.shade600,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力',
                        hintStyle: TextStyle(fontSize: 16, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
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

    _focusNode.unfocus();

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
    _focusNode.unfocus();

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
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