import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

// ============================================================
// H-02: ヒヤリハット一覧画面（メインエントリ）
// ============================================================
class HiyariScreen extends StatefulWidget {
  const HiyariScreen({super.key});

  @override
  State<HiyariScreen> createState() => _HiyariScreenState();
}

class _HiyariScreenState extends State<HiyariScreen> {
  String? _severityFilter;
  String? _locationFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('事故ヒヤリハット', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewReport,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新規報告', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: context.colors.cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _dropdown(
              value: _severityFilter,
              hint: '重大度（全て）',
              items: HiyariOptions.severity,
              onChanged: (v) => setState(() => _severityFilter = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdown(
              value: _locationFilter,
              hint: '場所（全て）',
              items: HiyariOptions.location,
              onChanged: (v) => setState(() => _locationFilter = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<({String id, String label})> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: TextStyle(fontSize: 13, color: context.colors.textHint)),
          style: TextStyle(fontSize: 13, color: context.colors.textPrimary),
          icon: Icon(Icons.expand_more, size: 16, color: context.colors.textSecondary),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(hint, style: TextStyle(fontSize: 13))),
            ...items.map((it) => DropdownMenuItem<String?>(
                  value: it.id,
                  child: Text(it.label, style: const TextStyle(fontSize: 13)),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildList() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('hiyari_reports')
        .orderBy('occurredAt', descending: true)
        .limit(100);
    if (_severityFilter != null) q = q.where('severity', isEqualTo: _severityFilter);
    if (_locationFilter != null) q = q.where('location', isEqualTo: _locationFilter);

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
                Icon(Icons.assignment_outlined, size: 56, color: context.colors.textTertiary),
                const SizedBox(height: 12),
                Text('報告はまだありません', style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                const SizedBox(height: 4),
                Text('右下の「新規報告」から記録できます', style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
          itemCount: docs.length,
          itemBuilder: (c, i) => _HiyariListTile(doc: docs[i]),
        );
      },
    );
  }

  Future<void> _openNewReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HiyariEditScreen()),
    );
  }
}

class _HiyariListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _HiyariListTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final occurredAt = (data['occurredAt'] as Timestamp?)?.toDate();
    final severity = data['severity'] as String? ?? 'hiyari';
    final location = data['location'] as String? ?? '';
    final activity = data['activityType'] as String? ?? '';
    final situation = data['situation'] as String? ?? '';
    final riskTags = List<String>.from(data['riskTags'] ?? []);
    final reporterName = data['reporterName'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';

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
            builder: (_) => HiyariEditScreen(doc: doc),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _severityBadge(severity),
                  const SizedBox(width: 8),
                  Text(
                    occurredAt != null ? DateFormat('M/d (E) HH:mm', 'ja').format(occurredAt) : '',
                    style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (location.isNotEmpty) _chip(HiyariOptions.labelOf(HiyariOptions.location, location)),
                  if (activity.isNotEmpty) _chip(HiyariOptions.labelOf(HiyariOptions.activity, activity)),
                  ...riskTags.take(2).map((t) => _chip(HiyariOptions.labelOf(HiyariOptions.riskTag, t))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                situation.length > 60 ? '${situation.substring(0, 60)}…' : situation,
                style: TextStyle(fontSize: 13, color: context.colors.textPrimary, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text('報告者: $reporterName', style: TextStyle(fontSize: 11, color: context.colors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Builder(builder: (context) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.chipBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
      );
    });
  }

  Widget _severityBadge(String id) {
    final (label, color) = switch (id) {
      'awareness' => ('気づき', Colors.green),
      'minorAccident' => ('軽微事故', Colors.red),
      'escalated' => ('重大', Colors.red),
      _ => ('ヒヤリ', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusBadge(String id) {
    return Builder(builder: (context) {
      final label = switch (id) {
        'reviewing' => '確認中',
        'analyzed' => '対策済',
        'shared' => '共有済',
        'closed' => 'クローズ',
        _ => '未確認',
      };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: context.colors.chipBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
      );
    });
  }
}

// ============================================================
// H-01: ヒヤリ入力/編集画面
// ============================================================
class HiyariEditScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const HiyariEditScreen({super.key, this.doc});

  @override
  State<HiyariEditScreen> createState() => _HiyariEditScreenState();
}

class _HiyariEditScreenState extends State<HiyariEditScreen> {
  DateTime _occurredAt = DateTime.now();
  String? _location;
  String? _activity;
  String _severity = 'hiyari';
  final Set<String> _riskTags = {};
  final _situationCtrl = TextEditingController();
  final _factorCtrl = TextEditingController();
  final _preventionCtrl = TextEditingController();
  bool _saving = false;
  bool _showAdmin = false;
  String _status = 'pending';

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    if (widget.doc != null) {
      final d = widget.doc!.data();
      _occurredAt = (d['occurredAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      _location = d['location'] as String?;
      _activity = d['activityType'] as String?;
      _severity = d['severity'] as String? ?? 'hiyari';
      _riskTags.addAll(List<String>.from(d['riskTags'] ?? []));
      _situationCtrl.text = d['situation'] as String? ?? '';
      _factorCtrl.text = d['factorAnalysis'] as String? ?? '';
      _preventionCtrl.text = d['preventiveMeasures'] as String? ?? '';
      _status = d['status'] as String? ?? 'pending';
    }
  }

  @override
  void dispose() {
    _situationCtrl.dispose();
    _factorCtrl.dispose();
    _preventionCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _location != null &&
      _activity != null &&
      _riskTags.isNotEmpty &&
      _situationCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    String reporterName = '';
    if (user != null) {
      try {
        final staff = await FirebaseFirestore.instance
            .collection('staffs')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (staff.docs.isNotEmpty) {
          reporterName = staff.docs.first.data()['name'] ?? '';
        }
      } catch (_) {}
    }
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'occurredAt': Timestamp.fromDate(_occurredAt),
      'location': _location,
      'activityType': _activity,
      'severity': _severity,
      'riskTags': _riskTags.toList(),
      'situation': _situationCtrl.text.trim(),
      'factorAnalysis': _factorCtrl.text.trim().isEmpty ? null : _factorCtrl.text.trim(),
      'preventiveMeasures': _preventionCtrl.text.trim().isEmpty ? null : _preventionCtrl.text.trim(),
      'status': _status,
      'updatedAt': now,
    };
    try {
      if (_isEdit) {
        await widget.doc!.reference.update(data);
      } else {
        data['createdAt'] = now;
        data['reporterId'] = user?.uid ?? '';
        data['reporterName'] = reporterName;
        await FirebaseFirestore.instance.collection('hiyari_reports').add(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? '更新しました' : '報告しました'), backgroundColor: Colors.green),
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
    if (!_isEdit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この報告を削除しますか？'),
        content: const Text('この操作は取り消せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
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
        title: Text(_isEdit ? '報告を編集' : 'ヒヤリ報告',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('(1) いつ？'),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _occurredAt = DateTime.now()),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('今すぐ'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickDateTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(DateFormat('M/d HH:mm', 'ja').format(_occurredAt)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('(2) どこで？ ※必須'),
            _chipGroup(
              options: HiyariOptions.location,
              selected: _location == null ? const {} : {_location!},
              onToggle: (id) => setState(() => _location = id),
              multiSelect: false,
            ),
            const SizedBox(height: 20),
            _sectionTitle('(3) 何をしていた時？ ※必須'),
            _chipGroup(
              options: HiyariOptions.activity,
              selected: _activity == null ? const {} : {_activity!},
              onToggle: (id) => setState(() => _activity = id),
              multiSelect: false,
            ),
            const SizedBox(height: 20),
            _sectionTitle('(4) 何が起きそうになった？ ※必須（複数可）'),
            _chipGroup(
              options: HiyariOptions.riskTag,
              selected: _riskTags,
              onToggle: (id) => setState(() {
                if (_riskTags.contains(id)) {
                  _riskTags.remove(id);
                } else {
                  _riskTags.add(id);
                }
              }),
              multiSelect: true,
            ),
            const SizedBox(height: 20),
            _sectionTitle('(5) 重大度 ※必須'),
            _chipGroup(
              options: HiyariOptions.severity,
              selected: {_severity},
              onToggle: (id) => setState(() => _severity = id),
              multiSelect: false,
            ),
            const SizedBox(height: 20),
            _sectionTitle('(6) 状況 ※必須'),
            TextField(
              controller: _situationCtrl,
              maxLines: 4,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '例：〇〇君が積み木で遊んでいた時、隣の友達の手に当たりそうになった。',
                hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                filled: true,
                fillColor: context.colors.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderLight),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 管理者入力欄（折りたたみ）
            InkWell(
              onTap: () => setState(() => _showAdmin = !_showAdmin),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_showAdmin ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: context.colors.textSecondary),
                    const SizedBox(width: 4),
                    Text('管理者記入欄（要因分析・対策）',
                        style: TextStyle(fontSize: 13, color: context.colors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            if (_showAdmin) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _factorCtrl,
                maxLines: 3,
                decoration: _adminDecoration('要因分析'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _preventionCtrl,
                maxLines: 3,
                decoration: _adminDecoration('再発防止策'),
              ),
              const SizedBox(height: 10),
              _chipGroup(
                options: HiyariOptions.status,
                selected: {_status},
                onToggle: (id) => setState(() => _status = id),
                multiSelect: false,
              ),
            ],
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

  InputDecoration _adminDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: context.colors.textSecondary),
      filled: true,
      fillColor: context.colors.cardBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.colors.borderLight),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
    );
  }

  Widget _chipGroup({
    required List<({String id, String label})> options,
    required Set<String> selected,
    required ValueChanged<String> onToggle,
    required bool multiSelect,
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
            child: Text(
              opt.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                color: isSel ? AppColors.primary : context.colors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
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
class HiyariOptions {
  static const List<({String id, String label})> location = [
    (id: 'therapyRoom', label: '療育室'),
    (id: 'feedbackRoom', label: 'フィードバック室'),
    (id: 'entrance', label: '玄関・下駄箱'),
    (id: 'toilet', label: 'トイレ'),
    (id: 'kitchen', label: '給湯・調理'),
    (id: 'outdoor', label: '園庭・屋外'),
    (id: 'vehicle', label: '送迎車両'),
    (id: 'offsite', label: '園外活動先'),
    (id: 'staffRoom', label: '職員室'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> activity = [
    (id: 'therapy', label: '療育中'),
    (id: 'feedback', label: 'フィードバック中'),
    (id: 'freePlay', label: '自由遊び'),
    (id: 'meal', label: '食事・おやつ'),
    (id: 'transition', label: '移動・着替え'),
    (id: 'pickup', label: '送迎'),
    (id: 'offsiteActivity', label: '園外活動'),
    (id: 'cleanup', label: '清掃・準備'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> riskTag = [
    (id: 'fall', label: '転倒・転落'),
    (id: 'collision', label: '衝突'),
    (id: 'ingestion', label: '誤飲・誤食'),
    (id: 'allergy', label: 'アレルギー'),
    (id: 'choking', label: '誤嚥・窒息'),
    (id: 'selfHarm', label: '自傷'),
    (id: 'harmToOthers', label: '他害'),
    (id: 'panic', label: 'パニック'),
    (id: 'elopement', label: '飛び出し'),
    (id: 'missedCheck', label: '見落とし'),
    (id: 'equipment', label: '設備・遊具'),
    (id: 'medication', label: '与薬'),
    (id: 'infection', label: '感染症'),
    (id: 'traffic', label: '交通'),
    (id: 'other', label: 'その他'),
  ];

  static const List<({String id, String label})> severity = [
    (id: 'awareness', label: '気づき'),
    (id: 'hiyari', label: 'ヒヤリハット'),
    (id: 'minorAccident', label: '軽微事故'),
  ];

  static const List<({String id, String label})> status = [
    (id: 'pending', label: '未確認'),
    (id: 'reviewing', label: '確認中'),
    (id: 'analyzed', label: '対策済'),
    (id: 'shared', label: '共有済'),
    (id: 'closed', label: 'クローズ'),
  ];

  static String labelOf(List<({String id, String label})> list, String id) {
    for (final o in list) {
      if (o.id == id) return o.label;
    }
    return id;
  }
}
