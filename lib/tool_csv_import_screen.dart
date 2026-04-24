import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';
import 'services/undo_service.dart';

class ToolCsvImportScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ToolCsvImportScreen({super.key, this.onBack});

  @override
  State<ToolCsvImportScreen> createState() => _ToolCsvImportScreenState();
}

class _ToolCsvImportScreenState extends State<ToolCsvImportScreen> {
  List<List<dynamic>> _csvData = [];
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _pickCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null) {
        final bytes = result.files.first.bytes!;
        final csvString = utf8.decode(bytes);
        
        setState(() {
          _csvData = const CsvToListConverter().convert(csvString);
          _statusMessage = '${_csvData.length - 1} 件のデータを読み込みました。';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'エラー: CSVを読み込めませんでした。\n$e');
    }
  }

  Future<void> _registerAll() async {
    if (_csvData.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '登録処理中...';
    });

    final firestore = FirebaseFirestore.instance;
    int successCount = 0;
    int errorCount = 0;
    // Undo 用に作成した doc ID を追跡
    final createdIds = <String>[];

    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      // 列順: [0]教具名, [1]ふりがな, [2]発達課題, [3]動画URL, [4]カテゴリ(任意)
      if (row.isEmpty) continue;

      try {
        final ref = await firestore.collection('tools').add({
          'name': row[0].toString().trim(),
          'furigana': row.length > 1 ? row[1].toString().trim() : '',
          'task': row.length > 2 ? row[2].toString().trim() : '',
          'videoUrl': row.length > 3 ? row[3].toString().trim() : '',
          'category': row.length > 4 ? row[4].toString().trim() : '感覚', // デフォルト
          'imageUrl': null, // 写真は後から手動登録
          'createdAt': FieldValue.serverTimestamp(),
        });
        successCount++;
        createdIds.add(ref.id);
      } catch (e) {
        errorCount++;
        debugPrint('Error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = '完了！\n成功: $successCount 件\n失敗: $errorCount 件';
        if (successCount > 0) _csvData = [];
      });
    }

    if (createdIds.isNotEmpty && mounted) {
      await UndoService.run<List<String>>(
        context: context,
        label: '教具 $successCount 件を登録',
        doneMessage: '教具 $successCount 件を登録しました',
        window: const Duration(seconds: 60),
        captureSnapshot: () async => createdIds,
        execute: () async {},
        undo: (snap) async {
          final batch = FirebaseFirestore.instance.batch();
          for (final id in snap) {
            batch.delete(FirebaseFirestore.instance
                .collection('tools')
                .doc(id));
          }
          await batch.commit();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
return Scaffold(
  appBar: AppBar(
    title: const Text('教具CSV一括登録'),
    centerTitle: true,
    backgroundColor: context.colors.cardBg,
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
      onPressed: () {
        if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.pop(context);
        }
      },
    ),
  ),
  body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderMedium),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('【CSVルール: 教具】', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('列順: 教具名, ふりがな, 発達課題, 動画URL, カテゴリ'),
                  SizedBox(height: 8),
                  Text('例: ピンクタワー,ぴんくたわー,大きさの識別,https://...,感覚', style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickCsv,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('CSVを選択'),
                ),
                const SizedBox(width: 16),
                if (_csvData.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _registerAll,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('登録開始'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoading) const LinearProgressIndicator(),
            Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}