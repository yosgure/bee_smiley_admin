import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'classroom_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'pdf_preview_stub.dart' if (dart.library.js_interop) 'pdf_preview_web.dart';
import 'package:flutter/cupertino.dart';
import 'app_theme.dart';
import 'chat_screen.dart' show VideoPlayerDialog;
import 'utils/recent_emojis.dart';
import 'widgets/emoji_stamp_picker.dart';

class ParentChatScreen extends StatefulWidget {
  final Map<String, dynamic>? familyData;

  const ParentChatScreen({super.key, this.familyData});

  @override
  State<ParentChatScreen> createState() => _ParentChatScreenState();
}

class _ParentChatScreenState extends State<ParentChatScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;
  String _myDisplayName = '';

  @override
  void initState() {
    super.initState();
    _setDisplayName();
    _ensureRoom();
  }

  Future<void> _ensureRoom() async {
    if (currentUser == null || widget.familyData == null) return;
    final familyRoomId = 'family_${currentUser!.uid}';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(familyRoomId)
          .get();
      if (!doc.exists) {
        await _createChatRoom();
      }
    } catch (e) {
      debugPrint('Error ensuring chat room: $e');
    }
  }

  void _setDisplayName() {
    if (widget.familyData != null) {
      final lastName = (widget.familyData!['lastName'] ?? '').toString().trim();
      final firstName = (widget.familyData!['firstName'] ?? '').toString().trim();
      _myDisplayName = '$lastName $firstName'.trim();
      if (_myDisplayName.isEmpty) _myDisplayName = '保護者';
    }
  }

  Future<void> _createChatRoom() async {
    if (currentUser == null || widget.familyData == null) return;

    try {
      // 子供の教室を取得
      final children = List<Map<String, dynamic>>.from(widget.familyData!['children'] ?? []);
      Set<String> classrooms = {};
      for (var child in children) {
        classrooms.addAll(getChildClassrooms(child));
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
                '${(staffData['lastName'] ?? '').toString().trim()} ${(staffData['firstName'] ?? '').toString().trim()}'.trim();
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
                '${(staffData['lastName'] ?? '').toString().trim()} ${(staffData['firstName'] ?? '').toString().trim()}'.trim();
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

    } catch (e) {
      debugPrint('Error creating chat room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('チャットルームの作成に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return Column(
        children: [
          _buildHeader('チャット'),
          const Expanded(child: Center(child: Text('ログインが必要です'))),
        ],
      );
    }

    final familyRoomId = 'family_${currentUser!.uid}';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(familyRoomId)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> names = {};
        List<String> members = [];
        final roomReady = snapshot.hasData && snapshot.data!.exists;
        if (roomReady) {
          final room = snapshot.data!.data() as Map<String, dynamic>;
          names = Map<String, dynamic>.from(room['names'] ?? {});
          members = List<String>.from(room['members'] ?? []);
        }
        final isGroup = members.length > 2;

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              _buildHeader('チャット'),
              Expanded(
                child: roomReady
                    ? _ChatMessageList(
                        roomId: familyRoomId,
                        myUid: currentUser!.uid,
                        isGroup: isGroup,
                        memberNames: names,
                      )
                    : Container(
                        color: context.colors.scaffoldBgAlt,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
              ),
              _ChatInputArea(
                roomId: familyRoomId,
                myName: _myDisplayName,
                ensureRoom: _ensureRoom,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(bottom: BorderSide(color: context.colors.borderLight)),
      ),
      child: Center(
        child: Text(
          title,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
      color: context.colors.scaffoldBgAlt,
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: context.colors.textSecondary),
                  SizedBox(height: 16),
                  Text('メッセージを送信してみましょう', style: TextStyle(color: context.colors.textSecondary)),
                ],
              ),
            );
          }

          _markAsRead(messages);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              if (_isFirstLoad) {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                _isFirstLoad = false;
              } else {
                // 新メッセージ: 下端付近にいる場合のみ自動スクロール
                final maxScroll = _scrollController.position.maxScrollExtent;
                final currentScroll = _scrollController.position.pixels;
                if (maxScroll - currentScroll < 200) {
                  _scrollController.animateTo(
                    maxScroll,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              }
            }
          });

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
    final unreadDocs = messages.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final readBy = List<String>.from(data['readBy'] ?? []);
      return !readBy.contains(widget.myUid);
    }).toList();

    if (unreadDocs.isEmpty) return;

    // WriteBatchで一括更新（最大500件ずつ）
    for (int i = 0; i < unreadDocs.length; i += 500) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = unreadDocs.skip(i).take(500);
      for (final doc in chunk) {
        batch.update(doc.reference, {
          'readBy': FieldValue.arrayUnion([widget.myUid]),
        });
      }
      await batch.commit();
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, String msgId) {
    final bool isMe = msg['senderId'] == widget.myUid;
    final String text = msg['text'] ?? '';
    final String type = msg['type'] ?? 'text';
    final readBy = List<String>.from(msg['readBy'] ?? []);
    final isRead = isMe && readBy.any((uid) => uid != widget.myUid);
    final stamps = Map<String, dynamic>.from(msg['stamps'] ?? {});
    final Map<String, dynamic>? replyTo =
        msg['replyTo'] is Map ? Map<String, dynamic>.from(msg['replyTo']) : null;

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
    final bool isEmojiOnly = type == 'text' && isEmojiOnlyMessage(text);
    final bool isImageOnly =
        (type == 'image' || type == 'video') && text.isEmpty;

    if (type == 'image') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(msg['url']),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: msg['url'],
                width: 200,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(width: 200, height: 150, decoration: BoxDecoration(color: context.colors.borderLight, borderRadius: BorderRadius.circular(12)), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))),
                errorWidget: (c, u, e) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif'])),
          ],
        ],
      );
    } else if (type == 'video') {
      final vUrl = (msg['url'] ?? '') as String;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (vUrl.isNotEmpty) {
                showDialog(
                  context: context,
                  barrierColor: Colors.black,
                  builder: (_) => VideoPlayerDialog(url: vUrl),
                );
              }
            },
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
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif'])),
          ],
        ],
      );
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
                    child: Icon(fIcon, color: context.colors.cardBg, size: 24),
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2),
                        if (expiryText.isNotEmpty) ...[
                          SizedBox(height: 2),
                          Text(expiryText, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                        ],
                        if (sizeText.isNotEmpty) ...[
                          SizedBox(height: 2),
                          Text('サイズ: $sizeText', style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (text.isNotEmpty) ...[const SizedBox(height: 8), Text(text, style: TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']))],
            SizedBox(height: 6),
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
    } else {
      content = Text(
        text,
        style: TextStyle(
          fontSize: isEmojiOnly ? 38 : 15,
          height: 1.5,
          fontFamily: 'NotoSansJP',
          fontFamilyFallback: const ['Hiragino Sans', 'Roboto', 'sans-serif'],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showActionSheet(msgId, isMe, type, text),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (senderName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(senderName, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isMe) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isRead) Text('既読', style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                        Text(timeStr, style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                      ],
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: (isImageOnly || isEmojiOnly) && replyTo == null
                        ? content
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: isMe ? context.colors.chatMyBubble : context.colors.chatOtherBubble,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (replyTo != null) _buildReplyQuote(replyTo, isMe),
                                content,
                              ],
                            ),
                          ),
                  ),
                  if (!isMe) ...[
                    const SizedBox(width: 8),
                    Text(timeStr, style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
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

  Widget _buildReplyQuote(Map<String, dynamic> replyTo, bool isMe) {
    final senderName = (replyTo['senderName'] ?? '') as String;
    final preview = (replyTo['preview'] ?? '') as String;
    final bgColor =
        isMe ? context.colors.chatMyBubble.withOpacity(0.3) : context.colors.chipBg;
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
          SizedBox(height: 1),
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

  // スタンプ表示ウィジェット（bee=ロゴ画像、それ以外=テキスト絵文字）
  static Widget _stampWidget(String stamp, {double size = 22}) {
    if (stamp == 'bee') {
      return Image.asset('assets/logo_beesmileymark.png', width: size * 1.4, height: size * 1.4);
    }
    return Text(
      stamp,
      style: TextStyle(
        inherit: false,
        fontSize: size,
        color: const Color(0xFF000000),
        fontFamily: 'Noto Color Emoji',
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Twemoji Mozilla',
          'EmojiOne Color',
        ],
      ),
    );
  }

  Widget _buildStampChip(String msgId, String emoji, dynamic count, bool isMe) {
    final List<String> userList = count is List ? List<String>.from(count) : [];
    final int c = count is int ? count : (count is List ? count.length : 1);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final bool alreadyReacted = userList.contains(uid);
    // uidから名前を解決
    final names = userList.map((u) {
      final name = widget.memberNames[u];
      if (name is String && name.isNotEmpty) return name;
      return u == uid ? 'あなた' : u;
    }).toList();
    final tooltipText = names.join('、');
    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 300),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
      child: GestureDetector(
        onTap: () => _toggleStamp(msgId, emoji),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(c, (_) => Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _stampWidget(emoji, size: 16),
          )),
        ),
      ),
    );
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

  Widget _buildQuickReactionBar(BuildContext sheetContext, String msgId) {
    const fallback = ['👍', '❤️', '😄', '🎉', '🙏', 'bee'];
    return FutureBuilder<List<String>>(
      future: RecentEmojis.load(),
      builder: (context, snapshot) {
        final recent = snapshot.data ?? const [];
        final List<String> emojis;
        if (recent.length >= 6) {
          emojis = recent.take(6).toList();
        } else {
          final seen = <String>{...recent};
          final filled = <String>[...recent];
          for (final e in fallback) {
            if (filled.length >= 6) break;
            if (seen.add(e)) filled.add(e);
          }
          emojis = filled;
        }
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in emojis)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    RecentEmojis.add(e);
                    _toggleStamp(msgId, e);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: _stampWidget(e, size: 26),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

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
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontFamily: 'NotoSansJP',
                fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif'],
              ),
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

  void _showEmojiPicker(String msgId) {
    showEmojiStampPicker(
      context: context,
      onSelected: (emoji) => _toggleStamp(msgId, emoji),
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
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('メッセージを編集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: null,
                minLines: 2,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'メッセージを入力',
                  filled: true,
                  fillColor: context.colors.chipBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text('キャンセル', style: TextStyle(color: context.colors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                _SwipeDownToDismiss(
                  onDismiss: () => Navigator.pop(dialogContext),
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (c, u) => Center(child: CircularProgressIndicator(color: context.colors.cardBg)),
                        errorWidget: (c, u, e) => Icon(Icons.broken_image, color: context.colors.cardBg, size: 48),
                      ),
                    ),
                  ),
                ),
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
                            icon: Icon(Icons.close, color: context.colors.cardBg, size: 28),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                          IconButton(
                            icon: isSaving
                                ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.cardBg))
                                : Icon(Icons.download, color: context.colors.cardBg, size: 28),
                            tooltip: '保存',
                            onPressed: isSaving
                                ? null
                                : () async {
                                    setDialogState(() => isSaving = true);
                                    await _saveImageToGallery(url, dialogContext);
                                    setDialogState(() => isSaving = false);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showFilePreview(String url, String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isPdf = ext == 'pdf';

    if (isImage) {
      _showImagePreview(url);
      return;
    }

    if (isPdf) {
      _showPdfPreview(url, fileName);
      return;
    }

    // その他のファイルは外部ブラウザで開く
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showPdfPreview(String url, String fileName) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 48,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        kIsWeb ? Icons.download : Icons.open_in_new,
                        color: Colors.white,
                      ),
                      tooltip: kIsWeb ? 'ダウンロード' : '他のアプリで開く',
                      onPressed: () async {
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.grey[900],
                  child: kIsWeb
                      ? buildWebPdfViewer(url)
                      : SfPdfViewer.network(
                          url,
                          canShowScrollHead: true,
                          canShowScrollStatus: true,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
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
              backgroundColor: AppColors.accent,
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
                backgroundColor: AppColors.accent,
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
  final Future<void> Function()? ensureRoom;

  const _ChatInputArea({required this.roomId, required this.myName, this.ensureRoom});

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
        color: context.colors.cardBg,
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
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: _isUploading ? context.colors.borderMedium : context.colors.textSecondary,
                    size: 24,
                  ),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  tooltip: '添付',
                  onPressed: _isUploading ? null : _showAttachmentMenu,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLines: null,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 15, height: 1.5, fontFamily: 'NotoSansJP', fontFamilyFallback: ['Hiragino Sans', 'Roboto', 'sans-serif']),
                      decoration: InputDecoration(
                        hintText: 'メッセージを入力',
                        filled: true,
                        fillColor: context.colors.chipBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 18),
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

  void _showAttachmentMenu() {
    _focusNode.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('写真・動画'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadPhotos();
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_file, color: context.colors.textSecondary),
              title: const Text('ファイル'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadAny();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhotos() async {
    if (_isUploading) return;
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultipleMedia();
    if (files.isEmpty) return;
    for (final file in files) {
      if (!mounted) return;
      setState(() => _isUploading = true);
      try {
        final Uint8List bytes = await file.readAsBytes();
        final name = file.name;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final isVideo = file.mimeType?.startsWith('video/') == true ||
            const ['mp4', 'mov', 'avi', 'webm', 'mkv', 'm4v'].contains(ext);
        if (isVideo && bytes.length > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('動画サイズが大きすぎます (50MBまで)')),
            );
          }
          continue;
        }
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$name';
        final ref = FirebaseStorage.instance.ref().child('chat_uploads/${widget.roomId}/$fileName');
        if (isVideo) {
          final contentType = ext == 'mov' ? 'video/quicktime' : 'video/mp4';
          await ref.putData(bytes, SettableMetadata(contentType: contentType));
          final url = await ref.getDownloadURL();
          await _sendMessage(type: 'video', url: url, fileName: name);
        } else {
          final contentType = ext == 'png'
              ? 'image/png'
              : ext == 'gif'
                  ? 'image/gif'
                  : ext == 'webp'
                      ? 'image/webp'
                      : 'image/jpeg';
          await ref.putData(bytes, SettableMetadata(contentType: contentType));
          final url = await ref.getDownloadURL();
          await _sendMessage(type: 'image', url: url);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('アップロード失敗: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAndUploadAny() async {
    if (_isUploading) return;
    _focusNode.unfocus();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'};
    const videoExts = {'mp4', 'mov', 'avi', 'webm', 'mkv', 'm4v'};
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      if (!mounted) return;
      setState(() => _isUploading = true);
      try {
        final name = file.name;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$name';
        final ref = FirebaseStorage.instance
            .ref()
            .child('chat_uploads/${widget.roomId}/$fileName');
        if (imageExts.contains(ext)) {
          final contentType = ext == 'png'
              ? 'image/png'
              : ext == 'gif'
                  ? 'image/gif'
                  : ext == 'webp'
                      ? 'image/webp'
                      : 'image/jpeg';
          await ref.putData(bytes, SettableMetadata(contentType: contentType));
          final url = await ref.getDownloadURL();
          await _sendMessage(type: 'image', url: url);
        } else if (videoExts.contains(ext)) {
          if (bytes.length > 50 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('動画サイズが大きすぎます (50MBまで)')),
              );
            }
            continue;
          }
          final contentType = ext == 'mov' ? 'video/quicktime' : 'video/mp4';
          await ref.putData(bytes, SettableMetadata(contentType: contentType));
          final url = await ref.getDownloadURL();
          await _sendMessage(type: 'video', url: url, fileName: name);
        } else {
          await ref.putData(bytes);
          final url = await ref.getDownloadURL();
          await _sendMessage(type: 'file', url: url, fileName: name);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('アップロード失敗: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _sendMessage({String type = 'text', String? url, String? fileName}) async {
    final text = _textController.text.trim();
    if (text.isEmpty && type == 'text') return;

    _focusNode.unfocus();

    if (type == 'text') _textController.clear();

    if (widget.ensureRoom != null) {
      await widget.ensureRoom!();
    }

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
    if (type == 'video') lastMsg = '動画を送信しました';
    await roomRef.update({
      'lastMessage': lastMsg,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

}

/// 下スワイプで閉じるラッパー。
class _SwipeDownToDismiss extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  const _SwipeDownToDismiss({required this.child, required this.onDismiss});

  @override
  State<_SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<_SwipeDownToDismiss> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 0 || _dy > 0) {
          setState(() => _dy = (_dy + d.delta.dy).clamp(0, 600));
        }
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy > 120 || v > 700) {
          widget.onDismiss();
        } else {
          setState(() => _dy = 0);
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dy),
        child: widget.child,
      ),
    );
  }
}