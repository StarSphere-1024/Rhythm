import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';
import 'package:rhythm/core/reminders.dart';
import 'package:rhythm/features/editor.dart';
import 'package:rhythm/features/lists.dart';
import 'package:rhythm/features/settings.dart';
import 'package:rhythm/features/shell.dart';

void main() {
  testWidgets('navigation preserves inbox input between primary pages', (
    tester,
  ) async {
    final planner = Planner.memory();
    final reminders = ReminderService(planner);
    addTearDown(() {
      reminders.dispose();
      planner.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RhythmShell(planner: planner, reminders: reminders),
      ),
    );
    await tester.tap(find.text('收集箱').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留这条输入');
    await tester.tap(find.text('周日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收集箱').last);
    await tester.pumpAndSettle();

    expect(find.text('保留这条输入'), findsOneWidget);
  });

  testWidgets('inbox create failure retains input and retry creates once', (
    tester,
  ) async {
    var failWrites = true;
    final planner = Planner.memory(
      persist: (_) async {
        if (failWrites) throw StateError('write failed');
      },
    );
    addTearDown(planner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InboxView(planner: planner)),
      ),
    );
    await tester.enterText(find.byType(TextField), '写入失败后保留');
    await tester.tap(find.byTooltip('保存到收集箱'));
    await tester.pumpAndSettle();

    expect(planner.inbox, isEmpty);
    expect(find.text('写入失败后保留'), findsOneWidget);

    failWrites = false;
    await tester.tap(find.byTooltip('保存到收集箱'));
    await tester.pumpAndSettle();
    expect(planner.inbox.map((task) => task.title), ['写入失败后保留']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('editor progressively hides and restores schedule values', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskEditor(planner: planner, scope: EditScope.entireSeries),
        ),
      ),
    );

    expect(find.text('时长（分钟）'), findsNothing);
    expect(find.text('重复'), findsNothing);
    await tester.tap(find.text('安排时间'));
    await tester.pumpAndSettle();
    expect(find.text('时长（分钟）'), findsOneWidget);
    expect(find.text('重复'), findsOneWidget);

    final durationField = find.byType(TextFormField).last;
    await tester.enterText(durationField, '75');
    await tester.tap(find.text('安排时间'));
    await tester.pumpAndSettle();
    expect(find.text('时长（分钟）'), findsNothing);

    await tester.tap(find.text('安排时间'));
    await tester.pumpAndSettle();
    expect(find.text('时长（分钟）'), findsOneWidget);
    expect(tester.widget<TextFormField>(durationField).controller!.text, '75');
  });
  testWidgets('review keeps routine records separate and can revoke one', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);
    await planner.saveRoutinePreferences(
      RoutinePreferences(bedtimeMinutes: 22 * 60),
    );
    await planner.recordRoutine(
      type: RoutineType.bedtime,
      targetDate: DateTime.utc(2026, 10, 5),
      recordedAt: DateTime.utc(2026, 10, 5, 22, 5),
      timezone: 'UTC',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: planner,
            builder: (context, _) => ReviewView(
              planner: planner,
              date: DateTime(2026, 10, 5),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final routineHeading = find.text('作息记录 · 1 条');
    await tester.scrollUntilVisible(find.text('无计划'), 300);
    expect(find.text('计划次数'), findsOneWidget);
    expect(find.text('无计划'), findsOneWidget);
    await tester.scrollUntilVisible(routineHeading, 400);
    expect(find.text('入睡打卡'), findsOneWidget);
    expect(find.textContaining('晚于目标 5 分钟'), findsOneWidget);
    final undoButton = find.byTooltip('撤销这次作息记录');
    await tester.ensureVisible(undoButton);
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(planner.routineRecords, isEmpty);
    final emptyHeading = find.text('作息记录 · 0 条');
    await tester.ensureVisible(emptyHeading);
    expect(emptyHeading, findsOneWidget);
  });

  testWidgets('settings can disable one routine entry independently', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    final reminders = ReminderService(planner);
    addTearDown(() {
      reminders.dispose();
      planner.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(planner: planner, reminders: reminders),
      ),
    );
    final bedtimeEntry = find.text('启用入睡打卡');
    await tester.scrollUntilVisible(bedtimeEntry, 300);
    await tester.tap(bedtimeEntry);
    await tester.pumpAndSettle();

    expect(planner.routinePreferences.bedtimeCheckInEnabled, isFalse);
    expect(planner.routinePreferences.wakeTimeCheckInEnabled, isTrue);
  });
  testWidgets('routine check-in records the device timezone', (tester) async {
    const timezoneChannel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (_) async => 'Asia/Tokyo');
    final planner = Planner.memory(timezone: 'UTC');
    final reminders = ReminderService(planner);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezoneChannel, null);
      reminders.dispose();
      planner.dispose();
    });
    await planner.saveRoutinePreferences(
      RoutinePreferences(bedtimeMinutes: 22 * 60),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        home: SettingsPage(planner: planner, reminders: reminders),
      ),
    );
    await tester.scrollUntilVisible(find.text('入睡打卡'), 300);
    await tester.tap(find.text('入睡打卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(planner.routineRecords, hasLength(1));
    expect(planner.routineRecords.single.timezone, 'Asia/Tokyo');
    expect(planner.timezone, 'UTC');
  });

  testWidgets('equal routine targets warn instead of folding the full day', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    final reminders = ReminderService(planner);
    addTearDown(() {
      reminders.dispose();
      planner.dispose();
    });
    await planner.saveRoutinePreferences(
      RoutinePreferences(
        bedtimeMinutes: 22 * 60,
        wakeTimeMinutes: 19 * 60,
        foldSleep: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        home: SettingsPage(planner: planner, reminders: reminders),
      ),
    );
    await tester.scrollUntilVisible(find.byTooltip('设置入睡目标'), 300);
    await tester.tap(find.byTooltip('设置入睡目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();

    final timeFields = find.byType(TextField);
    expect(timeFields, findsNWidgets(2));
    await tester.enterText(timeFields.at(0), '07');
    await tester.enterText(timeFields.at(1), '00');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(planner.routinePreferences.bedtimeMinutes, 19 * 60);
    expect(planner.routinePreferences.wakeTimeMinutes, 19 * 60);
    expect(planner.routinePreferences.foldSleep, isFalse);
    expect(find.text('入睡与起床目标相同，请更正；不会按全天睡眠处理。'), findsOneWidget);
  });

  testWidgets(
    'dirty editor dismissal confirms and preserves the form on cancel',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(planner.dispose);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTaskEditor(context, planner),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑器'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '待保留的名称');
      await tester.pumpAndSettle();

      await navigatorKey.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '待保留的名称',
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('取消'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '待保留的名称',
      );
      expect(planner.tasks, isEmpty);
    },
  );

  testWidgets('unchanged or reverted editor closes without a warning', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    addTearDown(planner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTaskEditor(context, planner),
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    final title = find.byType(TextFormField).first;
    await tester.enterText(title, '临时名称');
    await tester.enterText(title, '');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(planner.tasks, isEmpty);
  });

  testWidgets('saved more settings start collapsed with values summarized', (
    tester,
  ) async {
    final planner = Planner.memory(timezone: 'UTC');
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(planner.dispose);
    await planner.saveTask(
      const TaskDraft(
        title: '原任务',
        category: '学习',
        notes: '保留备注',
        color: 0xff6585a8,
      ),
    );
    final task = planner.tasks.single;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTaskEditor(context, planner, task: task),
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    expect(find.text('更多设置'), findsOneWidget);
    expect(find.text('学习 · 自选颜色 · 含备注'), findsOneWidget);
    expect(find.text('备注（可选）'), findsNothing);

    await tester.tap(find.text('更多设置'));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.elementAt(1).controller!.text, '学习');
    expect(fields.elementAt(2).controller!.text, '保留备注');
    await navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(planner.tasks.single.notes, '保留备注');
  });
  testWidgets('double-size text keeps week controls reachable at 360 dp', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final planner = Planner.memory(timezone: 'UTC');
    final reminders = ReminderService(planner);
    addTearDown(() {
      reminders.dispose();
      planner.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: RhythmShell(planner: planner, reminders: reminders),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('七日日程视图'));
    await tester.pumpAndSettle();

    expect(find.text('全览'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('放大'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
