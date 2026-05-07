import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../crm_lead_screen.dart' show CrmOptions;
import '../widgets/app_feedback.dart';
import 'campaign.dart';

/// Campaign の起案 / 編集ダイアログ。
/// `existing` が null の場合は新規起案、与えられた場合は編集。
class CampaignFormDialog extends StatefulWidget {
  final Campaign? existing;
  const CampaignFormDialog({super.key, this.existing});

  @override
  State<CampaignFormDialog> createState() => _CampaignFormDialogState();
}

class _CampaignFormDialogState extends State<CampaignFormDialog> {
  final _nameCtrl = TextEditingController();
  final _hypothesisCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _expectedLeadsCtrl = TextEditingController(text: '0');
  final _expectedConversionsCtrl = TextEditingController(text: '0');
  String _channel = 'instagram';
  CampaignType _type = CampaignType.organic;
  CampaignStatus _status = CampaignStatus.planning;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _hypothesisCtrl.text = e.hypothesis;
      _costCtrl.text = e.cost?.toString() ?? '';
      _expectedLeadsCtrl.text = e.expectedLeads.toString();
      _expectedConversionsCtrl.text = e.expectedConversions.toString();
      _channel = e.channel;
      _type = e.type;
      _status = e.status;
      _startDate = e.startDate;
      _endDate = e.endDate;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _hypothesisCtrl,
      _costCtrl,
      _expectedLeadsCtrl,
      _expectedConversionsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppFeedback.warning(context, '施策名を入力してください');
      return;
    }
    setState(() => _saving = true);
    try {
      final costText = _costCtrl.text.trim();
      final cost = costText.isEmpty ? null : num.tryParse(costText);
      final draft = Campaign(
        id: widget.existing?.id ?? '',
        businessId: widget.existing?.businessId ?? 'Plus',
        name: _nameCtrl.text.trim(),
        channel: _channel,
        type: _type,
        cost: cost,
        startDate: _startDate,
        endDate: _endDate,
        hypothesis: _hypothesisCtrl.text.trim(),
        expectedLeads: int.tryParse(_expectedLeadsCtrl.text.trim()) ?? 0,
        expectedConversions:
            int.tryParse(_expectedConversionsCtrl.text.trim()) ?? 0,
        status: _status,
        retrospective: widget.existing?.retrospective,
        createdAt: widget.existing?.createdAt,
        updatedAt: widget.existing?.updatedAt,
        createdBy: widget.existing?.createdBy,
      );
      final col = FirebaseFirestore.instance.collection('campaigns');
      if (widget.existing == null) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        await col.add(draft.toCreateMap(createdBy: uid));
      } else {
        await col.doc(widget.existing!.id).update(draft.toUpdateMap());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEdit ? '施策を編集' : '新規施策を起案',
                style: const TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '施策名（必須）',
                        hintText: 'Instagram_Reel_教具紹介_2026Q2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _channel,
                            decoration: const InputDecoration(
                              labelText: '媒体',
                              border: OutlineInputBorder(),
                            ),
                            items: CrmOptions.sources
                                .map((s) => DropdownMenuItem(
                                    value: s.id, child: Text(s.label)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _channel = v ?? 'instagram'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<CampaignType>(
                            initialValue: _type,
                            decoration: const InputDecoration(
                              labelText: 'タイプ',
                              border: OutlineInputBorder(),
                            ),
                            items: CampaignType.values
                                .map((t) => DropdownMenuItem(
                                    value: t, child: Text(t.label)))
                                .toList(),
                            onChanged: (v) => setState(
                                () => _type = v ?? CampaignType.organic),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _costCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '実費（円） — 空欄なら計上対象外（organic 等）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('開始: ${_fmt(_startDate)}'),
                            onPressed: () => _pickDate(start: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event_available, size: 16),
                            label: Text(_endDate == null
                                ? '終了: 未設定（進行中）'
                                : '終了: ${_fmt(_endDate!)}'),
                            onPressed: () => _pickDate(start: false),
                          ),
                        ),
                        if (_endDate != null)
                          IconButton(
                            tooltip: '終了日をクリア',
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                setState(() => _endDate = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hypothesisCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '仮説',
                        hintText: '教具動画は感覚教育関心層に刺さる',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _expectedLeadsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '想定 Lead 数',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _expectedConversionsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '想定入会数',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CampaignStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'ステータス',
                        border: OutlineInputBorder(),
                      ),
                      items: CampaignStatus.values
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(s.label)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _status = v ?? CampaignStatus.planning),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(isEdit ? '更新' : '起案'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => DateFormat('yyyy/M/d').format(d);
}
