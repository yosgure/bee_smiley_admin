import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'main.dart';

// ============================================================
// 苦情一覧画面
// ============================================================
class ComplaintScreen extends StatefulWidget {
  final VoidCallback? onClose;
  const ComplaintScreen({super.key, this.onClose});

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
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
        title: const Text('苦情受付', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: _close),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ComplaintEditScreen()));
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新規受付', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('complaint_reports')
            .orderBy('occurredAt', descending: true)
            .limit(100)
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
                  Icon(Icons.inbox_outlined, size: 56, color: context.colors.textTertiary),
                  const SizedBox(height: 12),
                  Text('受付記録はまだありません', style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('右下の「新規受付」から記録できます', style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
            itemCount: docs.length,
            itemBuilder: (c, i) => _ComplaintListTile(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ComplaintListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ComplaintListTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final occurredAt = (d['occurredAt'] as Timestamp?)?.toDate();
    final claimantName = d['claimantName'] as String? ?? '';
    final childName = d['childName'] as String? ?? '';
    final category = d['category'] as String? ?? '';
    final content = d['content'] as String? ?? '';
    final reporterToHq = d['reporterToHq'] as bool? ?? false;

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
            builder: (_) => ComplaintEditScreen(doc: doc),
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
                    occurredAt != null ? DateFormat('yyyy/M/d (E) HH:mm', 'ja').format(occurredAt) : '',
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
                      child: Text(ComplaintOptions.labelOf(ComplaintOptions.category, category),
                          style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                    ),
                  const Spacer(),
                  if (reporterToHq)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red, width: 0.5),
                      ),
                      child: const Text('本社報告', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '申出人: $claimantName${childName.isNotEmpty ? '　利用児: $childName' : ''}',
                style: TextStyle(fontSize: 13, color: context.colors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                content.length > 80 ? '${content.substring(0, 80)}…' : content,
                style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 苦情入力/編集画面
// ============================================================
class ComplaintEditScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const ComplaintEditScreen({super.key, this.doc});

  @override
  State<ComplaintEditScreen> createState() => _ComplaintEditScreenState();
}

class _ComplaintEditScreenState extends State<ComplaintEditScreen> {
  DateTime _occurredAt = DateTime.now();
  final _officeCtrl = TextEditingController(text: 'ビースマイリープラス湘南藤沢教室');
  final _reporterCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();
  final _claimantNameCtrl = TextEditingController();
  final _claimantKanaCtrl = TextEditingController();
  String _relation = 'mother';
  final _relationOtherCtrl = TextEditingController();
  final _childNameCtrl = TextEditingController();
  final _childKanaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _receiverCtrl = TextEditingController();
  TimeOfDay _receivedAt = TimeOfDay.now();
  TimeOfDay? _managerReportAt;
  String _category = 'staff';
  final _categoryOtherCtrl = TextEditingController();
  bool _reporterToHq = false;
  final _contentCtrl = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (widget.doc != null) {
      final d = widget.doc!.data();
      _occurredAt = (d['occurredAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      _officeCtrl.text = d['officeName'] ?? _officeCtrl.text;
      _reporterCtrl.text = d['reporterName'] ?? '';
      _managerCtrl.text = d['managerName'] ?? '';
      _claimantNameCtrl.text = d['claimantName'] ?? '';
      _claimantKanaCtrl.text = d['claimantKana'] ?? '';
      _relation = d['relation'] ?? 'mother';
      _relationOtherCtrl.text = d['relationOther'] ?? '';
      _childNameCtrl.text = d['childName'] ?? '';
      _childKanaCtrl.text = d['childKana'] ?? '';
      _addressCtrl.text = d['address'] ?? '';
      _phoneCtrl.text = d['phone'] ?? '';
      _receiverCtrl.text = d['receiverName'] ?? '';
      final rec = d['receivedAt'] as String?;
      if (rec != null && rec.contains(':')) {
        final parts = rec.split(':');
        _receivedAt = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
      final mr = d['managerReportAt'] as String?;
      if (mr != null && mr.contains(':')) {
        final parts = mr.split(':');
        _managerReportAt = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
      }
      _category = d['category'] ?? 'staff';
      _categoryOtherCtrl.text = d['categoryOther'] ?? '';
      _reporterToHq = d['reporterToHq'] ?? false;
      _contentCtrl.text = d['content'] ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _officeCtrl, _reporterCtrl, _managerCtrl, _claimantNameCtrl, _claimantKanaCtrl,
      _relationOtherCtrl, _childNameCtrl, _childKanaCtrl, _addressCtrl, _phoneCtrl,
      _receiverCtrl, _categoryOtherCtrl, _contentCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      _claimantNameCtrl.text.trim().isNotEmpty &&
      _contentCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    final now = FieldValue.serverTimestamp();
    String tt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final data = <String, dynamic>{
      'occurredAt': Timestamp.fromDate(_occurredAt),
      'officeName': _officeCtrl.text.trim(),
      'reporterName': _reporterCtrl.text.trim(),
      'managerName': _managerCtrl.text.trim(),
      'claimantName': _claimantNameCtrl.text.trim(),
      'claimantKana': _claimantKanaCtrl.text.trim(),
      'relation': _relation,
      'relationOther': _relation == 'other' ? _relationOtherCtrl.text.trim() : '',
      'childName': _childNameCtrl.text.trim(),
      'childKana': _childKanaCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'receiverName': _receiverCtrl.text.trim(),
      'receivedAt': tt(_receivedAt),
      'managerReportAt': _managerReportAt != null ? tt(_managerReportAt!) : null,
      'category': _category,
      'categoryOther': _category == 'other' ? _categoryOtherCtrl.text.trim() : '',
      'reporterToHq': _reporterToHq,
      'content': _contentCtrl.text.trim(),
      'updatedAt': now,
    };
    try {
      if (_isEdit) {
        await widget.doc!.reference.update(data);
      } else {
        data['createdAt'] = now;
        data['createdBy'] = user?.uid ?? '';
        await FirebaseFirestore.instance.collection('complaint_reports').add(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? '更新しました' : '受付しました'), backgroundColor: Colors.green),
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
        title: const Text('この受付記録を削除しますか？'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? '受付記録を編集' : '苦情受付',
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
            _section('事業所・発生日時'),
            _textField('事業所名', _officeCtrl),
            const SizedBox(height: 10),
            _dateTimeTile(),
            const SizedBox(height: 10),
            _rowFields([
              _textField('記入者', _reporterCtrl),
              _textField('管理者', _managerCtrl),
            ]),

            const SizedBox(height: 20),
            _section('申出人'),
            _textField('フリガナ', _claimantKanaCtrl),
            const SizedBox(height: 10),
            _textField('氏名', _claimantNameCtrl),
            const SizedBox(height: 10),
            _section2('利用者との関係'),
            _chipGroup(
              options: ComplaintOptions.relation,
              selected: {_relation},
              onToggle: (id) => setState(() => _relation = id),
            ),
            if (_relation == 'other') ...[
              const SizedBox(height: 8),
              _textField('その他の関係', _relationOtherCtrl),
            ],

            const SizedBox(height: 20),
            _section('利用児'),
            _textField('フリガナ', _childKanaCtrl),
            const SizedBox(height: 10),
            _textField('氏名', _childNameCtrl),

            const SizedBox(height: 20),
            _section('連絡先'),
            _textField('住所', _addressCtrl),
            const SizedBox(height: 10),
            _textField('電話', _phoneCtrl, keyboardType: TextInputType.phone),

            const SizedBox(height: 20),
            _section('受付'),
            _textField('苦情受付者', _receiverCtrl),
            const SizedBox(height: 10),
            _rowFields([
              _timeTile('受付時間', _receivedAt, (t) => setState(() => _receivedAt = t)),
              _timeTile('管理者報告', _managerReportAt, (t) => setState(() => _managerReportAt = t), nullable: true),
            ]),

            const SizedBox(height: 20),
            _section('分類'),
            _chipGroup(
              options: ComplaintOptions.category,
              selected: {_category},
              onToggle: (id) => setState(() => _category = id),
            ),
            if (_category == 'other') ...[
              const SizedBox(height: 8),
              _textField('その他の分類', _categoryOtherCtrl),
            ],

            const SizedBox(height: 16),
            _section2('本社運営への報告'),
            Row(
              children: [
                _yesNoChip('要', _reporterToHq, () => setState(() => _reporterToHq = true)),
                const SizedBox(width: 8),
                _yesNoChip('否', !_reporterToHq, () => setState(() => _reporterToHq = false)),
              ],
            ),

            const SizedBox(height: 20),
            _section('苦情内容'),
            Text('言われたことをそのまま記入してください（自分の感覚で文章を作らない）',
                style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              maxLines: 10,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '例：「〜と言われた」',
                hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                filled: true,
                fillColor: context.colors.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderLight),
                ),
              ),
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
                  : Text(_isEdit ? '更新' : '送 信',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
      );

  Widget _section2(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(s,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
      );

  Widget _textField(String label, TextEditingController c,
      {TextInputType? keyboardType, int maxLines = 1}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        isDense: true,
        filled: true,
        fillColor: context.colors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.borderLight),
        ),
      ),
    );
  }

  Widget _rowFields(List<Widget> fields) {
    return Row(
      children: [
        for (int i = 0; i < fields.length; i++) ...[
          Expanded(child: fields[i]),
          if (i < fields.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _dateTimeTile() {
    return InkWell(
      onTap: _pickDateTime,
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
            Icon(Icons.schedule, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('発生日時', style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
            const SizedBox(width: 12),
            Text(
              DateFormat('yyyy/M/d (E) HH:mm', 'ja').format(_occurredAt),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeTile(String label, TimeOfDay? t, ValueChanged<TimeOfDay> onPick, {bool nullable = false}) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: t ?? TimeOfDay.now(),
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 16, color: context.colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    t != null ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
                              : (nullable ? '未設定' : '—'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _yesNoChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : context.colors.borderMedium,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppColors.primary : context.colors.textPrimary,
            )),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (t == null) return;
    setState(() {
      _occurredAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }
}

// ============================================================
// 選択肢マスタ
// ============================================================
class ComplaintOptions {
  static const List<({String id, String label})> relation = [
    (id: 'mother', label: '母親'),
    (id: 'father', label: '父親'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> category = [
    (id: 'staff', label: '職員の対応'),
    (id: 'injury', label: '怪我・病気'),
    (id: 'hygiene', label: '保健衛生'),
    (id: 'facility', label: '施設設備'),
    (id: 'other', label: 'その他'),
  ];

  static String labelOf(List<({String id, String label})> list, String id) {
    for (final o in list) {
      if (o.id == id) return o.label;
    }
    return id;
  }
}
