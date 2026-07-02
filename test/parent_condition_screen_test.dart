import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:bee_smiley_admin/app_theme.dart';
import 'package:bee_smiley_admin/parent_condition_screen.dart';

/// 保護者コンディション画面の動作検証。
/// FakeFirebaseFirestore を注入して、日次きろく（キャラ・疲れ度・メモ）と
/// 月次かんたんシートの保存・復元を確認する。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  const familyUid = 'testparent001';
  const childId = '${familyUid}_はなこ';

  String todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String monthKey() => DateFormat('yyyy-MM').format(DateTime.now());

  Widget wrap(FakeFirebaseFirestore fs) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: <ThemeExtension<dynamic>>[AppColorScheme.light()],
      ),
      home: Scaffold(
        body: ParentConditionScreen(
          childId: childId,
          childName: 'はなこ',
          familyUid: familyUid,
          firestore: fs,
        ),
      ),
    );
  }

  testWidgets('初期表示: 5キャラ・疲れ度・週ストリップ・月次ボタンが出る', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    // 5キャラクター
    expect(find.text('げんきライオン'), findsOneWidget);
    expect(find.text('のんびりコアラ'), findsOneWidget);
    expect(find.text('ねむねむペンギン'), findsOneWidget);
    expect(find.text('そわそわリス'), findsOneWidget);
    expect(find.text('おやすみパンダ'), findsOneWidget);

    // 疲れ度の説明
    expect(find.textContaining('つかれ度'), findsOneWidget);

    // 月次シートボタン（未記入なので「記入」）。ListView 下部なのでスクロールして表示
    final monthLabel = DateFormat('M月', 'ja').format(DateTime.now());
    await tester.scrollUntilVisible(
        find.text('$monthLabelのシートを記入'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('$monthLabelのシートを記入'), findsOneWidget);
  });

  testWidgets('キャラをタップすると保存され、フレーズが表示される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('げんきライオン'));
    await tester.pumpAndSettle();

    // フレーズ表示 + 保存インジケータ
    expect(find.text('「げんきいっぱい！やってみたい」'), findsOneWidget);
    expect(find.text('ほぞんしました'), findsOneWidget);

    // Firestore に保存されている
    final doc = await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['character'], 'lion');
    expect(doc.data()!['familyUid'], familyUid);
    expect(doc.data()!['studentId'], childId);
  });

  testWidgets('キャラを再タップすると選択解除される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('のんびりコアラ'));
    await tester.pumpAndSettle();
    expect(find.text('「ゆっくりならできそう」'), findsOneWidget);

    await tester.tap(find.text('のんびりコアラ'));
    await tester.pumpAndSettle();
    expect(find.text('「ゆっくりならできそう」'), findsNothing);

    final doc = await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .get();
    expect(doc.data()!['character'], isNull);
  });

  testWidgets('疲れ度をタップすると保存される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    // 疲れ度 3 をタップ（丸ボタンの '3'）
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();

    final doc = await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['fatigue'], 3);
  });

  testWidgets('メモを入力してチェックで保存される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, '夕方に眠そうだった');
    await tester.tap(find.byTooltip('メモを保存'));
    await tester.pumpAndSettle();

    final doc = await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .get();
    expect(doc.data()!['note'], '夕方に眠そうだった');
  });

  testWidgets('既存の日次記録が初期表示に反映される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .set({
      'studentId': childId,
      'familyUid': familyUid,
      'dateKey': todayKey(),
      'character': 'panda',
      'fatigue': 5,
      'note': '疲れ気味',
    });

    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    expect(find.text('「つかれたよ、しっかりやすみたい」'), findsOneWidget);
    expect(find.text('疲れ気味'), findsOneWidget);
  });

  testWidgets('週ストリップで過去日を選ぶと、その日の記録として保存される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);

    // 週ストリップの昨日の日付セルをタップ（日番号のテキスト）
    await tester.tap(find.text('${yesterday.day}').first);
    await tester.pumpAndSettle();

    // カードの見出しが昨日の日付になる
    expect(
        find.textContaining(DateFormat('M月d日', 'ja').format(yesterday)),
        findsOneWidget);

    // キャラを選ぶと昨日の doc に入る
    await tester.tap(find.text('ねむねむペンギン'));
    await tester.pumpAndSettle();

    final doc = await fs
        .collection('condition_daily')
        .doc('${childId}_$yesterdayKey')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['character'], 'penguin');

    // 今日の doc は作られていない
    final todayDoc = await fs
        .collection('condition_daily')
        .doc('${childId}_${todayKey()}')
        .get();
    expect(todayDoc.exists, isFalse);
  });

  testWidgets('月次かんたんシート: 記入して保存すると condition_sheets に入る', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    final monthLabel = DateFormat('M月', 'ja').format(DateTime.now());
    await tester.scrollUntilVisible(
        find.text('$monthLabelのシートを記入'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('$monthLabelのシートを記入'));
    await tester.pumpAndSettle();

    // エディタが開いた
    expect(find.textContaining('かんたんシート'), findsWidgets);

    // 寝つき「よい」を選択（最初の「よい」チップ）
    await tester.ensureVisible(find.text('よい').first);
    await tester.tap(find.text('よい').first);
    await tester.pumpAndSettle();

    // 保存
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    final doc = await fs
        .collection('condition_sheets')
        .doc('${childId}_${monthKey()}')
        .get();
    expect(doc.exists, isTrue);
    expect((doc.data()!['sleep'] as Map)['fallAsleep'], 'よい');
    expect(doc.data()!['familyUid'], familyUid);

    // 一覧に戻り、ボタンが「編集」に変わる
    await tester.scrollUntilVisible(
        find.text('$monthLabelのシートを編集'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('$monthLabelのシートを編集'), findsOneWidget);

    // 保存成功 SnackBar のタイマーを消化してからテスト終了
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('既存の月次シートが編集時に復元される', (tester) async {
    final fs = FakeFirebaseFirestore();
    await fs
        .collection('condition_sheets')
        .doc('${childId}_${monthKey()}')
        .set({
      'studentId': childId,
      'familyUid': familyUid,
      'monthKey': monthKey(),
      'sleep': {'morningMood': '不安定'},
      'concernedBehavior': '帰宅後に泣きやすい',
    });

    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    final monthLabel = DateFormat('M月', 'ja').format(DateTime.now());
    await tester.scrollUntilVisible(
        find.text('$monthLabelのシートを編集'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('$monthLabelのシートを編集'));
    await tester.pumpAndSettle();

    // 「今月の様子」セクションはエディタ下部（遅延ビルド）なのでスクロールして表示
    await tester.scrollUntilVisible(find.text('帰宅後に泣きやすい'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('帰宅後に泣きやすい'), findsOneWidget);
  });
}
