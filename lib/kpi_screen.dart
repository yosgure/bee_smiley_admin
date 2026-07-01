import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

/// KPI（OKR週次進捗）画面。上田洋介・上田藍のみ（staffs.kpiAccess == true）。
///
/// 週次の「作業ドキュメント」。カテゴリ1件 = 1カード:
///   [識別: 名前 / KR / 目標バー] | [実績: その週の数字＋メモ] | [やること: タスク（縦に増やせる）]
/// 上部ヘッダーの ◀▶ / 今週へ で対象の週を切り替える。
///
/// データ:
///  - kpi_categories/{id}: { name, objective, krContent, krTarget(num?), order(int) }
///  - kpi_entries/{id} (id="{categoryId}_{yyyyMMdd(月曜)}"):
///      { categoryId, weekStart(Timestamp), resultValue(num?), note(String), tasks:[{title,done}] }
class KpiScreen extends StatefulWidget {
  const KpiScreen({super.key});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _categoriesRef =>
      _db.collection('kpi_categories');
  CollectionReference<Map<String, dynamic>> get _entriesRef =>
      _db.collection('kpi_entries');

  int _weekShift = 0; // 今週からのずらし幅（週単位、0=今週）

  /// 最新スナップショットの entries。コールバック実行時に常に最新を参照する
  /// （build時のクロージャ捕捉だと連続追加でタスクが消える競合が起きるため）。
  Map<String, Map<String, dynamic>> _entriesCache = {};

  // 「今週」ラベルを実カレンダーに追随させる（週跨ぎで開きっぱなしのタブ対策）
  Timer? _weekWatch;
  DateTime? _lastSeenMonday;

  @override
  void initState() {
    super.initState();
    _lastSeenMonday = _currentMonday;
    _weekWatch = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _currentMonday != _lastSeenMonday) {
        setState(() => _lastSeenMonday = _currentMonday);
      }
    });
  }

  @override
  void dispose() {
    _weekWatch?.cancel();
    super.dispose();
  }

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  DateTime get _currentMonday => _mondayOf(DateTime.now());
  DateTime get _focusMonday =>
      _currentMonday.add(Duration(days: 7 * _weekShift));
  bool get _focusIsCurrent => _weekShift == 0;

  String _weekKey(DateTime monday) => DateFormat('yyyyMMdd').format(monday);
  String _entryId(String categoryId, DateTime monday) =>
      '${categoryId}_${_weekKey(monday)}';

  Map<String, dynamic>? _entryOf(String catId, DateTime monday) =>
      _entriesCache[_entryId(catId, monday)];

  num? _resultAt(String catId, DateTime monday) {
    final v = _entryOf(catId, monday)?['resultValue'];
    // NaN/Infinity が紛れ込むと描画側の round()/toInt() で落ちるため弾く
    return (v is num && v.isFinite) ? v : null;
  }

  // 直近の非null実績（focus週から過去へ遡る）。目標バー用。
  num? _latestResult(String catId, DateTime focus) {
    for (var i = 0; i < 80; i++) {
      final r = _resultAt(catId, focus.subtract(Duration(days: 7 * i)));
      if (r != null) return r;
    }
    return null;
  }

  /// tasks[] を防御的に読む（コンソール編集等で型が崩れたデータでも落ちない）。
  List<Map<String, dynamic>> _tasksOf(Map<String, dynamic>? entry) {
    final raw = entry?['tasks'];
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  /// 引き継ぎ元: 直近の「タスクが入っている週」を最大8週遡って探し、
  /// その週の未完了（この週に同名がないもの）を返す。無ければ null。
  ({DateTime monday, List<Map<String, dynamic>> unfinished})? _carrySource(
      String catId, DateTime focus, List<Map<String, dynamic>> currentTasks) {
    final currentTitles =
        currentTasks.map((t) => (t['title'] ?? '').toString()).toSet();
    for (var i = 1; i <= 8; i++) {
      final m = focus.subtract(Duration(days: 7 * i));
      final tasks = _tasksOf(_entryOf(catId, m));
      if (tasks.isEmpty) continue;
      final unfinished = tasks
          .where((t) =>
              t['done'] != true &&
              !currentTitles.contains((t['title'] ?? '').toString()))
          .toList();
      return unfinished.isEmpty ? null : (monday: m, unfinished: unfinished);
    }
    return null;
  }

  String _numLabel(dynamic n) {
    if (n is num) {
      if (!n.isFinite) return '—';
      if (n == n.roundToDouble()) return n.toInt().toString();
      return n.toString();
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focus = _focusMonday;
    final end = focus.add(const Duration(days: 6));
    return Scaffold(
      backgroundColor: c.scaffoldBg,
      appBar: AppBar(
        backgroundColor: c.scaffoldBg,
        elevation: 0,
        foregroundColor: c.textPrimary,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('KPI',
                style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                '${DateFormat('M/d').format(focus)}〜${DateFormat('M/d').format(end)} の週',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSize.small, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            if (_focusIsCurrent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('今週',
                    style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        actions: [
          if (!_focusIsCurrent)
            TextButton(
              onPressed: () => setState(() => _weekShift = 0),
              child: const Text('今週へ'),
            ),
          IconButton(
            tooltip: '前の週へ',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _weekShift -= 1),
          ),
          IconButton(
            tooltip: '次の週へ',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _weekShift += 1),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _categoriesRef.orderBy('order').snapshots(),
        builder: (context, catSnap) {
          if (catSnap.hasError) {
            return _errorState('カテゴリの読み込みに失敗しました');
          }
          if (catSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = catSnap.data?.docs ?? [];
          if (categories.isEmpty) return _emptyState();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _entriesRef.snapshots(),
            builder: (context, entrySnap) {
              if (entrySnap.hasError) {
                return _errorState('データの読み込みに失敗しました');
              }
              // 初回スナップショット前に編集を許すと、空キャッシュ基準の保存で
              // 既存タスクを丸ごと消してしまうため必ず待つ。
              if (!entrySnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = <String, Map<String, dynamic>>{};
              for (final d in entrySnap.data!.docs) {
                entries[d.id] = d.data();
              }
              _entriesCache = entries;
              return _buildList(categories);
            },
          );
        },
      ),
    );
  }

  Widget _buildList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> categories) {
    final focus = _focusMonday;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            for (final cat in categories) ...[
              _cardFor(cat, focus),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _categoryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('カテゴリ／KRを追加'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _cardFor(
      QueryDocumentSnapshot<Map<String, dynamic>> cat, DateTime focus) {
    final data = cat.data();
    final entry = _entryOf(cat.id, focus);
    final tasks = _tasksOf(entry);
    final rv = entry?['resultValue'];
    final carrySource = _carrySource(cat.id, focus, tasks);
    final String carryLabel;
    if (carrySource == null) {
      carryLabel = '';
    } else if (focus.difference(carrySource.monday).inDays == 7) {
      carryLabel = '前週の未完了を引き継ぐ（${carrySource.unfinished.length}件）';
    } else {
      carryLabel =
          '${DateFormat('M/d').format(carrySource.monday)}週の未完了を引き継ぐ（${carrySource.unfinished.length}件）';
    }

    return KpiCategoryCard(
      key: ValueKey('${cat.id}_${_weekKey(focus)}'),
      name: (data['name'] ?? '') as String,
      krContent: (data['krContent'] ?? '') as String,
      objective: (data['objective'] ?? '') as String,
      target: (data['krTarget'] is num && (data['krTarget'] as num).isFinite)
          ? data['krTarget'] as num
          : null,
      result: (rv is num && rv.isFinite) ? rv : null,
      note: (entry?['note'] ?? '').toString(),
      tasks: tasks,
      latest: _latestResult(cat.id, focus),
      isCurrentWeek: _focusIsCurrent,
      carryOverLabel: carryLabel,
      numLabel: _numLabel,
      onEditCategory: () => _categoryDialog(doc: cat),
      onEditResult: () => _resultDialog(cat, focus),
      onAddTaskText: (text) => _addTask(cat.id, focus, text),
      onToggleTask: (i) => _toggleTask(cat.id, focus, i),
      onEditTask: (i) => _editTaskDialog(cat.id, focus, i),
      onCarryOver: () => _carryOverTasks(cat.id, focus),
    );
  }

  Widget _errorState(String message) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: c.iconMuted),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 4),
          Text('通信環境を確認して再読み込みしてください',
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textTertiary)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.track_changes, size: 56, color: c.iconMuted),
          const SizedBox(height: 12),
          Text('まだカテゴリがありません',
              style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _categoryDialog(),
            icon: const Icon(Icons.add),
            label: const Text('カテゴリ／KRを追加'),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ===== カテゴリの追加・編集 =====

  Future<void> _categoryDialog(
      {QueryDocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final objCtrl = TextEditingController(text: data['objective'] ?? '');
    final krCtrl = TextEditingController(text: data['krContent'] ?? '');
    final targetCtrl = TextEditingController(
        text: data['krTarget'] != null ? _numLabel(data['krTarget']) : '');

    final urgentColor = context.alerts.urgent.icon;
    String? nameError;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
        title: Text(doc == null ? 'カテゴリ／KRを追加' : 'カテゴリ／KRを編集'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                      labelText: 'カテゴリ名（例: BS湘南藤沢）',
                      errorText: nameError),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: objCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Objective（例: 生徒数の増加と継続）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: krCtrl,
                  decoration: const InputDecoration(
                      labelText: 'KR内容（例: 生徒数を60人達成）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '目標値（数字）'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (doc != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              style: TextButton.styleFrom(foregroundColor: urgentColor),
              child: const Text('削除'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () {
                // 名前が空のまま閉じると他の入力ごと消えるため、閉じずにエラー表示
                if (nameCtrl.text.trim().isEmpty) {
                  setDialog(() => nameError = 'カテゴリ名は必須です');
                  return;
                }
                Navigator.pop(context, 'save');
              },
              child: const Text('保存')),
        ],
        ),
      ),
    );

    if (result == 'save') {
      final targetVal =
          num.tryParse(_normalizeNumInput(targetCtrl.text.trim()));
      final payload = {
        'name': nameCtrl.text.trim(),
        'objective': objCtrl.text.trim(),
        'krContent': krCtrl.text.trim(),
        // NaN/Infinity は保存しない（描画時クラッシュの元）
        'krTarget': (targetVal != null && targetVal.isFinite) ? targetVal : null,
      };
      if (doc == null) {
        // order は最大値+1（件数だと削除後に重複しうる）
        final snap = await _categoriesRef.get();
        var maxOrder = -1;
        for (final d in snap.docs) {
          final o = d.data()['order'];
          if (o is num && o.isFinite && o > maxOrder) maxOrder = o.toInt();
        }
        await _categoriesRef.add({...payload, 'order': maxOrder + 1});
      } else {
        await doc.reference.update(payload);
      }
    } else if (result == 'delete' && doc != null) {
      await _confirmDeleteCategory(doc);
    }
  }

  Future<void> _confirmDeleteCategory(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final urgentColor = context.alerts.urgent.icon;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('カテゴリの削除'),
        content:
            Text('「${doc.data()['name']}」を削除しますか？\n（全週の数字・タスクも削除されます）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: urgentColor),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final snap =
        await _entriesRef.where('categoryId', isEqualTo: doc.id).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    batch.delete(doc.reference);
    await batch.commit();
  }

  // ===== 実績数字 / メモ =====

  Future<void> _resultDialog(
      QueryDocumentSnapshot<Map<String, dynamic>> cat, DateTime monday) async {
    final entry = _entryOf(cat.id, monday);
    final existing = _resultAt(cat.id, monday);
    final valueCtrl =
        TextEditingController(text: existing != null ? _numLabel(existing) : '');
    final noteCtrl =
        TextEditingController(text: (entry?['note'] ?? '').toString());

    final save = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${DateFormat('M/d').format(monday)}週の実績'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valueCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '実績の数字'),
                // 数字だけ入れてEnterで即保存（会議中に11件入力するため）
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'メモ（自由記入）',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (save != true) return;
    final raw = valueCtrl.text.trim();
    num? value;
    if (raw.isNotEmpty) {
      value = num.tryParse(_normalizeNumInput(raw));
      if (value == null || !value.isFinite) {
        // 読めない入力（NaN等含む）は既存値を消さずに中断
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('実績の数字が読み取れませんでした（例: 12 / 12.5）')));
        }
        return;
      }
    }
    await _entriesRef.doc(_entryId(cat.id, monday)).set({
      'categoryId': cat.id,
      'weekStart': Timestamp.fromDate(monday),
      'resultValue': value,
      'note': noteCtrl.text.trim(),
    }, SetOptions(merge: true));
  }

  /// 全角数字・記号をASCIIへ正規化（例: ６２ → 62）。IME入力対策。
  String _normalizeNumInput(String s) {
    const zenkaku = '０１２３４５６７８９';
    var out = s;
    for (var i = 0; i < zenkaku.length; i++) {
      out = out.replaceAll(zenkaku[i], '$i');
    }
    return out
        .replaceAll('．', '.')
        .replaceAll('，', '')
        .replaceAll(',', '')
        .replaceAll('－', '-')
        .replaceAll('ー', '-')
        .replaceAll(' ', '')
        .replaceAll('　', '');
  }

  // ===== タスク（常に _entriesCache から最新を読む）=====

  Future<void> _saveTasks(
      String categoryId, DateTime monday, List<Map<String, dynamic>> tasks) {
    return _entriesRef.doc(_entryId(categoryId, monday)).set({
      'categoryId': categoryId,
      'weekStart': Timestamp.fromDate(monday),
      'tasks': tasks,
    }, SetOptions(merge: true));
  }

  Future<void> _addTask(String catId, DateTime monday, String title) {
    final tasks = _tasksOf(_entryOf(catId, monday))
      ..add({'title': title, 'done': false});
    return _saveTasks(catId, monday, tasks);
  }

  Future<void> _toggleTask(String catId, DateTime monday, int idx) async {
    final tasks = _tasksOf(_entryOf(catId, monday));
    if (idx >= tasks.length) return;
    tasks[idx]['done'] = !(tasks[idx]['done'] == true);
    await _saveTasks(catId, monday, tasks);
  }

  /// 直近の作業週の未完了タスクをこの週へコピー。
  Future<void> _carryOverTasks(String catId, DateTime monday) async {
    final cur = _tasksOf(_entryOf(catId, monday));
    final source = _carrySource(catId, monday, cur);
    if (source == null) return;
    await _saveTasks(catId, monday, [
      ...cur,
      ...source.unfinished
          .map((t) => {'title': (t['title'] ?? '').toString(), 'done': false}),
    ]);
  }

  Future<void> _editTaskDialog(String catId, DateTime monday, int idx) async {
    final tasks = _tasksOf(_entryOf(catId, monday));
    if (idx >= tasks.length) return;
    final urgentColor = context.alerts.urgent.icon;
    // ダイアログ表示中に並びが変わっても正しい行を触れるよう、開いた時点の中身を控える
    final originalTitle = (tasks[idx]['title'] ?? '').toString();
    final originalDone = tasks[idx]['done'] == true;
    final ctrl = TextEditingController(text: originalTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('タスクを編集'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'タスク内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: urgentColor),
            child: const Text('削除'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    // 保存直前に最新を取り直し、開いた時点の行を内容で探し直す（indexズレで別の行を壊さない）
    final latest = _tasksOf(_entryOf(catId, monday));
    final sameAtIdx = idx < latest.length &&
        (latest[idx]['title'] ?? '').toString() == originalTitle &&
        (latest[idx]['done'] == true) == originalDone;
    final j = sameAtIdx
        ? idx
        : latest.indexWhere((t) =>
            (t['title'] ?? '').toString() == originalTitle &&
            (t['done'] == true) == originalDone);
    if (j < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('他の変更と競合したため保存できませんでした')));
      }
      return;
    }
    if (result == 'save') {
      if (ctrl.text.trim().isEmpty) return;
      latest[j]['title'] = ctrl.text.trim();
      await _saveTasks(catId, monday, latest);
    } else if (result == 'delete') {
      latest.removeAt(j);
      await _saveTasks(catId, monday, latest);
    }
  }
}

/// KPIカテゴリ1件のカード（週次作業ドキュメント）。
/// ウィジェットテストから直接検証できるよう公開クラスにしている。
class KpiCategoryCard extends StatefulWidget {
  final String name;
  final String krContent;
  final String objective;
  final num? target;
  final num? result;
  final String note;
  final List<Map<String, dynamic>> tasks;
  final num? latest;
  final bool isCurrentWeek;
  final String carryOverLabel; // 空なら引き継ぎボタン非表示
  final String Function(dynamic) numLabel;
  final VoidCallback onEditCategory;
  final VoidCallback onEditResult;
  final ValueChanged<String> onAddTaskText;
  final ValueChanged<int> onToggleTask;
  final ValueChanged<int> onEditTask;
  final VoidCallback onCarryOver;

  const KpiCategoryCard({
    super.key,
    required this.name,
    required this.krContent,
    required this.objective,
    required this.target,
    required this.result,
    required this.note,
    required this.tasks,
    required this.latest,
    required this.isCurrentWeek,
    required this.carryOverLabel,
    required this.numLabel,
    required this.onEditCategory,
    required this.onEditResult,
    required this.onAddTaskText,
    required this.onToggleTask,
    required this.onEditTask,
    required this.onCarryOver,
  });

  @override
  State<KpiCategoryCard> createState() => _KpiCategoryCardState();
}

class _KpiCategoryCardState extends State<KpiCategoryCard> {
  bool _addingTask = false;
  final _taskCtrl = TextEditingController();
  final _taskFocus = FocusNode();

  @override
  void dispose() {
    _taskCtrl.dispose();
    _taskFocus.dispose();
    super.dispose();
  }

  Color _ramp(double ratio, AlertPalette a) {
    if (ratio >= 1.0) return a.success.icon;
    if (ratio >= 0.7) return AppColors.primary;
    if (ratio >= 0.4) return a.warning.icon;
    return a.urgent.icon;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, cons) {
          if (cons.maxWidth >= 900) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _zoneIdentity(c)),
                  VerticalDivider(width: 1, color: c.borderLight),
                  SizedBox(width: 170, child: _zoneResult(c)),
                  VerticalDivider(width: 1, color: c.borderLight),
                  Expanded(child: _zoneTasks(c)),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _zoneIdentity(c),
              Divider(height: 1, color: c.borderLight),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 140, child: _zoneResult(c)),
                    VerticalDivider(width: 1, color: c.borderLight),
                    Expanded(child: _zoneTasks(c)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== 識別 + 目標バー =====
  Widget _zoneIdentity(AppColorScheme c) {
    return InkWell(
      onTap: widget.onEditCategory,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: widget.objective.isEmpty
                  ? widget.name
                  : widget.objective,
              child: Text(widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
            ),
            const SizedBox(height: 4),
            Text(widget.krContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: c.textPrimary,
                    height: 1.35)),
            const SizedBox(height: 12),
            _progress(c),
          ],
        ),
      ),
    );
  }

  Widget _progress(AppColorScheme c) {
    final a = context.alerts;
    final target = widget.target;
    if (target == null || target == 0) {
      return Text('目標 未設定',
          style:
              TextStyle(fontSize: AppTextSize.small, color: c.textTertiary));
    }
    final latest = (widget.latest != null && widget.latest!.isFinite)
        ? widget.latest
        : null;
    final ratio = latest == null ? 0.0 : (latest / target).toDouble();
    final pctLabel = (latest == null || !ratio.isFinite)
        ? '—'
        : '${(ratio * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
                '${latest == null ? '—' : widget.numLabel(latest)} / ${widget.numLabel(target)}',
                style: TextStyle(
                    fontSize: AppTextSize.small, color: c.textSecondary)),
            const Spacer(),
            Text(pctLabel,
                style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: c.scaffoldBgAlt),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(color: _ramp(ratio, a)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===== 実績（その週の数字 + メモ）=====
  Widget _zoneResult(AppColorScheme c) {
    final a = context.alerts;
    final result = widget.result;
    final target = widget.target;
    final reached = result != null && target != null && result >= target;
    return InkWell(
      onTap: widget.onEditResult,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('実績',
                style: TextStyle(
                    fontSize: AppTextSize.small, color: c.textSecondary)),
            const SizedBox(height: 4),
            // 桁が多い数字でもゾーン幅を超えないよう縮小フィット
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(result == null ? '—' : widget.numLabel(result),
                      style: TextStyle(
                          fontSize: AppTextSize.headline,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: result == null
                              ? c.textTertiary
                              : (reached ? a.success.icon : c.textPrimary))),
                  if (target != null) ...[
                    const SizedBox(width: 4),
                    Text('/ ${widget.numLabel(target)}',
                        style: TextStyle(
                            fontSize: AppTextSize.small,
                            color: c.textSecondary)),
                  ],
                ],
              ),
            ),
            if (widget.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(widget.note,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppTextSize.small,
                      color: c.textSecondary,
                      height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }

  // ===== やること（タスク：縦に増やせる）=====
  Widget _zoneTasks(AppColorScheme c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 「今週」と書けるのは実際に今週を表示している時だけ
          Text(widget.isCurrentWeek ? '今週やること' : 'やること',
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textSecondary)),
          const SizedBox(height: 6),
          for (var i = 0; i < widget.tasks.length; i++)
            _TaskRow(
              key: ValueKey('task_$i'),
              title: (widget.tasks[i]['title'] ?? '').toString(),
              done: widget.tasks[i]['done'] == true,
              onToggle: () => widget.onToggleTask(i),
              onEdit: () => widget.onEditTask(i),
            ),
          if (widget.carryOverLabel.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onCarryOver,
                icon: const Icon(Icons.redo, size: 15),
                label: Text(widget.carryOverLabel),
                style: TextButton.styleFrom(
                  foregroundColor: c.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: AppTextSize.small),
                ),
              ),
            ),
          const SizedBox(height: 2),
          if (_addingTask)
            _inlineAddField(c)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('タスクを追加'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: AppTextSize.small),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openAdd() {
    setState(() => _addingTask = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _taskFocus.requestFocus());
  }

  void _closeAdd() {
    setState(() {
      _addingTask = false;
      _taskCtrl.clear();
    });
  }

  void _submitTask(String v) {
    final t = v.trim();
    if (t.isEmpty) {
      _closeAdd();
      return;
    }
    widget.onAddTaskText(t);
    _taskCtrl.clear();
    // 連続追加できるようフォーカスを維持
    _taskFocus.requestFocus();
  }

  Widget _inlineAddField(AppColorScheme c) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, right: 4),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _taskCtrl,
          focusNode: _taskFocus,
          textInputAction: TextInputAction.done,
          style: TextStyle(
              fontSize: AppTextSize.body, color: c.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'タスクを入力して Enter（連続追加できます）',
            hintStyle: TextStyle(
                fontSize: AppTextSize.small, color: c.textHint),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            suffixIcon: InkWell(
              onTap: _closeAdd,
              child: Icon(Icons.close, size: 16, color: c.iconMuted),
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          onSubmitted: _submitTask,
        ),
      ),
    );
  }
}

/// タスク1行。タップで完了トグル、ホバーで編集アイコン（PC）、長押しで編集（タッチ）。
class _TaskRow extends StatefulWidget {
  final String title;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _TaskRow({
    super.key,
    required this.title,
    required this.done,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = context.alerts;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onToggle,
        onLongPress: widget.onEdit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  widget.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: widget.done ? a.success.icon : c.iconMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      height: 1.35,
                      decoration:
                          widget.done ? TextDecoration.lineThrough : null,
                      color: widget.done ? c.textTertiary : c.textPrimary,
                    )),
              ),
              // 編集はホバー時のみ表示（幅は常に確保して行の高さ・折返しを安定させる）
              SizedBox(
                width: 26,
                height: 20,
                child: Opacity(
                  opacity: _hover ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_hover,
                    child: Tooltip(
                      message: '編集',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onEdit,
                        child: Icon(Icons.edit_outlined,
                            size: 15, color: c.iconMuted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
