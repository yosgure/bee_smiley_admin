import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'main.dart';

// ============================================================
// 議事録一覧
// ============================================================
class MeetingMinutesScreen extends StatefulWidget {
  const MeetingMinutesScreen({super.key});

  @override
  State<MeetingMinutesScreen> createState() => _MeetingMinutesScreenState();
}

class _MeetingMinutesScreenState extends State<MeetingMinutesScreen> {
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
        title: const Text('議事録', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: _close),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MeetingMinutesEditScreen()));
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新規作成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('meeting_minutes')
            .orderBy('meetingDate', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return Center(child: Text('読み込みエラー: ${snap.error}', style: TextStyle(color: context.colors.textSecondary)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 56, color: context.colors.textTertiary),
                  const SizedBox(height: 12),
                  Text('議事録はまだありません', style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('右下の「新規作成」から記録できます', style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('NotionのURLを貼って過去議事録を登録できます', style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
            itemCount: docs.length,
            itemBuilder: (c, i) => _MeetingListTile(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _MeetingListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _MeetingListTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final date = (d['meetingDate'] as Timestamp?)?.toDate();
    final title = d['title'] as String? ?? '';
    final category = d['category'] as String? ?? '';
    final participantNames = List<String>.from(d['participantNames'] ?? []);
    final summary = d['summary'] as String? ?? '';
    final notionUrl = d['notionUrl'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => MeetingMinutesEditScreen(doc: doc),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    date != null ? DateFormat('yyyy/M/d (E)', 'ja').format(date) : '',
                    style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  if (category.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(MeetingOptions.labelOf(MeetingOptions.category, category),
                          style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                    ),
                  const Spacer(),
                  if (notionUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.tryParse(notionUrl);
                        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new, size: 12, color: AppColors.primary),
                            SizedBox(width: 3),
                            Text('Notion', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title.isEmpty ? '(タイトル未設定)' : title,
                style: TextStyle(fontSize: 14, color: context.colors.textPrimary, fontWeight: FontWeight.w700),
              ),
              if (participantNames.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '参加: ${participantNames.join('、')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary.length > 100 ? '${summary.substring(0, 100)}…' : summary,
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
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
// 議事録 入力/編集
// ============================================================
class MeetingMinutesEditScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const MeetingMinutesEditScreen({super.key, this.doc});

  @override
  State<MeetingMinutesEditScreen> createState() => _MeetingMinutesEditScreenState();
}

class _MeetingMinutesEditScreenState extends State<MeetingMinutesEditScreen> {
  DateTime _meetingDate = DateTime.now();
  final _titleCtrl = TextEditingController();
  String _category = 'regular';
  final List<_Staff> _participants = [];
  final _agendaCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _decisionsCtrl = TextEditingController();
  final _todoCtrl = TextEditingController();
  final _notionCtrl = TextEditingController();
  bool _saving = false;

  List<_Staff> _allStaffs = [];

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    _loadStaffs();
    if (widget.doc != null) {
      final d = widget.doc!.data();
      _meetingDate = (d['meetingDate'] as Timestamp?)?.toDate() ?? DateTime.now();
      _titleCtrl.text = d['title'] ?? '';
      _category = d['category'] ?? 'regular';
      _agendaCtrl.text = d['agenda'] ?? '';
      _summaryCtrl.text = d['summary'] ?? '';
      _decisionsCtrl.text = d['decisions'] ?? '';
      _todoCtrl.text = d['todo'] ?? '';
      _notionCtrl.text = d['notionUrl'] ?? '';
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
    for (final c in [_titleCtrl, _agendaCtrl, _summaryCtrl, _decisionsCtrl, _todoCtrl, _notionCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      _titleCtrl.text.trim().isNotEmpty ||
      _summaryCtrl.text.trim().isNotEmpty ||
      _notionCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'meetingDate': Timestamp.fromDate(_meetingDate),
      'title': _titleCtrl.text.trim(),
      'category': _category,
      'participantIds': _participants.map((s) => s.id).toList(),
      'participantNames': _participants.map((s) => s.name).toList(),
      'agenda': _agendaCtrl.text.trim(),
      'summary': _summaryCtrl.text.trim(),
      'decisions': _decisionsCtrl.text.trim(),
      'todo': _todoCtrl.text.trim(),
      'notionUrl': _notionCtrl.text.trim(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? '更新しました' : '登録しました'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この議事録を削除しますか？'),
        content: const Text('この操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.doc!.reference.delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除失敗: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? '議事録を編集' : '議事録作成',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isEdit)
            IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade400), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section('開催日'),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            _section('種類'),
            _chipGroup(
              options: MeetingOptions.category,
              selected: {_category},
              onToggle: (id) => setState(() => _category = id),
            ),

            const SizedBox(height: 20),
            _section('タイトル'),
            TextField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: '例：4月定例ミーティング'),
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
                        Text('参加者を選択', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
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
                                          fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                      ),
              ),
            ),

            const SizedBox(height: 20),
            _section('議題'),
            TextField(
              controller: _agendaCtrl,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: '例：シフト調整 / 利用児対応 ...'),
            ),

            const SizedBox(height: 20),
            _section('内容・サマリ'),
            TextField(
              controller: _summaryCtrl,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: '議事の要約'),
            ),

            const SizedBox(height: 20),
            _section('決定事項'),
            TextField(
              controller: _decisionsCtrl,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null),
            ),

            const SizedBox(height: 20),
            _section('ToDo / 次回までに'),
            TextField(
              controller: _todoCtrl,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null),
            ),

            const SizedBox(height: 20),
            _section('Notion原典リンク'),
            Text('過去の議事録はNotionのURLを貼って紐付けできます',
                style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
            const SizedBox(height: 6),
            TextField(
              controller: _notionCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(null, hint: 'https://www.notion.so/...'),
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
      labelStyle: TextStyle(fontSize: 13, color: context.colors.textSecondary),
      hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
      );

  Widget _chipGroup({
    required List<({String id, String label})> options,
    required Set<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSel = selected.contains(opt.id);
        return GestureDetector(
          onTap: () => onToggle(opt.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary.withValues(alpha: 0.15) : context.colors.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSel ? AppColors.primary : context.colors.borderMedium,
                width: isSel ? 1.5 : 0.8,
              ),
            ),
            child: Text(opt.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? AppColors.primary : context.colors.textPrimary,
                )),
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// 参加者選択ダイアログ（複数選択）
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
                  const Spacer(),
                  Text('${_selected.length}名', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
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
                    title: Text(s.name, style: const TextStyle(fontSize: 14)),
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
// モデル / 選択肢マスタ
// ============================================================
class _Staff {
  final String id;
  final String name;
  final String kana;
  const _Staff({required this.id, required this.name, required this.kana});
}

class MeetingOptions {
  static const List<({String id, String label})> category = [
    (id: 'regular', label: '定例'),
    (id: 'case', label: 'ケース会議'),
    (id: 'management', label: '運営'),
    (id: 'training', label: '研修'),
    (id: 'other', label: 'その他'),
  ];

  static String labelOf(List<({String id, String label})> list, String id) {
    for (final o in list) {
      if (o.id == id) return o.label;
    }
    return id;
  }
}
