import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'classroom_utils.dart';

class StudentManageScreen extends StatefulWidget {
  final VoidCallback? onBack;

  /// 表示・編集対象のコレクション。
  /// 'families' = ビースマイリー通常（湘南台/湘南藤沢）
  /// 'plus_families' = ビースマイリープラス（児童発達支援/放デイ）
  final String collectionName;

  /// AppBarに表示するタイトル（コレクション名に応じて切替えやすくするため）
  final String? title;

  const StudentManageScreen({
    super.key,
    this.onBack,
    this.collectionName = 'families',
    this.title,
  });
  @override
  State<StudentManageScreen> createState() => _StudentManageScreenState();
}

class _StudentManageScreenState extends State<StudentManageScreen> {
  late final CollectionReference _familiesRef =
      FirebaseFirestore.instance.collection(widget.collectionName);
  final CollectionReference _classroomsRef =
      FirebaseFirestore.instance.collection('classrooms');

  // Cloud Functions（リージョン指定）
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  List<String> _classroomList = [];

  // 検索用
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 教室フィルター
  String _selectedClassroomFilter = 'すべて';

  // ExpansionTileControllerのマップ
  final Map<String, ExpansionTileController> _controllers = {};
  
  // 現在展開中のドキュメントID
  String? _currentExpandedId;

  final List<String> _allCourses = [
    'ベビーコース',
    'プレキッズコース',
    'プリスクール',
    'キッズコース（1h）',
    'キッズコース（1.5h）',
    'キッズコース（2h）',
    '小学生',
    '運動（0.6〜1.0）',
    '運動（1.0〜1.6）',
  ];

  final List<String> _genders = ['男', '女', 'その他'];

  // 初期パスワードはCloud Functions (Secret Manager) で管理

  @override
  void initState() {
    super.initState();
    _fetchClassrooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClassrooms() async {
    try {
      final snapshot = await _classroomsRef.get();
      final isPlus = widget.collectionName == 'plus_families';
      setState(() {
        _classroomList = snapshot.docs
            .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            // 通常画面ではプラス教室を除外、プラス画面では通常教室を除外
            .where((name) =>
                isPlus ? name.contains('プラス') : !name.contains('プラス'))
            .toList();
      });
    } catch (e) {
      setState(() {
        _classroomList = widget.collectionName == 'plus_families'
            ? ['ビースマイリープラス湘南藤沢']
            : [
                'ビースマイリー湘南藤沢',
                'ビースマイリー湘南台',
              ];
      });
    }
  }

  /// _getKanaRow を呼ぶ前に、漢字の場合は代表的な姓のヨミから行を推定する。
  /// 万能ではないが「他」行に大量に流れ込むのを抑える。各漢字は1行のみ割当。
  static const Map<String, String> _kanjiToRow = {
    // あ行
    '赤': 'あ', '秋': 'あ', '浅': 'あ', '荒': 'あ', '相': 'あ', '阿': 'あ',
    '青': 'あ', '東': 'あ', '安': 'あ',
    '池': 'い', '石': 'い', '伊': 'い', '岩': 'い', '市': 'い', '稲': 'い', '今': 'い',
    '上': 'う', '内': 'う', '海': 'う', '宇': 'う', '梅': 'う', '浦': 'う',
    '江': 'え', '榎': 'え',
    '大': 'お', '岡': 'お', '小': 'お', '尾': 'お', '奥': 'お', '織': 'お',
    // か行
    '加': 'か', '柿': 'か', '河': 'か', '川': 'か', '梶': 'か', '神': 'か',
    '兼': 'か', '金': 'か', '亀': 'か', '門': 'か', '勝': 'か',
    '北': 'き', '木': 'き', '岸': 'き', '吉': 'き',
    '工': 'く', '久': 'く', '熊': 'く', '楠': 'く', '黒': 'く', '栗': 'く', '國': 'く',
    '甲': 'こ', '駒': 'こ', '近': 'こ', '後': 'こ',
    // さ行
    '佐': 'さ', '酒': 'さ', '坂': 'さ', '齋': 'さ', '斎': 'さ',
    '塩': 'し', '島': 'し', '清': 'し', '柴': 'し', '渋': 'し', '澁': 'し', '篠': 'し', '下': 'し',
    '杉': 'す', '鈴': 'す', '砂': 'す',
    '関': 'せ', '瀬': 'せ', '仙': 'せ', '千': 'せ',
    '園': 'そ', '惣': 'そ', '曽': 'そ', '草': 'そ',
    // た行
    '高': 'た', '髙': 'た', '田': 'た', '武': 'た', '竹': 'た', '玉': 'た', '田中': 'た', '滝': 'た', '達': 'た',
    '中': 'な', '中丸': 'な',
    '都': 'つ', '土': 'つ', '津': 'つ',
    'ティ': 'て', '寺': 'て',
    '十': 'と',
    // な行
    '永': 'な', '長': 'な', '成': 'な', '夏': 'な', '南': 'な', '名': 'な',
    '西': 'に', '新': 'に', '二': 'に',
    '布': 'ぬ',
    '根': 'ね',
    '野': 'の', '能': 'の',
    // は行
    '橋': 'は', '林': 'は', '原': 'は', '羽': 'は', '長谷': 'は', '濱': 'は', '浜': 'は', '萩': 'は', '花': 'は', '畑': 'は', '服': 'は', '春': 'は', '半': 'は', '花島': 'は',
    '日': 'ひ', '樋': 'ひ', '平': 'ひ', '広': 'ひ', '廣': 'ひ',
    '深': 'ふ', '福': 'ふ', '藤': 'ふ', '古': 'ふ', '舩': 'ふ', '船': 'ふ',
    '本': 'ほ', '保': 'ほ', '堀': 'ほ', '細': 'ほ', '北条': 'ほ',
    // ま行
    '前': 'ま', '松': 'ま', '丸': 'ま', '増': 'ま', '町': 'ま', '間': 'ま',
    '三': 'み', '宮': 'み', '水': 'み', '溝': 'み', '道': 'み', '三浦': 'み',
    '村': 'む', '武藤': 'む', '宗': 'む',
    '目': 'め',
    '森': 'も', '元': 'も',
    // や行
    '八': 'や', '矢': 'や', '山': 'や', '柳': 'や',
    '由': 'ゆ', '湯': 'ゆ',
    '横': 'よ', '余': 'よ',
    // ら行
    '陸': 'り',
    '若': 'わ', '渡': 'わ', '和': 'わ', '脇': 'わ',
  };

  String _getKanaRowFallback(String? text) {
    if (text == null || text.isEmpty) return '他';
    // 既存のひらがな・カタカナ判定を試す
    final kanaResult = _getKanaRow(text);
    if (kanaResult != '他') return kanaResult;
    // 漢字なら最初の文字で行を推定
    final ch = text.substring(0, 1);
    return _kanjiToRow[ch] ?? '他';
  }

  // 五十音の行を判定するヘルパーメソッド
  String _getKanaRow(String? text) {
    if (text == null || text.isEmpty) return '他';
    final char = text.substring(0, 1);

    if (RegExp(r'^[あいうえおアイウエオ]').hasMatch(char)) return 'あ';
    if (RegExp(r'^[かきくけこがぎぐげごカキクケコガギグゲゴ]').hasMatch(char)) return 'か';
    if (RegExp(r'^[さしすせそざじずぜぞサシスセソザジズゼゾ]').hasMatch(char)) return 'さ';
    if (RegExp(r'^[たちつてとだぢづでどタチツテトダヂヅデド]').hasMatch(char)) return 'た';
    if (RegExp(r'^[なにぬねのナニヌネノ]').hasMatch(char)) return 'な';
    if (RegExp(r'^[はひふへほばびぶべぼぱぴぷぺぽハヒフヘホバビブベボパピプペポ]').hasMatch(char)) return 'は';
    if (RegExp(r'^[まみむめもマミムメモ]').hasMatch(char)) return 'ま';
    if (RegExp(r'^[やゆよヤユヨ]').hasMatch(char)) return 'や';
    if (RegExp(r'^[らりるれろラリルレロ]').hasMatch(char)) return 'ら';
    if (RegExp(r'^[わをんワヲン]').hasMatch(char)) return 'わ';
    
    return '他';
  }

  // セクションヘッダーウィジェット
  Widget _buildSectionHeader(String headerText) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.info,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 8),
          Text(
            '$headerText行',
            style: TextStyle(
              fontSize: AppTextSize.titleLg,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '保護者・児童管理'),
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
      backgroundColor: context.colors.scaffoldBgAlt,
      body: Column(
        children: [
          // 検索窓 + 教室フィルター
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: context.colors.cardBg,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: Icon(Icons.search, color: context.colors.iconMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: context.colors.iconMuted),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.colors.borderMedium),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.colors.borderMedium),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.info),
                      ),
                      filled: true,
                      fillColor: context.colors.tagBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.colors.borderMedium),
                    borderRadius: BorderRadius.circular(8),
                    color: context.colors.tagBg,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedClassroomFilter,
                      icon: const Icon(Icons.filter_list, size: 20),
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: 'すべて', child: Text('すべての教室')),
                        ..._classroomList.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedClassroomFilter = value ?? 'すべて';
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // リスト部分
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _familiesRef.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('エラーが発生しました'));
                }

                // 旧モバイルアプリ互換用に families に複製した plus_families コピーは除外
                final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs)
                  .where((d) {
                    final data = d.data() as Map<String, dynamic>?;
                    return data?['_compat'] != true;
                  }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text('データがありません。\n右下のマークで追加してください。', style: TextStyle(color: context.colors.textSecondary)),
                  );
                }

                // ふりがな順に並び替え（姓のふりがな、無ければ姓そのものでフォールバック）
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  String kanaA = (dataA['lastNameKana'] ?? '').toString();
                  String kanaB = (dataB['lastNameKana'] ?? '').toString();
                  if (kanaA.isEmpty) kanaA = (dataA['lastName'] ?? '').toString();
                  if (kanaB.isEmpty) kanaB = (dataB['lastName'] ?? '').toString();
                  return kanaA.compareTo(kanaB);
                });

                // 教室フィルタリング
                // families コレクションは plus_families 分離後、通常レッスン（湘南台/湘南藤沢）のみ。
                // プラス利用児は plus_families に居るため、ここではステータスフィルタ不要。
                final classroomFiltered = _selectedClassroomFilter == 'すべて'
                    ? docs
                    : docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
                        return children.any((child) =>
                          childBelongsToClassroom(child, _selectedClassroomFilter));
                      }).toList();

                // 検索フィルタリング
                final filteredDocs = _searchQuery.isEmpty
                    ? classroomFiltered
                    : classroomFiltered.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final lastName = (data['lastName'] ?? '').toString().toLowerCase();
                        final firstName = (data['firstName'] ?? '').toString().toLowerCase();
                        final lastNameKana = (data['lastNameKana'] ?? '').toString().toLowerCase();
                        final firstNameKana = (data['firstNameKana'] ?? '').toString().toLowerCase();
                        final fullName = '$lastName$firstName';
                        final fullNameKana = '$lastNameKana$firstNameKana';

                        // 児童名も検索対象
                        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
                        final childMatch = children.any((child) {
                          final childName = (child['firstName'] ?? '').toString().toLowerCase();
                          final childKana = (child['firstNameKana'] ?? '').toString().toLowerCase();
                          return childName.contains(_searchQuery) || childKana.contains(_searchQuery);
                        });

                        return fullName.contains(_searchQuery) ||
                               fullNameKana.contains(_searchQuery) ||
                               childMatch;
                      }).toList();

                // リスト表示用のウィジェットリストを作成
                List<Widget> listWidgets = [];
                String currentHeader = '';

                // 検索結果0件の場合
                if (filteredDocs.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: context.colors.iconMuted),
                        SizedBox(height: 16),
                        Text(
                          '「$_searchQuery」に一致する結果がありません',
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                for (var familyDoc in filteredDocs) {
                  final data = familyDoc.data() as Map<String, dynamic>;
                  // ふりがなが無ければ漢字の姓を試す（_getKanaRow は漢字も先頭文字で判定）
                  String headerSource = (data['lastNameKana'] ?? '').toString();
                  if (headerSource.isEmpty) {
                    headerSource = (data['lastName'] ?? '').toString();
                  }
                  final header = _getKanaRowFallback(headerSource);

                  // 行が変わったらヘッダーを挿入
                  if (header != currentHeader) {
                    currentHeader = header;
                    listWidgets.add(_buildSectionHeader(header));
                  }

                  final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
                  final parentFullName = '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}';
                  final parentKanaName = '${data['lastNameKana'] ?? ''} ${data['firstNameKana'] ?? ''}';
                  
                  String fullAddress = data['address'] ?? '';
                  if (data['postalCode'] != null && data['postalCode'].toString().isNotEmpty) {
                    fullAddress = '〒${data['postalCode']} $fullAddress';
                  }

                  final hasAccount = data['uid'] != null && data['uid'].toString().isNotEmpty;
                  final isInitialPassword = data['isInitialPassword'] == true;

                  // コントローラーを取得または作成
                  final controller = _controllers.putIfAbsent(
                    familyDoc.id, 
                    () => ExpansionTileController(),
                  );

                  listWidgets.add(
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ExpansionTile(
                        controller: controller,
                        key: PageStorageKey(familyDoc.id),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        // アコーディオンの排他制御
                        onExpansionChanged: (isOpen) {
                          if (isOpen) {
                            // 他に開いているタイルがあれば閉じる
                            if (_currentExpandedId != null && _currentExpandedId != familyDoc.id) {
                              final prevController = _controllers[_currentExpandedId];
                              if (prevController != null) {
                                try {
                                  prevController.collapse();
                                } catch (_) {}
                              }
                            }
                            _currentExpandedId = familyDoc.id;
                          } else {
                            if (_currentExpandedId == familyDoc.id) {
                              _currentExpandedId = null;
                            }
                          }
                        },
                        leading: CircleAvatar(
                          backgroundColor: AppColors.infoBg,
                          child: const Icon(Icons.family_restroom, color: AppColors.info),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                parentFullName.trim().isEmpty ? '名称未設定' : parentFullName,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (hasAccount)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isInitialPassword ? AppColors.accent.shade100 : AppColors.successBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isInitialPassword ? '初期PW' : 'アクティブ',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: isInitialPassword ? AppColors.accent.shade800 : AppColors.successDark,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.colors.borderLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '未登録',
                                  style: TextStyle(fontSize: AppTextSize.xs, color: context.colors.textSecondary),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text('ID: ${data['loginId'] ?? "未設定"}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(),
                                Text('【保護者情報】', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
                                _buildInfoRow('ふりがな', parentKanaName),
                                _buildInfoRow('続柄', data['relation'] ?? ''),
                                _buildInfoRow('電話番号', data['phone'] ?? ''),
                                _buildInfoRow('メール', data['email'] ?? ''),
                                _buildInfoRow('住所', fullAddress),
                                SizedBox(height: 8),
                                Text('【緊急連絡先】', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
                                _buildInfoRow('氏名', data['emergencyName'] ?? ''),
                                _buildInfoRow('続柄', data['emergencyRelation'] ?? ''),
                                _buildInfoRow('電話', data['emergencyPhone'] ?? ''),
                                
                                SizedBox(height: 12),
                                Text('【児童詳細】', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
                                if (children.isEmpty) Text('登録なし', style: TextStyle(color: context.colors.textSecondary)),
                                ...children.map((child) => _buildChildCard(child)),

                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (hasAccount)
                                      TextButton.icon(
                                        icon: const Icon(Icons.badge_outlined, color: AppColors.secondary),
                                        label: const Text('ID変更', style: TextStyle(color: AppColors.secondary)),
                                        onPressed: () => _changeLoginId(
                                          familyDoc.id,
                                          data['uid'],
                                          data['loginId'] ?? '',
                                          parentFullName,
                                        ),
                                      ),
                                    if (hasAccount)
                                      TextButton.icon(
                                        icon: Icon(Icons.lock_reset, color: AppColors.accent),
                                        label: Text('PW初期化', style: TextStyle(color: AppColors.accent)),
                                        onPressed: () => _resetPassword(
                                          familyDoc.id,
                                          data['uid'],
                                          parentFullName,
                                        ),
                                      ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete, color: AppColors.error),
                                      label: const Text('削除', style: TextStyle(color: AppColors.error)),
                                      onPressed: () => _deleteFamily(
                                        familyDoc.id, 
                                        data['uid'], 
                                        parentFullName,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.edit),
                                      label: const Text('編集'),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.info, foregroundColor: Colors.white),
                                      onPressed: () => _showEditDialog(familyDoc: familyDoc),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: listWidgets,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, 
        onPressed: () => _showEditDialog(),
        backgroundColor: context.colors.cardBg,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo_beesmileymark.png',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_add, color: AppColors.info),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.small))),
          Expanded(child: Text(value, style: TextStyle(fontSize: AppTextSize.body))),
        ],
      ),
    );
  }

  Widget _buildChildCard(Map<String, dynamic> child) {
    String displayName = child['firstName'] ?? '';
    if (child['firstNameKana'] != null && child['firstNameKana'].isNotEmpty) {
      displayName += ' (${child['firstNameKana']})';
    }

    String classInfo = classroomsDisplayText(child);
    if (child['course'] != null && child['course'].isNotEmpty) {
      classInfo += ' / ${child['course']}';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$displayName  ${child['gender']}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd),
          ),
          const SizedBox(height: 4),
          Text('誕生日: ${child['birthDate']}', style: TextStyle(fontSize: AppTextSize.small)),
          Text('所属: $classInfo', style: TextStyle(fontSize: AppTextSize.small)),
          if ((child['allergy'] ?? '').isNotEmpty)
            Text('特記事項: ${child['allergy']}', style: TextStyle(fontSize: AppTextSize.small, color: AppColors.error)),
          if ((child['profileUrl'] ?? '').isNotEmpty)
            Text('URL: ${child['profileUrl']}', style: TextStyle(fontSize: AppTextSize.small, color: AppColors.info)),
        ],
      ),
    );
  }

  /// Cloud Functions経由でログインIDを変更
  Future<void> _changeLoginId(String docId, String? targetUid, String currentLoginId, String name) async {
    if (targetUid == null || targetUid.isEmpty) {
      AppFeedback.error(context, 'アカウントが作成されていません');
      return;
    }

    final controller = TextEditingController(text: currentLoginId);

    final newId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ログインID変更'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name さんのログインIDを変更します。', style: const TextStyle(fontSize: AppTextSize.body)),
            const SizedBox(height: 4),
            const Text(
              '※ 変更後は新しいIDでログインしてもらってください（パスワードは変わりません）。',
              style: TextStyle(fontSize: AppTextSize.caption, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新しいログインID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
            child: const Text('変更'),
          ),
        ],
      ),
    );

    if (newId == null || newId.isEmpty) return;
    if (newId == currentLoginId) return;

    try {
      _showLoadingDialog('ログインIDを変更中...');

      final callable = _functions.httpsCallable('updateParentLoginId');
      await callable.call({
        'targetUid': targetUid,
        'familyDocId': docId,
        'newLoginId': newId,
        'collectionName': widget.collectionName,
      });

      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        AppFeedback.success(context, '$name さんのログインIDを「$newId」に変更しました');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppFeedback.error(context, 'エラー: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppFeedback.error(context, 'エラー: $e');
      }
    }
  }

  /// Cloud Functions経由でパスワードを初期化
  Future<void> _resetPassword(String docId, String? targetUid, String name) async {
    if (targetUid == null || targetUid.isEmpty) {
      AppFeedback.error(context, 'アカウントが作成されていません');
      return;
    }

    final confirmed = await AppFeedback.confirm(
      context,
      title: 'パスワード初期化',
      message: '$name さんのパスワードを初期パスワードに戻しますか？\n\n次回ログイン時にパスワード変更が求められます。',
      confirmLabel: '初期化',
    );

    if (!confirmed) return;

    try {
      _showLoadingDialog('パスワードを初期化中...');

      final callable = _functions.httpsCallable('resetParentPassword');
      await callable.call({
        'targetUid': targetUid,
        'familyDocId': docId,
        'collectionName': widget.collectionName,
      });

      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        AppFeedback.success(context, '$name さんのパスワードを初期化しました');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        AppFeedback.error(context, 'エラー: $e');
      }
    }
  }

  /// Cloud Functions経由でアカウントを削除
  Future<void> _deleteFamily(String docId, String? targetUid, String name) async {
    final confirmed = await AppFeedback.confirm(context, title: '削除確認', message: '$name さんの情報を削除しますか？\n\n※ログインアカウントも削除されます。', confirmLabel: '削除', cancelLabel: 'キャンセル', destructive: true);

    if (confirmed != true) return;

    try {
      _showLoadingDialog('削除中...');

      final callable = _functions.httpsCallable('deleteParentAccount');
      await callable.call({
        'targetUid': targetUid,
        'familyDocId': docId,
        'collectionName': widget.collectionName,
      });

      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        AppFeedback.success(context, '削除しました');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ローディングを閉じる
        AppFeedback.error(context, 'エラー: $e');
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showEditDialog({DocumentSnapshot? familyDoc}) {
    final isEditing = familyDoc != null;
    final data = isEditing ? (familyDoc.data() as Map<String, dynamic>) : <String, dynamic>{};

    final loginIdCtrl = TextEditingController(text: data['loginId'] ?? '');
    final lastNameCtrl = TextEditingController(text: data['lastName'] ?? '');
    final firstNameCtrl = TextEditingController(text: data['firstName'] ?? '');
    final lastNameKanaCtrl = TextEditingController(text: data['lastNameKana'] ?? '');
    final firstNameKanaCtrl = TextEditingController(text: data['firstNameKana'] ?? '');
    
    final relationCtrl = TextEditingController(text: data['relation'] ?? '');
    final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
    final emailCtrl = TextEditingController(text: data['email'] ?? '');
    
    final postalCodeCtrl = TextEditingController(text: data['postalCode'] ?? '');
    final addressCtrl = TextEditingController(text: data['address'] ?? '');
    // プラス（HUG連携）用に分割: 都道府県 / 市町村・番地
    final cityCtrl = TextEditingController(text: data['city'] ?? '');
    String prefecture = data['prefecture'] ?? '';

    final emNameCtrl = TextEditingController(text: data['emergencyName'] ?? '');
    final emRelCtrl = TextEditingController(text: data['emergencyRelation'] ?? '');
    final emPhoneCtrl = TextEditingController(text: data['emergencyPhone'] ?? '');

    final isPlus = widget.collectionName == 'plus_families';

    List<Map<String, dynamic>> children = [];
    if (data['children'] != null) {
      children = List<Map<String, dynamic>>.from(data['children']);
    } else {
      children.add({
        'firstName': '',
        'firstNameKana': '',
        'gender': '男',
        'birthDate': '',
        'classrooms': _classroomList.isNotEmpty ? [_classroomList[0]] : <String>[],
        'course': _allCourses[0],
        'allergy': '',
      });
    }

    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEditing ? '登録情報の編集' : '新規登録'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 新規登録時の説明
                        if (!isEditing)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: AppColors.info, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '初回ログイン時にパスワード変更が必要です。\n初期パスワードは管理者にお問い合わせください。',
                                    style: TextStyle(fontSize: AppTextSize.small, color: AppColors.info),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        _buildDialogSectionTitle('保護者情報'),
                        _buildTextField(loginIdCtrl, 'ログインID', icon: Icons.vpn_key, enabled: !isEditing),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(lastNameCtrl, '姓', icon: Icons.person)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(firstNameCtrl, '名')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(lastNameKanaCtrl, 'せい (ふりがな)')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(firstNameKanaCtrl, 'めい (ふりがな)')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(relationCtrl, '続柄 (父, 母など)'),
                        const SizedBox(height: 8),
                        _buildTextField(phoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),
                        const SizedBox(height: 8),
                        _buildTextField(emailCtrl, 'メールアドレス', icon: Icons.email, type: TextInputType.emailAddress),
                        const SizedBox(height: 8),
                        
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: _buildTextField(postalCodeCtrl, isPlus ? '郵便番号(HUG必須)' : '郵便番号', icon: Icons.markunread_mailbox, type: TextInputType.number),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTextField(addressCtrl, '住所(旧)', icon: Icons.home),
                            ),
                          ],
                        ),
                        if (isPlus) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SizedBox(
                                width: 180,
                                child: _PrefectureDropdown(
                                  value: prefecture,
                                  onChanged: (v) => setStateDialog(() => prefecture = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildTextField(cityCtrl, '市町村・番地(HUG必須)', icon: Icons.location_city),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 24),
                        
                        _buildDialogSectionTitle('緊急連絡先'),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(emNameCtrl, '氏名')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(emRelCtrl, '続柄')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(emPhoneCtrl, '電話番号', icon: Icons.phone, type: TextInputType.phone),

                        const SizedBox(height: 24),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildDialogSectionTitle('児童情報'),
                            TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('兄弟を追加'),
                              onPressed: () {
                                setStateDialog(() {
                                  children.add({
                                    'firstName': '',
                                    'firstNameKana': '',
                                    'gender': '男',
                                    'birthDate': '',
                                    'classrooms': _classroomList.isNotEmpty ? [_classroomList[0]] : <String>[],
                                    'course': _allCourses[0],
                                    'allergy': '',
                                  });
                                });
                              },
                            ),
                          ],
                        ),
                        
                        ...children.asMap().entries.map((entry) {
                          int i = entry.key;
                          Map<String, dynamic> child = entry.value;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: context.colors.borderMedium),
                              borderRadius: BorderRadius.circular(8),
                              color: context.colors.cardBg,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('児童 ${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textSecondary)),
                                    if (children.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.close, color: AppColors.error, size: 20),
                                        onPressed: () {
                                          setStateDialog(() {
                                            children.removeAt(i);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: child['firstName'],
                                        decoration: InputDecoration(labelText: '名前 (名のみ)', isDense: true, border: OutlineInputBorder()),
                                        onChanged: (val) => child['firstName'] = val,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: child['firstNameKana'],
                                        decoration: InputDecoration(labelText: 'ふりがな', isDense: true, border: OutlineInputBorder()),
                                        onChanged: (val) => child['firstNameKana'] = val,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _genders.contains(child['gender']) ? child['gender'] : _genders[0],
                                        decoration: InputDecoration(labelText: '性別', isDense: true, border: OutlineInputBorder()),
                                        items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                        onChanged: (val) => setStateDialog(() => child['gender'] = val),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          DateTime initialDate = DateTime.now();
                                          if (child['birthDate'] != null && child['birthDate'].isNotEmpty) {
                                            try {
                                              List<String> parts = child['birthDate'].split('/');
                                              if (parts.length == 3) {
                                                initialDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                                              }
                                            } catch (_) {}
                                          }

                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: initialDate,
                                            firstDate: DateTime(2010),
                                            lastDate: DateTime.now(),
                                          );
                                          if (picked != null) {
                                            setStateDialog(() {
                                              child['birthDate'] = '${picked.year}/${picked.month}/${picked.day}';
                                            });
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: InputDecoration(labelText: '生年月日', isDense: true, border: OutlineInputBorder()),
                                          child: Text(child['birthDate']?.isEmpty ?? true ? 'YYYY/MM/DD' : child['birthDate']),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // 教室（複数選択）
                                InputDecorator(
                                  decoration: InputDecoration(labelText: '教室', isDense: true, border: OutlineInputBorder()),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      ...(_classroomList).map((c) {
                                        final selected = getChildClassrooms(child).contains(c);
                                        return FilterChip(
                                          label: Text(c, style: TextStyle(fontSize: AppTextSize.caption)),
                                          selected: selected,
                                          selectedColor: AppColors.primary.withValues(alpha: 0.2),
                                          checkmarkColor: AppColors.primary,
                                          onSelected: (val) {
                                            setStateDialog(() {
                                              final current = List<String>.from(getChildClassrooms(child));
                                              if (val) {
                                                if (!current.contains(c)) current.add(c);
                                              } else {
                                                current.remove(c);
                                              }
                                              child['classrooms'] = current;
                                              child.remove('classroom'); // 旧フィールド削除
                                            });
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: _allCourses.contains(child['course']) ? child['course'] : _allCourses[0],
                                  isExpanded: true,
                                  decoration: InputDecoration(labelText: 'コース', isDense: true, border: OutlineInputBorder()),
                                  items: _allCourses.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: AppTextSize.small)))).toList(),
                                  onChanged: (val) => setStateDialog(() => child['course'] = val),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: child['allergy'],
                                  decoration: InputDecoration(labelText: 'アレルギー・特記事項', isDense: true, border: OutlineInputBorder()),
                                  onChanged: (val) => child['allergy'] = val,
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: child['profileUrl'] ?? '',
                                  decoration: InputDecoration(
                                    labelText: 'プロフィールURL',
                                    hintText: 'https://...',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) => child['profileUrl'] = val,
                                ),
                                // 受給者証情報（プラス専用、HUG連携必須）
                                if (isPlus) ...[
                                  const SizedBox(height: 16),
                                  const Text('受給者証情報（HUG必須）',
                                      style: TextStyle(fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  _RecipientCertificateEditor(
                                    child: child,
                                    onChanged: () => setStateDialog(() {}),
                                  ),
                                ],
                                // 策定会議URL（プラス湘南藤沢の生徒のみ）
                                if (getChildClassrooms(child).any((c) => c.contains('プラス'))) ...[
                                  const SizedBox(height: 16),
                                  const Text('策定会議URL', style: TextStyle(fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  ...List.generate(5, (urlIndex) {
                                    const labels = ['アセスメント', '個別支援計画書(原案)', '議事録', '個別支援計画書', 'モニタリング'];
                                    final meetingUrls = child['meetingUrls'] as List<dynamic>? ?? [];
                                    final urlData = urlIndex < meetingUrls.length
                                        ? Map<String, dynamic>.from(meetingUrls[urlIndex])
                                        : {'label': labels[urlIndex], 'url': ''};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 160,
                                            child: Text(labels[urlIndex], style: TextStyle(fontSize: AppTextSize.body)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: urlData['url'] ?? '',
                                              decoration: InputDecoration(
                                                hintText: 'https://...',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (val) {
                                                const fixedLabels = ['アセスメント', '個別支援計画書(原案)', '議事録', '個別支援計画書', 'モニタリング'];
                                                final urls = List<Map<String, dynamic>>.from(
                                                  (child['meetingUrls'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e)),
                                                );
                                                while (urls.length <= urlIndex) {
                                                  urls.add({'label': fixedLabels[urls.length], 'url': ''});
                                                }
                                                urls[urlIndex]['label'] = fixedLabels[urlIndex];
                                                urls[urlIndex]['url'] = val;
                                                child['meetingUrls'] = urls;
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context), 
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final loginId = loginIdCtrl.text.trim();
                    
                    if (loginId.isEmpty) {
                      AppFeedback.error(context, 'ログインIDを入力してください');
                      return;
                    }

                    setStateDialog(() => isLoading = true);

                    try {
                      if (isEditing) {
                        // 編集の場合はFirestoreのみ更新
                        final saveData = {
                          'lastName': lastNameCtrl.text,
                          'firstName': firstNameCtrl.text,
                          'lastNameKana': lastNameKanaCtrl.text,
                          'firstNameKana': firstNameKanaCtrl.text,
                          'relation': relationCtrl.text,
                          'phone': phoneCtrl.text,
                          'email': emailCtrl.text,
                          'postalCode': postalCodeCtrl.text,
                          'address': addressCtrl.text,
                          if (isPlus) 'prefecture': prefecture,
                          if (isPlus) 'city': cityCtrl.text,
                          'emergencyName': emNameCtrl.text,
                          'emergencyRelation': emRelCtrl.text,
                          'emergencyPhone': emPhoneCtrl.text,
                          'children': children,
                        };
                        await _familiesRef.doc(familyDoc.id).update(saveData);
                      } else {
                        // 新規作成の場合はCloud Functionsを使用
                        final familyData = {
                          'lastName': lastNameCtrl.text,
                          'firstName': firstNameCtrl.text,
                          'lastNameKana': lastNameKanaCtrl.text,
                          'firstNameKana': firstNameKanaCtrl.text,
                          'relation': relationCtrl.text,
                          'phone': phoneCtrl.text,
                          'email': emailCtrl.text,
                          'postalCode': postalCodeCtrl.text,
                          'address': addressCtrl.text,
                          if (isPlus) 'prefecture': prefecture,
                          if (isPlus) 'city': cityCtrl.text,
                          'emergencyName': emNameCtrl.text,
                          'emergencyRelation': emRelCtrl.text,
                          'emergencyPhone': emPhoneCtrl.text,
                          'children': children,
                        };

                        final callable = _functions.httpsCallable('createParentAccount');
                        await callable.call({
                          'loginId': loginId,
                          'familyData': familyData,
                          'collectionName': widget.collectionName,
                        });
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        AppFeedback.success(context, isEditing ? '更新しました' : '登録しました');
                      }
                    } on FirebaseFunctionsException catch (e) {
                      setStateDialog(() => isLoading = false);
                      if (context.mounted) {
                        AppFeedback.error(context, 'エラー: ${e.message}');
                      }
                    } catch (e) {
                      setStateDialog(() => isLoading = false);
                      if (context.mounted) {
                        AppFeedback.error(context, 'エラー: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white),
                  child: isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: AppColors.info, margin: const EdgeInsets.only(right: 8)),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, TextInputType? type, bool enabled = true}) {
    return TextField(
      controller: controller,
      keyboardType: type,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: context.colors.iconMuted, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: enabled ? context.colors.cardBg : context.colors.borderLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        isDense: true,
      ),
    );
  }
}

/// HUG連携用 都道府県セレクト。プラス保護者・児童管理画面で使用。
class _PrefectureDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _PrefectureDropdown({required this.value, required this.onChanged});

  static const List<String> _prefectures = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
    "岐阜県", "静岡県", "愛知県", "三重県",
    "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
    "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県",
    "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
  ];

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: "都道府県(HUG必須)",
        labelStyle: TextStyle(fontSize: AppTextSize.small),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: value.isEmpty ? null : value,
          hint: const Text("選択"),
          items: _prefectures
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (v) => onChanged(v ?? ""),
        ),
      ),
    );
  }
}

/// 受給者証情報の入力 widget。子要素の `recipientCertificate` (Map)を直接編集する。
/// HUG連携必須の 利用開始日 / 受給者証番号 / 利用サービス / 負担上限月額 を入力。
class _RecipientCertificateEditor extends StatelessWidget {
  final Map<String, dynamic> child;
  final VoidCallback onChanged;
  const _RecipientCertificateEditor({required this.child, required this.onChanged});

  Map<String, dynamic> get _rc {
    final v = child['recipientCertificate'];
    if (v is Map) return Map<String, dynamic>.from(v);
    final fresh = <String, dynamic>{};
    child['recipientCertificate'] = fresh;
    return fresh;
  }

  void _set(String k, dynamic v) {
    final m = _rc;
    if (v == null) {
      m.remove(k);
    } else {
      m[k] = v;
    }
    child['recipientCertificate'] = m;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rc = _rc;
    final startAt = rc['startAt'];
    DateTime? startDate;
    if (startAt is Timestamp) startDate = startAt.toDate();
    if (startAt is String && startAt.isNotEmpty) {
      try {
        final p = startAt.split('/');
        if (p.length == 3) startDate = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      } catch (_) {}
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate ?? DateTime.now(),
                    firstDate: DateTime(2010),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  );
                  if (picked != null) {
                    _set('startAt', Timestamp.fromDate(picked));
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: '利用開始日', isDense: true, border: OutlineInputBorder()),
                  child: Text(startDate == null
                      ? 'YYYY/MM/DD'
                      : '${startDate.year}/${startDate.month.toString().padLeft(2, '0')}/${startDate.day.toString().padLeft(2, '0')}'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: (rc['number'] ?? '').toString(),
                decoration: const InputDecoration(
                    labelText: '受給者証番号', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => _set('number', v.trim().isEmpty ? null : v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: (rc['service'] is String && (rc['service'] as String).isNotEmpty) ? rc['service'] as String : 'after_school',
                decoration: const InputDecoration(
                    labelText: '利用サービス', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'after_school', child: Text('放課後等デイサービス')),
                  DropdownMenuItem(value: 'child_dev', child: Text('児童発達支援')),
                ],
                onChanged: (v) => _set('service', v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: rc['monthlyLimit']?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '負担上限月額(円)',
                    hintText: '例: 4600',
                    isDense: true,
                    border: OutlineInputBorder()),
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  _set('monthlyLimit', n);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
