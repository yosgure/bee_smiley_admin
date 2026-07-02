import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

/// 保護者用「コンディション」タブ（ビースマイリープラス保護者限定）
///
/// 2 段構えの記録:
/// 1. 毎日のきろく（30秒）: 子どもと一緒に「今日のキャラ」を選ぶ ＋ 疲れ度 1〜5
///    ＋ 一言メモ。タップした瞬間に自動保存。
///    → コレクション `condition_daily`、doc id = `${studentId}_${YYYY-MM-DD}`
/// 2. 月1かんたんシート（5分）: ゆっくり変わる項目だけ
///    （睡眠習慣・予定量・メディア傾向・今月の様子）。
///    → コレクション `condition_sheets`、doc id = `${studentId}_${YYYY-MM}`
///
/// 読み取りは決定的な doc id の直接 get のみで行い、クエリ（複合インデックス）を
/// 使わない。Firestore ルールは familyUid == uid の所有チェック。
///
/// 「できている／できていない」を評価するものではなく、どんな時に安定し、
/// どんな時に疲れやすいかを親子と支援者で見つけるための記録。
class ConditionCharacter {
  final String id;
  final String name;
  final String phrase; // 子ども向けの言葉
  final String emoji; // イラスト素材ができるまでの代用（将来 assetPath に差し替え）
  final Color color;

  const ConditionCharacter({
    required this.id,
    required this.name,
    required this.phrase,
    required this.emoji,
    required this.color,
  });
}

/// コンディションキャラクター（構想の基本5キャラ）。
/// 状態の意味が重ならないように選定されている。
const List<ConditionCharacter> kConditionCharacters = [
  ConditionCharacter(
    id: 'lion',
    name: 'げんきライオン',
    phrase: 'げんきいっぱい！やってみたい',
    emoji: '🦁',
    color: Color(0xFFF59E0B),
  ),
  ConditionCharacter(
    id: 'koala',
    name: 'のんびりコアラ',
    phrase: 'ゆっくりならできそう',
    emoji: '🐨',
    color: Color(0xFF66BB6A),
  ),
  ConditionCharacter(
    id: 'penguin',
    name: 'ねむねむペンギン',
    phrase: 'ねむいよ、ちょっとやすみたい',
    emoji: '🐧',
    color: Color(0xFF42A5F5),
  ),
  ConditionCharacter(
    id: 'squirrel',
    name: 'そわそわリス',
    phrase: 'まわりがきになっておちつかない',
    emoji: '🐿️',
    color: Color(0xFF9575CD),
  ),
  ConditionCharacter(
    id: 'panda',
    name: 'おやすみパンダ',
    phrase: 'つかれたよ、しっかりやすみたい',
    emoji: '🐼',
    color: Color(0xFF78909C),
  ),
];

class ParentConditionScreen extends StatefulWidget {
  final String? childId; // `${familyUid}_${firstName}`
  final String childName;
  final String? familyUid;
  final List<Map<String, dynamic>> allChildren;
  final int selectedChildIndex;
  final Function(int)? onChildChanged;

  /// テスト時に FakeFirebaseFirestore を注入するための口。通常は null。
  final FirebaseFirestore? firestore;

  const ParentConditionScreen({
    super.key,
    required this.childId,
    required this.childName,
    required this.familyUid,
    this.allChildren = const [],
    this.selectedChildIndex = 0,
    this.onChildChanged,
    this.firestore,
  });

  @override
  State<ParentConditionScreen> createState() => _ParentConditionScreenState();
}

class _ParentConditionScreenState extends State<ParentConditionScreen> {
  FirebaseFirestore get _fs => widget.firestore ?? FirebaseFirestore.instance;

  // 月次シートの編集中の月（null = 通常表示）
  DateTime? _editingMonth;

  // 表示モード: 0 = きろく（日次入力） / 1 = ふりかえり（月の可視化）
  int _viewMode = 0;

  // ふりかえりの対象月と、月まるごとの日次キャッシュ（monthKey → dateKey → データ）
  late DateTime _reviewMonth;
  final Map<String, Map<String, Map<String, dynamic>>> _monthCache = {};
  bool _monthLoading = false;

  // 日次記録の表示・編集対象日（週ストリップで切替、初期値は今日）
  late String _selectedDateKey;

  // 読み込んだ日次記録（dateKey → データ）と月次シート（monthKey → データ）
  final Map<String, Map<String, dynamic>> _daily = {};
  final Map<String, Map<String, dynamic>> _sheets = {};
  bool _loading = true;
  bool _savingNote = false;
  DateTime? _lastSavedAt;

  final _noteCtl = TextEditingController();

  static String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static String _monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

  String get _todayKey => _dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _selectedDateKey = _todayKey;
    final now = DateTime.now();
    _reviewMonth = DateTime(now.year, now.month);
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant ParentConditionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      // 子ども切替時はリセットして再読み込み
      _daily.clear();
      _sheets.clear();
      _monthCache.clear();
      _selectedDateKey = _todayKey;
      _editingMonth = null;
      _lastSavedAt = null;
      _loadAll();
      if (_viewMode == 1) _loadMonth(_reviewMonth);
    }
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
  }

  /// 直近7日の日次記録 + 直近12ヶ月の月次シートを doc id 直接 get で読み込む。
  /// クエリを使わないので複合インデックス不要・ルールも単純な所有チェックで済む。
  Future<void> _loadAll() async {
    final childId = widget.childId;
    if (childId == null) return;
    setState(() => _loading = true);

    try {
      final fs = _fs;
      final now = DateTime.now();

      final dateKeys = List.generate(
          7, (i) => _dateKey(now.subtract(Duration(days: 6 - i))));
      final monthKeys =
          List.generate(12, (i) => _monthKey(DateTime(now.year, now.month - i)));

      final results = await Future.wait([
        ...dateKeys.map(
            (k) => fs.collection('condition_daily').doc('${childId}_$k').get()),
        ...monthKeys.map((k) =>
            fs.collection('condition_sheets').doc('${childId}_$k').get()),
      ]);

      if (!mounted || childId != widget.childId) return;

      _daily.clear();
      _sheets.clear();
      for (var i = 0; i < dateKeys.length; i++) {
        final doc = results[i];
        if (doc.exists) _daily[dateKeys[i]] = doc.data()!;
      }
      for (var i = 0; i < monthKeys.length; i++) {
        final doc = results[dateKeys.length + i];
        if (doc.exists) _sheets[monthKeys[i]] = doc.data()!;
      }
      _syncNoteController();
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('condition load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _syncNoteController() {
    _noteCtl.text = (_daily[_selectedDateKey]?['note'] ?? '').toString();
  }

  /// ふりかえり用に、対象月の日次記録を doc id 直接 get でまとめて読み込む。
  Future<void> _loadMonth(DateTime month) async {
    final childId = widget.childId;
    if (childId == null) return;
    final mk = _monthKey(month);
    if (_monthCache.containsKey(mk)) return;
    setState(() => _monthLoading = true);

    try {
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      final dateKeys = List.generate(
          lastDay, (i) => _dateKey(DateTime(month.year, month.month, i + 1)));
      final snaps = await Future.wait(dateKeys.map((k) =>
          _fs.collection('condition_daily').doc('${childId}_$k').get()));

      if (!mounted || childId != widget.childId) return;
      final map = <String, Map<String, dynamic>>{};
      for (var i = 0; i < dateKeys.length; i++) {
        if (snaps[i].exists) map[dateKeys[i]] = snaps[i].data()!;
      }
      setState(() {
        _monthCache[mk] = map;
        _monthLoading = false;
      });
    } catch (e) {
      debugPrint('condition month load error: $e');
      if (mounted) setState(() => _monthLoading = false);
    }
  }

  /// 日次記録の部分保存（タップした瞬間に呼ぶ）。
  /// character は明示的に null を渡すと「選択解除」として保存する。
  Future<void> _saveDaily({
    Object? character = _noChange,
    Object? fatigue = _noChange,
    Object? note = _noChange,
  }) async {
    final childId = widget.childId;
    if (childId == null || widget.familyUid == null) return;
    final dateKey = _selectedDateKey;

    final payload = <String, dynamic>{
      'studentId': childId,
      'familyUid': widget.familyUid,
      'childName': widget.childName,
      'dateKey': dateKey,
      'date': Timestamp.fromDate(DateTime.parse(dateKey)),
      'createdBy': 'parent',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (character != _noChange) payload['character'] = character;
    if (fatigue != _noChange) payload['fatigue'] = fatigue;
    if (note != _noChange) payload['note'] = note;

    // 先にローカル状態へ反映（タップの手応えを即座に返す）
    setState(() {
      final local = Map<String, dynamic>.from(_daily[dateKey] ?? {});
      if (character != _noChange) local['character'] = character;
      if (fatigue != _noChange) local['fatigue'] = fatigue;
      if (note != _noChange) local['note'] = note;
      _daily[dateKey] = local;
      // ふりかえり用の月キャッシュにも反映
      final mk = dateKey.substring(0, 7);
      _monthCache[mk]?[dateKey] = local;
      _lastSavedAt = DateTime.now();
    });

    try {
      await _fs
          .collection('condition_daily')
          .doc('${childId}_$dateKey')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, '保存に失敗しました: $e');
        setState(() => _lastSavedAt = null);
      }
    }
  }

  static const Object _noChange = Object();

  @override
  Widget build(BuildContext context) {
    if (widget.childId == null) {
      return Center(
        child: Text('お子さまの情報がありません',
            style: TextStyle(color: context.colors.textSecondary)),
      );
    }

    if (_editingMonth != null) {
      return _MonthlySheetEditor(
        key: ValueKey('${widget.childId}_${_monthKey(_editingMonth!)}'),
        firestore: _fs,
        studentId: widget.childId!,
        familyUid: widget.familyUid,
        childName: widget.childName,
        month: _editingMonth!,
        initialData: _sheets[_monthKey(_editingMonth!)],
        onClose: (saved) {
          setState(() => _editingMonth = null);
          if (saved != null) {
            setState(() => _sheets[_monthKey(saved)] = _sheets[_monthKey(saved)] ?? {});
            _loadAll();
          }
        },
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    label: Text('きろく'),
                    icon: Icon(Icons.edit_note, size: 18)),
                ButtonSegment(
                    value: 1,
                    label: Text('ふりかえり'),
                    icon: Icon(Icons.insights, size: 18)),
              ],
              selected: {_viewMode},
              onSelectionChanged: (s) {
                setState(() => _viewMode = s.first);
                if (s.first == 1) _loadMonth(_reviewMonth);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _viewMode == 0
                      ? [
                          _buildWeekStrip(),
                          const SizedBox(height: 12),
                          _buildDailyCard(),
                          const SizedBox(height: 24),
                          _buildMonthlySection(),
                          const SizedBox(height: 24),
                        ]
                      : _buildReviewChildren(),
                ),
        ),
      ],
    );
  }

  // ---------------- ヘッダー（子ども切替） ----------------
  Widget _buildHeader() {
    final hasMultipleChildren = widget.allChildren.length > 1;
    final title = '${widget.childName}のコンディション';
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(bottom: BorderSide(color: context.colors.borderLight)),
      ),
      child: Center(
        child: hasMultipleChildren
            ? PopupMenuButton<int>(
                onSelected: (index) => widget.onChildChanged?.call(index),
                offset: const Offset(0, 40),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: AppTextSize.title,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down,
                        color: context.colors.iconMuted),
                  ],
                ),
                itemBuilder: (context) {
                  return widget.allChildren.asMap().entries.map((entry) {
                    final index = entry.key;
                    final child = entry.value;
                    final firstName = child['firstName'] ?? '';
                    final photoUrl = child['photoUrl'];
                    final isSelected = index == widget.selectedChildIndex;
                    return PopupMenuItem<int>(
                      value: index,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                AppColors.primary.withOpacity(0.1),
                            backgroundImage:
                                photoUrl != null && photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                            child: photoUrl == null || photoUrl.isEmpty
                                ? const Icon(Icons.person,
                                    size: 14, color: AppColors.primary)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Text(firstName,
                              style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          if (isSelected) ...[
                            const Spacer(),
                            const Icon(Icons.check,
                                color: AppColors.primary, size: 18),
                          ],
                        ],
                      ),
                    );
                  }).toList();
                },
              )
            : Text(title,
                style: const TextStyle(
                    fontSize: AppTextSize.title, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ---------------- 週ストリップ（直近7日、タップで対象日切替） ----------------
  Widget _buildWeekStrip() {
    final now = DateTime.now();
    final days =
        List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Row(
        children: days.map((d) {
          final key = _dateKey(d);
          final data = _daily[key];
          final charId = data?['character'] as String?;
          final char = charId == null
              ? null
              : kConditionCharacters
                  .where((c) => c.id == charId)
                  .firstOrNull;
          final fatigue = data?['fatigue'] as int?;
          final isSelected = key == _selectedDateKey;
          final isToday = key == _todayKey;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _selectedDateKey = key;
                _syncNoteController();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('E', 'ja').format(d),
                      style: TextStyle(
                          fontSize: AppTextSize.caption,
                          color: isToday
                              ? AppColors.primary
                              : context.colors.textSecondary,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal),
                    ),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: AppTextSize.body,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(char?.emoji ?? '・',
                        style:
                            const TextStyle(fontSize: AppTextSize.titleLg)),
                    const SizedBox(height: 3),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fatigue != null && fatigue > 0
                            ? _fatigueColor(fatigue)
                            : context.colors.borderLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------- 日次きろくカード ----------------
  Widget _buildDailyCard() {
    final data = _daily[_selectedDateKey];
    final selectedChar = data?['character'] as String?;
    final fatigue = data?['fatigue'] as int? ?? 0;
    final date = DateTime.parse(_selectedDateKey);
    final isToday = _selectedDateKey == _todayKey;
    final dateLabel = isToday
        ? 'きょう（${DateFormat('M/d(E)', 'ja').format(date)}）'
        : DateFormat('M月d日(E)', 'ja').format(date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('$dateLabelのようす',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
              const Spacer(),
              if (_lastSavedAt != null)
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text('ほぞんしました',
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: context.colors.textSecondary)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('お子さんと一緒に、今のきもちに近いキャラクターを選んでください',
              style: TextStyle(
                  fontSize: AppTextSize.small,
                  color: context.colors.textSecondary)),
          const SizedBox(height: 12),

          // キャラクター選択
          LayoutBuilder(builder: (context, constraints) {
            const spacing = 8.0;
            final tileW = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: kConditionCharacters.map((c) {
                final isSel = selectedChar == c.id;
                return GestureDetector(
                  onTap: () =>
                      _saveDaily(character: isSel ? null : c.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: tileW,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSel
                          ? c.color.withOpacity(0.18)
                          : context.colors.chipBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSel
                              ? c.color
                              : context.colors.borderLight,
                          width: isSel ? 2 : 1),
                    ),
                    child: Column(
                      children: [
                        Text(c.emoji,
                            style:
                                const TextStyle(fontSize: AppTextSize.hero)),
                        const SizedBox(height: 4),
                        Text(c.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: AppTextSize.caption,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: context.colors.textPrimary)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),

          // 選んだキャラの子ども向けフレーズ
          if (selectedChar != null) ...[
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final c = kConditionCharacters
                  .where((c) => c.id == selectedChar)
                  .firstOrNull;
              if (c == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: c.color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('「${c.phrase}」',
                    style: TextStyle(
                        fontSize: AppTextSize.body,
                        color: context.colors.textPrimary)),
              );
            }),
          ],

          const SizedBox(height: 16),
          Text('つかれ度（保護者から見て）',
              style: const TextStyle(
                  fontSize: AppTextSize.body, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('1=元気 ・ 3=疲れているが過ごせる ・ 5=限界に近い',
              style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: context.colors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (j) {
              final level = j + 1;
              final isSel = fatigue == level;
              return GestureDetector(
                onTap: () => _saveDaily(fatigue: isSel ? null : level),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isSel ? _fatigueColor(level) : context.colors.chipBg,
                    border: Border.all(
                        color: isSel
                            ? _fatigueColor(level)
                            : context.colors.borderLight),
                  ),
                  alignment: Alignment.center,
                  child: Text('$level',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.bodyLarge,
                          color: isSel
                              ? Colors.white
                              : context.colors.textSecondary)),
                ),
              );
            }),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _noteCtl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: '気になった様子・メモ（任意）',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              suffixIcon: _savingNote
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(Icons.check, color: AppColors.primary),
                      tooltip: 'メモを保存',
                      onPressed: () async {
                        setState(() => _savingNote = true);
                        await _saveDaily(note: _noteCtl.text.trim());
                        if (mounted) setState(() => _savingNote = false);
                      },
                    ),
            ),
            onSubmitted: (v) => _saveDaily(note: v.trim()),
          ),
        ],
      ),
    );
  }

  Color _fatigueColor(int level) {
    switch (level) {
      case 1:
        return AppColors.success;
      case 2:
        return const Color(0xFF9CCC65);
      case 3:
        return AppColors.warning;
      case 4:
        return const Color(0xFFFB8C00);
      case 5:
        return AppColors.error;
      default:
        return context.colors.borderLight;
    }
  }

  // ---------------- 月1かんたんシートセクション ----------------
  Widget _buildMonthlySection() {
    final now = DateTime.now();
    final thisMonthKey = _monthKey(now);
    final hasThisMonth = _sheets.containsKey(thisMonthKey);

    // 過去分（今月以外）を新しい順に
    final pastKeys = _sheets.keys.where((k) => k != thisMonthKey).toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('月1かんたんシート',
            style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.bold,
                color: context.colors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          '睡眠・メディア・予定量など、月に1回だけまとめて記録します。毎月の面談で一緒にふりかえります。',
          style: TextStyle(
              fontSize: AppTextSize.small,
              height: 1.5,
              color: context.colors.textSecondary),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => setState(
                () => _editingMonth = DateTime(now.year, now.month)),
            icon: Icon(hasThisMonth ? Icons.edit : Icons.add),
            label: Text(hasThisMonth
                ? '${DateFormat('M月', 'ja').format(now)}のシートを編集'
                : '${DateFormat('M月', 'ja').format(now)}のシートを記入'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (pastKeys.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...pastKeys.map((k) {
            DateTime? month;
            try {
              final parts = k.split('-');
              month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
            } catch (_) {}
            final label = month != null
                ? DateFormat('yyyy年 M月', 'ja').format(month)
                : k;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.colors.borderLight),
              ),
              child: ListTile(
                onTap: month == null
                    ? null
                    : () => setState(() => _editingMonth = month),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month,
                      color: AppColors.primary),
                ),
                title: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyLarge)),
                trailing:
                    Icon(Icons.chevron_right, color: context.colors.iconMuted),
              ),
            );
          }),
        ],
      ],
    );
  }

  // ---------------- ふりかえり（月の可視化） ----------------
  List<Widget> _buildReviewChildren() {
    final mk = _monthKey(_reviewMonth);
    final monthData = _monthCache[mk];
    final now = DateTime.now();
    final isCurrentMonth =
        _reviewMonth.year == now.year && _reviewMonth.month == now.month;
    // さかのぼりは11ヶ月前まで（月次シートの読み込み範囲と揃える）
    final oldest = DateTime(now.year, now.month - 11);
    final canGoBack = _reviewMonth.isAfter(oldest);

    return [
      _buildMonthNav(isCurrentMonth: isCurrentMonth, canGoBack: canGoBack),
      const SizedBox(height: 12),
      if (_monthLoading || monthData == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (monthData.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          alignment: Alignment.center,
          child: Column(
            children: [
              Icon(Icons.insights,
                  size: 48, color: context.colors.borderMedium),
              const SizedBox(height: 12),
              Text('この月の記録はまだありません',
                  style: TextStyle(color: context.colors.textSecondary)),
            ],
          ),
        )
      else ...[
        _buildCharDistCard(monthData),
        const SizedBox(height: 16),
        _buildFatigueChartCard(monthData),
        const SizedBox(height: 16),
        ..._buildNotesCard(monthData),
      ],
      const SizedBox(height: 8),
      _buildReviewSheetButton(mk),
      const SizedBox(height: 24),
    ];
  }

  Widget _buildMonthNav(
      {required bool isCurrentMonth, required bool canGoBack}) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: canGoBack
              ? () {
                  final prev = DateTime(
                      _reviewMonth.year, _reviewMonth.month - 1);
                  setState(() => _reviewMonth = prev);
                  _loadMonth(prev);
                }
              : null,
        ),
        Expanded(
          child: Text(
            DateFormat('yyyy年 M月', 'ja').format(_reviewMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: AppTextSize.title, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrentMonth
              ? null
              : () {
                  final next = DateTime(
                      _reviewMonth.year, _reviewMonth.month + 1);
                  setState(() => _reviewMonth = next);
                  _loadMonth(next);
                },
        ),
      ],
    );
  }

  Widget _buildCharDistCard(Map<String, Map<String, dynamic>> monthData) {
    final counts = {for (final c in kConditionCharacters) c.id: 0};
    var recordedDays = 0;
    for (final d in monthData.values) {
      final charId = d['character'] as String?;
      if (charId != null && counts.containsKey(charId)) counts[charId] = counts[charId]! + 1;
      if (charId != null || (d['fatigue'] as int? ?? 0) > 0) recordedDays++;
    }
    final maxCount =
        counts.values.fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pets, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text('キャラクターのぶんぷ',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
              const Spacer(),
              Text('記録 $recordedDays日',
                  style: TextStyle(
                      fontSize: AppTextSize.small,
                      color: context.colors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          ...kConditionCharacters.map((c) {
            final count = counts[c.id]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(c.emoji,
                      style: const TextStyle(fontSize: AppTextSize.titleLg)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 108,
                    child: Text(c.name,
                        style:
                            const TextStyle(fontSize: AppTextSize.small)),
                  ),
                  Expanded(
                    child: Container(
                      height: 12,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: count / maxCount,
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text('$count日',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: AppTextSize.small,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFatigueChartCard(Map<String, Map<String, dynamic>> monthData) {
    final points = <MapEntry<int, int>>[];
    monthData.forEach((dateKey, d) {
      final f = d['fatigue'] as int?;
      if (f != null && f >= 1 && f <= 5) {
        points.add(MapEntry(int.parse(dateKey.substring(8)), f));
      }
    });
    points.sort((a, b) => a.key.compareTo(b.key));
    final daysInMonth =
        DateTime(_reviewMonth.year, _reviewMonth.month + 1, 0).day;
    final avg = points.isEmpty
        ? null
        : points.map((p) => p.value).reduce((a, b) => a + b) / points.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text('つかれ度のすいい',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
              const Spacer(),
              if (avg != null)
                Text('平均 ${avg.toStringAsFixed(1)}',
                    style: TextStyle(
                        fontSize: AppTextSize.small,
                        color: context.colors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Text('1=元気 〜 5=限界に近い',
              style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: context.colors.textSecondary)),
          const SizedBox(height: 8),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('つかれ度の記録がありません',
                    style:
                        TextStyle(color: context.colors.textSecondary)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 160,
              child: CustomPaint(
                painter: _FatigueChartPainter(
                  points: points,
                  daysInMonth: daysInMonth,
                  gridColor: context.colors.borderLight,
                  labelColor: context.colors.textSecondary,
                  lineColor: context.colors.borderMedium,
                  levelColors: [
                    for (var lv = 1; lv <= 5; lv++) _fatigueColor(lv)
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNotesCard(Map<String, Map<String, dynamic>> monthData) {
    final notes = monthData.entries
        .where((e) => (e.value['note'] ?? '').toString().trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (notes.isEmpty) return [];

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.sticky_note_2_outlined,
                    color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('気になった様子・メモ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyLarge,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            ...notes.map((e) {
              final date = DateTime.parse(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        DateFormat('M/d(E)', 'ja').format(date),
                        style: const TextStyle(
                            fontSize: AppTextSize.small,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(e.value['note'].toString(),
                          style: const TextStyle(
                              fontSize: AppTextSize.body, height: 1.5)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildReviewSheetButton(String mk) {
    final hasSheet = _sheets.containsKey(mk);
    final label = DateFormat('M月', 'ja').format(_reviewMonth);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _editingMonth =
            DateTime(_reviewMonth.year, _reviewMonth.month)),
        icon: Icon(hasSheet ? Icons.description : Icons.add, size: 18),
        label: Text(hasSheet ? '$labelのかんたんシートを見る・編集' : '$labelのかんたんシートを記入'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// 疲れ度の月間推移チャート（依存ライブラリなしの CustomPainter 実装）。
/// 横軸 = 日（1〜月末）、縦軸 = 疲れ度 1〜5（上ほど疲れている）。
/// 点は疲れ度レベルの色、点同士は控えめな線でつなぐ。
class _FatigueChartPainter extends CustomPainter {
  final List<MapEntry<int, int>> points; // (日, 疲れ度) 昇順
  final int daysInMonth;
  final Color gridColor;
  final Color labelColor;
  final Color lineColor;
  final List<Color> levelColors; // index 0 = レベル1

  _FatigueChartPainter({
    required this.points,
    required this.daysInMonth,
    required this.gridColor,
    required this.labelColor,
    required this.lineColor,
    required this.levelColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 22.0, rightPad = 8.0, topPad = 8.0, bottomPad = 20.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    double yFor(num level) => topPad + plotH * (5 - level) / 4;
    double xFor(int day) => daysInMonth <= 1
        ? leftPad
        : leftPad + plotW * (day - 1) / (daysInMonth - 1);

    // 横グリッド（レベル1〜5）と左ラベル
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var lv = 1; lv <= 5; lv++) {
      final y = yFor(lv);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      _label(canvas, '$lv', Offset(4, y - 6));
    }
    // 下部の日ラベル
    for (final d in const [1, 5, 10, 15, 20, 25, 30]) {
      if (d > daysInMonth) continue;
      _label(canvas, '$d', Offset(xFor(d) - 4, size.height - 14));
    }

    // 折れ線
    if (points.length >= 2) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(xFor(points.first.key), yFor(points.first.value));
      for (final p in points.skip(1)) {
        path.lineTo(xFor(p.key), yFor(p.value));
      }
      canvas.drawPath(path, linePaint);
    }
    // ドット（レベル色）
    for (final p in points) {
      canvas.drawCircle(
        Offset(xFor(p.key), yFor(p.value)),
        4.5,
        Paint()..color = levelColors[(p.value - 1).clamp(0, 4)],
      );
    }
  }

  void _label(Canvas canvas, String s, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: AppTextSize.xs, color: labelColor)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FatigueChartPainter old) =>
      old.points != points ||
      old.daysInMonth != daysInMonth ||
      old.gridColor != gridColor ||
      old.lineColor != lineColor;
}

// ============================================================
// 月1かんたんシート（スリム版・約5分で記入できる分量）
// 毎日変わるもの（キャラ・疲れ度）は日次記録に移したので、
// ここはゆっくり変わる傾向だけを聞く。
// ============================================================
class _MonthlySheetEditor extends StatefulWidget {
  final FirebaseFirestore firestore;
  final String studentId;
  final String? familyUid;
  final String childName;
  final DateTime month;
  final Map<String, dynamic>? initialData;

  /// 保存して閉じたら月を、キャンセルなら null を渡して呼ばれる
  final void Function(DateTime? savedMonth) onClose;

  const _MonthlySheetEditor({
    super.key,
    required this.firestore,
    required this.studentId,
    required this.familyUid,
    required this.childName,
    required this.month,
    required this.initialData,
    required this.onClose,
  });

  @override
  State<_MonthlySheetEditor> createState() => _MonthlySheetEditorState();
}

class _MonthlySheetEditorState extends State<_MonthlySheetEditor> {
  final Map<String, String> _choices = {};
  final Set<String> _multi = {};
  TimeOfDay? _bedtime;
  TimeOfDay? _wakeTime;
  final _concernedCtl = TextEditingController();
  final _stableCtl = TextEditingController();
  bool _saving = false;

  String get _monthKey => DateFormat('yyyy-MM').format(widget.month);
  String get _docId => '${widget.studentId}_$_monthKey';

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    if (data != null) {
      final sleep = (data['sleep'] as Map?) ?? {};
      final schedule = (data['schedule'] as Map?) ?? {};
      final media = (data['media'] as Map?) ?? {};
      final mediaStop = (data['mediaStop'] as Map?) ?? {};

      _bedtime = _parseTime(sleep['bedtime']);
      _wakeTime = _parseTime(sleep['wakeTime']);
      for (final k in _sleepChoiceKeys) {
        if (sleep[k] is String) _choices['sleep.$k'] = sleep[k];
      }
      for (final k in _scheduleLabels) {
        if (schedule[k] == true) _multi.add('schedule.$k');
      }
      for (final k in _mediaKeys) {
        if (media[k] is String) _choices['media.$k'] = media[k];
      }
      for (final t in (data['mediaTimings'] as List? ?? [])) {
        _multi.add('mediaTiming.$t');
      }
      for (final k in _mediaStopKeys) {
        if (mediaStop[k] is String) _choices['mediaStop.$k'] = mediaStop[k];
      }
      _concernedCtl.text = (data['concernedBehavior'] ?? '').toString();
      _stableCtl.text = (data['stableScenes'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _concernedCtl.dispose();
    _stableCtl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(dynamic v) {
    if (v is! String || !v.contains(':')) return null;
    final parts = v.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String? _fmtTime(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final sleep = <String, dynamic>{
        'bedtime': _fmtTime(_bedtime),
        'wakeTime': _fmtTime(_wakeTime),
      };
      for (final k in _sleepChoiceKeys) {
        sleep[k] = _choices['sleep.$k'];
      }
      final schedule = <String, dynamic>{
        for (final k in _scheduleLabels) k: _multi.contains('schedule.$k'),
      };
      final media = <String, dynamic>{
        for (final k in _mediaKeys) k: _choices['media.$k'],
      };
      final mediaStop = <String, dynamic>{
        for (final k in _mediaStopKeys) k: _choices['mediaStop.$k'],
      };
      final mediaTimings = _mediaTimingLabels
          .where((t) => _multi.contains('mediaTiming.$t'))
          .toList();

      await widget.firestore
          .collection('condition_sheets')
          .doc(_docId)
          .set({
        'studentId': widget.studentId,
        'familyUid': widget.familyUid,
        'childName': widget.childName,
        'monthKey': _monthKey,
        'month': Timestamp.fromDate(widget.month),
        'type': 'monthly',
        'createdBy': 'parent',
        'sleep': sleep,
        'schedule': schedule,
        'media': media,
        'mediaTimings': mediaTimings,
        'mediaStop': mediaStop,
        'concernedBehavior': _concernedCtl.text.trim(),
        'stableScenes': _stableCtl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      AppFeedback.success(context, '保存しました');
      widget.onClose(widget.month);
    } catch (e) {
      if (mounted) AppFeedback.error(context, '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('yyyy年 M月', 'ja').format(widget.month);

    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            border:
                Border(bottom: BorderSide(color: context.colors.borderLight)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: _saving ? null : () => widget.onClose(null),
              ),
              Expanded(
                child: Text('$monthLabel のかんたんシート',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: AppTextSize.title,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'できている・できていないの評価ではありません。お子さんが安定しやすい生活リズムを一緒に探すための記録です。',
                style: TextStyle(
                    fontSize: AppTextSize.small,
                    height: 1.5,
                    color: context.colors.textSecondary),
              ),
              const SizedBox(height: 16),
              _buildSleepSection(),
              const SizedBox(height: 20),
              _buildScheduleSection(),
              const SizedBox(height: 20),
              _buildMediaSection(),
              const SizedBox(height: 20),
              _buildNotesSection(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('保存する',
                        style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _choiceRow(String label, String key, List<String> options) {
    final selected = _choices[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTextSize.body, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final isSel = selected == o;
              return ChoiceChip(
                label: Text(o),
                selected: isSel,
                onSelected: (_) => setState(() {
                  if (isSel) {
                    _choices.remove(key);
                  } else {
                    _choices[key] = o;
                  }
                }),
                labelStyle: TextStyle(
                    fontSize: AppTextSize.body,
                    color: isSel ? Colors.white : context.colors.textPrimary),
                selectedColor: AppColors.primary,
                backgroundColor: context.colors.chipBg,
                showCheckmark: false,
                side: BorderSide(color: context.colors.borderLight),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _multiRow(String label, String prefix, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(label,
                style: const TextStyle(
                    fontSize: AppTextSize.body, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final k = '$prefix.$o';
              final isSel = _multi.contains(k);
              return FilterChip(
                label: Text(o),
                selected: isSel,
                onSelected: (_) => setState(() {
                  if (isSel) {
                    _multi.remove(k);
                  } else {
                    _multi.add(k);
                  }
                }),
                labelStyle: TextStyle(
                    fontSize: AppTextSize.body,
                    color: isSel ? Colors.white : context.colors.textPrimary),
                selectedColor: AppColors.primary,
                checkmarkColor: Colors.white,
                backgroundColor: context.colors.chipBg,
                side: BorderSide(color: context.colors.borderLight),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _timeRow(
      String label, TimeOfDay? value, ValueChanged<TimeOfDay?> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: AppTextSize.body, fontWeight: FontWeight.w600)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: value ?? const TimeOfDay(hour: 21, minute: 0),
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (picked != null) onPick(picked);
            },
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(value == null
                ? '選択'
                : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: context.colors.borderMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepSection() {
    return _section('睡眠・生活リズム（いつもの傾向）', Icons.bedtime, [
      _timeRow('いつもの就寝時間', _bedtime, (t) => setState(() => _bedtime = t)),
      _timeRow('いつもの起床時間', _wakeTime, (t) => setState(() => _wakeTime = t)),
      _choiceRow('寝つき', 'sleep.fallAsleep', const ['よい', '時間がかかる', '日による']),
      _choiceRow('夜中に起きる', 'sleep.nightWaking', const ['なし', '1回', '2回以上']),
      _choiceRow('朝の機嫌', 'sleep.morningMood', const ['よい', 'ふつう', '不安定']),
    ]);
  }

  Widget _buildScheduleSection() {
    return _section('今月の予定量', Icons.event_note, [
      Text('あてはまるものを選んでください',
          style: TextStyle(
              fontSize: AppTextSize.small,
              color: context.colors.textSecondary)),
      const SizedBox(height: 10),
      _multiRow('', 'schedule', _scheduleLabels),
    ]);
  }

  Widget _buildMediaSection() {
    return _section('メディア利用（いつもの傾向）', Icons.tv, [
      ..._mediaLabels.entries
          .map((e) => _choiceRow(e.value, 'media.${e.key}', _mediaAmounts)),
      const Divider(height: 24),
      _multiRow('よく見るタイミング', 'mediaTiming', _mediaTimingLabels),
      const Divider(height: 24),
      _choiceRow('声かけでやめられる', 'mediaStop.voiceStop',
          const ['できる', '時々できる', '難しい']),
      _choiceRow('やめる時に泣く・怒ることがある', 'mediaStop.cryAngry',
          const ['よくある', '時々ある', 'ない']),
    ]);
  }

  Widget _buildNotesSection() {
    return _section('今月の様子', Icons.edit_note, [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: _concernedCtl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '気になった行動',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
      ),
      TextField(
        controller: _stableCtl,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: '安定していた場面',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
    ]);
  }

  // ---------- キー定義（Firestore 保存キーは Phase 1 と互換） ----------
  static const _sleepChoiceKeys = ['fallAsleep', 'nightWaking', 'morningMood'];
  static const List<String> _scheduleLabels = [
    '園・療育後に予定が多かった',
    '習い事や外出が続いた',
    '移動時間が長かった',
    '人が多い場所に行った',
    '休む時間が少なかった',
    '家でゆっくり過ごす時間があった',
  ];
  static const Map<String, String> _mediaLabels = {
    'tv': 'テレビ',
    'youtube': 'YouTube',
    'game': 'ゲーム',
    'tablet': 'スマホ・タブレット',
  };
  static const _mediaKeys = ['tv', 'youtube', 'game', 'tablet'];
  static const _mediaAmounts = ['なし', '30分以内', '1時間', '2時間', '3時間以上'];
  static const _mediaTimingLabels = [
    '朝の準備前',
    '食事中',
    '帰宅後すぐ',
    '寝る前',
    '癇癪を落ち着かせるため',
    '親が忙しい時',
  ];
  static const _mediaStopKeys = ['voiceStop', 'cryAngry'];
}
