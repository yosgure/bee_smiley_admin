import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'main.dart';

// ============================================================
// 議事録・研修記録 一覧
// ============================================================
class MeetingMinutesScreen extends StatefulWidget {
  const MeetingMinutesScreen({super.key});

  @override
  State<MeetingMinutesScreen> createState() => _MeetingMinutesScreenState();
}

class _MeetingMinutesScreenState extends State<MeetingMinutesScreen> {
  String? _categoryFilter;
  String? _selectedDocId;

  // ビルド毎に Stream を再生成すると StreamBuilder が再購読して
  // 一瞬 waiting 状態（チカチカ）になるので、State に保持して使い回す。
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _docsStream =
      FirebaseFirestore.instance
          .collection('meeting_minutes')
          .orderBy('meetingDate', descending: true)
          .limit(300)
          .snapshots();

  void _close() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      AdminShell.hideOverlay(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('議事録・研修記録',
            style: TextStyle(
                fontSize: AppTextSize.title, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: _close),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const MeetingMinutesEditScreen()));
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新規作成',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _docsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return Center(
                child: Text('読み込みエラー: ${snap.error}',
                    style: TextStyle(color: context.colors.textSecondary)));
          }
          final allDocs = snap.data?.docs ?? [];
          final counts = <String, int>{};
          for (final d in allDocs) {
            final c = d.data()['category'] as String? ?? 'other';
            counts[c] = (counts[c] ?? 0) + 1;
          }
          final filtered = _categoryFilter == null
              ? allDocs
              : allDocs
                  .where((d) => d.data()['category'] == _categoryFilter)
                  .toList();
          // 選択 doc が現在のフィルタに居ない場合は解除
          QueryDocumentSnapshot<Map<String, dynamic>>? selectedDoc;
          for (final d in filtered) {
            if (d.id == _selectedDocId) {
              selectedDoc = d;
              break;
            }
          }

          return LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 200,
                    child: _categoryRail(counts, allDocs.length),
                  ),
                  VerticalDivider(
                      width: 1, color: context.colors.borderLight),
                  SizedBox(
                    width: 380,
                    child: _list(filtered),
                  ),
                  VerticalDivider(
                      width: 1, color: context.colors.borderLight),
                  Expanded(child: _detail(selectedDoc)),
                ],
              );
            }
            // 狭い画面: ドロップダウン + 一覧（タップで編集画面）
            return Column(
              children: [
                _categoryDropdown(),
                const Divider(height: 1),
                Expanded(child: _list(filtered, narrow: true)),
              ],
            );
          });
        },
      ),
    );
  }

  // ---- 左ペイン: 種別ナビ ----
  Widget _categoryRail(Map<String, int> counts, int total) {
    final c = context.colors;
    final all = MeetingCategory.all;
    return Container(
      color: c.cardBg,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _railTile(label: 'すべて', count: total, value: null),
          const SizedBox(height: 4),
          for (final cat in all)
            _railTile(
                label: cat.label,
                count: counts[cat.id] ?? 0,
                value: cat.id),
        ],
      ),
    );
  }

  Widget _railTile(
      {required String label, required int count, required String? value}) {
    final c = context.colors;
    final selected = _categoryFilter == value;
    return InkWell(
      onTap: () => setState(() {
        _categoryFilter = value;
        _selectedDocId = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.small,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : c.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text('$count',
                style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: selected ? AppColors.primary : c.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ---- 狭い画面用ドロップダウン ----
  Widget _categoryDropdown() {
    return Container(
      color: context.colors.cardBg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _categoryFilter,
            isExpanded: true,
            icon: Icon(Icons.expand_more,
                color: context.colors.textSecondary),
            style: TextStyle(
                fontSize: AppTextSize.body,
                color: context.colors.textPrimary),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('種類: すべて')),
              ...MeetingCategory.all.map((c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.label),
                  )),
            ],
            onChanged: (v) => setState(() => _categoryFilter = v),
          ),
        ),
      ),
    );
  }

  // ---- 中央ペイン: 一覧 ----
  Widget _list(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {bool narrow = false}) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 56, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text('記録はありません',
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: AppTextSize.bodyMd)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
      itemCount: docs.length,
      itemBuilder: (c, i) {
        final doc = docs[i];
        return _MeetingListTile(
          doc: doc,
          selected: !narrow && doc.id == _selectedDocId,
          compact: !narrow,
          onTap: () {
            if (narrow) {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MeetingMinutesEditScreen(doc: doc),
                  ));
            } else {
              setState(() => _selectedDocId = doc.id);
            }
          },
        );
      },
    );
  }

  // ---- 右ペイン: 詳細 ----
  Widget _detail(QueryDocumentSnapshot<Map<String, dynamic>>? doc) {
    if (doc == null) {
      return Container(
        color: context.colors.scaffoldBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 56, color: context.colors.textTertiary),
              const SizedBox(height: 12),
              Text('左の一覧から記録を選択してください',
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: AppTextSize.body)),
            ],
          ),
        ),
      );
    }
    return _MeetingDetailView(doc: doc);
  }
}

class _MeetingListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  const _MeetingListTile({
    required this.doc,
    this.selected = false,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final date = (d['meetingDate'] as Timestamp?)?.toDate();
    final category = d['category'] as String? ?? 'other';
    final categoryOther = (d['categoryOther'] as String? ?? '').trim();
    final note = (d['note'] as String? ?? '').trim();
    final participantNames = List<String>.from(d['participantNames'] ?? []);
    final content = d['content'] as String? ?? '';
    final materials = List<String>.from(d['materials'] ?? []);

    final categoryLabel = category == 'other' && categoryOther.isNotEmpty
        ? categoryOther
        : MeetingCategory.labelOf(category);

    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.12)
            : c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : c.borderLight,
          width: selected ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    date != null
                        ? DateFormat('yyyy/M/d (E)', 'ja').format(date)
                        : '',
                    style: TextStyle(
                        fontSize: AppTextSize.small,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(categoryLabel,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppTextSize.caption,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const Spacer(),
                  if (materials.isNotEmpty)
                    Row(children: [
                      Icon(Icons.attach_file,
                          size: 12, color: c.textTertiary),
                      const SizedBox(width: 2),
                      Text('${materials.length}',
                          style: TextStyle(
                              fontSize: AppTextSize.caption,
                              color: c.textTertiary)),
                    ]),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(note,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600)),
              ],
              if (!compact && participantNames.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '参加: ${participantNames.join('、')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppTextSize.caption, color: c.textTertiary),
                ),
              ],
              if (!compact && content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  content.length > 140
                      ? '${content.substring(0, 140)}…'
                      : content,
                  style: TextStyle(
                      fontSize: AppTextSize.small,
                      color: c.textSecondary,
                      height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 詳細ビュー（右ペイン）
// ============================================================
class _MeetingDetailView extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _MeetingDetailView({required this.doc});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = doc.data();
    final date = (d['meetingDate'] as Timestamp?)?.toDate();
    final category = d['category'] as String? ?? 'other';
    final categoryOther = (d['categoryOther'] as String? ?? '').trim();
    final note = (d['note'] as String? ?? '').trim();
    final participantNames = List<String>.from(d['participantNames'] ?? []);
    final content = d['content'] as String? ?? '';
    final materials = List<String>.from(d['materials'] ?? []);

    final categoryLabel = category == 'other' && categoryOther.isNotEmpty
        ? categoryOther
        : MeetingCategory.labelOf(category);

    return Container(
      color: c.scaffoldBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ヘッダー
          Container(
            color: c.cardBg,
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            date != null
                                ? DateFormat('yyyy/M/d (E)', 'ja')
                                    .format(date)
                                : '',
                            style: TextStyle(
                              fontSize: AppTextSize.bodyLarge,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(categoryLabel,
                                style: const TextStyle(
                                    fontSize: AppTextSize.caption,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(note,
                            style: TextStyle(
                                fontSize: AppTextSize.bodyLarge,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MeetingMinutesEditScreen(doc: doc),
                        ));
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('編集'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle:
                        const TextStyle(fontSize: AppTextSize.small),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.borderLight),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (participantNames.isNotEmpty) ...[
                    _sectionLabel(context, '参加者'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in participantNames)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.chipBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(n,
                                style: TextStyle(
                                    fontSize: AppTextSize.caption,
                                    color: c.textPrimary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _sectionLabel(context, '内容'),
                  const SizedBox(height: 6),
                  if (content.isEmpty)
                    Text('（記載なし）',
                        style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: c.textTertiary,
                            fontStyle: FontStyle.italic))
                  else
                    SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: c.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  if (materials.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel(context, '資料'),
                    const SizedBox(height: 6),
                    for (final raw in materials)
                      _materialTile(context, raw),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(label,
        style: TextStyle(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w700,
          color: context.colors.textSecondary,
          letterSpacing: 0.3,
        ));
  }

  Widget _materialTile(BuildContext context, String raw) {
    final m = _Material.fromRaw(raw);
    final c = context.colors;
    final display = m.label.isNotEmpty ? m.label : m.url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final uri = Uri.tryParse(m.url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.attach_file, size: 16, color: c.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(display,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTextSize.body,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 編集画面
// ============================================================
class MeetingMinutesEditScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const MeetingMinutesEditScreen({super.key, this.doc});

  @override
  State<MeetingMinutesEditScreen> createState() => _MeetingMinutesEditScreenState();
}

class _MeetingMinutesEditScreenState extends State<MeetingMinutesEditScreen> {
  DateTime _meetingDate = DateTime.now();
  String _category = MeetingCategory.all.first.id;
  final List<_Staff> _participants = [];
  final _contentCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _categoryOtherCtrl = TextEditingController();
  final List<_Material> _materials = [];
  bool _saving = false;
  bool _uploading = false;

  List<_Staff> _allStaffs = [];

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    _loadStaffs();
    if (widget.doc != null) {
      final d = widget.doc!.data();
      _meetingDate = (d['meetingDate'] as Timestamp?)?.toDate() ?? DateTime.now();
      _category = (d['category'] as String?) ?? MeetingCategory.all.first.id;
      _categoryOtherCtrl.text = d['categoryOther'] ?? '';
      _contentCtrl.text = d['content'] ?? '';
      _noteCtrl.text = d['note'] ?? '';
      final rawMats = List<String>.from(d['materials'] ?? []);
      _materials.addAll(rawMats.map(_Material.fromRaw));
    }
  }

  Future<void> _loadStaffs() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('staffs').get();
      final list = <_Staff>[];
      for (final d in snap.docs) {
        final data = d.data();
        final name = (data['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        list.add(_Staff(id: d.id, name: name, kana: (data['kana'] as String? ?? '').trim()));
      }
      list.sort((a, b) => a.kana.compareTo(b.kana));
      if (!mounted) return;
      setState(() {
        _allStaffs = list;
        if (widget.doc != null) {
          final d = widget.doc!.data();
          final ids = List<String>.from(d['participantIds'] ?? []);
          _participants
            ..clear()
            ..addAll(list.where((s) => ids.contains(s.id)));
        }
      });
    } catch (e) {
      debugPrint('Error loading staffs: $e');
    }
  }

  @override
  void dispose() {
    for (final c in [_contentCtrl, _noteCtrl, _categoryOtherCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit => _contentCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'meetingDate': Timestamp.fromDate(_meetingDate),
      'category': _category,
      'categoryOther': _category == 'other' ? _categoryOtherCtrl.text.trim() : '',
      'note': _noteCtrl.text.trim(),
      'participantIds': _participants.map((s) => s.id).toList(),
      'participantNames': _participants.map((s) => s.name).toList(),
      'content': _contentCtrl.text.trim(),
      'materials': _materials.map((m) => m.toStorage()).toList(),
      'updatedAt': now,
    };
    try {
      if (_isEdit) {
        await widget.doc!.reference.update(data);
      } else {
        data['createdAt'] = now;
        data['createdBy'] = user?.uid ?? '';
        await FirebaseFirestore.instance.collection('meeting_minutes').add(data);
      }
      if (mounted) {
        AppFeedback.success(context, _isEdit ? '更新しました' : '登録しました');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '保存失敗: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await AppFeedback.confirm(
      context,
      title: 'この記録を削除しますか？',
      message: 'この操作は取り消せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.doc!.reference.delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppFeedback.info(context, '削除失敗: $e');
      }
    }
  }

  Future<void> _pickParticipants() async {
    final result = await showDialog<List<_Staff>>(
      context: context,
      builder: (c) => _StaffMultiPickerDialog(all: _allStaffs, initial: _participants),
    );
    if (result != null) {
      setState(() {
        _participants
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _addMaterial() async {
    final result = await showDialog<_Material>(
      context: context,
      builder: (c) => const _MaterialDialog(),
    );
    if (result != null) setState(() => _materials.add(result));
  }

  Future<void> _uploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeName = f.name.replaceAll(RegExp(r'[\s/\\]'), '_');
        final ref = FirebaseStorage.instance
            .ref('meeting_minutes/$ts-$safeName');
        await ref.putData(bytes);
        final url = await ref.getDownloadURL();
        setState(() => _materials.add(_Material(label: f.name, url: url)));
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'アップロード失敗: $e');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editMaterial(int i) async {
    final result = await showDialog<_Material>(
      context: context,
      builder: (c) => _MaterialDialog(initial: _materials[i]),
    );
    if (result != null) {
      setState(() {
        if (result.label.isEmpty && result.url.isEmpty) {
          _materials.removeAt(i);
        } else {
          _materials[i] = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? '議事録・研修記録を編集' : '議事録・研修記録を作成',
            style: const TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isEdit)
            IconButton(icon: Icon(Icons.delete_outline, color: AppColors.errorBorder), onPressed: _delete),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section('種類'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.borderMedium),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  icon: Icon(Icons.expand_more, color: context.colors.textSecondary),
                  style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textPrimary),
                  items: MeetingCategory.all
                      .map((c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(c.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
              ),
            ),
            if (_category == 'other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _categoryOtherCtrl,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('種類を入力', hint: '例：○○勉強会'),
              ),
            ],

            const SizedBox(height: 20),
            _section('実施日'),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _meetingDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _meetingDate = d);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.borderMedium),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(DateFormat('yyyy/M/d (E)', 'ja').format(_meetingDate),
                        style: TextStyle(fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            _section('参加者'),
            InkWell(
              onTap: _pickParticipants,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.borderMedium),
                ),
                child: _participants.isEmpty
                    ? Row(children: [
                        Icon(Icons.add_circle_outline, size: 18, color: context.colors.textSecondary),
                        const SizedBox(width: 8),
                        Text('参加者を選択', style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary)),
                      ])
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _participants
                            .map((s) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(s.name,
                                      style: const TextStyle(
                                          fontSize: AppTextSize.small, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                      ),
              ),
            ),

            const SizedBox(height: 20),
            _section('内容'),
            TextField(
              controller: _contentCtrl,
              maxLines: 14,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: '研修内容・議事内容'),
            ),

            const SizedBox(height: 20),
            _section('資料'),
            ..._materials.asMap().entries.map((e) => _materialTile(e.key, e.value)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _uploadFiles,
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file, size: 18),
                    label: Text(_uploading ? 'アップロード中…' : 'ファイルをアップロード'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addMaterial,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('URLを追加'),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _section('備考（任意）'),
            TextField(
              controller: _noteCtrl,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: '一覧で表示するメモ'),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_canSubmit && !_saving) ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isEdit ? '更新' : '登 録',
                      style: const TextStyle(fontSize: AppTextSize.bodyLarge, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _materialTile(int i, _Material m) {
    final hasUrl = m.url.startsWith('http');
    final noUrl = m.url.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          hasUrl ? Icons.link : Icons.insert_drive_file_outlined,
          size: 18,
          color: hasUrl ? AppColors.primary : context.colors.textSecondary,
        ),
        title: Text(m.label.isNotEmpty ? m.label : m.url,
            style: const TextStyle(fontSize: AppTextSize.body), overflow: TextOverflow.ellipsis),
        subtitle: noUrl
            ? Text('URL未設定（タップで設定）',
                style: TextStyle(fontSize: AppTextSize.caption, color: AppColors.warning))
            : (m.label.isNotEmpty
                ? Text(m.url,
                    style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textTertiary),
                    overflow: TextOverflow.ellipsis)
                : null),
        onTap: () => _editMaterial(i),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasUrl)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 16),
                tooltip: '開く',
                onPressed: () async {
                  final uri = Uri.tryParse(m.url);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: AppColors.errorBorder),
              onPressed: () => setState(() => _materials.removeAt(i)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String? label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary),
      hintStyle: TextStyle(fontSize: AppTextSize.body, color: context.colors.textHint),
      filled: true,
      fillColor: context.colors.cardBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.colors.borderLight),
      ),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: TextStyle(fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
      );

}

// ============================================================
// 資料モデル + ダイアログ
// ============================================================
class _Material {
  final String label;
  final String url;
  const _Material({required this.label, required this.url});

  // Firestore保存形式は "label|url"（labelなしなら url のみ）
  String toStorage() => label.isEmpty ? url : '$label|$url';

  factory _Material.fromRaw(String raw) {
    if (raw.contains('|')) {
      final i = raw.indexOf('|');
      return _Material(label: raw.substring(0, i), url: raw.substring(i + 1));
    }
    return _Material(label: '', url: raw);
  }
}

class _MaterialDialog extends StatefulWidget {
  final _Material? initial;
  const _MaterialDialog({this.initial});
  @override
  State<_MaterialDialog> createState() => _MaterialDialogState();
}

class _MaterialDialogState extends State<_MaterialDialog> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _url = TextEditingController(text: widget.initial?.url ?? '');

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '資料を追加' : '資料を編集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'タイトル（任意）'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL / ファイル名'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        TextButton(
          onPressed: () {
            Navigator.pop(context, _Material(label: _label.text.trim(), url: _url.text.trim()));
          },
          child: const Text('OK', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ============================================================
// 参加者選択（複数）
// ============================================================
class _StaffMultiPickerDialog extends StatefulWidget {
  final List<_Staff> all;
  final List<_Staff> initial;
  const _StaffMultiPickerDialog({required this.all, required this.initial});
  @override
  State<_StaffMultiPickerDialog> createState() => _StaffMultiPickerDialogState();
}

class _StaffMultiPickerDialogState extends State<_StaffMultiPickerDialog> {
  late final Set<String> _selected = widget.initial.map((s) => s.id).toSet();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = _q.isEmpty
        ? widget.all
        : widget.all
            .where((s) => s.name.toLowerCase().contains(_q.toLowerCase()) || s.kana.contains(_q))
            .toList();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('参加者を選択',
                      style: TextStyle(fontSize: AppTextSize.titleSm, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
                  const Spacer(),
                  Text('${_selected.length}名', style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '名前で検索',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final s = list[i];
                  final sel = _selected.contains(s.id);
                  return CheckboxListTile(
                    value: sel,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(s.id);
                      } else {
                        _selected.remove(s.id);
                      }
                    }),
                    title: Text(s.name, style: const TextStyle(fontSize: AppTextSize.bodyMd)),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                  TextButton(
                    onPressed: () {
                      final result = widget.all.where((s) => _selected.contains(s.id)).toList();
                      Navigator.pop(context, result);
                    },
                    child: const Text('決定', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// モデル
// ============================================================
class _Staff {
  final String id;
  final String name;
  final String kana;
  const _Staff({required this.id, required this.name, required this.kana});
}

class MeetingCategory {
  final String id;
  final String label;
  const MeetingCategory({required this.id, required this.label});

  static const all = <MeetingCategory>[
    MeetingCategory(id: 'overall_support_meeting', label: '全体支援会議'),
    MeetingCategory(id: 'abuse_committee', label: '虐待防止/身体拘束適正化委員会'),
    MeetingCategory(id: 'abuse_training', label: '虐待防止研修'),
    MeetingCategory(id: 'restraint_training', label: '身体的拘束適正化研修'),
    MeetingCategory(id: 'infection_committee', label: '感染防止対策委員会'),
    MeetingCategory(id: 'infection_training', label: '感染症・食中毒予防研修'),
    MeetingCategory(id: 'infection_drill', label: '感染症・食中毒予防訓練'),
    MeetingCategory(id: 'infection_bcp_training', label: '感染症BCP研修'),
    MeetingCategory(id: 'infection_bcp_drill', label: '感染症BCP訓練'),
    MeetingCategory(id: 'disaster_bcp_training', label: '自然災害BCP研修'),
    MeetingCategory(id: 'disaster_bcp_drill', label: '自然災害BCP訓練'),
    MeetingCategory(id: 'disaster_drill', label: '防災訓練'),
    MeetingCategory(id: 'practical_training', label: '実践研修'),
    MeetingCategory(id: 'liaison_meeting', label: '児童発達支援事業所連絡会'),
    MeetingCategory(id: 'other', label: 'その他'),
  ];

  static String labelOf(String id) {
    for (final c in all) {
      if (c.id == id) return c.label;
    }
    return 'その他';
  }
}
