import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AiCommandManageScreen extends StatefulWidget {
  const AiCommandManageScreen({super.key});

  @override
  State<AiCommandManageScreen> createState() => _AiCommandManageScreenState();
}

class _AiCommandManageScreenState extends State<AiCommandManageScreen> {
  List<Map<String, dynamic>> _commands = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCommands();
  }

  Future<void> _loadCommands() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ai_chat_commands')
          .orderBy('order')
          .get();

      if (mounted) {
        setState(() {
          _commands = snap.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading commands: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addCommand() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CommandEditScreen(onSaved: _loadCommands)),
    );
  }

  void _editCommand(Map<String, dynamic> cmd) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CommandEditScreen(existing: cmd, onSaved: _loadCommands),
      ),
    );
  }

  Future<void> _deleteCommand(Map<String, dynamic> cmd) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('コマンドを削除'),
        content: Text('「/${cmd['label']}」を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('ai_chat_commands')
          .doc(cmd['docId'])
          .delete();
      _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除に失敗: $e')));
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _commands.removeAt(oldIndex);
    _commands.insert(newIndex, item);
    setState(() {});

    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < _commands.length; i++) {
      batch.update(
        FirebaseFirestore.instance.collection('ai_chat_commands').doc(_commands[i]['docId']),
        {'order': i},
      );
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('AI相談コマンド設定', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCommand,
        backgroundColor: const Color(0xFF7C3AED),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
          : _commands.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tag_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('コマンドがありません', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('右下の + ボタンから追加してください',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _commands.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final cmd = _commands[index];
                        final questions = cmd['questions'] as List<dynamic>? ?? [];
                        return Card(
                          key: ValueKey(cmd['docId']),
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: InkWell(
                            onTap: () => _editCommand(cmd),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7C3AED).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '/${cmd['label'] ?? ''}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF7C3AED),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${questions.length}問',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                            ),
                                          ],
                                        ),
                                        if ((cmd['description'] ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(cmd['description'],
                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300),
                                    onPressed: () => _deleteCommand(cmd),
                                  ),
                                  Icon(Icons.drag_handle_rounded, size: 20, color: Colors.grey.shade400),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

// ================================================
// コマンド編集画面（質問管理付き）
// ================================================
class _CommandEditScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _CommandEditScreen({this.existing, required this.onSaved});

  @override
  State<_CommandEditScreen> createState() => _CommandEditScreenState();
}

class _CommandEditScreenState extends State<_CommandEditScreen> {
  late TextEditingController _labelController;
  late TextEditingController _descController;
  late TextEditingController _scriptController;
  List<Map<String, dynamic>> _questions = [];
  bool _isSaving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.existing?['label'] ?? '');
    _descController = TextEditingController(text: widget.existing?['description'] ?? '');
    _scriptController = TextEditingController(text: widget.existing?['script'] ?? '');

    final existingQuestions = widget.existing?['questions'] as List<dynamic>? ?? [];
    _questions = existingQuestions
        .map((q) => Map<String, dynamic>.from(q as Map))
        .toList();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _descController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  void _addQuestion() {
    setState(() {
      _questions.add({
        'question': '',
        'type': 'text',
        'options': <String>[],
        'placeholder': '',
        'required': false,
      });
    });
  }

  void _removeQuestion(int index) {
    setState(() => _questions.removeAt(index));
  }

  void _editQuestion(int index) async {
    final q = _questions[index];
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _QuestionEditScreen(question: q)),
    );
    if (result != null) {
      setState(() => _questions[index] = result);
    }
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コマンド名を入力してください')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = {
        'label': label,
        'description': _descController.text.trim(),
        'script': _scriptController.text.trim(),
        'questions': _questions,
      };

      if (_isNew) {
        data['order'] = _questions.length;
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('ai_chat_commands').add(data);
      } else {
        await FirebaseFirestore.instance
            .collection('ai_chat_commands')
            .doc(widget.existing!['docId'])
            .update(data);
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isNew ? 'コマンドを追加' : 'コマンドを編集', style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: _isSaving ? Colors.grey : const Color(0xFF7C3AED),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 基本情報
              _buildSectionTitle('基本情報'),
              const SizedBox(height: 12),
              _buildTextField('コマンド名', _labelController, 'ケア記録'),
              const SizedBox(height: 12),
              _buildTextField('説明', _descController, 'ケア記録を作成'),
              const SizedBox(height: 12),
              _buildTextField('スクリプト（AIへの指示）', _scriptController,
                  'このコマンドで集めた回答をもとにAIが処理する指示...',
                  maxLines: 4),

              const SizedBox(height: 32),
              // 質問設定
              Row(
                children: [
                  _buildSectionTitle('質問設定'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('質問を追加', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF7C3AED)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_questions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.quiz_outlined, size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('質問がありません',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('「質問を追加」から追加してください',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _questions.length,
                  onReorder: (old, newIdx) {
                    if (newIdx > old) newIdx--;
                    final item = _questions.removeAt(old);
                    _questions.insert(newIdx, item);
                    setState(() {});
                  },
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final type = q['type'] as String? ?? 'text';
                    final options = (q['options'] as List<dynamic>?)?.cast<String>() ?? [];
                    final typeLabel = type == 'select'
                        ? '選択式'
                        : type == 'select_or_text'
                            ? '選択+自由入力'
                            : '自由入力';

                    return Card(
                      key: ValueKey('q_$index'),
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: InkWell(
                        onTap: () => _editQuestion(index),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      q['question'] as String? ?? '(未入力)',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(typeLabel,
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                        ),
                                        if (options.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text('${options.length}択',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                                onPressed: () => _removeQuestion(index),
                              ),
                              Icon(Icons.drag_handle_rounded, size: 18, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF7C3AED)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}

// ================================================
// 質問編集画面
// ================================================
class _QuestionEditScreen extends StatefulWidget {
  final Map<String, dynamic> question;

  const _QuestionEditScreen({required this.question});

  @override
  State<_QuestionEditScreen> createState() => _QuestionEditScreenState();
}

class _QuestionEditScreenState extends State<_QuestionEditScreen> {
  late TextEditingController _questionController;
  late TextEditingController _placeholderController;
  late String _type;
  late bool _required;
  late List<String> _options;
  final _optionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.question['question'] ?? '');
    _placeholderController = TextEditingController(text: widget.question['placeholder'] ?? '');
    _type = widget.question['type'] as String? ?? 'text';
    _required = widget.question['required'] as bool? ?? false;
    _options = List<String>.from(
        (widget.question['options'] as List<dynamic>?)?.cast<String>() ?? []);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _placeholderController.dispose();
    _optionController.dispose();
    super.dispose();
  }

  void _addOption() {
    final text = _optionController.text.trim();
    if (text.isEmpty) return;
    setState(() => _options.add(text));
    _optionController.clear();
  }

  void _save() {
    Navigator.pop(context, {
      'question': _questionController.text.trim(),
      'type': _type,
      'options': _options,
      'placeholder': _placeholderController.text.trim(),
      'required': _required,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('質問を編集', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('完了',
                style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 質問テキスト
              Text('質問テキスト',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  hintText: '例: 今日の様子は？',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF7C3AED)),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 回答タイプ
              Text('回答タイプ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildTypeChip('text', '自由入力'),
                  _buildTypeChip('select', '選択式'),
                  _buildTypeChip('select_or_text', '選択+自由入力'),
                ],
              ),
              const SizedBox(height: 20),

              // 選択肢（select or select_or_text の場合）
              if (_type == 'select' || _type == 'select_or_text') ...[
                Text('選択肢',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                ..._options.asMap().entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(entry.value, style: const TextStyle(fontSize: 14)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _options.removeAt(entry.key)),
                          child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionController,
                        onSubmitted: (_) => _addOption(),
                        decoration: InputDecoration(
                          hintText: '選択肢を入力...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF7C3AED)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add_circle, color: Color(0xFF7C3AED)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // プレースホルダー（text の場合）
              if (_type == 'text' || _type == 'select_or_text') ...[
                Text('プレースホルダー',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _placeholderController,
                  decoration: InputDecoration(
                    hintText: '例: 活動内容を入力してください',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF7C3AED)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 必須
              SwitchListTile(
                value: _required,
                onChanged: (v) => setState(() => _required = v),
                title: const Text('必須項目', style: TextStyle(fontSize: 14)),
                subtitle: Text('この質問は回答必須にする', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                activeColor: const Color(0xFF7C3AED),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String value, String label) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF7C3AED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF7C3AED) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
