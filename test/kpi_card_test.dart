import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bee_smiley_admin/app_theme.dart';
import 'package:bee_smiley_admin/kpi_screen.dart';

/// KPI 週ペイン / カテゴリカードの動作検証。
/// Firebase不要（ウィジェット単体を実レンダリングして操作する）。
void main() {
  Widget wrap(Widget child, {double width = 1100}) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: <ThemeExtension<dynamic>>[AppColorScheme.light()],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
              width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  KpiWeekPane pane({
    List<Map<String, dynamic>> tasks = const [],
    num? result = 8,
    num? target = 15,
    String note = '',
    bool highlight = false,
    bool muted = false,
    bool showRetroGhost = false,
    String carryOverLabel = '',
    ValueChanged<String>? onAdd,
    ValueChanged<int>? onToggle,
    ValueChanged<int>? onEdit,
    VoidCallback? onCarry,
    VoidCallback? onEditResult,
  }) {
    return KpiWeekPane(
      highlight: highlight,
      muted: muted,
      result: result,
      target: target,
      note: note,
      tasks: tasks,
      showRetroGhost: showRetroGhost,
      carryOverLabel: carryOverLabel,
      numLabel: (n) => '$n',
      onEditResult: onEditResult ?? () {},
      onAddTaskText: onAdd ?? (_) {},
      onToggleTask: onToggle ?? (_) {},
      onEditTask: onEdit ?? (_) {},
      onCarryOver: onCarry ?? () {},
    );
  }

  KpiCategoryCard card({
    Widget? left,
    Widget? right,
    num? target = 15,
    num? latest = 8,
  }) {
    return KpiCategoryCard(
      name: 'BS湘南台',
      krContent: '生徒数を60人達成 (年間目標基準)',
      objective: '生徒数の増加と継続',
      target: target,
      latest: latest,
      numLabel: (n) => '$n',
      onEditCategory: () {},
      leftPane: left ?? pane(muted: true, showRetroGhost: true),
      rightPane: right ?? pane(highlight: true),
    );
  }

  testWidgets('ペイン基本表示: 実績・目標・メモ・タスクが出る', (tester) async {
    await tester.pumpWidget(wrap(pane(
      tasks: [
        {'title': 'チラシ配り', 'done': false},
      ],
      note: '問合せ2件。園訪問は流れた',
    )));
    expect(find.text('8'), findsOneWidget);
    expect(find.text(' / 15'), findsOneWidget);
    expect(find.text('チラシ配り'), findsOneWidget);
    expect(find.text('問合せ2件。園訪問は流れた'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('メモ導線: 前週側は「振り返りメモ」・今週側は「メモ」、タップで編集が開く',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(pane(
      note: '',
      showRetroGhost: true,
      onEditResult: () => opened = true,
    )));
    expect(find.text('振り返りメモ'), findsOneWidget);
    await tester.tap(find.text('振り返りメモ'));
    expect(opened, isTrue);

    // 今週側は「メモ」表記（行のリズムを左右で揃えるため両側に出す）
    await tester.pumpWidget(wrap(pane(note: '', showRetroGhost: false)));
    await tester.pumpAndSettle();
    expect(find.text('振り返りメモ'), findsNothing);
    expect(find.text('メモ'), findsOneWidget);
  });

  testWidgets('インライン追加: 入力してEnterで追加され、続けて入力できる',
      (tester) async {
    final added = <String>[];
    await tester.pumpWidget(wrap(pane(onAdd: added.add)));

    await tester.tap(find.text('タスクを追加'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '園訪問（洋介・藍）');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(added, ['園訪問（洋介・藍）']);
    expect(find.byType(TextField), findsOneWidget); // 連続追加

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
    await tester.pumpWidget(wrap(pane(
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
    await tester.pumpWidget(wrap(pane(
      tasks: [
        {'title': 'タスクA', 'done': false},
      ],
      onEdit: (i) => edited = i,
    )));

    Opacity opacityOf() => tester.widget<Opacity>(find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(Opacity)));

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
    await tester.pumpWidget(wrap(pane(
      tasks: const [],
      carryOverLabel: '前週の未完了を引き継ぐ（3件）',
      onCarry: () => carried = true,
    )));
    expect(find.text('前週の未完了を引き継ぐ（3件）'), findsOneWidget);
    await tester.tap(find.text('前週の未完了を引き継ぐ（3件）'));
    expect(carried, isTrue);

    await tester.pumpWidget(wrap(pane(carryOverLabel: '')));
    await tester.pumpAndSettle();
    expect(find.textContaining('引き継ぐ'), findsNothing);
  });

  testWidgets('カード2ペイン: 広幅・中幅・狭幅でレイアウト例外が出ない',
      (tester) async {
    final longTasks = [
      {
        'title': 'とても長いタスク名のテスト。折返しが必要になるほど長い文字列を入れて'
            'オーバーフローが起きないことを確認する。',
        'done': false,
      },
    ];
    for (final w in [1100.0, 700.0, 380.0]) {
      await tester.pumpWidget(wrap(
        card(
          left: pane(muted: true, tasks: longTasks, note: '長いメモのテスト。' * 5),
          right: pane(highlight: true, tasks: longTasks),
        ),
        width: w,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$w でレイアウト例外');
    }
    expect(find.text('BS湘南台'), findsOneWidget);
  });

  testWidgets('巨大な数字でもオーバーフローしない', (tester) async {
    for (final w in [1100.0, 380.0]) {
      await tester.pumpWidget(wrap(
        card(
          left: pane(result: 1250000, target: 20000000, muted: true),
          right: pane(result: 1250000, target: 20000000, highlight: true),
          target: 20000000,
          latest: 1250000,
        ),
        width: w,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$w でレイアウト例外');
    }
  });

  testWidgets('目標未設定・実績未入力・Infinityでもクラッシュしない',
      (tester) async {
    await tester.pumpWidget(wrap(card(
      left: pane(target: null, result: null, muted: true),
      right: pane(target: null, result: null),
      target: null,
      latest: null,
    )));
    expect(find.text('目標 未設定'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 進捗バーに Infinity が渡ってもクラッシュしない
    await tester.pumpWidget(wrap(card(
      target: 15,
      latest: double.infinity,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
