// 入会前アンケート 公開フォーム画面（個別トークンリンク経由）。
//
// アクセス: https://bee-smiley-admin.web.app/#/intake-final?t={token}
// 入会意思取得時にスタッフが SMS で送付。既知情報は事前入力し、空欄＋受給者証写真だけ埋めてもらう。
//
// バックエンド:
//   - getIntakeContext  … 本人確認・事前入力（最小限）
//   - submitFinalIntake … 回答＋受給者証写真（base64）を書き戻し。画像は関数が Storage 保存。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../widgets/brand_header.dart';

const String _base =
    'https://asia-northeast1-bee-smiley-admin.cloudfunctions.net';

class _PickedImage {
  final Uint8List bytes;
  final String name;
  final String contentType;
  const _PickedImage(this.bytes, this.name, this.contentType);
}

class IntakeFinalScreen extends StatefulWidget {
  final String? token;
  const IntakeFinalScreen({super.key, this.token});

  @override
  State<IntakeFinalScreen> createState() => _IntakeFinalScreenState();
}

class _IntakeFinalScreenState extends State<IntakeFinalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // 保護者（受給者証・実績記録票に載る氏名）
  final _payerNameCtrl = TextEditingController();
  final _payerNameKanaCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _parentRelationCtrl = TextEditingController(); // 保護者の児童との続柄(父/母等)
  // 緊急連絡先（名前・電話・続柄）
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _emergencyRelationCtrl = TextEditingController();

  // 受給者証
  String _permitStatus = '';
  final _certNumberCtrl = TextEditingController();
  final List<_PickedImage> _certImages = [];

  // 園・学校
  final _schoolCtrl = TextEditingController(); // 園/保育所名 → kindergarten
  final _kindergartenPhoneCtrl = TextEditingController(); // 園の連絡先
  final _homeroomTeacherCtrl = TextEditingController(); // 担任
  final _gradeCtrl = TextEditingController(); // 学年
  // 医療
  final _hospitalCtrl = TextEditingController();
  final _hospitalPhoneCtrl = TextEditingController(); // 病院連絡先
  final _doctorCtrl = TextEditingController();
  final _allergyCtrl = TextEditingController();
  final _severeSymptomsCtrl = TextEditingController();
  // その他（HUGプロフィール）
  final _lunchTypeCtrl = TextEditingController(); // お弁当の種類
  final _familyCompositionCtrl = TextEditingController(); // 家族構成

  // ヒアリング
  final _sensitivitiesCtrl = TextEditingController();
  final _precautionsCtrl = TextEditingController();
  final _childWishesCtrl = TextEditingController();
  final _familyWishesCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  final _honeypotCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;
  String? _banner; // コンテキスト取得失敗時の注意書き
  String _parentName = '';
  String _childName = '';

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _banner = 'リンクが正しくありません。お手数ですが届いたSMSのリンクから再度お開きください。';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$_base/getIntakeContext?token=$token'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final prefill = (data['prefill'] as Map?)?.cast<String, dynamic>() ?? {};
        setState(() {
          _parentName = (data['parentName'] as String?) ?? '';
          _childName = (data['childName'] as String?) ?? '';
          _payerNameCtrl.text = (prefill['payerName'] as String?) ?? '';
          _payerNameKanaCtrl.text = (prefill['payerNameKana'] as String?) ?? '';
          _postalCodeCtrl.text = (prefill['postalCode'] as String?) ?? '';
          _addressCtrl.text = (prefill['addressDetail'] as String?) ?? '';
          _parentRelationCtrl.text = (prefill['parentRelation'] as String?) ?? '';
          _emergencyNameCtrl.text = (prefill['emergencyName'] as String?) ?? '';
          _emergencyPhoneCtrl.text = (prefill['emergencyPhone'] as String?) ?? '';
          _emergencyRelationCtrl.text =
              (prefill['emergencyRelation'] as String?) ?? '';
          _schoolCtrl.text = (prefill['kindergarten'] as String?) ?? '';
          _kindergartenPhoneCtrl.text =
              (prefill['kindergartenPhone'] as String?) ?? '';
          _homeroomTeacherCtrl.text =
              (prefill['homeroomTeacher'] as String?) ?? '';
          _gradeCtrl.text = (prefill['grade'] as String?) ?? '';
          _hospitalCtrl.text = (prefill['hospitalName'] as String?) ?? '';
          _hospitalPhoneCtrl.text = (prefill['hospitalPhone'] as String?) ?? '';
          _doctorCtrl.text = (prefill['doctorName'] as String?) ?? '';
          _lunchTypeCtrl.text = (prefill['lunchType'] as String?) ?? '';
          _familyCompositionCtrl.text =
              (prefill['familyComposition'] as String?) ?? '';
          _certNumberCtrl.text = (prefill['certificateNumber'] as String?) ?? '';
          _permitStatus = _normPermit((prefill['permitStatus'] as String?) ?? '');
          _loading = false;
        });
      } else {
        String msg = 'リンクを確認できませんでした。';
        try {
          msg = (jsonDecode(res.body)['error'] as String?) ?? msg;
        } catch (_) {}
        setState(() {
          _banner = msg;
          _loading = false;
        });
      }
    } catch (_) {
      // ネットワーク/未デプロイ等。フォームは表示して入力は可能にする。
      setState(() {
        _banner = null;
        _loading = false;
      });
    }
  }

  String _normPermit(String v) {
    if (v == 'have') return '有';
    if (v == 'applying') return '申請中';
    if (v == 'none') return '無';
    return '';
  }

  String _permitToCode(String v) {
    if (v == '有') return 'have';
    if (v == '申請中') return 'applying';
    if (v == '無') return 'none';
    return '';
  }

  @override
  void dispose() {
    for (final c in [
      _payerNameCtrl, _payerNameKanaCtrl, _postalCodeCtrl, _addressCtrl,
      _parentRelationCtrl, _emergencyNameCtrl,
      _emergencyPhoneCtrl, _emergencyRelationCtrl, _certNumberCtrl,
      _schoolCtrl, _kindergartenPhoneCtrl, _homeroomTeacherCtrl, _gradeCtrl,
      _hospitalCtrl, _hospitalPhoneCtrl, _doctorCtrl, _allergyCtrl,
      _severeSymptomsCtrl, _lunchTypeCtrl, _familyCompositionCtrl,
      _sensitivitiesCtrl, _precautionsCtrl, _childWishesCtrl, _familyWishesCtrl,
      _memoCtrl, _honeypotCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
      if (files.isEmpty) return;
      for (final f in files) {
        if (_certImages.length >= 4) break;
        final bytes = await f.readAsBytes();
        final ct = f.mimeType ??
            (f.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
        _certImages.add(_PickedImage(bytes, f.name, ct));
      }
      setState(() {});
    } catch (e) {
      setState(() => _errorMessage = '画像の読み込みに失敗しました: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_permitStatus.isEmpty) {
      setState(() => _errorMessage = '受給者証の有無を選択してください');
      return;
    }
    if (_permitStatus == '有' && _certImages.isEmpty) {
      setState(() => _errorMessage = '受給者証をお持ちの場合は、受給者証の写真（表・裏）を添付してください');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final payload = {
      'token': widget.token,
      'payerName': _payerNameCtrl.text.trim(),
      'payerNameKana': _payerNameKanaCtrl.text.trim(),
      'postalCode': _postalCodeCtrl.text.trim(),
      'addressDetail': _addressCtrl.text.trim(),
      'parentRelation': _parentRelationCtrl.text.trim(),
      'emergencyName': _emergencyNameCtrl.text.trim(),
      'emergencyPhone': _emergencyPhoneCtrl.text.trim(),
      'emergencyRelation': _emergencyRelationCtrl.text.trim(),
      'permitStatus': _permitToCode(_permitStatus),
      'certificateNumber': _certNumberCtrl.text.trim(),
      'kindergarten': _schoolCtrl.text.trim(),
      'kindergartenPhone': _kindergartenPhoneCtrl.text.trim(),
      'homeroomTeacher': _homeroomTeacherCtrl.text.trim(),
      'grade': _gradeCtrl.text.trim(),
      'hospitalName': _hospitalCtrl.text.trim(),
      'hospitalPhone': _hospitalPhoneCtrl.text.trim(),
      'doctorName': _doctorCtrl.text.trim(),
      'lunchType': _lunchTypeCtrl.text.trim(),
      'familyComposition': _familyCompositionCtrl.text.trim(),
      'allergy': _allergyCtrl.text.trim(),
      'severeSymptoms': _severeSymptomsCtrl.text.trim(),
      'sensitivities': _sensitivitiesCtrl.text.trim(),
      'precautions': _precautionsCtrl.text.trim(),
      'childWishes': _childWishesCtrl.text.trim(),
      'familyWishes': _familyWishesCtrl.text.trim(),
      'memo': _memoCtrl.text.trim(),
      'certImages': _certImages
          .map((i) => {
                'name': i.name,
                'contentType': i.contentType,
                'dataBase64': base64Encode(i.bytes),
              })
          .toList(),
      '_hp': _honeypotCtrl.text,
    };

    try {
      final res = await http.post(
        Uri.parse('$_base/submitFinalIntake'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200) {
        setState(() {
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
        title: const Text('ビースマイリープラス 入会前アンケート'),
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
            Text('ご回答ありがとうございました',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
            const SizedBox(height: 8),
            Text('内容を確認のうえ、担当者からご連絡させていただきます。',
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
                const BrandHeader(),
                _intro(),
                if (_banner != null) ...[
                  const SizedBox(height: 12),
                  _bannerBox(_banner!),
                ],
                const SizedBox(height: 16),
                _section('受給者証・実績記録票に記載されるお名前', [
                  _labelHint('保護者さまのお名前（漢字）',
                      '受給者証・実績記録票に記載されるお名前をご記入ください', required: true),
                  _input('', _payerNameCtrl, required: true),
                  _labelHint('保護者さまのお名前（フリガナ）', '', required: true),
                  _input('', _payerNameKanaCtrl, required: true),
                ]),
                _section('ご住所・連絡先', [
                  _input('郵便番号', _postalCodeCtrl,
                      required: true,
                      keyboard: TextInputType.number,
                      hint: '例: 251-0042'),
                  _input('ご住所（番地まで）', _addressCtrl,
                      required: true, maxLines: 2),
                  _input('保護者さまの続柄（お子さまから見て）', _parentRelationCtrl,
                      hint: '例: 父 / 母'),
                  _labelHint('緊急連絡先', '保護者さま以外で連絡がつく方（任意）'),
                  _input('お名前', _emergencyNameCtrl, hint: '例: 山田 花子'),
                  _row2(
                    _input('電話', _emergencyPhoneCtrl,
                        keyboard: TextInputType.phone, hint: '任意'),
                    _input('続柄', _emergencyRelationCtrl, hint: '例: 祖母'),
                  ),
                ]),
                _section('受給者証について', [
                  _permitSelector(),
                  if (_permitStatus == '有') ...[
                    const SizedBox(height: 10),
                    _certHint(
                        '受給者証の表・裏を撮影して、写真を添付してください。受給者証番号を書き写していただく必要はありません（写真から確認します）。'),
                    const SizedBox(height: 10),
                    _certUploader(),
                    const SizedBox(height: 8),
                    _input('受給者証番号（任意）', _certNumberCtrl,
                        keyboard: TextInputType.number,
                        hint: '写真がぼやけてしまった場合のみ、10桁の番号をご記入ください'),
                  ],
                  if (_permitStatus == '申請中') ...[
                    const SizedBox(height: 10),
                    _certHint('受給者証が届きましたら、表・裏のお写真をお送りください。'),
                  ],
                ]),
                _section('園・学校について', [
                  _input('幼稚園・保育園・学校名', _schoolCtrl, required: true),
                  _row2(
                    _input('学年', _gradeCtrl, hint: '例: 年長 / 小1'),
                    _input('担任の先生', _homeroomTeacherCtrl, hint: '任意'),
                  ),
                  _input('園・学校の連絡先', _kindergartenPhoneCtrl,
                      keyboard: TextInputType.phone, hint: '任意'),
                ]),
                _section('医療について', [
                  _input('かかりつけ病院名', _hospitalCtrl, required: true),
                  _row2(
                    _input('医師名', _doctorCtrl, hint: 'お分かりになれば'),
                    _input('病院の連絡先', _hospitalPhoneCtrl,
                        keyboard: TextInputType.phone, hint: '任意'),
                  ),
                  _labelHint('アレルギー', '食物・薬・その他。なければ空欄'),
                  _input('', _allergyCtrl, maxLines: 2),
                  _labelHint('てんかん・ひきつけ・喘息などの発作',
                      '急に起きて重症となる発作・症状があればご記入ください'),
                  _input('', _severeSymptomsCtrl, maxLines: 3),
                ]),
                _section('ヒアリング（分かる範囲で・任意）', [
                  _labelHint('敏感なもの・こと', '例：音、光、匂い、触覚など'),
                  _input('', _sensitivitiesCtrl, maxLines: 3),
                  _labelHint('気をつけてほしいこと', ''),
                  _input('', _precautionsCtrl, maxLines: 3),
                  _labelHint('ご本人の希望', '例：ビースマイリーでのご本人の意向'),
                  _input('', _childWishesCtrl, maxLines: 3),
                  _labelHint('ご家族の希望', '例：ビースマイリーでの保護者さまの意向'),
                  _input('', _familyWishesCtrl, maxLines: 3),
                ]),
                _section('ご家族・その他', [
                  _input('家族構成', _familyCompositionCtrl,
                      hint: '例: 父・母・本人・弟', maxLines: 2),
                  _input('お弁当の種類', _lunchTypeCtrl,
                      hint: '例: 標準 / 手作り弁当 / アレルギー対応'),
                  _input('その他お伝えしたいこと', _memoCtrl, maxLines: 3),
                ]),
                Offstage(
                  child: TextField(
                    controller: _honeypotCtrl,
                    decoration: const InputDecoration(labelText: 'website'),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _bannerBox(_errorMessage!, urgent: true),
                ],
                const SizedBox(height: 24),
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
    final greeting =
        _parentName.trim().isNotEmpty ? '$_parentName 様' : '保護者さまへ';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting,
              style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary)),
          if (_childName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('お子さま：$_childName さん',
                style: TextStyle(
                    fontSize: AppTextSize.caption, color: c.textSecondary)),
          ],
          const SizedBox(height: 10),
          Text(
              'このたびはご入会いただきありがとうございます。通いはじめのお手続きのため、下記のご入力をお願いいたします。',
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textSecondary,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _bannerBox(String text, {bool urgent = false}) {
    final a = urgent ? context.alerts.urgent : context.alerts.warning;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: a.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: a.border),
      ),
      child: Text(text,
          style: TextStyle(fontSize: AppTextSize.body, color: a.text)),
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
      int maxLines = 1,
      TextInputType? keyboard}) {
    final hasLabel = label.isNotEmpty;
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: hasLabel ? label + (required ? ' *' : '') : null,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) return '入力してください';
        return null;
      },
    );
  }

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

  Widget _permitSelector() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '受給者証の有無 *',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: Wrap(
        spacing: 8,
        children: [
          for (final v in const ['有', '無', '申請中'])
            ChoiceChip(
              label: Text(v,
                  style: const TextStyle(fontSize: AppTextSize.caption)),
              selected: _permitStatus == v,
              onSelected: (s) {
                if (s) setState(() => _permitStatus = v);
              },
            ),
        ],
      ),
    );
  }

  // 受給者証の有無に応じた、保護者向けの案内文（淡い色のミニカード）。
  Widget _certHint(String text) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: AppTextSize.body, color: c.textSecondary, height: 1.5)),
    );
  }

  Widget _certUploader() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelHint('受給者証の写真（表・裏）', '表と裏の2枚をご添付ください', required: true),
        if (_certImages.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _certImages.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_certImages[i].bytes,
                          width: 96, height: 96, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        icon: const Icon(Icons.cancel),
                        color: context.alerts.urgent.icon,
                        iconSize: 22,
                        onPressed: () =>
                            setState(() => _certImages.removeAt(i)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _certImages.length >= 4 ? null : _addImages,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_certImages.isEmpty ? '写真を追加' : '写真を追加（${_certImages.length}/4）',
              style: const TextStyle(fontSize: AppTextSize.body)),
        ),
        Text('スマホのカメラ・写真から選べます',
            style: TextStyle(fontSize: AppTextSize.xs, color: c.textTertiary)),
      ],
    );
  }
}
