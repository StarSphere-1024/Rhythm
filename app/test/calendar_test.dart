import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';
import 'package:rhythm/features/calendar.dart';
import 'package:rhythm/features/editor.dart';

Future<void> pumpWeek(
  WidgetTester tester,
  Planner planner, {
  DateTime? date,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WeekView(
          planner: planner,
          date: date ?? DateTime(2026, 10, 5),
          onChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> addAt(
  Planner planner,
  String title,
  int hour,
  int minute, {
  int duration = 30,
}) => planner.saveTask(
  TaskDraft(
    title: title,
    start: DateTime(2026, 10, 6, hour, minute).toUtc(),
    durationMinutes: duration,
    timezone: 'UTC',
  ),
);

void main() {
  testWidgets('week zoom offers three named seven-column levels', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);
    await pumpWeek(tester, planner);

    final overview = find.widgetWithText(ChoiceChip, '全览');
    final standard = find.widgetWithText(ChoiceChip, '标准');
    final expanded = find.widgetWithText(ChoiceChip, '放大');
    expect(overview, findsOneWidget);
    expect(standard, findsOneWidget);
    expect(expanded, findsOneWidget);
    expect(tester.widget<ChoiceChip>(overview).selected, isTrue);
    expect(
      find.byKey(const ValueKey('week-day-2026-10-05T00:00:00.000')),
      findsOneWidget,
    );

    await tester.tap(standard);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(standard).selected, isTrue);
    await tester.tap(expanded);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(expanded).selected, isTrue);
    expect(planner.tasks, isEmpty);
  });

  testWidgets(
    'fold expansion is shared and half-open summary excludes wake boundary',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      addTearDown(planner.dispose);
      await planner.saveRoutinePreferences(
        RoutinePreferences(
          bedtimeMinutes: 23 * 60,
          wakeTimeMinutes: 7 * 60,
          foldSleep: true,
        ),
      );
      await addAt(planner, '边界前安排', 6, 30);
      await addAt(planner, '起床边界安排', 7, 0);
      await pumpWeek(tester, planner);

      expect(find.text('1项'), findsOneWidget);
      await tester.tap(find.text('1项'));
      await tester.pumpAndSettle();
      expect(find.text('1项'), findsNothing);
      final grouped = find.bySemanticsLabel(RegExp('边界前安排'));
      expect(grouped, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('起床边界安排')), findsOneWidget);
      await tester.tap(grouped);
      await tester.pumpAndSettle();
      expect(find.text('边界前安排'), findsOneWidget);
      expect(find.text('起床边界安排'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('完整24小时'));
      await tester.pumpAndSettle();
      expect(planner.routinePreferences.foldSleep, isTrue);
      expect(planner.tasks, hasLength(2));
    },
  );

  testWidgets(
    'blank tap selects without creating; explicit action opens the editor',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      addTearDown(planner.dispose);
      await pumpWeek(tester, planner);

      final semantics = tester.ensureSemantics();
      try {
        final blankBand = find.bySemanticsLabel(RegExp('2026年10月7日.*空白时段'));
        expect(blankBand, findsOneWidget);
        await tester.tap(blankBand);
        await tester.pumpAndSettle();
        expect(find.text('在此新建'), findsOneWidget);
        expect(planner.tasks, isEmpty);
      } finally {
        semantics.dispose();
      }
      await tester.tap(find.text('在此新建'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(planner.tasks, isEmpty);
    },
  );

  testWidgets(
    'cross-midnight occurrence is annotated on each day as one instance',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      addTearDown(planner.dispose);
      await addAt(planner, '跨午夜安排', 23, 30, duration: 90);
      await pumpWeek(tester, planner);

      expect(
        find.bySemanticsLabel(RegExp('跨午夜安排.*延续到次日.*同一实例')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('跨午夜安排.*承接前一天.*同一实例')),
        findsOneWidget,
      );
      expect(planner.tasks, hasLength(1));
      expect(
        planner.occurrences(DateTime(2026, 10, 5), DateTime(2026, 10, 12)),
        hasLength(1),
      );
    },
  );
  testWidgets('changing weeks clears a selection from the previous week', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);
    await pumpWeek(tester, planner);
    await tester.tap(
      find.byKey(const ValueKey('week-day-2026-10-07T00:00:00.000')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('在此新建'), findsOneWidget);

    await pumpWeek(tester, planner, date: DateTime(2026, 10, 12));
    expect(find.text('在此新建'), findsNothing);
    expect(planner.tasks, isEmpty);
  });
  testWidgets('overview fits inside a compact app viewport', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('周日程')),
          body: WeekView(
            planner: planner,
            date: DateTime(2026, 10, 5),
            onChanged: (_) {},
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 1,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today), label: '今日'),
              NavigationDestination(icon: Icon(Icons.view_week), label: '周'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
  });

  testWidgets('daytime sleep remains ordered and expands in all columns', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);
    await planner.saveRoutinePreferences(
      RoutinePreferences(
        bedtimeMinutes: 2 * 60,
        wakeTimeMinutes: 10 * 60,
        foldSleep: true,
      ),
    );
    await pumpWeek(tester, planner);

    expect(find.text('02:00–10:00'), findsOneWidget);
    expect(find.text('已折叠'), findsNWidgets(7));
    await tester.tap(find.text('已折叠').first);
    await tester.pumpAndSettle();

    expect(find.text('已折叠'), findsNothing);
    expect(find.text('02:00–10:00'), findsNothing);
    expect(find.text('04:00'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(planner.routinePreferences.foldSleep, isTrue);
  });

  testWidgets('overlapping current tasks share one scroll anchor', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);
    final start = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    for (final title in ['当前重叠一', '当前重叠二']) {
      await planner.saveTask(
        TaskDraft(
          title: title,
          start: start,
          durationMinutes: 90,
          timezone: 'UTC',
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayView(
            planner: planner,
            date: DateTime.now(),
            onChanged: (_) {},
            onWeek: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前重叠一'), findsOneWidget);
    expect(find.text('当前重叠二'), findsOneWidget);
  });
}
