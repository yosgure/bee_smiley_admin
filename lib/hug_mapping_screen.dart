import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// hug連携のIDマッピング管理画面
/// Firestoreの hug_settings/child_mapping, hug_settings/staff_mapping を管理
class HugMappingScreen extends StatefulWidget {
  const HugMappingScreen({super.key});

  @override
  State<HugMappingScreen> createState() => _HugMappingScreenState();
}

class _HugMappingScreenState extends State<HugMappingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFetching = false;

  Map<String, String> _childMapping = {};
  Map<String, String> _staffMapping = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMappings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMappings() async {
    setState(() => _isLoading = true);
    try {
      final childDoc = await FirebaseFirestore.instance
          .collection('hug_settings')
          .doc('child_mapping')
          .get();
      final staffDoc = await FirebaseFirestore.instance
          .collection('hug_settings')
          .doc('staff_mapping')
          .get();

      setState(() {
        _childMapping = Map<String, String>.from(childDoc.data() ?? {});
        _staffMapping = Map<String, String>.from(staffDoc.data() ?? {});
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('読み込みエラー: $e')),
        );
      }
    }
  }

  Future<void> _saveChildMapping() async {
    await FirebaseFirestore.instance
        .collection('hug_settings')
        .doc('child_mapping')
        .set(_childMapping);
  }

  Future<void> _saveStaffMapping() async {
    await FirebaseFirestore.instance
        .collection('hug_settings')
        .doc('staff_mapping')
        .set(_staffMapping);
  }

  /// hugからマッピング候補を自動取得
  Future<void> _fetchFromHug() async {
    setState(() => _isFetching = true);
    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'asia-northeast1')
              .httpsCallable('fetchHugMappings');
      final result = await callable.call();
      final data = result.data as Map<String, dynamic>;

      final children =
          (data['children'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final staffList =
          (data['staffList'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (!mounted) return;

      // 取得結果を表示して選択
      await showDialog(
        context: context,
        builder: (ctx) => _FetchResultDialog(
          children: children,
          staffList: staffList,
          currentChildMapping: _childMapping,
          currentStaffMapping: _staffMapping,
          onApply: (newChildMap, newStaffMap) {
            setState(() {
              _childMapping = newChildMap;
              _staffMapping = newStaffMap;
            });
            _saveChildMapping();
            _saveStaffMapping();
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('hugからの取得エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('hug連携設定'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '児童マッピング'),
            Tab(text: 'スタッフマッピング'),
          ],
        ),
        actions: [
          _isFetching
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'hugから自動取得',
                  onPressed: _fetchFromHug,
                ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _MappingList(
                  mapping: _childMapping,
                  label: '児童名',
                  idLabel: 'hug児童ID (c_id)',
                  onAdd: (name, id) {
                    setState(() => _childMapping[name] = id);
                    _saveChildMapping();
                  },
                  onRemove: (name) {
                    setState(() => _childMapping.remove(name));
                    _saveChildMapping();
                  },
                ),
                _MappingList(
                  mapping: _staffMapping,
                  label: 'スタッフ名',
                  idLabel: 'hugスタッフID (record_staff)',
                  onAdd: (name, id) {
                    setState(() => _staffMapping[name] = id);
                    _saveStaffMapping();
                  },
                  onRemove: (name) {
                    setState(() => _staffMapping.remove(name));
                    _saveStaffMapping();
                  },
                ),
              ],
            ),
    );
  }
}

/// マッピング一覧・編集ウィジェット
class _MappingList extends StatelessWidget {
  final Map<String, String> mapping;
  final String label;
  final String idLabel;
  final void Function(String name, String id) onAdd;
  final void Function(String name) onRemove;

  const _MappingList({
    required this.mapping,
    required this.label,
    required this.idLabel,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final entries = mapping.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_off, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('マッピングが未設定です',
                          style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('右下の＋ボタンで追加するか、\nAppBarの↓ボタンでhugから自動取得してください',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(entry.key),
                      subtitle: Text('$idLabel: ${entry.value}'),
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => onRemove(entry.key),
                      ),
                      onTap: () => _showEditDialog(context, entry.key, entry.value),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: Text('$labelを追加'),
            onPressed: () => _showEditDialog(context, '', ''),
          ),
        ),
      ],
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, String currentName, String currentId) async {
    final nameController = TextEditingController(text: currentName);
    final idController = TextEditingController(text: currentId);
    final isNew = currentName.isEmpty;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'マッピング追加' : 'マッピング編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              enabled: isNew,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idController,
              decoration: InputDecoration(
                labelText: idLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      final id = idController.text.trim();
      if (name.isNotEmpty && id.isNotEmpty) {
        onAdd(name, id);
      }
    }

    nameController.dispose();
    idController.dispose();
  }
}

/// hugから取得した結果を表示するダイアログ
class _FetchResultDialog extends StatefulWidget {
  final List<Map<String, dynamic>> children;
  final List<Map<String, dynamic>> staffList;
  final Map<String, String> currentChildMapping;
  final Map<String, String> currentStaffMapping;
  final void Function(Map<String, String>, Map<String, String>) onApply;

  const _FetchResultDialog({
    required this.children,
    required this.staffList,
    required this.currentChildMapping,
    required this.currentStaffMapping,
    required this.onApply,
  });

  @override
  State<_FetchResultDialog> createState() => _FetchResultDialogState();
}

class _FetchResultDialogState extends State<_FetchResultDialog> {
  late Map<String, String> _childMap;
  late Map<String, String> _staffMap;

  @override
  void initState() {
    super.initState();
    _childMap = Map<String, String>.from(widget.currentChildMapping);
    _staffMap = Map<String, String>.from(widget.currentStaffMapping);

    // hugから取得した情報で未登録分を追加
    for (final child in widget.children) {
      final name = child['name'] as String? ?? '';
      final cId = child['cId'] as String? ?? '';
      if (name.isNotEmpty && cId.isNotEmpty && !_childMap.containsKey(name)) {
        _childMap[name] = cId;
      }
    }
    for (final staff in widget.staffList) {
      final name = staff['name'] as String? ?? '';
      final staffId = staff['staffId'] as String? ?? '';
      if (name.isNotEmpty &&
          staffId.isNotEmpty &&
          !_staffMap.containsKey(name)) {
        _staffMap[name] = staffId;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('hugから取得した情報'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '児童'),
                  Tab(text: 'スタッフ'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildMappingPreview(
                      widget.children
                          .map((c) => MapEntry(
                              c['name'] as String? ?? '',
                              c['cId'] as String? ?? ''))
                          .where(
                              (e) => e.key.isNotEmpty && e.value.isNotEmpty)
                          .toList(),
                      widget.currentChildMapping,
                    ),
                    _buildMappingPreview(
                      widget.staffList
                          .map((s) => MapEntry(
                              s['name'] as String? ?? '',
                              s['staffId'] as String? ?? ''))
                          .where(
                              (e) => e.key.isNotEmpty && e.value.isNotEmpty)
                          .toList(),
                      widget.currentStaffMapping,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        ElevatedButton(
          onPressed: () {
            widget.onApply(_childMap, _staffMap);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('マッピングを更新しました'),
                backgroundColor: Colors.green,
              ),
            );
          },
          child: const Text('適用'),
        ),
      ],
    );
  }

  Widget _buildMappingPreview(
    List<MapEntry<String, String>> entries,
    Map<String, String> currentMapping,
  ) {
    if (entries.isEmpty) {
      return const Center(child: Text('データが見つかりませんでした'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isNew = !currentMapping.containsKey(entry.key);
        return ListTile(
          dense: true,
          leading: Icon(
            isNew ? Icons.add_circle : Icons.check_circle,
            color: isNew ? Colors.blue : Colors.green,
            size: 20,
          ),
          title: Text(entry.key, style: const TextStyle(fontSize: 14)),
          subtitle: Text('ID: ${entry.value}',
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            isNew ? '新規' : '登録済',
            style: TextStyle(
              fontSize: 11,
              color: isNew ? Colors.blue : Colors.grey,
            ),
          ),
        );
      },
    );
  }
}
