// 体験アンケート 公開フォーム画面（自前化、Googleフォーム代替）。
//
// アクセス: https://bee-smiley-admin.web.app/#/intake
// 認証なしでアクセス可能。送信時に Cloud Function `intakeFormPublic` に POST。
// セキュリティ: ハニーポット（隠しフィールド _hp）+ Cloud Function 側のレート制限。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app_theme.dart';

/// Cloud Function 公開エンドポイント URL。
const String _intakeUrl =
    'https://asia-northeast1-bee-smiley-admin.cloudfunctions.net/intakeFormPublic';

class IntakeFormScreen extends StatefulWidget {
  const IntakeFormScreen({super.key});

  @override
  State<IntakeFormScreen> createState() => _IntakeFormScreenState();
}

class _IntakeFormScreenState extends State<IntakeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // 保護者
  final _parentLastNameCtrl = TextEditingController();
  final _parentFirstNameCtrl = TextEditingController();
  final _parentLastNameKanaCtrl = TextEditingController();
  final _parentFirstNameKanaCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // 児童
  final _childLastNameCtrl = TextEditingController();
  final _childFirstNameCtrl = TextEditingController();
  final _childLastNameKanaCtrl = TextEditingController();
  final _childFirstNameKanaCtrl = TextEditingController();
  DateTime? _childBirthDate;
  String _childGender = '';
  final _kindergartenCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();

  // ヒアリング系
  String _permitStatus = '';
  final _diagnosisCtrl = TextEditingController();
  final _mainConcernCtrl = TextEditingController();
  final _likesCtrl = TextEditingController();
  final _dislikesCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();
  final _trialAttendeeCtrl = TextEditingController();
  String _source = '';
  final _memoCtrl = TextEditingController();

  // ハニーポット（ボット対策）
  final _honeypotCtrl = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in [
      _parentLastNameCtrl,
      _parentFirstNameCtrl,
      _parentLastNameKanaCtrl,
      _parentFirstNameKanaCtrl,
      _emailCtrl,
      _phoneCtrl,
      _addressCtrl,
      _childLastNameCtrl,
      _childFirstNameCtrl,
      _childLastNameKanaCtrl,
      _childFirstNameKanaCtrl,
      _kindergartenCtrl,
      _gradeCtrl,
      _diagnosisCtrl,
      _mainConcernCtrl,
      _likesCtrl,
      _dislikesCtrl,
      _medicalHistoryCtrl,
      _trialAttendeeCtrl,
      _memoCtrl,
      _honeypotCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_childGender.isEmpty) {
      setState(() => _errorMessage = 'お子様の性別を選択してください');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final payload = {
      'submittedAt': DateTime.now().toIso8601String(),
      'parentLastName': _parentLastNameCtrl.text.trim(),
      'parentFirstName': _parentFirstNameCtrl.text.trim(),
      'parentLastNameKana': _parentLastNameKanaCtrl.text.trim(),
      'parentFirstNameKana': _parentFirstNameKanaCtrl.text.trim(),
      'childLastName': _childLastNameCtrl.text.trim(),
      'childFirstName': _childFirstNameCtrl.text.trim(),
      'childLastNameKana': _childLastNameKanaCtrl.text.trim(),
      'childFirstNameKana': _childFirstNameKanaCtrl.text.trim(),
      'childBirthDate': _childBirthDate == null
          ? ''
          : DateFormat('yyyy/MM/dd').format(_childBirthDate!),
      'childGender': _childGender,
      'address': _addressCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'permitStatus': _permitStatus,
      'diagnosis': _diagnosisCtrl.text.trim(),
      'kindergarten': _kindergartenCtrl.text.trim(),
      'grade': _gradeCtrl.text.trim(),
      'mainConcern': _mainConcernCtrl.text.trim(),
      'likes': _likesCtrl.text.trim(),
      'dislikes': _dislikesCtrl.text.trim(),
      'medicalHistory': _medicalHistoryCtrl.text.trim(),
      'trialAttendee': _trialAttendeeCtrl.text.trim(),
      'source': _source,
      'memo': _memoCtrl.text.trim(),
      '_hp': _honeypotCtrl.text, // ハニーポット（空であるべき）
    };

    try {
      final res = await http.post(
        Uri.parse(_intakeUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        setState(() {
          _submitted = true;
          _submitting = false;
        });
      } else {
        setState(() {
          _errorMessage = '送信に失敗しました（${res.statusCode}）。少し時間をおいて再度お試しください。';
          _submitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '送信エラー: ${e.toString()}';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('ビースマイリープラス 体験アンケート'),
        elevation: 0,
      ),
      body: _submitted ? _buildThanks() : _buildForm(),
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
            Icon(Icons.check_circle,
                size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            Text('ご回答ありがとうございました',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
            const SizedBox(height: 8),
            Text(
                '内容を確認のうえ、担当者からご連絡させていただきます。\n体験日程の調整など、追ってご案内いたします。',
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
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _intro(),
                const SizedBox(height: 16),
                _section('保護者さまについて', [
                  _row2(
                      _input('姓', _parentLastNameCtrl, required: true),
                      _input('名', _parentFirstNameCtrl, required: true)),
                  _row2(
                      _input('姓ふりがな', _parentLastNameKanaCtrl,
                          required: true),
                      _input('名ふりがな', _parentFirstNameKanaCtrl,
                          required: true)),
                  _input('メールアドレス', _emailCtrl,
                      keyboard: TextInputType.emailAddress,
                      required: true,
                      validator: _emailValidator),
                  _input('電話番号', _phoneCtrl,
                      keyboard: TextInputType.phone,
                      required: true,
                      hint: '09000000000'),
                  _input('ご住所（郵便番号から）', _addressCtrl,
                      hint: '〒251-0042 神奈川県藤沢市…',
                      required: true,
                      maxLines: 2),
                ]),
                _section('お子さまについて', [
                  _row2(
                      _input('姓', _childLastNameCtrl, required: true),
                      _input('名', _childFirstNameCtrl, required: true)),
                  _row2(
                      _input('姓ふりがな', _childLastNameKanaCtrl,
                          required: true),
                      _input('名ふりがな', _childFirstNameKanaCtrl,
                          required: true)),
                  // 誕生日と性別はモバイル可読性のため縦並び
                  _birthDatePicker(),
                  _genderSelector(),
                  _input('幼稚園・保育園・学校名', _kindergartenCtrl,
                      hint: '通っていない場合は空欄'),
                  _input('学年', _gradeCtrl, hint: '例: 年中、小1'),
                  _permitSelector(),
                  _input('診断名', _diagnosisCtrl,
                      hint: 'ある場合のみ。なければ空欄'),
                ]),
                _section('体験について', [
                  _labelHint('体験を希望される理由', 'お困りごと、不安なことなど',
                      required: true),
                  _input('', _mainConcernCtrl,
                      required: true, maxLines: 4),
                  _labelHint(
                      'お子さまの好きなこと、得意なこと', '得意なこと・夢中になっていることなど'),
                  _input('', _likesCtrl, maxLines: 3),
                  _labelHint(
                      'お子さまの嫌いなこと、苦手なこと', '苦手な刺激・困りやすい場面など'),
                  _input('', _dislikesCtrl, maxLines: 3),
                  _labelHint('既往歴', 'ある場合はできるだけ詳しく'),
                  _input('', _medicalHistoryCtrl, maxLines: 3),
                  _labelHint('体験当日の来所予定の方', '例: 母'),
                  _input('', _trialAttendeeCtrl),
                ]),
                _section('その他', [
                  _sourceSelector(),
                  _input('その他お伝えしたいこと', _memoCtrl, maxLines: 3),
                ]),
                // ハニーポット（ユーザーには見えない）
                Offstage(
                  child: TextField(
                    controller: _honeypotCtrl,
                    decoration:
                        const InputDecoration(labelText: 'website'),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.alerts.urgent.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: context.alerts.urgent.border),
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
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
                      : const Text('送信する',
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

  Widget _intro() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('体験ご検討ありがとうございます',
              style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
          const SizedBox(height: 6),
          Text(
              'お子さまに合わせた体験のご準備のため、以下のアンケートにご回答をお願いいたします。所要時間は5〜10分程度です。',
              style: TextStyle(
                  fontSize: AppTextSize.body, color: c.textSecondary)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
          const SizedBox(height: 12),
          for (final w in children) ...[
            w,
            const SizedBox(height: 12),
          ],
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
      int maxLines = 1,
      TextInputType? keyboard,
      String? Function(String?)? validator}) {
    final hasLabel = label.isNotEmpty;
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        // ラベル空文字（_labelHint で外側に出している）の場合は labelText 自体を出さない
        labelText: hasLabel ? label + (required ? ' *' : '') : null,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: validator ??
          (v) {
            if (required && (v == null || v.trim().isEmpty)) {
              return '入力してください';
            }
            return null;
          },
    );
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return '入力してください';
    if (!v.contains('@')) return 'メール形式で入力してください';
    return null;
  }

  /// ラベル + 補足ヒントを TextField の上に独立表示。
  /// 長いガイド文が labelText に入って入力時に縮んで読みづらくなる問題を回避。
  Widget _labelHint(String label, String hint, {bool required = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary)),
              if (required) ...[
                const SizedBox(width: 6),
                Text('*',
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: context.alerts.urgent.icon)),
              ],
            ],
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: TextStyle(
                    fontSize: AppTextSize.xs, color: c.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _birthDatePicker() {
    final display = _childBirthDate == null
        ? '日付を選択 *'
        : DateFormat('yyyy/M/d', 'ja').format(_childBirthDate!);
    return InkWell(
      onTap: () async {
        final picked = await _showSimpleDatePicker();
        if (picked != null) {
          setState(() => _childBirthDate = picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'お誕生日 *',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(display,
            style: TextStyle(
                fontSize: AppTextSize.body,
                color: _childBirthDate == null
                    ? context.colors.textTertiary
                    : context.colors.textPrimary)),
      ),
    );
  }

  /// ヘッダなしの日付ピッカー（CalendarDatePicker をダイアログで包む）。
  Future<DateTime?> _showSimpleDatePicker() async {
    DateTime selected = _childBirthDate ?? DateTime(2020, 1, 1);
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          contentPadding:
              const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 320,
            height: 360,
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime(2010),
              lastDate: DateTime.now(),
              onDateChanged: (d) => selected = d,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
                label: Text(g,
                    style:
                        const TextStyle(fontSize: AppTextSize.caption)),
                selected: _childGender == g,
                onSelected: (s) {
                  if (s) setState(() => _childGender = g);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _permitSelector() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '受給者証の有無',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: Wrap(
        spacing: 8,
        children: [
          for (final v in const [
            ('有', '有'),
            ('無', '無'),
            ('申請中', '申請中')
          ])
            ChoiceChip(
              label: Text(v.$2,
                  style: const TextStyle(fontSize: AppTextSize.caption)),
              selected: _permitStatus == v.$1,
              onSelected: (s) {
                if (s) setState(() => _permitStatus = v.$1);
              },
            ),
        ],
      ),
    );
  }

  Widget _sourceSelector() {
    const sources = [
      'Instagram',
      'Google検索',
      'HP',
      '紹介',
      'チラシ',
      'SNS',
      'その他',
    ];
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'どちらでビースマイリーを知りましたか',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in sources)
            ChoiceChip(
              label: Text(s,
                  style: const TextStyle(fontSize: AppTextSize.caption)),
              selected: _source == s,
              onSelected: (sel) {
                if (sel) setState(() => _source = s);
              },
            ),
        ],
      ),
    );
  }
}
