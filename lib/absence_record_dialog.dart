import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

/// プラスのスケジュールから呼び出す欠席記録入力ダイアログ。
/// 7項目を1画面で入力し、【タグ】\n回答 形式の文字列として結果を返す。
class AbsenceRecordDialog extends StatefulWidget {
  final String studentName;
  final DateTime absenceDate;

  const AbsenceRecordDialog({
    super.key,
    required this.studentName,
    required this.absenceDate,
  });

  @override
  State<AbsenceRecordDialog> createState() => _AbsenceRecordDialogState();

  /// ダイアログを表示し、キャンセル時は null、送信時は整形済みテキストを返す
  static Future<String?> show(
    BuildContext context, {
    required String studentName,
    required DateTime absenceDate,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AbsenceRecordDialog(
        studentName: studentName,
        absenceDate: absenceDate,
      ),
    );
  }
}

class _AbsenceRecordDialogState extends State<AbsenceRecordDialog> {
  DateTime? _contactDate; // 欠席の連絡のあった日
  final _callerController = TextEditingController(); // 誰が電話してきたか
  String? _responder; // 連絡を受けた対応者（プラススタッフ）
  final _reasonController = TextEditingController(); // 欠席の理由
  final _conditionController = TextEditingController(); // 当日のご本人の様子
  final _supportController = TextEditingController(); // 相談援助内容
  DateTime? _nextVisitDate; // 次回通所予定日

  List<String>? _plusStaffOptions;
  bool _loadingStaff = true;

  static const String _defaultSupportText =
      '安静に過ごしていただくよう助言した。\n受診した際は結果報告いただけるよう依頼した。\n次回利用日を確認した。';

  static const List<String> _callerOptions = ['母', '父'];
  static const List<String> _reasonOptions = ['発熱', '怪我', '家庭都合'];

  @override
  void initState() {
    super.initState();
    _contactDate = widget.absenceDate;
    _supportController.text = _defaultSupportText;
    _loadPlusStaff();
  }

  @override
  void dispose() {
    _callerController.dispose();
    _reasonController.dispose();
    _conditionController.dispose();
    _supportController.dispose();
    super.dispose();
  }

  Future<void> _loadPlusStaff() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('staffs').get();
      final names = <Map<String, String>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final classrooms = (data['classrooms'] as List?) ?? [];
        if (classrooms.any((c) => c.toString().contains('プラス'))) {
          names.add({
            'name': (data['name'] ?? '') as String,
            'furigana': (data['furigana'] ?? '') as String,
          });
        }
      }
      names.sort((a, b) => (a['furigana'] ?? '').compareTo(b['furigana'] ?? ''));
      if (mounted) {
        setState(() {
          _plusStaffOptions = names.map((m) => m['name'] ?? '').where((n) => n.isNotEmpty).toList();
          _loadingStaff = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _plusStaffOptions = [];
          _loadingStaff = false;
        });
      }
    }
  }

  Future<void> _pickDate(DateTime? initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ja'),
    );
    if (picked != null) onPicked(picked);
  }

  bool get _canSubmit => true; // 必須項目なし

  void _submit() {
    final df = DateFormat('yyyy/MM/dd');
    final b = StringBuffer();
    b.writeln('【欠席の連絡のあった日】');
    b.writeln(_contactDate != null ? df.format(_contactDate!) : '');
    b.writeln();
    b.writeln('【誰が電話してきたか】');
    b.writeln(_callerController.text.trim());
    b.writeln();
    b.writeln('【連絡を受けた対応者】');
    b.writeln(_responder ?? '');
    b.writeln();
    b.writeln('【欠席の理由】');
    b.writeln(_reasonController.text.trim());
    b.writeln();
    b.writeln('【当日のご本人の様子】');
    b.writeln(_conditionController.text.trim());
    b.writeln();
    b.writeln('【相談援助内容】');
    b.writeln(_supportController.text.trim());
    b.writeln();
    b.writeln('【次回通所予定日】');
    b.writeln(_nextVisitDate != null ? df.format(_nextVisitDate!) : '');
    Navigator.pop(context, b.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final df = DateFormat('yyyy/MM/dd (E)', 'ja');
    return Dialog(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダ
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.event_busy_rounded, size: 20, color: AppColors.errorBorder),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('欠席記録入力', style: TextStyle(fontSize: AppTextSize.titleSm, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.studentName} / 欠席日 ${df.format(widget.absenceDate)}',
                          style: TextStyle(fontSize: AppTextSize.caption, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.borderLight),

            // 本文
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dateField(
                      label: '欠席の連絡のあった日',
                      value: _contactDate,
                      onTap: () => _pickDate(_contactDate, (d) => setState(() => _contactDate = d)),
                    ),
                    const SizedBox(height: 12),
                    _chipsWithTextField(
                      label: '誰が電話してきたか',
                      options: _callerOptions,
                      controller: _callerController,
                      hint: 'その他（自由入力）',
                    ),
                    const SizedBox(height: 12),
                    _responderField(),
                    const SizedBox(height: 12),
                    _chipsWithTextField(
                      label: '欠席の理由',
                      options: _reasonOptions,
                      controller: _reasonController,
                      hint: 'その他（自由入力）',
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      label: '当日のご本人の様子',
                      controller: _conditionController,
                      hint: '',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      label: '相談援助内容',
                      controller: _supportController,
                      hint: '',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    _dateField(
                      label: '次回通所予定日',
                      value: _nextVisitDate,
                      onTap: () => _pickDate(_nextVisitDate, (d) => setState(() => _nextVisitDate = d)),
                    ),
                  ],
                ),
              ),
            ),

            // フッタ
            Divider(height: 1, color: c.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: Text('キャンセル', style: TextStyle(color: c.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorBorder,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
      );

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(label),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          style: const TextStyle(fontSize: AppTextSize.bodyMd),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: AppTextSize.body, color: c.textHint),
            filled: true,
            fillColor: c.tagBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.aiAccent),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _chipsWithTextField({
    required String label,
    required List<String> options,
    required TextEditingController controller,
    required String hint,
  }) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(label),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final selected = controller.text.trim() == opt;
            return GestureDetector(
              onTap: () {
                setState(() {
                  controller.text = selected ? '' : opt;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? c.aiAccent : c.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected ? c.aiAccent : c.borderMedium),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: selected ? Colors.white : c.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: AppTextSize.bodyMd),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: AppTextSize.body, color: c.textHint),
            filled: true,
            fillColor: c.tagBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.aiAccent),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final df = DateFormat('yyyy/MM/dd (E)', 'ja');
    final hasValue = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: c.tagBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hasValue ? c.aiAccent : c.borderMedium),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: hasValue ? c.aiAccent : c.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasValue ? df.format(value) : '日付を選択...',
                    style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      color: hasValue ? c.textPrimary : c.textHint,
                      fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
                if (hasValue)
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: c.textTertiary),
                    onPressed: () => setState(() {
                      if (label.contains('次回')) {
                        _nextVisitDate = null;
                      } else {
                        _contactDate = null;
                      }
                    }),
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _responderField() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('連絡を受けた対応者'),
        if (_loadingStaff)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_plusStaffOptions == null || _plusStaffOptions!.isEmpty)
          Text('プラス所属スタッフが見つかりません', style: TextStyle(fontSize: AppTextSize.body, color: c.textTertiary))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _plusStaffOptions!.map((name) {
              final selected = _responder == name;
              return GestureDetector(
                onTap: () => setState(() => _responder = selected ? null : name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? c.aiAccent : c.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? c.aiAccent : c.borderMedium),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: AppTextSize.small,
                      color: selected ? Colors.white : c.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
