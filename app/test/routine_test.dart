import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';

DateTime _date(int day) => DateTime.utc(2026, 10, day);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('routine preferences', () {
    test('defaults are unconfigured and independent check-ins are enabled', () {
      final preferences = RoutinePreferences();
      expect(preferences.bedtimeMinutes, isNull);
      expect(preferences.wakeTimeMinutes, isNull);
      expect(preferences.foldSleep, isFalse);
      expect(preferences.bedtimeCheckInEnabled, isTrue);
      expect(preferences.wakeTimeCheckInEnabled, isTrue);
    });

    test('rejects invalid times and impossible fold settings', () {
      expect(() => RoutinePreferences(bedtimeMinutes: -1), throwsArgumentError);
      expect(
        () => RoutinePreferences(wakeTimeMinutes: 1440),
        throwsArgumentError,
      );
      expect(
        () => RoutinePreferences(bedtimeMinutes: 1380, foldSleep: true),
        throwsArgumentError,
      );
      expect(
        () => RoutinePreferences(
          bedtimeMinutes: 600,
          wakeTimeMinutes: 600,
          foldSleep: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('routine records', () {
    late Planner planner;
    setUp(() {
      planner = Planner.memory(
        timezone: 'UTC',
        clock: () => DateTime.utc(2026, 10, 5, 12),
      );
    });
    tearDown(() => planner.dispose());

    test(
      'records target and timezone snapshots and updates one effective entry',
      () async {
        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 23 * 60, wakeTimeMinutes: 7 * 60),
        );
        final targetDate = _date(5);
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: targetDate,
          recordedAt: DateTime.utc(2026, 10, 5, 23, 15),
          timezone: 'America/Los_Angeles',
        );
        final first = planner.routineRecords.single;
        expect(first.type, RoutineType.bedtime);
        expect(first.targetDate, targetDate);
        expect(first.targetMinutes, 1380);
        expect(first.timezone, 'America/Los_Angeles');
        expect(first.recordedAt, DateTime.utc(2026, 10, 5, 23, 15));

        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 22 * 60, wakeTimeMinutes: 8 * 60),
        );
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: targetDate,
          recordedAt: DateTime.utc(2026, 10, 6, 0, 10),
          timezone: 'Asia/Tokyo',
        );
        final corrected = planner.routineRecords.single;
        expect(corrected.id, first.id);
        expect(corrected.targetMinutes, 1320);
        expect(corrected.timezone, 'Asia/Tokyo');
        expect(corrected.recordedAt, DateTime.utc(2026, 10, 6, 0, 10));

        await planner.recordRoutine(
          type: RoutineType.wakeTime,
          targetDate: targetDate,
          recordedAt: DateTime.utc(2026, 10, 5, 7),
          timezone: 'UTC',
        );
        expect(planner.routineRecords, hasLength(2));
        expect(planner.routineRecords.map((r) => r.type).toSet(), {
          RoutineType.bedtime,
          RoutineType.wakeTime,
        });
      },
    );

    test(
      'requires enabled, configured targets and a date-only UTC carrier',
      () async {
        await expectLater(
          planner.recordRoutine(
            type: RoutineType.bedtime,
            targetDate: _date(5),
            recordedAt: DateTime.utc(2026, 10, 5),
            timezone: 'UTC',
          ),
          throwsStateError,
        );
        await planner.saveRoutinePreferences(
          RoutinePreferences(
            bedtimeMinutes: 1380,
            bedtimeCheckInEnabled: false,
          ),
        );
        await expectLater(
          planner.recordRoutine(
            type: RoutineType.bedtime,
            targetDate: _date(5),
            recordedAt: DateTime.utc(2026, 10, 5),
            timezone: 'UTC',
          ),
          throwsStateError,
        );
        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 1380),
        );
        await expectLater(
          planner.recordRoutine(
            type: RoutineType.bedtime,
            targetDate: DateTime.utc(2026, 10, 5, 1),
            recordedAt: DateTime.utc(2026, 10, 5),
            timezone: 'UTC',
          ),
          throwsArgumentError,
        );
        expect(planner.routineRecords, isEmpty);
      },
    );

    test(
      'undo removes only the selected type and date, not other history',
      () async {
        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 1380, wakeTimeMinutes: 420),
        );
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: _date(5),
          recordedAt: DateTime.utc(2026, 10, 5, 23),
          timezone: 'UTC',
        );
        await planner.recordRoutine(
          type: RoutineType.wakeTime,
          targetDate: _date(5),
          recordedAt: DateTime.utc(2026, 10, 6, 7),
          timezone: 'UTC',
        );
        final bedtime = planner.routineRecords.firstWhere(
          (r) => r.type == RoutineType.bedtime,
        );
        await planner.undoRoutine(bedtime);
        expect(planner.routineRecords, hasLength(1));
        expect(planner.routineRecords.single.type, RoutineType.wakeTime);
      },
    );

    test(
      'routine state serializes as schema 2 and valid v1 restores to defaults',
      () async {
        await planner.saveTask(const TaskDraft(title: '旧任务'));
        await planner.saveRoutinePreferences(
          RoutinePreferences(
            bedtimeMinutes: 1380,
            wakeTimeMinutes: 420,
            foldSleep: true,
            wakeTimeCheckInEnabled: false,
          ),
        );
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: _date(5),
          recordedAt: DateTime.utc(2026, 10, 5, 23),
          timezone: 'UTC',
        );
        final current =
            jsonDecode(planner.exportJson()) as Map<String, dynamic>;
        expect(current['schemaVersion'], 2);
        expect(current['routinePreferences'], isA<Map<String, dynamic>>());
        expect(current['routineRecords'], hasLength(1));

        final v1 = Map<String, dynamic>.of(current)
          ..['schemaVersion'] = 1
          ..remove('routinePreferences')
          ..remove('routineRecords');
        await planner.restoreJson(jsonEncode(v1));
        expect(planner.routinePreferences.bedtimeMinutes, isNull);
        expect(planner.routinePreferences.foldSleep, isFalse);
        expect(planner.tasks.single.title, '旧任务');
        expect(jsonDecode(planner.exportJson())['schemaVersion'], 2);
      },
    );

    test(
      'rejects malformed or duplicate routine snapshots atomically',
      () async {
        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 1380),
        );
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: _date(5),
          recordedAt: DateTime.utc(2026, 10, 5, 23),
          timezone: 'UTC',
        );
        final valid = jsonDecode(planner.exportJson()) as Map<String, dynamic>;
        final original = Map<String, dynamic>.of(
          (valid['routineRecords'] as List).single as Map<String, dynamic>,
        );
        final duplicateRecord = Map<String, dynamic>.of(original)
          ..['id'] = '${original['id']}-other';
        final duplicate = Map<String, dynamic>.of(valid)
          ..['routineRecords'] = [original, duplicateRecord];
        expect(
          () => planner.restoreJson(jsonEncode(duplicate)),
          throwsFormatException,
        );
        final badPreferences = Map<String, dynamic>.of(valid)
          ..['routinePreferences'] = {
            'bedtimeMinutes': 1380,
            'wakeTimeMinutes': null,
            'foldSleep': true,
            'bedtimeCheckInEnabled': true,
            'wakeTimeCheckInEnabled': true,
          };
        expect(
          () => planner.restoreJson(jsonEncode(badPreferences)),
          throwsFormatException,
        );
        expect(planner.routineRecords.single.targetMinutes, 1380);
      },
    );

    test('failed persistence does not publish routines and later mutation succeeds', () async {
      var fail = true;
      final writes = <String>[];
      final p = Planner.memory(
        persist: (source) async {
          if (fail) throw StateError('write failed');
          writes.add(source);
        },
      );
      addTearDown(p.dispose);
      final preference = RoutinePreferences(bedtimeMinutes: 1380);
      await expectLater(p.saveRoutinePreferences(preference), throwsStateError);
      expect(p.routinePreferences.bedtimeMinutes, isNull);
      fail = false;
      await p.saveRoutinePreferences(preference);
      await p.recordRoutine(
        type: RoutineType.bedtime,
        targetDate: _date(5),
        recordedAt: DateTime.utc(2026, 10, 5, 23),
        timezone: 'UTC',
      );
      expect(p.routineRecords, hasLength(1));
      expect(writes, hasLength(2));
    });

    test(
      'routine mutations do not affect task history or week statistics',
      () async {
        await planner.saveTask(const TaskDraft(title: '普通任务'));
        await planner.completeTask(planner.inbox.single);
        await planner.saveRoutinePreferences(
          RoutinePreferences(bedtimeMinutes: 1380, wakeTimeMinutes: 420),
        );
        final before = planner.summary(_date(5));
        await planner.recordRoutine(
          type: RoutineType.bedtime,
          targetDate: _date(5),
          recordedAt: DateTime.utc(2026, 10, 5, 23),
          timezone: 'UTC',
        );
        final after = planner.summary(_date(5));
        expect(planner.tasks, hasLength(1));
        expect(planner.records, hasLength(1));
        expect(after.planned, before.planned);
        expect(after.completed, before.completed);
        expect(after.skipped, before.skipped);
        expect(after.actualCompleted, before.actualCompleted);
        expect(after.completionRate, before.completionRate);
        expect(after.categoryCounts, before.categoryCounts);
        expect(after.history, hasLength(1));
      },
    );
  });
}
