import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:bee_smiley_admin/app_theme.dart';
import 'package:bee_smiley_admin/staff_condition_screen.dart';

/// 職員向けコンディション面談ビューの動作検証。
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  const familyUid = 'parent001';
  const childId = '${familyUid}_はなこ';

  String dk(int day) {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, day));
  }

  String monthKey() => DateFormat('yyyy-MM').format(DateTime.now());

  Widget wrap(FakeFirebaseFirestore fs) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: <ThemeExtension<dynamic>>[AppColorScheme.light()],
      ),
      home: StaffConditionScreen(
        studentId: childId,
        familyUid: familyUid,
        childName: '山田 はなこ',
        staffUid: 'staff001',
        firestore: fs,
      ),
    );
  }

  testWidgets('日次記録・かんたんシート要約が表示され、職員コメントを保存できる', (tester) async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('condition_daily').doc('${childId}_${dk(1)}').set({
      'studentId': childId,
      'familyUid': familyUid,
      'dateKey': dk(1),
      'character': 'lion',
      'fatigue': 2,
      'note': '公園で元気に遊んだ',
    });
    await fs.collection('condition_sheets').doc('${childId}_${monthKey()}').set({
      'studentId': childId,
      'familyUid': familyUid,
      'monthKey': monthKey(),
      'sleep': {'bedtime': '21:00', 'wakeTime': '07:00', 'fallAsleep': 'よい'},
      'media': {'youtube': '1時間'},
      'concernedBehavior': '帰宅後に泣きやすい',
    });

    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    // ヘッダー・可視化
    expect(find.text('山田 はなこのコンディション（面談用）'), findsOneWidget);
    expect(find.text('キャラクターのぶんぷ'), findsOneWidget);

    // かんたんシート要約
    await tester.scrollUntilVisible(find.text('保護者の月1かんたんシート'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('就寝 21:00 / 起床 07:00'), findsOneWidget);
    expect(find.text('YouTube: 1時間'), findsOneWidget);
    expect(find.text('帰宅後に泣きやすい'), findsOneWidget);

    // 職員コメントを入力して保存
    await tester.scrollUntilVisible(find.text('コメントを保存'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('コメントを保存'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '予定が続いた週に疲れが出やすい');
    await tester.enterText(fields.at(1), '帰宅後に10分の休憩時間を作る');
    await tester.enterText(fields.at(2), '切り替え前の声かけを継続');
    await tester.tap(find.text('コメントを保存'));
    await tester.pumpAndSettle();

    final doc = await fs
        .collection('condition_sheets')
        .doc('${childId}_${monthKey()}')
        .get();
    expect(doc.data()!['staffSummary'], '予定が続いた週に疲れが出やすい');
    expect(doc.data()!['staffHomeTip'], '帰宅後に10分の休憩時間を作る');
    expect(doc.data()!['staffClassroomSupport'], '切り替え前の声かけを継続');
    expect(doc.data()!['staffCommentUpdatedBy'], 'staff001');
    // 既存の保護者記入フィールドが消えていないこと（merge 保存）
    expect((doc.data()!['sleep'] as Map)['fallAsleep'], 'よい');

    // SnackBar タイマーを消化してから終了
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('記録がない月は空表示＋シート未記入表示になる', (tester) async {
    final fs = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    expect(find.text('この月の毎日のきろくはありません'), findsOneWidget);
    expect(find.text('この月のかんたんシートは未記入です'), findsOneWidget);
  });

  testWidgets('既存の職員コメントが表示され、月を戻すと切り替わる', (tester) async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('condition_sheets').doc('${childId}_${monthKey()}').set({
      'studentId': childId,
      'familyUid': familyUid,
      'monthKey': monthKey(),
      'staffSummary': '既存の見立てコメント',
    });

    await tester.pumpWidget(wrap(fs));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('既存の見立てコメント'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('既存の見立てコメント'), findsOneWidget);

    // 前月へ → コメント欄は空になる
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('既存の見立てコメント'), findsNothing);
  });
}
