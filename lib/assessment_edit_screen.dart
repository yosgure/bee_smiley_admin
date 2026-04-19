import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'app_theme.dart';
import 'main.dart';

class AssessmentEditScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String type;
  final String? docId;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onClose;

  const AssessmentEditScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.type,
    this.docId,
    this.initialData,
    this.onClose,
  });

  @override
  State<AssessmentEditScreen> createState() => _AssessmentEditScreenState();
}

class _AssessmentEditScreenState extends State<AssessmentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late Future<void> _initializationFuture;

  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  void _close() {
    if (widget.onClose != null) {
      AdminShell.hideOverlay(context);
    } else {
      Navigator.pop(context);
    }
  }

  List<Map<String, dynamic>> _weeklyEntries = [];
  List<Map<String, String>> _toolList = [];
  final List<String> _durationOptions = ['0〜5分', '6〜10分', '11〜20分', '20分以上'];

  final TextEditingController _monthlySummaryController = TextEditingController();
  List<Map<String, String?>> _monthlyEntries = [];

  Map<String, List<String>> _nonCognitiveSkillMap = {};

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _fetchMasters();
    
    if (widget.initialData != null) {
      _initializeEditData();
    } else {
      _initializeNewData();
    }
  }

  Future<void> _fetchMasters() async {
    try {
      if (widget.type == 'weekly') {
        final toolsSnap = await FirebaseFirestore.instance.collection('tools').get();
        _toolList = toolsSnap.docs.map((d) {
          final data = d.data();
          return {
            'name': (data['name'] ?? '') as String,
            'furigana': (data['furigana'] ?? '') as String,
            'task': (data['task'] ?? '') as String,
          };
        }).toList();

        if (_toolList.isEmpty) {
          _toolList = [
            {'name': '円柱さし', 'furigana': 'えんちゅうさし'},
            {'name': 'ピンクタワー', 'furigana': 'ぴんくたわー'},
          ];
        }
        
        _toolList.sort((a, b) {
          final ka = a['furigana'] ?? a['name'] ?? '';
          final kb = b['furigana'] ?? b['name'] ?? '';
          return ka.compareTo(kb);
        });

      } else {
        final ncSnap = await FirebaseFirestore.instance.collection('non_cognitive_skills').get();

        _nonCognitiveSkillMap = {};
        for (var doc in ncSnap.docs) {
          final data = doc.data();
          final name = data['name'] as String;

          List<String> skills = List<String>.from(data['strengths'] ?? []);
          if (skills.isEmpty) {
            skills = List<String>.from(data['growing_skills'] ?? []);
          }
          if (skills.isEmpty) {
            skills = List<String>.from(data['growingSkills'] ?? []);
          }

          _nonCognitiveSkillMap[name] = skills;
        }
      }
    } catch (e) {
      debugPrint('Error fetching masters: $e');
    }
  }

  void _initializeNewData() {
    if (widget.type == 'weekly') {
      _addWeeklyEntry();
    } else {
      _addMonthlyEntry();
    }
  }

  void _initializeEditData() {
    final data = widget.initialData!;
    if (data['date'] != null) {
      _selectedDate = (data['date'] as Timestamp).toDate();
    }

    if (widget.type == 'weekly') {
      final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      for (var entry in entries) {
        // 既存データのマイグレーション: mediaItems > photoUrl > [] の優先順
        final List<Map<String, dynamic>> media = [];
        final mediaItemsRaw = entry['mediaItems'] as List<dynamic>?;
        if (mediaItemsRaw != null && mediaItemsRaw.isNotEmpty) {
          for (var m in mediaItemsRaw) {
            if (m is Map) {
              media.add({
                'type': m['type'] ?? 'image',
                'url': m['url'],
                'localFile': null,
              });
            }
          }
        } else if (entry['photoUrl'] != null && (entry['photoUrl'] as String).isNotEmpty) {
          media.add({'type': 'image', 'url': entry['photoUrl'], 'localFile': null});
        }
        _weeklyEntries.add({
          'tool': entry['tool'] ?? '',
          'rating': entry['rating'] ?? '○',
          'duration': entry['duration'],
          'comment': entry['comment'] ?? '',
          'media': media,
        });
      }
      if (_weeklyEntries.isEmpty) _addWeeklyEntry();
    } else {
      _monthlySummaryController.text = data['summary'] ?? '';
      // 非認知能力エントリー
      final savedEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);
      for (var entry in savedEntries) {
        _monthlyEntries.add({
          'category': entry['category'] as String?,
          'skill': entry['skill'] as String?,
        });
      }
      if (_monthlyEntries.isEmpty) _addMonthlyEntry();
    }
  }

  void _addWeeklyEntry() {
    setState(() {
      _weeklyEntries.add({
        'tool': null,
        'rating': '○',
        'duration': null,
        'comment': '',
        'media': <Map<String, dynamic>>[],
      });
    });
  }

  void _removeWeeklyEntry(int index) {
    setState(() {
      _weeklyEntries.removeAt(index);
    });
  }

  Future<void> _pickMedia(int index) async {
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultipleMedia();
    if (files.isNotEmpty) {
      setState(() {
        final media = _weeklyEntries[index]['media'] as List<Map<String, dynamic>>;
        for (final f in files) {
          media.add({'type': _detectMediaType(f), 'url': null, 'localFile': f});
        }
      });
    }
  }

  String _detectMediaType(XFile f) {
    final mime = f.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('image/')) return 'image';
    final lower = f.name.toLowerCase();
    const videoExt = ['.mp4', '.mov', '.webm', '.m4v', '.avi', '.mkv', '.3gp'];
    if (videoExt.any(lower.endsWith)) return 'video';
    return 'image';
  }

  void _removeMedia(int entryIndex, int mediaIndex) {
    setState(() {
      final media = _weeklyEntries[entryIndex]['media'] as List<Map<String, dynamic>>;
      media.removeAt(mediaIndex);
    });
  }

  void _addMonthlyEntry() {
    setState(() {
      _monthlyEntries.add({
        'category': null,
        'skill': null,
      });
    });
  }

  void _removeMonthlyEntry(int index) {
    setState(() {
      _monthlyEntries.removeAt(index);
    });
  }

  // ★修正: 画像を圧縮してアップロード（目標: 約500KB以下）
  Future<String?> _uploadImage(XFile file) async {
    try {
      Uint8List fileBytes = await file.readAsBytes();

      // 画像を圧縮
      fileBytes = await _compressImage(fileBytes);

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('assessment_photos/$fileName');
      await ref.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<String?> _uploadVideo(XFile file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('assessment_videos/$fileName');
      // 拡張子から content type を簡易判定（mp4/mov/webm 等）
      final lower = file.name.toLowerCase();
      String contentType = 'video/mp4';
      if (lower.endsWith('.mov')) contentType = 'video/quicktime';
      else if (lower.endsWith('.webm')) contentType = 'video/webm';
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading video: $e');
      return null;
    }
  }

  // ★追加: 画像圧縮処理（目標: 約500KB）
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    try {
      // 画像をデコード
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return bytes;

      // 長辺を1200pxに制限（これで大体500KB以下になる）
      const int maxDimension = 1200;
      if (image.width > maxDimension || image.height > maxDimension) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: maxDimension);
        } else {
          image = img.copyResize(image, height: maxDimension);
        }
      }

      // JPEG品質80%で圧縮
      final compressed = img.encodeJpg(image, quality: 80);
      
      debugPrint('Image compressed: ${bytes.length} -> ${compressed.length} bytes');
      return Uint8List.fromList(compressed);
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return bytes; // 圧縮に失敗した場合は元の画像を返す
    }
  }

  // 下書き保存
  Future<void> _saveDraft() async {
    await _save(isPublished: false);
  }

  // 公開保存
  Future<void> _publish() async {
    await _save(isPublished: true);
  }

  Future<void> _save({required bool isPublished}) async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String staffName = '担当スタッフ'; 
      if (user != null) {
         final snap = await FirebaseFirestore.instance.collection('staffs').where('uid', isEqualTo: user.uid).get();
         if (snap.docs.isNotEmpty) staffName = snap.docs.first.data()['name'] ?? '担当スタッフ';
      }

      final Map<String, dynamic> data = {
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'type': widget.type,
        'date': _selectedDate,
        'staffId': user?.uid,
        'staffName': staffName, 
        'updatedAt': FieldValue.serverTimestamp(),
        'isPublished': isPublished, // ★追加: 公開フラグ
      };

      if (widget.type == 'weekly') {
        List<Map<String, dynamic>> savedEntries = [];
        for (var entry in _weeklyEntries) {
          // メディアをアップロードして mediaItems を作る
          final List<Map<String, dynamic>> mediaInput =
              List<Map<String, dynamic>>.from(entry['media'] as List);
          final List<Map<String, dynamic>> mediaItems = [];
          for (final m in mediaInput) {
            String? url = m['url'] as String?;
            final XFile? local = m['localFile'] as XFile?;
            if (local != null) {
              if (m['type'] == 'video') {
                url = await _uploadVideo(local);
              } else {
                url = await _uploadImage(local);
              }
            }
            if (url != null && url.isNotEmpty) {
              mediaItems.add({'type': m['type'] ?? 'image', 'url': url});
            }
          }
          // 旧フィールド互換: 先頭の画像URL
          final firstImageUrl = mediaItems
              .firstWhere((m) => m['type'] == 'image', orElse: () => <String, dynamic>{})['url'];

          savedEntries.add({
            'tool': entry['tool'] ?? '未選択',
            'rating': entry['rating'],
            'duration': entry['duration'],
            'comment': entry['comment'],
            'photoUrl': firstImageUrl,
            'mediaItems': mediaItems,
            'task': _toolList.firstWhere((t) => t['name'] == entry['tool'], orElse: () => {'task': ''})['task'] ?? '',
          });
        }
        data['entries'] = savedEntries;
        data['dateRange'] = DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate);
        
        if (savedEntries.isNotEmpty) {
          final first = savedEntries.first;
          data['content'] = '${first['tool']} (${first['rating']})... 他${savedEntries.length - 1}件';
        } else {
          data['content'] = '(記録なし)';
        }
      } else {
        data['summary'] = _monthlySummaryController.text;
        data['monthlyEntries'] = _monthlyEntries;
        
        final flatSkills = _monthlyEntries
            .map((e) => e['skill'])
            .where((s) => s != null)
            .cast<String>()
            .toList();
        final flatCategories = _monthlyEntries
            .map((e) => e['category'])
            .where((c) => c != null)
            .cast<String>()
            .toSet()
            .toList();

        data['strengths'] = flatSkills;
        data['skills'] = [
          ...flatCategories,
          ...flatSkills,
        ];
      }

      if (widget.docId != null) {
        await FirebaseFirestore.instance.collection('assessments').doc(widget.docId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('assessments').add(data);
      }

      if (mounted) _close();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showToolSelectDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => _ToolSelectDialog(
        tools: _toolList,
        onSelected: (toolName) {
          setState(() {
            _weeklyEntries[index]['tool'] = toolName;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 既に公開済みかどうか
    final isAlreadyPublished = widget.initialData?['isPublished'] == true;
    
    return Scaffold(
      backgroundColor: context.colors.cardBg,
      appBar: AppBar(
        title: Text(widget.type == 'weekly' ? '週次アセスメント編集' : '月次サマリ編集'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        actions: [
          // 公開済みでない場合は「下書き保存」ボタンを表示
          if (!isAlreadyPublished)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              child: OutlinedButton(
                onPressed: _isSaving ? null : _saveDraft,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: AppColors.primary),
                ),
                child: _isSaving 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('下書き保存', style: TextStyle(fontSize: 13, color: AppColors.primary)),
              ),
            ),
          // 公開ボタン（公開済みの場合は「更新」）
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _publish,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(60, 36),
              ),
              child: _isSaving 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                : Text(isAlreadyPublished ? '更新' : '公開', style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: FutureBuilder(
            future: _initializationFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          widget.studentName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: context.colors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildDateSelector(),
                      const SizedBox(height: 24),
                      if (widget.type == 'weekly') _buildWeeklyForm() else _buildMonthlyForm(),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection(int entryIndex, Map<String, dynamic> entry) {
    final media = (entry['media'] as List).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('写真・動画', style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: media.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == media.length) {
                return _addMediaButton(
                  icon: Icons.perm_media,
                  label: '追加',
                  onTap: () => _pickMedia(entryIndex),
                );
              }
              final m = media[i];
              return _mediaThumb(m, () => _removeMedia(entryIndex, i));
            },
          ),
        ),
      ],
    );
  }

  Widget _addMediaButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.borderLight, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: context.colors.textSecondary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _mediaThumb(Map<String, dynamic> m, VoidCallback onRemove) {
    final type = m['type'] as String? ?? 'image';
    final XFile? local = m['localFile'] as XFile?;
    final String? url = m['url'] as String?;
    Widget content;
    if (type == 'video') {
      content = Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
      );
    } else if (local != null) {
      content = kIsWeb
          ? Image.network(local.path, fit: BoxFit.cover)
          : Image.file(File(local.path), fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      content = Image.network(url, fit: BoxFit.cover);
    } else {
      content = Container(color: context.colors.inputFill);
    }
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 80, height: 80, child: content),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
          if (type == 'video')
            const Positioned(
              bottom: 4,
              left: 4,
              child: Icon(Icons.videocam, color: Colors.white, size: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final isWeekly = widget.type == 'weekly';
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          locale: const Locale('ja'),
        );
        if (picked != null) {
          setState(() {
            _selectedDate = picked;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: AppStyles.radius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isWeekly ? 'レッスン日' : '対象月', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  isWeekly 
                      ? DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate)
                      : DateFormat('yyyy年 M月度').format(_selectedDate),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyForm() {
    return Column(
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _weeklyEntries.length,
          itemBuilder: (context, index) {
            final entry = _weeklyEntries[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('教具 ${index + 1}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                      if (_weeklyEntries.length > 1)
                        IconButton(
                          icon: Icon(Icons.close, color: context.colors.textSecondary, size: 20),
                          onPressed: () => _removeWeeklyEntry(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  InkWell(
                    onTap: () => _showToolSelectDialog(index),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: context.colors.inputFill,
                        borderRadius: AppStyles.radiusSmall,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry['tool'] ?? '教具を選択',
                            style: TextStyle(
                              color: entry['tool'] == null ? context.colors.textSecondary : context.colors.textPrimary,
                              fontSize: 16,
                              fontWeight: entry['tool'] != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Text('評価', style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      _buildCircleRating(index, '△', Colors.blue),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '○', AppColors.accent),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '◎', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    initialValue: entry['comment'],
                    decoration: const InputDecoration(
                      hintText: 'コメントを入力...',
                    ),
                    maxLines: 2,
                    onChanged: (val) => entry['comment'] = val,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildMediaSection(index, entry),
                ],
              ),
            );
          },
        ),
        Center(
          child: OutlinedButton.icon(
            onPressed: _addWeeklyEntry,
            icon: const Icon(Icons.add),
            label: const Text('教具を追加'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              side: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircleRating(int index, String label, Color color) {
    final isSelected = _weeklyEntries[index]['rating'] == label;
    return InkWell(
      onTap: () => setState(() => _weeklyEntries[index]['rating'] = label),
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : context.colors.cardBg,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? color : context.colors.iconMuted),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.colors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('非認知能力・伸びている力', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
        ),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _monthlyEntries.length,
          itemBuilder: (context, index) {
            final entry = _monthlyEntries[index];
            final selectedCategory = entry['category'];
            final skillOptions = selectedCategory != null ? (_nonCognitiveSkillMap[selectedCategory] ?? []) : <String>[];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('項目 ${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary, fontSize: 12)),
                      if (_monthlyEntries.length > 1)
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
                          onPressed: () => _removeMonthlyEntry(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  
                  DropdownButtonFormField<String>(
                    value: _nonCognitiveSkillMap.keys.contains(entry['category']) ? entry['category'] : null,
                    decoration: const InputDecoration(
                      labelText: '非認知能力',
                    ),
                    isExpanded: true,
                    items: _nonCognitiveSkillMap.keys.map((key) => DropdownMenuItem(value: key, child: Text(key))).toList(),
                    onChanged: (val) {
                      setState(() {
                        entry['category'] = val;
                        entry['skill'] = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    value: skillOptions.contains(entry['skill']) ? entry['skill'] : null,
                    decoration: InputDecoration(
                      labelText: '伸びている力',
                      filled: selectedCategory == null,
                      fillColor: selectedCategory == null ? context.colors.chipBg : context.colors.inputFill,
                    ),
                    isExpanded: true,
                    items: skillOptions.map((skill) => DropdownMenuItem(value: skill, child: Text(skill))).toList(),
                    onChanged: selectedCategory == null ? null : (val) {
                      setState(() => entry['skill'] = val);
                    },
                  ),
                ],
              ),
            );
          },
        ),

        Center(
          child: OutlinedButton.icon(
            onPressed: _addMonthlyEntry,
            icon: const Icon(Icons.add),
            label: const Text('項目を追加'),
          ),
        ),
        const SizedBox(height: 24),

        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('月間総評', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
        ),
        TextField(
          controller: _monthlySummaryController,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '今月の様子や成長した点などを入力してください...',
          ),
        ),
      ],
    );
  }
}

class _ToolSelectDialog extends StatefulWidget {
  final List<Map<String, String>> tools;
  final Function(String) onSelected;

  const _ToolSelectDialog({required this.tools, required this.onSelected});

  @override
  State<_ToolSelectDialog> createState() => _ToolSelectDialogState();
}

class _ToolSelectDialogState extends State<_ToolSelectDialog> {
  List<Map<String, String>> _filteredTools = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredTools = widget.tools;
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredTools = widget.tools;
      } else {
        _filteredTools = widget.tools.where((tool) {
          return (tool['name']!.contains(query)) || (tool['furigana']!.contains(query));
        }).toList();
      }
    });
  }

  // ひらがなの五十音順でヘッダーを判定（Unicodeコードポイント使用）
  String _getIndexHeader(String kana) {
    if (kana.isEmpty) return '他';
    final c = kana.codeUnitAt(0);
    // あ行: U+3042(あ) - U+304A(お)
    if (c >= 0x3042 && c <= 0x304A) return 'あ';
    // か行: U+304B(か) - U+3054(ご) ※濁音含む
    if (c >= 0x304B && c <= 0x3054) return 'か';
    // さ行: U+3055(さ) - U+305E(ぞ)
    if (c >= 0x3055 && c <= 0x305E) return 'さ';
    // た行: U+305F(た) - U+3069(ど)
    if (c >= 0x305F && c <= 0x3069) return 'た';
    // な行: U+306A(な) - U+306E(の)
    if (c >= 0x306A && c <= 0x306E) return 'な';
    // は行: U+306F(は) - U+307D(ぽ)
    if (c >= 0x306F && c <= 0x307D) return 'は';
    // ま行: U+307E(ま) - U+3082(も)
    if (c >= 0x307E && c <= 0x3082) return 'ま';
    // や行: U+3084(や), U+3086(ゆ), U+3088(よ)
    if (c >= 0x3083 && c <= 0x3088) return 'や';
    // ら行: U+3089(ら) - U+308D(ろ)
    if (c >= 0x3089 && c <= 0x308D) return 'ら';
    // わ行: U+308F(わ) - U+3093(ん)
    if (c >= 0x308E && c <= 0x3093) return 'わ';
    return '他';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 400,
        height: 600,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('教具を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '教具名で検索...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _onSearch,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.textSecondary),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredTools.length,
                itemBuilder: (context, index) {
                  final tool = _filteredTools[index];
                  final header = _getIndexHeader(tool['furigana'] ?? '');
                  bool showHeader = true;
                  if (index > 0) {
                    final prevHeader = _getIndexHeader(_filteredTools[index - 1]['furigana'] ?? '');
                    if (prevHeader == header) showHeader = false;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          color: context.colors.inputFill,
                          child: Text(header, style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
                        ),
                      ListTile(
                        title: Text(tool['name']!),
                        onTap: () {
                          widget.onSelected(tool['name']!);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}