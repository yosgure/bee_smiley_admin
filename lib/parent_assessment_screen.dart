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
import 'app_theme.dart';
import 'skeleton_loading.dart';

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
              // 顔写真
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: widget.childPhotoUrl != null && widget.childPhotoUrl!.isNotEmpty
                    ? NetworkImage(widget.childPhotoUrl!)
                    : null,
                child: widget.childPhotoUrl == null || widget.childPhotoUrl!.isEmpty
                    ? const Icon(Icons.person, size: 20, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 10),
              
              // 子どもの名前
              if (showBack)
                // 詳細画面: 週次アセスメント or 月次サマリ
                Text(
                  _selectedType == 'weekly' ? '週次アセスメント' : '月次サマリ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                style: TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return const AssessmentSkeleton();
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

    // サブタイトル
    String subtitle = '';
    if (type == 'weekly') {
      final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      subtitle = '${entries.length}件の活動';
    } else {
      final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);
      final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
      subtitle = '${monthlyEntries.length}項目の評価・${sensitivePeriods.length}つの敏感期';
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        trailing: Icon(Icons.chevron_right, color: context.colors.iconMuted),
      ),
    );
  }

  /// 詳細画面
  Widget _buildDetailScreen() {
    return Column(
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
                return const AssessmentSkeleton();
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
            Row(
              children: [
                const Icon(Icons.extension, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tool,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // タスク
            if (task.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(task, style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
              ),
            
            // 評価と時間
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Text('評価: $rating', style: TextStyle(fontSize: 12))),
                if (duration.toString().isNotEmpty)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.timer_outlined, size: 14, color: context.colors.iconMuted), SizedBox(width: 4), Text(duration.toString(), style: TextStyle(fontSize: 12))])),
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
                child: Text(comment, style: TextStyle(fontSize: 14, height: 1.5)),
              ),
            ],
            
            // 写真・動画
            if (mediaItems.isNotEmpty) ...[
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: mediaItems.map((m) {
                  final url = m['url'] as String?;
                  if (url == null || url.isEmpty) return const SizedBox.shrink();
                  if (m['type'] == 'video') {
                    return GestureDetector(
                      onTap: () => _launchUrl(url),
                      child: Container(
                        width: 160, height: 120,
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                      ),
                    );
                  }
                  return GestureDetector(
                    onTap: () => _showImagePreview(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: 160, height: 120, fit: BoxFit.cover,
                        placeholder: (c, u) => Container(width: 160, height: 120, color: context.colors.chipBg, child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                        errorWidget: (c, u, e) => Container(width: 160, height: 120, color: context.colors.borderLight, child: const Icon(Icons.broken_image)),
                      ),
                    ),
                  );
                }).toList(),
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
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
                      style: TextStyle(fontSize: 14),
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sensitivePeriods.map((tag) => Chip(
                label: Text(tag, style: TextStyle(fontSize: 12, color: Colors.white)),
                backgroundColor: Colors.green,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],
          
          // 総評
          const Text(
            '今月の様子・総評',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
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
              style: TextStyle(height: 1.6, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                // 画像（ピンチズーム対応）
                Center(
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("写真へのアクセスが許可されていません")),
            );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("写真を保存しました"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("保存に失敗しました: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}