// 体験予約 公開フォーム（HP問い合わせ用）。STORES予約の自前置き換え。
//
// アクセス: https://bee-smiley-admin.web.app/#/book
// STEP1 日時選択（空き枠から選ぶ）/ STEP2 お客様情報（最小限の6項目）。
// 送信で submitTrialBooking → plus_families にリード作成＋枠を確保。
// 詳細な体験前アンケートは後追いでSMS/メール送付（2段アンケート構想）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../widgets/brand_header.dart';

const String _base =
    'https://asia-northeast1-bee-smiley-admin.cloudfunctions.net';

class _SlotDate {
  final String date; // YYYY-MM-DD
  final String weekday;
  final List<_Slot> slots;
  const _SlotDate(this.date, this.weekday, this.slots);
}

class _Slot {
  final String id;
  final String start;
  final String end;
  const _Slot(this.id, this.start, this.end);
}

class TrialBookingScreen extends StatefulWidget {
  const TrialBookingScreen({super.key});

  @override
  State<TrialBookingScreen> createState() => _TrialBookingScreenState();
}

class _TrialBookingScreenState extends State<TrialBookingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _parentLastCtrl = TextEditingController();
  final _parentFirstCtrl = TextEditingController();
  final _childLastCtrl = TextEditingController();
  final _childFirstCtrl = TextEditingController();
  DateTime? _birthDate;
  String _gender = '';
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _honeypotCtrl = TextEditingController();

  List<_SlotDate> _dates = [];
  String? _selectedSlotId;
  _SlotDate? _selectedDate;

  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;
  String _bookedLabel = '';

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    try {
      final res = await http.get(Uri.parse('$_base/getTrialSlots'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['dates'] as List?) ?? [];
        setState(() {
          _dates = list.map((d) {
            final m = d as Map<String, dynamic>;
            final slots = ((m['slots'] as List?) ?? []).map((sl) {
              final s = sl as Map<String, dynamic>;
              return _Slot(s['id'] as String, s['start'] as String, s['end'] as String);
            }).toList();
            return _SlotDate(m['date'] as String, (m['weekday'] as String?) ?? '', slots);
          }).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
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
          // 枠が埋まった場合は再読込
          if (res.statusCode == 409) {
            _selectedSlotId = null;
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
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('ビースマイリープラス 体験予約'),
        elevation: 0,
      ),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            Text('体験のご予約ありがとうございました',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
            const SizedBox(height: 8),
            Text('ご予約日時：$_bookedLabel',
                style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            Text('当日に向けて、担当者から詳しいご案内（事前アンケート等）をお送りします。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandHeader(),
                _stepHeader('STEP 1', '日時を選択'),
                _slotSelector(),
                const SizedBox(height: 8),
                _stepHeader('STEP 2', 'お客様情報'),
                _section([
                  _row2(_input('保護者 姓', _parentLastCtrl, required: true),
                      _input('保護者 名', _parentFirstCtrl, required: true)),
                  _row2(_input('お子さま 姓', _childLastCtrl, required: true),
                      _input('お子さま 名', _childFirstCtrl, required: true)),
                  _genderSelector(),
                  _birthPicker(),
                  _input('メールアドレス', _emailCtrl,
                      required: true,
                      keyboard: TextInputType.emailAddress,
                      validator: _emailValidator),
                  _input('電話番号', _phoneCtrl,
                      required: true,
                      keyboard: TextInputType.phone,
                      hint: '09000000000'),
                ]),
                Offstage(
                  child: TextField(controller: _honeypotCtrl,
                      decoration: const InputDecoration(labelText: 'website')),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.alerts.urgent.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.alerts.urgent.border),
                    ),
                    child: Text(_errorMessage!,
                        style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: context.alerts.urgent.text)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── パーツ ───

  Widget _stepHeader(String step, String title) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step,
              style: TextStyle(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.title,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
        ],
      ),
    );
  }

  Widget _slotSelector() {
    final c = context.colors;
    if (_dates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.borderLight),
        ),
        child: Text('現在ご予約いただける空き枠がありません。お手数ですがお電話でお問い合わせください。',
            style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in _dates)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_dateLabel(d.date)}（${d.weekday}）',
                    style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in d.slots)
                      ChoiceChip(
                        label: Text('${s.start}〜${s.end}',
                            style: const TextStyle(fontSize: AppTextSize.body)),
                        selected: _selectedSlotId == s.id,
                        onSelected: (sel) {
                          setState(() {
                            _selectedSlotId = sel ? s.id : null;
                            _selectedDate = sel ? d : null;
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (_selectedDate != null && _selectedSlotId != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
                '選択中: ${_dateLabel(_selectedDate!.date)}（${_selectedDate!.weekday}） '
                '${_selectedDate!.slots.firstWhere((s) => s.id == _selectedSlotId, orElse: () => _selectedDate!.slots.first).start}〜',
                style: TextStyle(
                    fontSize: AppTextSize.caption, color: AppColors.primary)),
          ),
      ],
    );
  }

  Widget _section(List<Widget> children) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in children) ...[w, const SizedBox(height: 12)],
        ],
      ),
    );
  }

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
