// 体験予約 公開フォーム（HP問い合わせ用）。STORES予約の自前置き換え。
//
// アクセス: https://bee-smiley-admin.web.app/#/book
// STEP1 カレンダーで日付選択 → 時間枠選択 / STEP2 お客様情報（最小限の6項目）。
// 送信で submitTrialBooking → plus_families にリード作成＋枠を確保。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../widgets/brand_header.dart';

const String _base =
    'https://asia-northeast1-bee-smiley-admin.cloudfunctions.net';

class _Slot {
  final String id;
  final String start;
  final String end;
  const _Slot(this.id, this.start, this.end);
}

class _SlotDate {
  final String date; // YYYY-MM-DD
  final String weekday;
  final List<_Slot> slots;
  const _SlotDate(this.date, this.weekday, this.slots);
}

class TrialBookingScreen extends StatefulWidget {
  const TrialBookingScreen({super.key});

  @override
  State<TrialBookingScreen> createState() => _TrialBookingScreenState();
}

class _TrialBookingScreenState extends State<TrialBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _weekHeaders = ['日', '月', '火', '水', '木', '金', '土'];

  final _parentLastCtrl = TextEditingController();
  final _parentFirstCtrl = TextEditingController();
  final _childLastCtrl = TextEditingController();
  final _childFirstCtrl = TextEditingController();
  DateTime? _birthDate;
  String _gender = '';
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _honeypotCtrl = TextEditingController();

  final Map<String, _SlotDate> _byDate = {};
  late DateTime _calMonth;
  String? _selectedDate;
  String? _selectedSlotId;

  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;
  String _bookedLabel = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calMonth = DateTime(now.year, now.month, 1);
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    try {
      final res = await http.get(Uri.parse('$_base/getTrialSlots'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['dates'] as List?) ?? [];
        _byDate.clear();
        for (final d in list) {
          final m = d as Map<String, dynamic>;
          final slots = ((m['slots'] as List?) ?? []).map((sl) {
            final s = sl as Map<String, dynamic>;
            return _Slot(s['id'] as String, s['start'] as String, s['end'] as String);
          }).toList();
          final sd = _SlotDate(
              m['date'] as String, (m['weekday'] as String?) ?? '', slots);
          _byDate[sd.date] = sd;
        }
        // 最初の空き日の月を初期表示
        if (_byDate.isNotEmpty) {
          final first = (_byDate.keys.toList()..sort()).first;
          final fd = _parseDate(first);
          _calMonth = DateTime(fd.year, fd.month, 1);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [
      _parentLastCtrl, _parentFirstCtrl, _childLastCtrl, _childFirstCtrl,
      _emailCtrl, _phoneCtrl, _honeypotCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _parseDate(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  // 月を移動したら選択中の日付・時間をクリア（別月の選択が残って紛らわしいのを防ぐ）
  void _changeCalMonth(int delta) {
    setState(() {
      _calMonth = DateTime(_calMonth.year, _calMonth.month + delta, 1);
      _selectedDate = null;
      _selectedSlotId = null;
    });
  }

  String _dateLabel(String date) {
    final p = date.split('-');
    if (p.length != 3) return date;
    return '${int.parse(p[1])}月${int.parse(p[2])}日';
  }

  Future<void> _submit() async {
    if (_selectedSlotId == null) {
      setState(() => _errorMessage = '体験の日時を選択してください');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_gender.isEmpty) {
      setState(() => _errorMessage = 'お子さまの性別を選択してください');
      return;
    }
    if (_birthDate == null) {
      setState(() => _errorMessage = 'お子さまの生年月日を選択してください');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final payload = {
      'slotId': _selectedSlotId,
      'parentLastName': _parentLastCtrl.text.trim(),
      'parentFirstName': _parentFirstCtrl.text.trim(),
      'childLastName': _childLastCtrl.text.trim(),
      'childFirstName': _childFirstCtrl.text.trim(),
      'childGender': _gender,
      'childBirthDate': DateFormat('yyyy/MM/dd').format(_birthDate!),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      '_hp': _honeypotCtrl.text,
    };

    try {
      final res = await http.post(
        Uri.parse('$_base/submitTrialBooking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _bookedLabel =
              '${_dateLabel(d['date'] as String)} ${d['start']}〜${d['end']}';
          _submitted = true;
          _submitting = false;
        });
      } else {
        String msg = '送信に失敗しました（${res.statusCode}）。';
        try {
          msg = (jsonDecode(res.body)['error'] as String?) ?? msg;
        } catch (_) {}
        setState(() {
          _errorMessage = msg;
          _submitting = false;
          if (res.statusCode == 409) {
            _selectedSlotId = null;
            _selectedDate = null;
            _loadSlots();
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '送信エラー: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // STORES風にフラット（カード枠なし・単色背景）
      backgroundColor: context.colors.cardBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _submitted
              ? _buildThanks()
              : _buildForm(),
    );
  }

  Widget _buildThanks() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            Text('体験のご予約ありがとうございました',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
            const SizedBox(height: 12),
            Text('ご予約日時：$_bookedLabel',
                style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            Text('当日に向けて、担当者から詳しいご案内をお送りします。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final c = context.colors;
    final content = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                  const BrandHeader(height: 48),
                  const SizedBox(height: 10),
                  Text(
                    'このたびはビースマイリープラスにご興味をお持ちいただき、ありがとうございます。\n無料体験のご予約ページです。ご希望の日時とお客さま情報をご入力ください。ご予約後、担当者より当日のご案内をお送りします。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        height: 1.7,
                        color: c.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  _stepHeader('STEP 1', '日時を選択'),
                  const SizedBox(height: 12),
                  _calendar(),
                  if (_selectedDate != null) ...[
                    const SizedBox(height: 16),
                    _timeList(),
                  ],
                  const SizedBox(height: 28),
                  _stepHeader('STEP 2', 'お客様情報'),
                  const SizedBox(height: 12),
                  _row2(_input('保護者 姓', _parentLastCtrl, required: true),
                      _input('保護者 名', _parentFirstCtrl, required: true)),
                  const SizedBox(height: 12),
                  _row2(_input('お子さま 姓', _childLastCtrl, required: true),
                      _input('お子さま 名', _childFirstCtrl, required: true)),
                  const SizedBox(height: 12),
                  _genderSelector(),
                  const SizedBox(height: 12),
                  _birthPicker(),
                  const SizedBox(height: 12),
                  _input('メールアドレス', _emailCtrl,
                      required: true,
                      keyboard: TextInputType.emailAddress,
                      validator: _emailValidator),
                  const SizedBox(height: 12),
                  _input('電話番号', _phoneCtrl,
                      required: true,
                      keyboard: TextInputType.phone,
                      hint: '09000000000'),
                  Offstage(
                    child: TextField(controller: _honeypotCtrl),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.alerts.urgent.background,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: context.alerts.urgent.border),
                      ),
                      child: Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: AppTextSize.body,
                              color: context.alerts.urgent.text)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('予約を確定する',
                            style: TextStyle(
                                fontSize: AppTextSize.bodyLarge,
                                fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );

    // 枠なし・フラット。中央寄せ＆上揃えで、内容に応じて下に伸びる。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Container(
        width: double.infinity,
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: content,
        ),
      ),
    );
  }

  // ─── STEP1: カレンダー ───

  Widget _stepHeader(String step, String title) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step,
            style: TextStyle(
                fontSize: AppTextSize.caption,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(title,
            style: TextStyle(
                fontSize: AppTextSize.titleSm,
                fontWeight: FontWeight.bold,
                color: c.textPrimary)),
        const SizedBox(height: 10),
        Divider(height: 1, color: c.borderLight),
      ],
    );
  }

  Widget _calendar() {
    final c = context.colors;
    if (_byDate.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.scaffoldBgAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('現在ご予約いただける空き枠がありません。お手数ですがお電話でお問い合わせください。',
            style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary)),
      );
    }

    final year = _calMonth.year, month = _calMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday % 7; // 日始まり
    final cells = <int?>[];
    for (int i = 0; i < leading; i++) {
      cells.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(d);
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        // 月ナビ
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeCalMonth(-1),
            ),
            SizedBox(
              width: 120,
              child: Text('$year年$month月',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeCalMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (int i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(_weekHeaders[i],
                      style: TextStyle(
                          fontSize: AppTextSize.caption,
                          fontWeight: FontWeight.bold,
                          color: i == 0
                              ? AppColors.error
                              : i == 6
                                  ? AppColors.secondary
                                  : c.textSecondary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.0,
          children: [
            for (final d in cells) _dayCell(d, year, month),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(int? day, int year, int month) {
    final c = context.colors;
    if (day == null) return const SizedBox.shrink();
    final dateStr =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final available = _byDate.containsKey(dateStr);
    final selected = _selectedDate == dateStr;
    final weekday = DateTime(year, month, day).weekday; // Mon=1..Sun=7

    Color textColor;
    if (selected) {
      textColor = Colors.white;
    } else if (available) {
      textColor = AppColors.primary;
    } else {
      textColor = weekday == DateTime.sunday
          ? AppColors.error.withValues(alpha: 0.4)
          : c.textTertiary;
    }

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: available
            ? () => setState(() {
                  _selectedDate = dateStr;
                  _selectedSlotId = null;
                })
            : null,
        child: Container(
          width: 38,
          height: 38,
          decoration: available
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.5),
                      width: 1.5),
                )
              : null,
          alignment: Alignment.center,
          child: Text('$day',
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: available ? FontWeight.bold : FontWeight.normal,
                  color: textColor)),
        ),
      ),
    );
  }

  Widget _timeList() {
    final c = context.colors;
    final sd = _byDate[_selectedDate];
    if (sd == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_dateLabel(sd.date)}（${sd.weekday}）の時間を選択',
            style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
                color: c.textPrimary)),
        const SizedBox(height: 8),
        for (final s in sd.slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selectedSlotId = s.id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _selectedSlotId == s.id
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : c.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _selectedSlotId == s.id
                          ? AppColors.primary
                          : c.borderLight,
                      width: _selectedSlotId == s.id ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Text('${s.start} 〜 ${s.end}',
                        style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            color: c.textPrimary)),
                    const Spacer(),
                    Icon(
                      _selectedSlotId == s.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _selectedSlotId == s.id
                          ? AppColors.primary
                          : c.iconMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── STEP2: フォーム部品 ───

  Widget _row2(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _input(String label, TextEditingController ctrl,
      {bool required = false,
      String? hint,
      TextInputType? keyboard,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: validator ??
          (v) {
            if (required && (v == null || v.trim().isEmpty)) return '入力してください';
            return null;
          },
    );
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return '入力してください';
    if (!v.contains('@')) return 'メール形式で入力してください';
    return null;
  }

  Widget _genderSelector() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '性別 *',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: Row(
        children: [
          for (final g in const ['男', '女'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(g, style: const TextStyle(fontSize: AppTextSize.caption)),
                selected: _gender == g,
                onSelected: (s) {
                  if (s) setState(() => _gender = g);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _birthPicker() {
    final display = _birthDate == null
        ? '日付を選択 *'
        : DateFormat('yyyy/M/d', 'ja').format(_birthDate!);
    return InkWell(
      onTap: () async {
        DateTime sel = _birthDate ?? DateTime(2020, 1, 1);
        final picked = await showDialog<DateTime>(
          context: context,
          builder: (ctx) => AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            content: SizedBox(
              width: 320,
              height: 360,
              child: CalendarDatePicker(
                initialDate: sel,
                firstDate: DateTime(2010),
                lastDate: DateTime.now(),
                onDateChanged: (d) => sel = d,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('OK')),
            ],
          ),
        );
        if (picked != null) setState(() => _birthDate = picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'お子さまの生年月日 *',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(display,
            style: TextStyle(
                fontSize: AppTextSize.body,
                color: _birthDate == null
                    ? context.colors.textTertiary
                    : context.colors.textPrimary)),
      ),
    );
  }
}
