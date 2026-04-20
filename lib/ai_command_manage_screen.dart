import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';

class AiCommandManageScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AiCommandManageScreen({super.key, this.onBack});

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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommandEditDialog(onSaved: _loadCommands),
    );
  }

  void _editCommand(Map<String, dynamic> cmd) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommandEditDialog(existing: cmd, onSaved: _loadCommands),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('AI相談コマンド設定', style: TextStyle(fontSize: 16)),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.colors.textSecondary),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.colors.borderLight, height: 0.5),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCommand,
        backgroundColor: context.colors.aiAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.colors.aiAccent))
          : _commands.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tag_rounded, size: 64, color: context.colors.borderMedium),
                      SizedBox(height: 16),
                      Text('コマンドがありません', style: TextStyle(color: context.colors.textTertiary, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('右下の + ボタンから追加してください',
                          style: TextStyle(color: context.colors.textHint, fontSize: 13)),
                    ],
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _commands.length,
                      itemBuilder: (context, index) {
                        final cmd = _commands[index];
                        final questions = cmd['questions'] as List<dynamic>? ?? [];
                        return Card(
                          key: ValueKey(cmd['docId']),
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: context.colors.borderLight),
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
                                                color: context.colors.aiAccent.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '/${cmd['label'] ?? ''}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: context.colors.aiAccent,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              cmd['freeform'] == true ? '自由記述' : '${questions.length}問',
                                              style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300),
                                    onPressed: () => _deleteCommand(cmd),
                                  ),
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
// コマンド編集ダイアログ（質問管理付き）
// ================================================
class _CommandEditDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _CommandEditDialog({this.existing, required this.onSaved});

  @override
  State<_CommandEditDialog> createState() => _CommandEditDialogState();
}

class _CommandEditDialogState extends State<_CommandEditDialog> {
  late TextEditingController _labelController;
  late TextEditingController _descController;
  late TextEditingController _scriptController;
  List<Map<String, dynamic>> _questions = [];
  bool _isSaving = false;
  bool _freeform = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.existing?['label'] ?? '');
    _descController = TextEditingController(text: widget.existing?['description'] ?? '');
    _scriptController = TextEditingController(text: widget.existing?['script'] ?? '');
    _freeform = widget.existing?['freeform'] == true;

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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuestionEditDialog(question: q),
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
        'questions': _freeform ? <Map<String, dynamic>>[] : _questions,
        'freeform': _freeform,
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
    return Dialog(
      backgroundColor: context.colors.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.colors.borderLight, width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: context.colors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _isNew ? 'コマンドを追加' : 'コマンドを編集',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: Text(
                      '保存',
                      style: TextStyle(
                        color: _isSaving ? context.colors.textHint : context.colors.aiAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // コンテンツ
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
              // 基本情報
              _buildSectionTitle('基本情報'),
              const SizedBox(height: 12),
              _buildTextField('コマンド名', _labelController, 'ケア記録'),
              const SizedBox(height: 12),
              _buildTextField('説明', _descController, 'コマンドの説明（自由記述モード時に表示）'),
              const SizedBox(height: 12),
              _buildTextField('スクリプト（AIへの指示）', _scriptController,
                  'このコマンドで集めた回答をもとにAIが処理する指示...',
                  maxLines: 4),

              const SizedBox(height: 20),
              // 自由記述モード切替
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _freeform ? context.colors.aiAccent.withOpacity(0.06) : context.colors.tagBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _freeform ? context.colors.aiAccent.withOpacity(0.3) : context.colors.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 20,
                      color: _freeform ? context.colors.aiAccent : context.colors.textTertiary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '自由記述モード',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _freeform ? context.colors.aiAccent : context.colors.textSecondary,
                            ),
                          ),
                          Text(
                            'ONにすると、質問形式ではなく自由記述で入力し、AIが整形する',
                            style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _freeform,
                      activeColor: context.colors.aiAccent,
                      onChanged: (v) => setState(() => _freeform = v),
                    ),
                  ],
                ),
              ),

              if (!_freeform) ...[
              const SizedBox(height: 32),
              // 質問設定
              Row(
                children: [
                  _buildSectionTitle('質問設定'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('質問を追加', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(foregroundColor: context.colors.aiAccent),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_questions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: context.colors.tagBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderLight, style: BorderStyle.solid),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.quiz_outlined, size: 32, color: context.colors.textHint),
                      SizedBox(height: 8),
                      Text('質問がありません',
                          style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
                      SizedBox(height: 4),
                      Text('「質問を追加」から追加してください',
                          style: TextStyle(color: context.colors.textHint, fontSize: 12)),
                    ],
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _questions.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _questions.removeAt(oldIndex);
                      _questions.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    final type = q['type'] as String? ?? 'text';
                    final options = (q['options'] as List<dynamic>?)?.cast<String>() ?? [];
                    final typeLabel = {
                      'select': '選択式',
                      'select_or_text': '選択+自由入力',
                      'date': '日付',
                      'datetime': '日時',
                      'plus_staff': 'プラススタッフ',
                    }[type] ?? '自由入力';

                    return Padding(
                      key: ValueKey(q),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.colors.borderLight),
                        ),
                        child: InkWell(
                          onTap: () => _editQuestion(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(Icons.drag_indicator,
                                        size: 20, color: context.colors.textTertiary),
                                  ),
                                ),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: context.colors.aiAccent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.aiAccent,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        q['question'] as String? ?? '(未入力)',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: context.colors.chipBg,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(typeLabel,
                                                style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                                          ),
                                          if (options.isNotEmpty) ...[
                                            SizedBox(width: 6),
                                            Text('${options.length}択',
                                                style: TextStyle(fontSize: 10, color: context.colors.textTertiary)),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ], // if (!_freeform)
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
            filled: true,
            fillColor: context.colors.tagBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.aiAccent),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}

// ================================================
// 質問編集ダイアログ
// ================================================
class _QuestionEditDialog extends StatefulWidget {
  final Map<String, dynamic> question;

  const _QuestionEditDialog({required this.question});

  @override
  State<_QuestionEditDialog> createState() => _QuestionEditDialogState();
}

class _QuestionEditDialogState extends State<_QuestionEditDialog> {
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
    return Dialog(
      backgroundColor: context.colors.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.colors.borderLight, width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: context.colors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '質問を編集',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    child: Text('完了',
                        style: TextStyle(color: context.colors.aiAccent, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            // コンテンツ
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
              // 質問テキスト
              Text('質問テキスト',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
              SizedBox(height: 6),
              TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  hintText: '例: 今日の様子は？',
                  hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                  filled: true,
                  fillColor: context.colors.tagBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.borderMedium),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.aiAccent),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 回答タイプ
              Text('回答タイプ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildTypeChip('text', '自由入力'),
                  _buildTypeChip('select', '選択式'),
                  _buildTypeChip('select_or_text', '選択+自由入力'),
                  _buildTypeChip('date', '日付'),
                  _buildTypeChip('datetime', '日時'),
                  _buildTypeChip('plus_staff', 'プラススタッフ'),
                ],
              ),
              const SizedBox(height: 20),

              // 選択肢（select or select_or_text の場合）
              if (_type == 'select' || _type == 'select_or_text') ...[
                Text('選択肢',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                SizedBox(height: 8),
                ..._options.asMap().entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.tagBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.borderLight),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(entry.value, style: TextStyle(fontSize: 14)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _options.removeAt(entry.key)),
                          child: Icon(Icons.close_rounded, size: 18, color: context.colors.textTertiary),
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
                          hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                          filled: true,
                          fillColor: context.colors.tagBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.colors.borderMedium),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.colors.aiAccent),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: _addOption,
                      icon: Icon(Icons.add_circle, color: context.colors.aiAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // プレースホルダー（text の場合）
              if (_type == 'text' || _type == 'select_or_text') ...[
                Text('プレースホルダー',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                SizedBox(height: 6),
                TextField(
                  controller: _placeholderController,
                  decoration: InputDecoration(
                    hintText: '例: 活動内容を入力してください',
                    hintStyle: TextStyle(fontSize: 13, color: context.colors.textHint),
                    filled: true,
                    fillColor: context.colors.tagBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.colors.borderMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.colors.aiAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 必須
              SwitchListTile(
                value: _required,
                onChanged: (v) => setState(() => _required = v),
                title: Text('必須項目', style: TextStyle(fontSize: 14)),
                subtitle: Text('この質問は回答必須にする', style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
                activeColor: context.colors.aiAccent,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
          ],
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
          color: selected ? context.colors.aiAccent : context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? context.colors.aiAccent : context.colors.borderMedium,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : context.colors.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
