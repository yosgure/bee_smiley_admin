import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
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
        title: const Text('議事録・研修記録', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
      body: Column(
        children: [
          Container(
            color: context.colors.cardBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(null, '全て'),
                  const SizedBox(width: 6),
                  ...MeetingCategory.all.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _filterChip(c.id, c.label),
                      )),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _filterChip(String? value, String label) {
    final sel = _categoryFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _categoryFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary.withValues(alpha: 0.15) : context.colors.chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? AppColors.primary : context.colors.textSecondary,
            )),
      ),
    );
  }

  Widget _buildList() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('meeting_minutes')
        .orderBy('meetingDate', descending: true)
        .limit(300);
    if (_categoryFilter != null) q = q.where('category', isEqualTo: _categoryFilter);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
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
                Text('記録はありません', style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
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
    final category = d['category'] as String? ?? 'other';
    final note = (d['note'] as String? ?? '').trim();
    final participantNames = List<String>.from(d['participantNames'] ?? []);
    final conductor = d['conductor'] as String? ?? '';
    final location = d['location'] as String? ?? '';
    final content = d['content'] as String? ?? '';
    final materials = List<String>.from(d['materials'] ?? []);

    final categoryLabel = MeetingCategory.labelOf(category);

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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(categoryLabel,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  if (materials.isNotEmpty)
                    Row(children: [
                      Icon(Icons.attach_file, size: 12, color: context.colors.textTertiary),
                      const SizedBox(width: 2),
                      Text('${materials.length}',
                          style: TextStyle(fontSize: 11, color: context.colors.textTertiary)),
                    ]),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(note,
                    style: TextStyle(fontSize: 13, color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
              ],
              if (conductor.isNotEmpty || location.isNotEmpty || participantNames.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (conductor.isNotEmpty) '実施者: $conductor',
                    if (location.isNotEmpty) '場所: $location',
                    if (participantNames.isNotEmpty) '参加: ${participantNames.join('、')}',
                  ].join('　'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
                ),
              ],
              if (content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  content.length > 140 ? '${content.substring(0, 140)}…' : content,
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
  final _conductorCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final List<_Material> _materials = [];
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
      _category = (d['category'] as String?) ?? MeetingCategory.all.first.id;
      _conductorCtrl.text = d['conductor'] ?? '';
      _locationCtrl.text = d['location'] ?? '';
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
    for (final c in [_conductorCtrl, _locationCtrl, _contentCtrl, _noteCtrl]) {
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
      'note': _noteCtrl.text.trim(),
      'participantIds': _participants.map((s) => s.id).toList(),
      'participantNames': _participants.map((s) => s.name).toList(),
      'conductor': _conductorCtrl.text.trim(),
      'location': _locationCtrl.text.trim(),
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
        title: const Text('この記録を削除しますか？'),
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

  Future<void> _addMaterial() async {
    final result = await showDialog<_Material>(
      context: context,
      builder: (c) => const _MaterialDialog(),
    );
    if (result != null) setState(() => _materials.add(result));
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
            _section('種類'),
            _chipGroup(
              options: MeetingCategory.all.map((c) => (id: c.id, label: c.label)).toList(),
              selected: {_category},
              onToggle: (id) => setState(() => _category = id),
            ),

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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _conductorCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration('実施者'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _locationCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration('開催場所'),
                  ),
                ),
              ],
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
            OutlinedButton.icon(
              onPressed: _addMaterial,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('資料を追加'),
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialTile(int i, _Material m) {
    final hasUrl = m.url.startsWith('http');
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
            style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
        subtitle: m.label.isNotEmpty && m.url.isNotEmpty
            ? Text(m.url,
                style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
                overflow: TextOverflow.ellipsis)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasUrl)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 16),
                onPressed: () async {
                  final uri = Uri.tryParse(m.url);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editMaterial(i),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
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
