import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

class ParentAssessmentScreen extends StatefulWidget {
  final String? childId;
  final String childName;
  final String? childPhotoUrl;
  final List<Map<String, dynamic>> allChildren;
  final int selectedChildIndex;
  final Function(int)? onChildChanged;

  const ParentAssessmentScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.childPhotoUrl,
    this.allChildren = const [],
    this.selectedChildIndex = 0,
    this.onChildChanged,
  });

  @override
  State<ParentAssessmentScreen> createState() => _ParentAssessmentScreenState();
}

class _ParentAssessmentScreenState extends State<ParentAssessmentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 選択中のアセスメント
  String? _selectedAssessmentId;
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.childId == null) {
      return Center(
        child: Text('お子さまの情報がありません', style: TextStyle(color: context.colors.textSecondary)),
      );
    }

    // 詳細画面
    if (_selectedAssessmentId != null && _selectedType != null) {
      return _buildDetailScreen();
    }

    // 一覧画面
    return Column(
      children: [
        _buildHeader(),
        Container(
          color: context.colors.cardBg,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: context.colors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: '週次アセスメント'),
              Tab(text: '月次サマリ'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDateList(type: 'weekly'),
              _buildDateList(type: 'monthly'),
            ],
          ),
        ),
      ],
    );
  }

Widget _buildHeader({bool showBack = false}) {
  final hasMultipleChildren = widget.allChildren.length > 1;

  return Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      border: Border(bottom: BorderSide(color: context.colors.borderLight)),
    ),
    child: Row(
      children: [
        if (showBack) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: () => setState(() {
              _selectedAssessmentId = null;
              _selectedType = null;
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 子どもの名前
              if (showBack)
                // 詳細画面: 週次アセスメント or 月次サマリ
                Text(
                  _selectedType == 'weekly' ? '週次アセスメント' : '月次サマリ',
                  style: TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
                )
              else if (hasMultipleChildren)
                // 一覧画面（複数の子ども）: ドロップダウン
                PopupMenuButton<int>(
                  onSelected: (index) {
                    widget.onChildChanged?.call(index);
                  },
                  offset: const Offset(0, 40),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.childName}のアセスメント',
                        style: TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: context.colors.iconMuted),
                    ],
                  ),
                  itemBuilder: (context) {
                    return widget.allChildren.asMap().entries.map((entry) {
                      final index = entry.key;
                      final child = entry.value;
                      final firstName = child['firstName'] ?? '';
                      final photoUrl = child['photoUrl'];
                      final isSelected = index == widget.selectedChildIndex;

                      return PopupMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.primary.withOpacity(0.1),
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? const Icon(Icons.person, size: 14, color: AppColors.primary)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              firstName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (isSelected) ...[
                              const Spacer(),
                              const Icon(Icons.check, color: AppColors.primary, size: 18),
                            ],
                          ],
                        ),
                      );
                    }).toList();
                  },
                )
              else
                // 一覧画面（子ども1人）: シンプルなテキスト
                Text(
                  '${widget.childName}のアセスメント',
                  style: TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        if (showBack) const SizedBox(width: 48),
      ],
    ),
  );
}

  /// 日付一覧
  Widget _buildDateList({required String type}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assessments')
          .where('studentId', isEqualTo: widget.childId)
          .where('type', isEqualTo: type)
          .where('isPublished', isEqualTo: true)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'データの取得に失敗しました\n${snapshot.error}',
                style: TextStyle(color: AppColors.error, fontSize: AppTextSize.small),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == 'weekly' ? Icons.assignment_outlined : Icons.summarize_outlined,
                  size: 64,
                  color: context.colors.borderMedium,
                ),
                SizedBox(height: 16),
                Text(
                  type == 'weekly' ? '週次アセスメントはまだありません' : '月次サマリはまだありません',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildDateCard(doc.id, data, type);
          },
        );
      },
    );
  }

  /// 日付カード
  Widget _buildDateCard(String docId, Map<String, dynamic> data, String type) {
    final date = (data['date'] as Timestamp).toDate();
    String dateStr;
    if (type == 'weekly') {
      dateStr = DateFormat('yyyy年M月d日(E)', 'ja').format(date);
    } else {
      dateStr = DateFormat('yyyy年 M月', 'ja').format(date);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.borderLight),
      ),
      child: ListTile(
        onTap: () => setState(() {
          _selectedAssessmentId = docId;
          _selectedType = type;
        }),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            type == 'weekly' ? Icons.edit_calendar : Icons.assessment,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          dateStr,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLarge),
        ),
        trailing: Icon(Icons.chevron_right, color: context.colors.iconMuted),
      ),
    );
  }

  /// 詳細画面
  Widget _buildDetailScreen() {
    return GestureDetector(
      // 右方向（左→右）に大きくスワイプしたら一覧に戻る（iOS風スワイプバック）
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 300) {
          setState(() {
            _selectedAssessmentId = null;
            _selectedType = null;
          });
        }
      },
      child: Column(
      children: [
        _buildHeader(showBack: true),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('assessments')
                .doc(_selectedAssessmentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data == null) {
                return const Center(child: Text('データが見つかりません'));
              }

              if (_selectedType == 'weekly') {
                return _buildWeeklyDetail(data);
              } else {
                return _buildMonthlyDetail(data);
              }
            },
          ),
        ),
      ],
      ),
    );
  }

  /// 週次詳細
  Widget _buildWeeklyDetail(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp).toDate();
    final dateStr = DateFormat('yyyy年M月d日(E)', 'ja').format(date);
    final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日付ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // 活動リスト
          ...entries.map((entry) => _buildWeeklyEntryCard(entry)),
          
          if (entries.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('活動記録がありません', style: TextStyle(color: context.colors.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeeklyEntryCard(Map<String, dynamic> entry) {
    final tool = entry['tool'] ?? '';
    final rating = entry['rating'] ?? '';
    final duration = entry['duration'] ?? '';
    final comment = entry['comment'] ?? '';
    final photoUrl = entry['photoUrl'] as String?;
    final task = entry['task'] ?? '';
    // mediaItems があればそちら、なければ photoUrl を1件として表示
    final List<Map<String, dynamic>> mediaItems = [];
    final rawMedia = entry['mediaItems'] as List<dynamic>?;
    if (rawMedia != null && rawMedia.isNotEmpty) {
      for (final m in rawMedia) {
        if (m is Map) mediaItems.add({'type': m['type'] ?? 'image', 'url': m['url']});
      }
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      mediaItems.add({'type': 'image', 'url': photoUrl});
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 教具名
            Text(
              tool,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm),
            ),
            const SizedBox(height: 12),
            // タスク
            if (task.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(task, style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary)),
              ),
            
            // 評価と時間
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Text('評価: $rating', style: TextStyle(fontSize: AppTextSize.small))),
                if (duration.toString().isNotEmpty)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.timer_outlined, size: 14, color: context.colors.iconMuted), SizedBox(width: 4), Text(duration.toString(), style: TextStyle(fontSize: AppTextSize.small))])),
              ],
            ),
            
            // コメント
            if (comment.isNotEmpty) ...[
              SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.tagBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(comment, style: TextStyle(fontSize: AppTextSize.bodyMd, height: 1.5)),
              ),
            ],
            
            // 写真・動画
            if (mediaItems.isNotEmpty) ...[
              SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final tileWidth = (constraints.maxWidth - spacing) / 2;
                  final tileHeight = tileWidth * 0.75;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: mediaItems.map((m) {
                      final url = m['url'] as String?;
                      if (url == null || url.isEmpty) return const SizedBox.shrink();
                      if (m['type'] == 'video') {
                        return GestureDetector(
                          onTap: () => _showVideoPreview(url),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: tileWidth, height: tileHeight,
                              color: Colors.black87,
                              alignment: Alignment.center,
                              child: Stack(
                                alignment: Alignment.center,
                                children: const [
                                  Icon(Icons.videocam, color: Colors.white24, size: 56),
                                  Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      return GestureDetector(
                        onTap: () => _showImagePreview(url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            width: tileWidth, height: tileHeight, fit: BoxFit.cover,
                            placeholder: (c, u) => Container(width: tileWidth, height: tileHeight, color: context.colors.chipBg, child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                            errorWidget: (c, u, e) => Container(width: tileWidth, height: tileHeight, color: context.colors.borderLight, child: const Icon(Icons.broken_image)),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 月次詳細
  Widget _buildMonthlyDetail(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp).toDate();
    final dateStr = DateFormat('yyyy年 M月', 'ja').format(date);
    final summary = data['summary'] ?? '';
    final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
    final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // 非認知能力リスト
          if (monthlyEntries.isNotEmpty) ...[
            const Text(
              '非認知能力・伸びている力',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLarge, color: AppColors.primary),
            ),
            SizedBox(height: 12),
            ...monthlyEntries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${e['category'] ?? ''}: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: e['skill'] ?? ''),
                        ],
                      ),
                      style: TextStyle(fontSize: AppTextSize.bodyMd),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),
          ],

          // 敏感期
          if (sensitivePeriods.isNotEmpty) ...[
            const Text(
              '敏感期',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLarge, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sensitivePeriods.map((tag) => Chip(
                label: Text(tag, style: TextStyle(fontSize: AppTextSize.small, color: Colors.white)),
                backgroundColor: AppColors.success,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],
          
          // 総評
          const Text(
            '今月の様子・総評',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLarge, color: AppColors.primary),
          ),
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.tagBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              summary.isEmpty ? 'なし' : summary,
              style: TextStyle(height: 1.6, fontSize: AppTextSize.bodyLarge),
            ),
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
                // 画像（ピンチズーム + 下スワイプで閉じる）
                _SwipeDownToDismiss(
                  onDismiss: () => Navigator.pop(dialogContext),
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (c, u) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (c, u, e) => const Icon(
                          Icons.broken_image, color: Colors.white, size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
                // 上部バー（閉じる・保存）
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
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                          IconButton(
                            icon: isSaving
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download, color: Colors.white, size: 28),
                            tooltip: '保存',
                            onPressed: isSaving
                                ? null
                                : () async {
                                    setDialogState(() => isSaving = true);
                                    await _downloadImage(url, dialogContext);
                                    if (dialogContext.mounted) {
                                      setDialogState(() => isSaving = false);
                                    }
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

  Future<void> _downloadImage(String url, BuildContext dialogContext) async {
    if (kIsWeb) {
      // Web: アンカー要素でダウンロード
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      return;
    }
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
            AppFeedback.info(context, "写真へのアクセスが許可されていません");
          }
          return;
        }
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = "beesmiley_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final file = File("${tempDir.path}/$fileName");
        await file.writeAsBytes(response.bodyBytes);
        await Gal.putImage(file.path, album: "Beesmiley");
        await file.delete();
        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
          AppFeedback.success(context, "写真を保存しました");
        }
      }
    } catch (e) {
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
        AppFeedback.error(context, "保存に失敗しました: $e");
      }
    }
  }

  void _showVideoPreview(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => _AssessmentVideoDialog(url: url),
    );
  }
}

class _AssessmentVideoDialog extends StatefulWidget {
  final String url;
  const _AssessmentVideoDialog({required this.url});

  @override
  State<_AssessmentVideoDialog> createState() => _AssessmentVideoDialogState();
}

class _AssessmentVideoDialogState extends State<_AssessmentVideoDialog> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isSaving = false;
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

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _save() async {
    if (kIsWeb) {
      await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) {
            AppFeedback.info(context, "写真へのアクセスが許可されていません");
          }
          return;
        }
      }
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = "beesmiley_${DateTime.now().millisecondsSinceEpoch}.mp4";
        final file = File("${tempDir.path}/$fileName");
        await file.writeAsBytes(response.bodyBytes);
        await Gal.putVideo(file.path, album: "Beesmiley");
        await file.delete();
        if (mounted) {
          AppFeedback.success(context, "動画を保存しました");
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, "保存に失敗しました: $e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
                ? Text('再生できません: $_error', style: const TextStyle(color: Colors.white))
                : !_initialized || _controller == null
                    ? const CircularProgressIndicator(color: Colors.white)
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
                            Container(
                              color: Colors.black45,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                      _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Expanded(
                                    child: ValueListenableBuilder<VideoPlayerValue>(
                                      valueListenable: _controller!,
                                      builder: (_, value, __) {
                                        final total = value.duration;
                                        final pos = value.position;
                                        return Row(
                                          children: [
                                            Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: AppTextSize.small)),
                                            Expanded(
                                              child: Slider(
                                                value: pos.inMilliseconds.toDouble().clamp(0, total.inMilliseconds.toDouble()),
                                                max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                                                onChanged: (v) {
                                                  _controller!.seekTo(Duration(milliseconds: v.toInt()));
                                                },
                                                activeColor: Colors.white,
                                                inactiveColor: Colors.white24,
                                              ),
                                            ),
                                            Text(_fmt(total), style: const TextStyle(color: Colors.white, fontSize: AppTextSize.small)),
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
            top: 8, left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: _isSaving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download, color: Colors.white, size: 28),
              tooltip: '保存',
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// 下スワイプで閉じるラッパー。子要素ごと垂直方向に追従させ、
/// 一定距離以上スワイプ or 速度が出たら onDismiss を呼ぶ。
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