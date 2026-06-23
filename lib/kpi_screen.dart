import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

/// KPI（OKR週次進捗）画面。上田洋介・上田藍のみ（staffs.kpiAccess == true）。
///
/// 週次の「作業ドキュメント」。カテゴリ1件 = 1カード:
///   [識別: 名前 / KR / 目標バー] | [実績: その週の数字＋メモ] | [今週やること: タスク（縦に増やせる）]
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

  num? _resultAt(
      String catId, Map<String, dynamic> entries, DateTime monday) {
    final v = entries[_entryId(catId, monday)]?['resultValue'];
    return v is num ? v : null;
  }

  // 直近の非null実績（focus週から過去へ遡る）。目標バー用。
  num? _latestResult(
      String catId, Map<String, dynamic> entries, DateTime focus) {
    for (var i = 0; i < 80; i++) {
      final r = _resultAt(catId, entries, focus.subtract(Duration(days: 7 * i)));
      if (r != null) return r;
    }
    return null;
  }

  List<Map<String, dynamic>> _tasksOf(Map<String, dynamic>? entry) {
    return List<Map<String, dynamic>>.from(
        (entry?['tasks'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
            const []);
  }

  String _numLabel(dynamic n) {
    if (n is num) {
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
            Text(
              '${DateFormat('M/d').format(focus)}〜${DateFormat('M/d').format(end)} の週',
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textSecondary),
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
                        fontSize: 10,
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
          if (catSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = catSnap.data?.docs ?? [];
          if (categories.isEmpty) return _emptyState();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _entriesRef.snapshots(),
            builder: (context, entrySnap) {
              final entries = <String, dynamic>{};
              for (final d in entrySnap.data?.docs ?? []) {
                entries[d.id] = d.data();
              }
              return _buildList(categories, entries);
            },
          );
        },
      ),
    );
  }

  Widget _buildList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> categories,
    Map<String, dynamic> entries,
  ) {
    final focus = _focusMonday;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            for (final cat in categories) ...[
              _cardFor(cat, entries, focus),
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
    QueryDocumentSnapshot<Map<String, dynamic>> cat,
    Map<String, dynamic> entries,
    DateTime focus,
  ) {
    final data = cat.data();
    final entry = entries[_entryId(cat.id, focus)] as Map<String, dynamic>?;
    return _CategoryCard(
      key: ValueKey('${cat.id}_${_weekKey(focus)}'),
      name: (data['name'] ?? '') as String,
      krContent: (data['krContent'] ?? '') as String,
      objective: (data['objective'] ?? '') as String,
      target: data['krTarget'] is num ? data['krTarget'] as num : null,
      result:
          entry?['resultValue'] is num ? entry!['resultValue'] as num : null,
      note: (entry?['note'] ?? '').toString(),
      tasks: _tasksOf(entry),
      latest: _latestResult(cat.id, entries, focus),
      numLabel: _numLabel,
      onEditCategory: () => _categoryDialog(doc: cat),
      onEditResult: () => _resultDialog(cat, focus, entry),
      onAddTask: () => _addTaskDialog(cat, focus, entry),
      onToggleTask: (i) => _toggleTask(cat, focus, entry, i),
      onEditTask: (i, t) => _editTaskDialog(cat, focus, entry, i, t),
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

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(doc == null ? 'カテゴリ／KRを追加' : 'カテゴリ／KRを編集'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'カテゴリ名（例: BS湘南藤沢）'),
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
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
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

    if (result == 'save') {
      if (nameCtrl.text.trim().isEmpty) return;
      final payload = {
        'name': nameCtrl.text.trim(),
        'objective': objCtrl.text.trim(),
        'krContent': krCtrl.text.trim(),
        'krTarget': num.tryParse(targetCtrl.text.trim()),
      };
      if (doc == null) {
        final cnt = (await _categoriesRef.get()).docs.length;
        await _categoriesRef.add({...payload, 'order': cnt});
      } else {
        await doc.reference.update(payload);
      }
    } else if (result == 'delete' && doc != null) {
      await _confirmDeleteCategory(doc);
    }
  }

  Future<void> _confirmDeleteCategory(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
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
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
    QueryDocumentSnapshot<Map<String, dynamic>> cat,
    DateTime monday,
    Map<String, dynamic>? entry,
  ) async {
    final valueCtrl = TextEditingController(
        text: entry?['resultValue'] != null
            ? _numLabel(entry!['resultValue'])
            : '');
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '実績の数字'),
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
    await _entriesRef.doc(_entryId(cat.id, monday)).set({
      'categoryId': cat.id,
      'weekStart': Timestamp.fromDate(monday),
      'resultValue': num.tryParse(valueCtrl.text.trim()),
      'note': noteCtrl.text.trim(),
    }, SetOptions(merge: true));
  }

  // ===== タスク =====

  Future<void> _saveTasks(
    String categoryId,
    DateTime monday,
    List<Map<String, dynamic>> tasks,
  ) async {
    await _entriesRef.doc(_entryId(categoryId, monday)).set({
      'categoryId': categoryId,
      'weekStart': Timestamp.fromDate(monday),
      'tasks': tasks,
    }, SetOptions(merge: true));
  }

  Future<void> _addTaskDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> cat,
    DateTime monday,
    Map<String, dynamic>? entry,
  ) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('タスクを追加'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'タスク内容'),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('追加')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final tasks = _tasksOf(entry)
      ..add({'title': ctrl.text.trim(), 'done': false});
    await _saveTasks(cat.id, monday, tasks);
  }

  Future<void> _toggleTask(
    QueryDocumentSnapshot<Map<String, dynamic>> cat,
    DateTime monday,
    Map<String, dynamic>? entry,
    int idx,
  ) async {
    final tasks = _tasksOf(entry);
    if (idx >= tasks.length) return;
    tasks[idx]['done'] = !(tasks[idx]['done'] == true);
    await _saveTasks(cat.id, monday, tasks);
  }

  Future<void> _editTaskDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> cat,
    DateTime monday,
    Map<String, dynamic>? entry,
    int idx,
    Map<String, dynamic> task,
  ) async {
    final ctrl =
        TextEditingController(text: (task['title'] ?? '').toString());
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
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
    final tasks = _tasksOf(entry);
    if (idx >= tasks.length) return;
    if (result == 'save') {
      if (ctrl.text.trim().isEmpty) return;
      tasks[idx]['title'] = ctrl.text.trim();
      await _saveTasks(cat.id, monday, tasks);
    } else if (result == 'delete') {
      tasks.removeAt(idx);
      await _saveTasks(cat.id, monday, tasks);
    }
  }
}

/// カテゴリ1件のカード（週次作業ドキュメント）。
class _CategoryCard extends StatelessWidget {
  final String name;
  final String krContent;
  final String objective;
  final num? target;
  final num? result;
  final String note;
  final List<Map<String, dynamic>> tasks;
  final num? latest;
  final String Function(dynamic) numLabel;
  final VoidCallback onEditCategory;
  final VoidCallback onEditResult;
  final VoidCallback onAddTask;
  final void Function(int) onToggleTask;
  final void Function(int, Map<String, dynamic>) onEditTask;

  const _CategoryCard({
    super.key,
    required this.name,
    required this.krContent,
    required this.objective,
    required this.target,
    required this.result,
    required this.note,
    required this.tasks,
    required this.latest,
    required this.numLabel,
    required this.onEditCategory,
    required this.onEditResult,
    required this.onAddTask,
    required this.onToggleTask,
    required this.onEditTask,
  });

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
                  SizedBox(width: 300, child: _zoneIdentity(context, c)),
                  VerticalDivider(width: 1, color: c.borderLight),
                  SizedBox(width: 170, child: _zoneResult(context, c)),
                  VerticalDivider(width: 1, color: c.borderLight),
                  Expanded(child: _zoneTasks(context, c)),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _zoneIdentity(context, c),
              Divider(height: 1, color: c.borderLight),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 140, child: _zoneResult(context, c)),
                    VerticalDivider(width: 1, color: c.borderLight),
                    Expanded(child: _zoneTasks(context, c)),
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
  Widget _zoneIdentity(BuildContext context, AppColorScheme c) {
    return InkWell(
      onTap: onEditCategory,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: objective.isEmpty ? name : objective,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.bodyLarge,
                      color: AppColors.primary)),
            ),
            const SizedBox(height: 4),
            Text(krContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: c.textPrimary,
                    height: 1.35)),
            const SizedBox(height: 12),
            _progress(context, c),
          ],
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, AppColorScheme c) {
    final a = context.alerts;
    if (target == null || target == 0) {
      return Text('目標 未設定',
          style:
              TextStyle(fontSize: AppTextSize.small, color: c.textTertiary));
    }
    final ratio = latest == null ? 0.0 : (latest! / target!);
    final pctLabel = latest == null ? '—' : '${(ratio * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
                '${latest == null ? '—' : numLabel(latest)} / ${numLabel(target)}',
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
  Widget _zoneResult(BuildContext context, AppColorScheme c) {
    final a = context.alerts;
    final reached = result != null && target != null && result! >= target!;
    return InkWell(
      onTap: onEditResult,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(result == null ? '—' : numLabel(result),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: result == null
                            ? c.textTertiary
                            : (reached ? a.success.icon : c.textPrimary))),
                if (target != null) ...[
                  const SizedBox(width: 4),
                  Text('/ ${numLabel(target)}',
                      style: TextStyle(
                          fontSize: AppTextSize.small,
                          color: c.textSecondary)),
                ],
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note,
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

  // ===== 今週やること（タスク：縦に増やせる）=====
  Widget _zoneTasks(BuildContext context, AppColorScheme c) {
    final a = context.alerts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('今週やること',
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textSecondary)),
          const SizedBox(height: 6),
          for (var i = 0; i < tasks.length; i++)
            _taskRow(c, a, i, tasks[i]),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddTask,
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

  Widget _taskRow(
      AppColorScheme c, AlertPalette a, int i, Map<String, dynamic> t) {
    final done = t['done'] == true;
    return InkWell(
      onTap: () => onToggleTask(i),
      onLongPress: () => onEditTask(i, t),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: done ? a.success.icon : c.iconMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text((t['title'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    height: 1.35,
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? c.textTertiary : c.textPrimary,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
