import 'dart:convert';

import 'package:flutter/material.dart';
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

  testWidgets(
    'collect then arrange preserves identity and cancel leaves inbox unchanged',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      addTearDown(planner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: AnimatedBuilder(
                animation: planner,
                builder: (context, _) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showTaskCreation(
                        context,
                        planner,
                        preset: DateTime.utc(2026, 10, 19, 9),
                      ),
                      child: const Text('创建'),
                    ),
                    Expanded(child: InboxView(planner: planner)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收集任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '准备入睡');
      await tester.ensureVisible(find.text('保存任务'));
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      final taskId = planner.inbox.single.id;
      expect(planner.rules, isEmpty);
      final beforeArrange = planner.exportJson();

      await tester.tap(find.byTooltip('安排时间 准备入睡'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('取消'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsNothing);
      expect(planner.exportJson(), beforeArrange);

      await tester.tap(find.byTooltip('安排时间 准备入睡'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存任务'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(planner.inbox, isEmpty);
      expect(planner.tasks.single.id, taskId);
      expect(planner.rules.single.taskId, taskId);
    },
  );

  testWidgets(
    'schedule creation preserves preset instant in the planner timezone',
    (tester) async {
      final planner = Planner.memory(timezone: 'Asia/Tokyo');
      addTearDown(planner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTaskCreation(
                  context,
                  planner,
                  preset: DateTime.utc(2026, 10, 19, 9, 30),
                ),
                child: const Text('创建'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排日程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '起床');
      await tester.scrollUntilVisible(
        find.text('保存任务'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(planner.rules.single.start, DateTime.utc(2026, 10, 19, 18, 30));
      expect(planner.rules.single.timezone, 'Asia/Tokyo');
      final occurrence = planner
          .occurrences(DateTime.utc(2026, 10, 19), DateTime.utc(2026, 10, 20))
          .single;
      expect(occurrence.start, DateTime.utc(2026, 10, 19, 9, 30));
      expect(planner.inbox, isEmpty);
    },
  );

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

  testWidgets(
    'changing sleep display preserves the visible read-only legacy archive',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      final reminders = ReminderService(planner);
      addTearDown(() {
        reminders.dispose();
        planner.dispose();
      });
      final legacy = jsonDecode(planner.exportJson()) as Map<String, dynamic>;
      legacy
        ..['schemaVersion'] = 2
        ..remove('sleepDisplayPreferences')
        ..remove('archivedRoutineRecords')
        ..['routinePreferences'] = {
          'bedtimeMinutes': 1380,
          'wakeTimeMinutes': 420,
          'foldSleep': true,
          'bedtimeCheckInEnabled': true,
          'wakeTimeCheckInEnabled': false,
        }
        ..['routineRecords'] = [
          {
            'id': 'old-bedtime',
            'type': 'bedtime',
            'targetDate': '2026-10-05T00:00:00.000Z',
            'targetMinutes': 1380,
            'timezone': 'Asia/Tokyo',
            'recordedAt': '2026-10-05T14:15:00.000Z',
          },
        ];
      await planner.restoreJson(jsonEncode(legacy));
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(planner: planner, reminders: reminders),
        ),
      );
      await tester.scrollUntilVisible(find.textContaining('原目标 23:00'), 250);
      final beforeView = planner.exportJson();
      await tester.tap(find.textContaining('原目标 23:00'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsNothing);
      expect(planner.exportJson(), beforeView);
      expect(find.textContaining('Asia/Tokyo'), findsOneWidget);
      expect(find.textContaining('2026-10-05T14:15:00.000Z'), findsOneWidget);
      await tester.scrollUntilVisible(find.byTooltip('清除睡眠折叠起始边界'), -250);
      await tester.tap(find.byTooltip('清除睡眠折叠起始边界'));
      await tester.pumpAndSettle();
      expect(planner.sleepDisplayPreferences.foldSleep, isFalse);
      final record = planner.archivedRoutineRecords.single;
      expect(record.id, 'old-bedtime');
      expect(record.targetMinutes, 1380);
      expect(record.timezone, 'Asia/Tokyo');
      expect(record.recordedAt, DateTime.utc(2026, 10, 5, 14, 15));
      expect(planner.tasks, isEmpty);
      expect(planner.summary(DateTime(2026, 10, 5)).actualCompleted, 0);
    },
  );

  testWidgets(
    'equal sleep boundaries disable folding instead of hiding the full day',
    (tester) async {
      final planner = Planner.memory(timezone: 'UTC');
      final reminders = ReminderService(planner);
      addTearDown(() {
        reminders.dispose();
        planner.dispose();
      });
      await planner.saveSleepDisplayPreferences(
        SleepDisplayPreferences(
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
      await tester.scrollUntilVisible(find.byTooltip('设置睡眠折叠起始边界'), 300);
      await tester.tap(find.byTooltip('设置睡眠折叠起始边界'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      final timeFields = find.byType(TextField);
      expect(timeFields, findsNWidgets(2));
      await tester.enterText(timeFields.at(0), '07');
      await tester.enterText(timeFields.at(1), '00');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(planner.sleepDisplayPreferences.bedtimeMinutes, 19 * 60);
      expect(planner.sleepDisplayPreferences.wakeTimeMinutes, 19 * 60);
      expect(planner.sleepDisplayPreferences.foldSleep, isFalse);
    },
  );

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
