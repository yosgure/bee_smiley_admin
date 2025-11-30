import 'package:flutter/material.dart';

class GenericMasterScreen extends StatefulWidget {
  final String title;          // 画面タイトル (例: 教室設定)
  final String itemLabel;      // 項目のラベル (例: 教室名)
  final List<String> initialData; // 初期のデータリスト

  const GenericMasterScreen({
    super.key,
    required this.title,
    required this.itemLabel,
    required this.initialData,
  });

  @override
  State<GenericMasterScreen> createState() => _GenericMasterScreenState();
}

class _GenericMasterScreenState extends State<GenericMasterScreen> {
  late List<String> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              title: Text(_items[index], style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: () => _deleteItem(index),
              ),
              onTap: () => _showEditDialog(index: index),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(heroTag: null, 
        onPressed: () => _showEditDialog(),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _deleteItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text('${_items[index]} を削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              setState(() => _items.removeAt(index));
              Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog({int? index}) {
    final isEditing = index != null;
    final controller = TextEditingController(text: isEditing ? _items[index] : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '編集' : '新規追加'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: widget.itemLabel, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  if (isEditing) {
                    _items[index] = controller.text;
                  } else {
                    _items.add(controller.text);
                  }
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}