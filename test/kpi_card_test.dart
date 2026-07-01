import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bee_smiley_admin/app_theme.dart';
import 'package:bee_smiley_admin/kpi_screen.dart';

/// KPIカテゴリカードの動作検証。
/// Firebase不要（カード単体を実レンダリングして操作する）。
void main() {
  Widget wrap(Widget child, {double width = 1100}) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: <ThemeExtension<dynamic>>[AppColorScheme.light()],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  KpiCategoryCard card({
    List<Map<String, dynamic>> tasks = const [],
    bool isCurrentWeek = true,
    String carryOverLabel = '',
    num? result = 8,
    num? target = 15,
    num? latest,
    bool latestSameAsResult = true,
    String note = '',
    ValueChanged<String>? onAdd,
    ValueChanged<int>? onToggle,
    ValueChanged<int>? onEdit,
    VoidCallback? onCarry,
  }) {
    return KpiCategoryCard(
      name: 'BS湘南台',
      krContent: '生徒数を60人達成 (年間目標基準)',
      objective: '生徒数の増加と継続',
      target: target,
      result: result,
      note: note,
      tasks: tasks,
      latest: latestSameAsResult ? result : latest,
      isCurrentWeek: isCurrentWeek,
      carryOverLabel: carryOverLabel,
      numLabel: (n) => '$n',
      onEditCategory: () {},
      onEditResult: () {},
      onAddTaskText: onAdd ?? (_) {},
      onToggleTask: onToggle ?? (_) {},
      onEditTask: onEdit ?? (_) {},
      onCarryOver: onCarry ?? () {},
    );
  }

  testWidgets('基本表示: 名前・KR・実績・目標バーが出る', (tester) async {
    await tester.pumpWidget(wrap(card(
        tasks: [
          {'title': 'チラシ配り', 'done': false},
        ],
        note: '先生募集ヒアリング')));
    expect(find.text('BS湘南台'), findsOneWidget);
    expect(find.text('生徒数を60人達成 (年間目標基準)'), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // 実績
    expect(find.text('/ 15'), findsOneWidget); // 実績ゾーンの目標（1回だけ）
    expect(find.text('チラシ配り'), findsOneWidget);
    expect(find.text('先生募集ヒアリング'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「今週やること」は今週表示の時だけ。他の週では「やること」',
      (tester) async {
    await tester.pumpWidget(wrap(card(isCurrentWeek: true)));
    expect(find.text('今週やること'), findsOneWidget);

    await tester.pumpWidget(wrap(card(isCurrentWeek: false)));
    await tester.pumpAndSettle();
    expect(find.text('今週やること'), findsNothing);
    expect(find.text('やること'), findsOneWidget);
  });

  testWidgets('インライン追加: 入力してEnterで追加され、続けて入力できる',
      (tester) async {
    final added = <String>[];
    await tester.pumpWidget(wrap(card(onAdd: added.add)));

    await tester.tap(find.text('タスクを追加'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '園訪問（洋介・藍）');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(added, ['園訪問（洋介・藍）']);
    // フィールドは開いたまま（連続追加）
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'チラシ配布');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(added, ['園訪問（洋介・藍）', 'チラシ配布']);

    // 空でEnter → 閉じる
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('タスクのタップで完了トグルが呼ばれる', (tester) async {
    int? toggled;
    await tester.pumpWidget(wrap(card(
      tasks: [
        {'title': 'タスクA', 'done': false},
        {'title': 'タスクB', 'done': true},
      ],
      onToggle: (i) => toggled = i,
    )));
    await tester.tap(find.text('タスクB'));
    expect(toggled, 1);
  });

  testWidgets('ホバーで編集アイコンが現れ、タップで編集が呼ばれる',
      (tester) async {
    int? edited;
    await tester.pumpWidget(wrap(card(
      tasks: [
        {'title': 'タスクA', 'done': false},
      ],
      onEdit: (i) => edited = i,
    )));

    Opacity opacityOf() => tester.widget<Opacity>(find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(Opacity)));

    // ホバー前は非表示
    expect(opacityOf().opacity, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('タスクA')));
    await tester.pumpAndSettle();

    expect(opacityOf().opacity, 1);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edited, 0);
  });

  testWidgets('引き継ぎボタンはラベルがある時だけ表示・タップで発火', (tester) async {
    var carried = false;
    await tester.pumpWidget(wrap(card(
      tasks: const [],
      carryOverLabel: '前週の未完了を引き継ぐ（3件）',
      onCarry: () => carried = true,
    )));
    expect(find.text('前週の未完了を引き継ぐ（3件）'), findsOneWidget);
    await tester.tap(find.text('前週の未完了を引き継ぐ（3件）'));
    expect(carried, isTrue);

    // ラベルが空なら出ない
    await tester.pumpWidget(wrap(card(
      tasks: [
        {'title': 'x', 'done': false},
      ],
      carryOverLabel: '',
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('引き継ぐ'), findsNothing);
  });

  testWidgets('狭い幅(380px)・長文タスクでもレイアウト例外が出ない',
      (tester) async {
    await tester.pumpWidget(wrap(
      card(tasks: [
        {
          'title': 'とても長いタスク名のテスト。折返しが必要になるほど長い文字列を入れて'
              'オーバーフローが起きないことを確認する。',
          'done': false,
        },
      ]),
      width: 380,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('とても長いタスク名'), findsOneWidget);
  });

  testWidgets('目標未設定なら「目標 未設定」、実績未入力なら「—」',
      (tester) async {
    await tester.pumpWidget(wrap(card(target: null, result: null)));
    expect(find.text('目標 未設定'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('巨大な数字でもオーバーフローしない（広幅・狭幅）', (tester) async {
    for (final w in [1100.0, 380.0]) {
      await tester.pumpWidget(wrap(
        card(result: 1250000, target: 20000000, note: '大きな数のテスト'),
        width: w,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'width=$w でレイアウト例外');
    }
  });

  testWidgets('latest が Infinity でも進捗バーがクラッシュしない', (tester) async {
    await tester.pumpWidget(wrap(card(
      latestSameAsResult: false,
      latest: double.infinity,
      result: 8,
      target: 15,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 非有限値はパーセント表示しない
    expect(find.text('—%'), findsNothing);
  });
}
