import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';

DateTime _date(int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

const _legacyV2 = '''
{
  "schemaVersion": 2,
  "settings": {"timezone": "Asia/Shanghai", "timezoneDetectionFallback": false},
  "categories": ["生活"],
  "tasks": [{
    "id": "reading-task", "title": "晚间阅读", "category": "生活",
    "notes": "保留任务", "color": 4284383604, "durationMinutes": 30,
    "archivedAt": null
  }],
  "rules": [{
    "id": "reading-rule", "taskId": "reading-task", "timezone": "UTC",
    "start": "2026-10-05T20:00:00.000Z", "until": null,
    "durationMinutes": 30, "repeat": "daily", "weekdays": [],
    "reminderMinutes": 10, "seriesId": "reading-rule", "version": 1,
    "active": true,
    "task": {
      "id": "reading-task", "title": "原始阅读", "category": "生活",
      "notes": "规则快照", "color": 4284383604, "durationMinutes": 30,
      "archivedAt": null
    }
  }],
  "overrides": [{
    "id": "reading-rule@1791316800000000", "ruleId": "reading-rule",
    "taskId": "reading-task", "originalStart": "2026-10-06T20:00:00.000Z",
    "newStart": "2026-10-06T21:00:00.000Z", "cancelled": false,
    "task": {
      "id": "reading-task", "title": "延后阅读", "category": "生活",
      "notes": "单次快照", "color": 4284383604, "durationMinutes": 45,
      "archivedAt": null
    },
    "durationMinutes": 45, "reminderMinutes": 5, "replacesReminder": true
  }],
  "records": [{
    "id": "reading-completed", "taskId": "reading-task",
    "occurrenceId": "reading-rule@1791230400000000", "ruleId": "reading-rule",
    "originalStart": "2026-10-05T20:00:00.000Z",
    "executedAt": "2026-10-05T20:35:00.000Z", "status": "completed",
    "task": {
      "id": "reading-task", "title": "原始阅读", "category": "生活",
      "notes": "执行快照", "color": 4284383604, "durationMinutes": 30,
      "archivedAt": null
    },
    "plannedStart": "2026-10-05T20:00:00.000Z",
    "plannedEnd": "2026-10-05T20:30:00.000Z", "timezone": "UTC",
    "reminderMinutes": 10, "postponed": false
  }],
  "routinePreferences": {
    "bedtimeMinutes": 1380, "wakeTimeMinutes": 420, "foldSleep": true,
    "bedtimeCheckInEnabled": true, "wakeTimeCheckInEnabled": false
  },
  "routineRecords": [{
    "id": "legacy-bedtime", "type": "bedtime",
    "targetDate": "2026-10-05T00:00:00.000Z", "targetMinutes": 1320,
    "timezone": "America/Los_Angeles", "recordedAt": "2026-10-06T05:15:00.000Z"
  }, {
    "id": "legacy-wake", "type": "wakeTime",
    "targetDate": "2026-10-05T00:00:00.000Z", "targetMinutes": 450,
    "timezone": "Asia/Tokyo", "recordedAt": "2026-10-05T22:35:00.000Z"
  }]
}
''';

const _legacyV1 = '''
{
  "schemaVersion": 1,
  "settings": {"timezone": "UTC", "timezoneDetectionFallback": true},
  "categories": ["学习"],
  "tasks": [{
    "id": "old-task", "title": "旧版笔记", "category": "学习",
    "notes": "旧版内容", "color": 4284383604, "durationMinutes": 25,
    "archivedAt": null
  }],
  "rules": [], "overrides": [],
  "records": [{
    "id": "old-completion", "taskId": "old-task", "occurrenceId": null,
    "ruleId": null, "originalStart": null,
    "executedAt": "2026-10-05T12:00:00.000Z", "status": "completed",
    "task": {
      "id": "old-task", "title": "旧版笔记", "category": "学习",
      "notes": "旧版执行内容", "color": 4284383604, "durationMinutes": 25,
      "archivedAt": null
    },
    "plannedStart": null, "plannedEnd": null, "timezone": null,
    "reminderMinutes": null, "postponed": false
  }]
}
''';

void _expectArchive(Planner planner) {
  final records = planner.archivedRoutineRecords;
  expect(records, hasLength(2));
  final bedtime = records.firstWhere((r) => r.id == 'legacy-bedtime');
  expect(bedtime.type, RoutineType.bedtime);
  expect(bedtime.targetDate, _date(5));
  expect(bedtime.targetMinutes, 1320);
  expect(bedtime.timezone, 'America/Los_Angeles');
  expect(bedtime.recordedAt, _date(6, 5, 15));
  final wake = records.firstWhere((r) => r.id == 'legacy-wake');
  expect(wake.type, RoutineType.wakeTime);
  expect(wake.targetDate, _date(5));
  expect(wake.targetMinutes, 450);
  expect(wake.timezone, 'Asia/Tokyo');
  expect(wake.recordedAt, _date(5, 22, 35));
}

void _expectTaskHistory(Planner planner) {
  expect(planner.tasks.single.id, 'reading-task');
  expect(planner.tasks.single.title, '晚间阅读');
  expect(planner.tasks.single.notes, '保留任务');
  expect(planner.rules.single.id, 'reading-rule');
  expect(planner.rules.single.task.title, '原始阅读');
  expect(planner.rules.single.timezone, 'UTC');
  final history = planner.records.single;
  expect(history.id, 'reading-completed');
  expect(history.task.notes, '执行快照');
  expect(history.plannedStart, _date(5, 20));
  expect(history.plannedEnd, _date(5, 20, 30));
  expect(history.executedAt, _date(5, 20, 35));
  expect(history.reminderMinutes, 10);
  final moved = planner.occurrences(_date(6), _date(7)).single;
  expect(moved.id, 'reading-rule@1791316800000000');
  expect(moved.originalStart, _date(6, 20));
  expect(moved.start, _date(6, 21));
  expect(moved.task.title, '延后阅读');
  expect(moved.task.durationMinutes, 45);
  expect(moved.reminderMinutes, 5);
  expect(moved.postponed, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('legacy routine archive', () {
    late Planner planner;
    setUp(() {
      planner = Planner.memory(clock: () => _date(5, 12));
    });
    tearDown(() => planner.dispose());

    test(
      'schema 2 retains folding, history and archived target snapshots',
      () async {
        await planner.restoreJson(_legacyV2);
        expect(planner.timezone, 'Asia/Shanghai');
        expect(planner.sleepDisplayPreferences.bedtimeMinutes, 1380);
        expect(planner.sleepDisplayPreferences.wakeTimeMinutes, 420);
        expect(planner.sleepDisplayPreferences.foldSleep, isTrue);
        _expectArchive(planner);
        _expectTaskHistory(planner);
        expect(
          () => planner.archivedRoutineRecords.clear(),
          throwsUnsupportedError,
        );

        final summary = planner.summary(_date(5));
        expect(summary.planned, 7);
        expect(summary.completed, 1);
        expect(summary.skipped, 0);
        expect(summary.actualCompleted, 1);
        expect(summary.completionRate, 1 / 7);
        expect(summary.categoryCounts, {'生活': 1});
        expect(summary.history.single.id, 'reading-completed');

        final exported =
            jsonDecode(planner.exportJson()) as Map<String, dynamic>;
        expect(exported['schemaVersion'], 3);
        expect(exported.containsKey('routinePreferences'), isFalse);
        expect(exported.containsKey('routineRecords'), isFalse);
        expect(exported['sleepDisplayPreferences'], {
          'bedtimeMinutes': 1380,
          'wakeTimeMinutes': 420,
          'foldSleep': true,
        });
        expect(exported['archivedRoutineRecords'], hasLength(2));
      },
    );

    test('repeated schema 3 restore and export retain stable identities and snapshots', () async {
      await planner.restoreJson(_legacyV2);
      await planner.saveSleepDisplayPreferences(
        SleepDisplayPreferences(
          bedtimeMinutes: 1410,
          wakeTimeMinutes: 390,
          foldSleep: false,
        ),
      );
      await planner.setTimezone('Europe/London');
      final backup = planner.exportJson();
      for (var round = 0; round < 3; round++) {
        final restored = Planner.memory();
        try {
          await restored.restoreJson(backup);
          expect(restored.exportJson(), backup);
          expect(restored.timezone, 'Europe/London');
          expect(restored.sleepDisplayPreferences.bedtimeMinutes, 1410);
          expect(restored.sleepDisplayPreferences.wakeTimeMinutes, 390);
          expect(restored.sleepDisplayPreferences.foldSleep, isFalse);
          _expectArchive(restored);
          _expectTaskHistory(restored);
          await planner.restoreJson(restored.exportJson());
          expect(planner.exportJson(), backup);
        } finally {
          restored.dispose();
        }
      }
    });

    test(
      'authentic schema 1 task history still restores and exports as schema 3',
      () async {
        await planner.restoreJson(_legacyV2);
        await planner.restoreJson(_legacyV1);
        expect(planner.timezone, 'UTC');
        expect(planner.timezoneDetectionFallback, isTrue);
        expect(planner.tasks.single.id, 'old-task');
        expect(planner.tasks.single.notes, '旧版内容');
        expect(planner.rules, isEmpty);
        expect(planner.archivedRoutineRecords, isEmpty);
        expect(planner.records.single.id, 'old-completion');
        expect(planner.records.single.task.notes, '旧版执行内容');
        expect(planner.inbox, isEmpty);
        final summary = planner.summary(_date(5));
        expect(summary.planned, 0);
        expect(summary.actualCompleted, 1);
        expect(summary.categoryCounts, {'学习': 1});
        expect(summary.history.single.id, 'old-completion');
        expect(jsonDecode(planner.exportJson())['schemaVersion'], 3);
      },
    );

    test(
      'retired schema 2 enable flags remain strictly validated and atomic',
      () async {
        await planner.restoreJson(_legacyV2);
        final before = planner.exportJson();
        var notified = 0;
        planner.addListener(() => notified++);
        for (final field in [
          'bedtimeCheckInEnabled',
          'wakeTimeCheckInEnabled',
        ]) {
          for (final invalid in [null, 0, 'false', <Object?>[]]) {
            final document = jsonDecode(_legacyV2) as Map<String, dynamic>;
            (document['routinePreferences'] as Map<String, dynamic>)[field] =
                invalid;
            expect(
              () => planner.restoreJson(jsonEncode(document)),
              throwsFormatException,
              reason: '$field must reject $invalid',
            );
          }
          final document = jsonDecode(_legacyV2) as Map<String, dynamic>;
          (document['routinePreferences'] as Map<String, dynamic>).remove(
            field,
          );
          expect(
            () => planner.restoreJson(jsonEncode(document)),
            throwsFormatException,
            reason: '$field remains required in schema 2',
          );
        }
        expect(planner.exportJson(), before);
        expect(notified, 0);
        _expectArchive(planner);
      },
    );

    test('schema 2 and 3 reject duplicate and invalid archives without publication', () async {
      await planner.restoreJson(_legacyV2);
      final before = planner.exportJson();
      var notified = 0;
      planner.addListener(() => notified++);
      final invalidFields = <String, List<Object?>>{
        'id': ['', null],
        'type': ['sleep', null],
        'targetDate': [
          '2026-10-05T01:00:00.000Z',
          '2026-10-05T00:00:00.000',
          '2026-02-30T00:00:00.000Z',
        ],
        'targetMinutes': [-1, 1440, 1320.5, null],
        'timezone': ['', 'Not/A_Timezone', null],
        'recordedAt': ['2026-10-06T05:15:00.000', 'not-a-date', null],
      };
      for (final source in [_legacyV2, before]) {
        final archiveKey = source == _legacyV2
            ? 'routineRecords'
            : 'archivedRoutineRecords';
        Map<String, dynamic> document() =>
            jsonDecode(source) as Map<String, dynamic>;
        for (final entry in invalidFields.entries) {
          for (final invalid in entry.value) {
            final bad = document();
            final archive = bad[archiveKey] as List;
            (archive.first as Map<String, dynamic>)[entry.key] = invalid;
            expect(
              () => planner.restoreJson(jsonEncode(bad)),
              throwsFormatException,
              reason: '${entry.key} must reject $invalid',
            );
          }
          final bad = document();
          ((bad[archiveKey] as List).first as Map<String, dynamic>).remove(
            entry.key,
          );
          expect(
            () => planner.restoreJson(jsonEncode(bad)),
            throwsFormatException,
          );
        }
        for (final duplicateId in [true, false]) {
          final bad = document();
          final archive = bad[archiveKey] as List;
          final duplicate = Map<String, dynamic>.of(
            archive.first as Map<String, dynamic>,
          );
          if (duplicateId) {
            duplicate['targetDate'] = '2026-10-06T00:00:00.000Z';
          } else {
            duplicate['id'] = 'different-id-same-target';
          }
          archive.add(duplicate);
          expect(
            () => planner.restoreJson(jsonEncode(bad)),
            throwsFormatException,
          );
        }
        final missing = document()..remove(archiveKey);
        expect(
          () => planner.restoreJson(jsonEncode(missing)),
          throwsFormatException,
        );
        final notAList = document()..[archiveKey] = {};
        expect(
          () => planner.restoreJson(jsonEncode(notAList)),
          throwsFormatException,
        );
      }
      expect(planner.exportJson(), before);
      expect(notified, 0);
      _expectTaskHistory(planner);
      _expectArchive(planner);
    });

    test('both versions strictly reject invalid folding boundaries', () async {
      await planner.restoreJson(_legacyV2);
      final before = planner.exportJson();
      for (final source in [_legacyV2, before]) {
        final preferenceKey = source == _legacyV2
            ? 'routinePreferences'
            : 'sleepDisplayPreferences';
        final mutations = <void Function(Map<String, dynamic>)>[
          (p) => p['bedtimeMinutes'] = -1,
          (p) => p['wakeTimeMinutes'] = 1440,
          (p) => p['wakeTimeMinutes'] = '420',
          (p) => p['foldSleep'] = 1,
          (p) => p['bedtimeMinutes'] = null,
          (p) => p['wakeTimeMinutes'] = p['bedtimeMinutes'],
          (p) => p.remove('foldSleep'),
        ];
        for (final mutate in mutations) {
          final bad = jsonDecode(source) as Map<String, dynamic>;
          mutate(bad[preferenceKey] as Map<String, dynamic>);
          expect(
            () => planner.restoreJson(jsonEncode(bad)),
            throwsFormatException,
          );
        }
      }
      expect(planner.exportJson(), before);
    });

    test('sleep and wake daily tasks use ordinary execution, reminders, summary and undo', () async {
      await planner.restoreJson(_legacyV2);
      final archived = planner.archivedRoutineRecords;
      void expectUnchangedArchive() {
        _expectArchive(planner);
        expect(planner.archivedRoutineRecords.first, same(archived.first));
        expect(planner.archivedRoutineRecords.last, same(archived.last));
      }

      await planner.saveSleepDisplayPreferences(
        SleepDisplayPreferences(
          bedtimeMinutes: 1410,
          wakeTimeMinutes: 390,
          foldSleep: true,
        ),
      );
      expect(planner.tasks, hasLength(1));
      expect(planner.records, hasLength(1));
      expectUnchangedArchive();
      await planner.setTimezone('Asia/Tokyo');
      expectUnchangedArchive();
      for (final entry in [('睡觉', 23, 10), ('起床', 7, 0)]) {
        await planner.saveTask(
          TaskDraft(
            title: entry.$1,
            start: _date(5, entry.$2),
            repeat: Repeat.daily,
            durationMinutes: 15,
            reminderMinutes: entry.$3,
            timezone: 'UTC',
          ),
        );
        expectUnchangedArchive();
      }
      final today = planner.occurrences(_date(5), _date(6));
      final sleep = today.firstWhere((o) => o.task.title == '睡觉');
      final wake = today.firstWhere((o) => o.task.title == '起床');
      expect(sleep.reminderMinutes, 10);
      expect(wake.reminderMinutes, 0);
      expect(planner.summary(_date(5)).planned, 21);
      await planner.complete(sleep);
      expectUnchangedArchive();
      await planner.skip(wake);
      expectUnchangedArchive();
      final wakeRecord = planner.records.firstWhere(
        (r) => r.occurrenceId == wake.id,
      );
      var summary = planner.summary(_date(5));
      expect(summary.completed, 2);
      expect(summary.skipped, 1);
      expect(summary.actualCompleted, 2);
      expect(summary.categoryCounts, {'生活': 2});
      expect(summary.history, hasLength(3));
      expect(summary.completionRate, 2 / 21);

      await planner.undo(sleep);
      expectUnchangedArchive();
      summary = planner.summary(_date(5));
      expect(summary.completed, 1);
      expect(summary.skipped, 1);
      expect(summary.actualCompleted, 1);
      await planner.complete(wake);
      expectUnchangedArchive();
      expect(
        planner.records.firstWhere((r) => r.occurrenceId == wake.id).id,
        wakeRecord.id,
      );
      expect(planner.summary(_date(5)).skipped, 0);
      expect(planner.summary(_date(5)).actualCompleted, 2);
      await planner.undoRecord(wakeRecord);
      expectUnchangedArchive();
      expect(planner.records.single.id, 'reading-completed');
      expect(planner.summary(_date(5)).completed, 1);

      await planner.postpone(sleep, _date(6, 0, 30));
      expectUnchangedArchive();
      final movedSleep = planner
          .occurrences(_date(6), _date(7))
          .firstWhere((o) => o.id == sleep.id);
      expect(movedSleep.originalStart, _date(5, 23));
      expect(movedSleep.start, _date(6, 0, 30));
      expect(movedSleep.reminderMinutes, 10);
      await planner.saveTask(
        TaskDraft(
          title: '早点睡觉',
          start: _date(5, 22),
          repeat: Repeat.daily,
          durationMinutes: 15,
          reminderMinutes: 5,
          timezone: 'UTC',
        ),
        taskId: sleep.taskId,
      );
      expectUnchangedArchive();
      await planner.deleteTask(
        planner.tasks.firstWhere((t) => t.id == wake.taskId),
      );
      expectUnchangedArchive();
      await planner.saveTask(const TaskDraft(title: '整理卧室'));
      expectUnchangedArchive();
      await planner.completeTask(planner.inbox.single);
      expectUnchangedArchive();
      await planner.undoRecord(
        planner.records.firstWhere((r) => r.occurrenceId == null),
      );
      expectUnchangedArchive();
      final backup = planner.exportJson();
      await planner.restoreJson(backup);
      _expectArchive(planner);
      expect(planner.exportJson(), backup);
    });
  });
}
