// 音声録音 → Cloud Function (Gemini) で議事録/ドキュメント自動生成する再利用可能 Widget。
// 議事録以外（事故ヒヤリハット・苦情受付など）でも documentType を変えれば使い回せる設計。

import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import '../app_theme.dart';
import 'app_feedback.dart';

class AudioMinuteRecorder extends StatefulWidget {
  /// 生成対象のドキュメント種別。現状 Cloud Function は 'morning_meeting' のみ対応。
  final String documentType;

  /// プロンプトに渡す実施日。
  final DateTime? meetingDate;

  /// プロンプトに渡す参加者名。
  final List<String> participants;

  /// 生成完了時に呼ばれる。引数は整形済みテキスト。
  final ValueChanged<String> onGenerated;

  /// 既存内容（あれば上書き確認を出す）
  final String existingContent;

  /// 案内文（カード上部のヘルプ）
  final String description;

  const AudioMinuteRecorder({
    super.key,
    required this.documentType,
    required this.onGenerated,
    this.meetingDate,
    this.participants = const [],
    this.existingContent = '',
    this.description = 'マイクで会議を録音すると、AIが議事録として整形して挿入します。',
  });

  @override
  State<AudioMinuteRecorder> createState() => _AudioMinuteRecorderState();
}

class _AudioMinuteRecorderState extends State<AudioMinuteRecorder> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  DateTime? _recordingStartedAt;
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _start() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) AppFeedback.error(context, 'マイクの使用が許可されていません');
        return;
      }
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: 'audio_minute.webm',
      );
      _recordingStartedAt = DateTime.now();
      setState(() {
        _isRecording = true;
        _duration = Duration.zero;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _recordingStartedAt == null) return;
        setState(() {
          _duration = DateTime.now().difference(_recordingStartedAt!);
        });
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, '録音開始失敗: $e');
    }
  }

  Future<void> _cancel() async {
    try {
      _timer?.cancel();
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _duration = Duration.zero;
        _recordingStartedAt = null;
      });
    }
  }

  Future<void> _stopAndGenerate() async {
    _timer?.cancel();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        AppFeedback.error(context, '録音停止失敗: $e');
      }
      return;
    }
    setState(() => _isRecording = false);

    if (path == null) {
      if (mounted) AppFeedback.error(context, '録音データが取得できませんでした');
      return;
    }

    if (widget.existingContent.trim().isNotEmpty) {
      if (!mounted) return;
      final overwrite = await AppFeedback.confirm(
        context,
        title: '既存の内容を置き換えますか？',
        message: '生成された議事録で内容を上書きします。',
        confirmLabel: '置き換える',
      );
      if (!overwrite) {
        if (!mounted) return;
        setState(() {
          _duration = Duration.zero;
          _recordingStartedAt = null;
        });
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      Uint8List bytes;
      if (kIsWeb) {
        final res = await http.get(Uri.parse(path));
        if (res.statusCode != 200) {
          throw '録音データの取得に失敗 (HTTP ${res.statusCode})';
        }
        bytes = res.bodyBytes;
      } else {
        final res = await http.get(Uri.parse('file://$path'));
        bytes = res.bodyBytes;
      }
      if (bytes.isEmpty) throw '録音データが空です';

      const mimeType = 'audio/webm';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final audioPath = 'meeting_minutes/audio_${uid}_$ts.webm';

      final storageRef = FirebaseStorage.instance.ref(audioPath);
      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: mimeType),
      );

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast1')
          .httpsCallable(
        'generateMorningMeetingMinutes',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'audioPath': audioPath,
        'mimeType': mimeType,
        'documentType': widget.documentType,
        'meetingDate': widget.meetingDate != null
            ? DateFormat('yyyy/M/d (E)', 'ja').format(widget.meetingDate!)
            : '',
        'participants': widget.participants,
      });
      final text = (result.data['minutes'] as String?)?.trim() ?? '';
      if (text.isEmpty) throw '議事録が生成されませんでした';

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _duration = Duration.zero;
        _recordingStartedAt = null;
      });
      widget.onGenerated(text);
      if (mounted) AppFeedback.success(context, '議事録を生成しました');
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppFeedback.error(context, '議事録生成失敗: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isProcessing)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '議事録を生成中…（音声長に応じて10秒〜2分程度かかります）',
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            )
          else if (_isRecording)
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.errorBorder,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '録音中  ${_formatDuration(_duration)}',
                  style: const TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.bold,
                    color: AppColors.errorBorder,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _cancel,
                  child: Text(
                    'キャンセル',
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: _stopAndGenerate,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止して生成'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorBorder,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.mic, size: 18),
                    label: const Text('録音を開始'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
