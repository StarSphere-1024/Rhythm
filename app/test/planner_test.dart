import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';
import 'package:rhythm/core/recurrence.dart';
import 'package:rhythm/core/snapshot_store.dart';

class _TestSnapshotStore implements SnapshotStore {
  String? document;
  bool fail = false;
  @override
  Future<String?> read() async => document;
  @override
  Future<void> write(String source) async {
    if (fail) throw StateError('事务提交失败');
    document = source;
  }

  @override
  Future<void> close() async {}
}

DateTime utc(int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);
TaskDraft scheduled({
  String title = '健身',
  int day = 5,
  int hour = 19,
  int duration = 60,
  Repeat repeat = Repeat.weekly,
  Set<int> weekdays = const {1, 3},
  String category = '健身',
  String timezone = 'UTC',
  int? reminder = 10,
}) => TaskDraft(
  title: title,
  category: category,
  start: utc(day, hour),
  durationMinutes: duration,
  repeat: repeat,
  weekdays: weekdays,
  timezone: timezone,
  reminderMinutes: reminder,
);
List<Occurrence> week(Planner p) => p.occurrences(utc(5), utc(12));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'title-only inbox, completion, undo and scheduling share one task identity',
    () async {
      final p = Planner.memory(clock: () => DateTime(2026, 10, 6, 10));
      await p.saveTask(const TaskDraft(title: '整理房间'));
      final task = p.inbox.single;
      expect(p.rules, isEmpty);
      await p.completeTask(task);
      await p.completeTask(task);
      expect(p.records, hasLength(1));
      expect(p.inbox, isEmpty);
      final summary = p.summary(DateTime(2026, 10, 5));
      expect(summary.planned, 0);
      expect(summary.completionRate, isNull);
      expect(summary.actualCompleted, 1);
      expect(summary.history.single.occurrenceId, isNull);
      await p.undoRecord(p.records.single);
      expect(p.inbox.single.id, task.id);
      await p.saveTask(scheduled(repeat: Repeat.none), taskId: task.id);
      expect(p.tasks, hasLength(1));
      expect(week(p).single.taskId, task.id);
      expect(p.inbox, isEmpty);
    },
  );

  test('weekly multiple weekdays and daily expansion are bounded, unique and half-open', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled());
    expect(week(p).map((o) => o.start), [utc(5, 19), utc(7, 19)]);
    expect(p.occurrences(utc(5, 19), utc(7, 19)), hasLength(1));
    await p.saveTask(scheduled(title: '每天', repeat: Repeat.daily));
    final occurrences = week(p);
    expect(occurrences, hasLength(9));
    expect(occurrences.map((o) => o.id).toSet(), hasLength(9));
    final backup = jsonDecode(p.exportJson()) as Map<String, dynamic>;
    expect(backup['rules'], hasLength(2));
    expect(backup['overrides'], isEmpty);
    // Even a query decades away does not materialize stored occurrence rows.
    final future = p.occurrences(
      DateTime.utc(2050, 1, 3),
      DateTime.utc(2050, 1, 10),
    );
    expect(future, hasLength(9));
    expect(p.rules, hasLength(2));
    expect(p.exportJson(), isNot(contains('2050')));
  });

  test('overdue remains pending, skip has no roll-forward and undo fixes denominator statistics', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 10, 23));
    await p.saveTask(scheduled());
    final original = week(p);
    expect(original.every((o) => o.status == null), isTrue);
    await p.skip(original.last);
    var s = p.summary(DateTime(2026, 10, 5));
    expect(s.planned, 2);
    expect(s.skipped, 1);
    expect(s.completed, 0);
    expect(s.completionRate, 0);
    expect(s.actualCompleted, 0);
    expect(s.history.single.status, ExecutionStatus.skipped);
    expect(week(p).map((o) => o.start), original.map((o) => o.start));
    await p.complete(original.first);
    await p.complete(original.first);
    s = p.summary(DateTime(2026, 10, 5));
    expect(s.completed, 1);
    expect(s.completionRate, .5);
    expect(s.actualCompleted, 1);
    expect(p.records, hasLength(2));
    await p.undo(original.first);
    expect(p.summary(DateTime(2026, 10, 5)).completed, 0);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 0);
    expect(week(p).first.status, isNull);
  });

  test('postpone retains identity, moves into remote windows and retains original plan week', () async {
    var now = DateTime(2026, 10, 5, 20);
    final p = Planner.memory(clock: () => now);
    await p.saveTask(scheduled());
    final monday = week(p).first;
    await p.postpone(monday, utc(19, 20));
    final remote = p
        .occurrences(utc(19), utc(20))
        .firstWhere((o) => o.id == monday.id);
    expect(remote.id, monday.id);
    expect(remote.originalStart, monday.originalStart);
    expect(remote.postponed, isTrue);
    expect(week(p), hasLength(1));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    now = DateTime(2026, 10, 19, 21);
    await p.complete(remote);
    expect(p.summary(DateTime(2026, 10, 5)).completed, 1);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 0);
    final actualWeek = p.summary(DateTime(2026, 10, 19));
    expect(actualWeek.completed, 0);
    expect(actualWeek.actualCompleted, 1);
    expect(actualWeek.categoryCounts, {'健身': 1});
    expect(p.records, hasLength(1));
    final occurrences = p.occurrences(utc(19), utc(26));
    expect(occurrences.where((o) => o.id == monday.id), hasLength(1));
  });

  test('cross-midnight overlap is visible in two days with one identity and one record', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 6, 1));
    await p.saveTask(scheduled(hour: 23, duration: 120, repeat: Repeat.none));
    final a = p.occurrences(utc(5), utc(6)).single;
    final b = p.occurrences(utc(6), utc(7)).single;
    expect(a.id, b.id);
    expect(a.end, utc(6, 1));
    expect(p.occurrences(utc(6, 1), utc(7)), isEmpty);
    await p.complete(a);
    await p.complete(b);
    expect(p.records, hasLength(1));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 1);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 1);
  });

  test('single occurrence metadata, reminder and duration never mutate series defaults', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled());
    final task = p.tasks.single;
    final first = week(p).first;
    await p.saveTask(
      TaskDraft(
        title: '仅本次改名',
        category: '学习',
        notes: '局部备注',
        color: 0xff112233,
        durationMinutes: 90,
        start: utc(5, 20),
        repeat: Repeat.daily,
        timezone: 'UTC',
      ),
      taskId: task.id,
      occurrence: first,
      scope: EditScope.thisOccurrence,
    );
    final current = week(p);
    expect(current.first.id, first.id);
    expect(current.first.task.title, '仅本次改名');
    expect(current.first.task.category, '学习');
    expect(current.first.end, utc(5, 21, 30));
    expect(current.first.reminderMinutes, isNull);
    expect(current.first.postponed, isTrue);
    expect(current.last.task.title, '健身');
    expect(current.last.start, utc(7, 19));
    expect(current.last.reminderMinutes, 10);
    expect(p.tasks.single.title, '健身');
    expect(p.rules.single.repeat, Repeat.weekly);
    await p.complete(current.first);
    final snapshot = p.records.single.task;
    await p.saveTask(scheduled(title: '新系列'), taskId: task.id);
    expect(p.records.single.task.title, snapshot.title);
    expect(p.records.single.task.notes, '局部备注');
    expect(
      week(p).where((o) => o.originalStart == first.originalStart),
      hasLength(1),
    );
  });

  test('future rule versions preserve earlier metadata and immutable execution snapshots', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 5, 21));
    await p.saveTask(scheduled());
    final task = p.tasks.single;
    final first = week(p).first;
    final wednesday = week(p).last;
    await p.complete(first);
    final recordJson = jsonEncode(p.records.single.toJson());
    await p.saveTask(
      scheduled(title: '未来改名', day: 7, hour: 20, duration: 90),
      taskId: task.id,
      occurrence: wednesday,
      scope: EditScope.thisAndFuture,
    );
    final occurrences = week(p);
    expect(occurrences, hasLength(2));
    expect(occurrences.first.id, first.id);
    expect(occurrences.first.task.title, '健身');
    expect(occurrences.last.start, utc(7, 20));
    expect(occurrences.last.task.title, '未来改名');
    expect(p.rules, hasLength(2));
    expect(p.rules.first.until, wednesday.originalStart);
    expect(jsonEncode(p.records.single.toJson()), recordJson);
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    final nextWeek = p.occurrences(utc(12), utc(19));
    expect(nextWeek.map((o) => o.start.hour), everyElement(20));
    final restored = Planner.memory();
    await restored.restoreJson(p.exportJson());
    expect(restored.exportJson(), p.exportJson());
  });

  test('future time edits may move earlier within selected day without overlapping versions', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled());
    final task = p.tasks.single;
    final selected = week(p).last;
    await p.saveTask(
      scheduled(day: 7, hour: 17),
      taskId: task.id,
      occurrence: selected,
      scope: EditScope.thisAndFuture,
    );
    expect(week(p).map((o) => o.start), [utc(5, 19), utc(7, 17)]);
    final restored = Planner.memory();
    await restored.restoreJson(p.exportJson());
    expect(week(restored).map((o) => o.start), [utc(5, 19), utc(7, 17)]);
    final before = p.exportJson();
    await expectLater(
      p.saveTask(
        scheduled(day: 4),
        taskId: task.id,
        occurrence: week(p).last,
        scope: EditScope.thisAndFuture,
      ),
      throwsArgumentError,
    );
    expect(p.exportJson(), before);
  });

  test('scope-aware editor drafts preserve series root anchor and exclude single overrides', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled(repeat: Repeat.daily));
    final task = p.tasks.single;
    final selected = week(p)[2];
    await p.saveTask(
      TaskDraft(title: '仅本次', durationMinutes: 90, start: utc(7, 22)),
      taskId: task.id,
      occurrence: selected,
      scope: EditScope.thisOccurrence,
    );
    final changed = week(p)[2];
    final single = p.draftFor(task, occurrence: changed);
    expect(single.title, '仅本次');
    expect(single.start!.hour, 22);
    expect(single.reminderMinutes, isNull);
    final future = p.draftFor(
      task,
      occurrence: changed,
      scope: EditScope.thisAndFuture,
    );
    expect(future.title, '健身');
    expect(future.start!.day, 7);
    expect(future.start!.hour, 19);
    expect(future.reminderMinutes, 10);
    final entire = p.draftFor(
      task,
      occurrence: changed,
      scope: EditScope.entireSeries,
    );
    expect(entire.start!.day, 5);
    expect(entire.start!.hour, 19);
    expect(entire.title, '健身');
    expect(entire.durationMinutes, 60);
    await p.saveTask(
      scheduled(title: '未来默认', day: 7, hour: 20, repeat: Repeat.daily),
      taskId: task.id,
      occurrence: changed,
      scope: EditScope.thisAndFuture,
    );
    final afterSplit = week(p)[2];
    final entireAfterSplit = p.draftFor(
      p.tasks.single,
      occurrence: afterSplit,
      scope: EditScope.entireSeries,
    );
    expect(
      entireAfterSplit.start!.day,
      5,
    ); // NOT the clicked instance/version's day.
    expect(entireAfterSplit.start!.hour, 20);
    expect(entireAfterSplit.title, '未来默认');
    final countBefore = p.summary(DateTime(2026, 10, 5)).planned;
    await p.saveTask(
      entireAfterSplit,
      taskId: task.id,
      occurrence: afterSplit,
      scope: EditScope.entireSeries,
    );
    expect(p.summary(DateTime(2026, 10, 5)).planned, countBefore);
    expect(week(p).first.start.day, 5);
  });

  test('entire-series edits retain executed originals without double planning their days', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 5, 21));
    await p.saveTask(scheduled());
    final task = p.tasks.single;
    final first = week(p).first;
    await p.complete(first);
    final execution = jsonEncode(p.records.single.toJson());
    await p.saveTask(
      scheduled(title: '整个系列新名', hour: 20),
      taskId: task.id,
      occurrence: week(p).last,
      scope: EditScope.entireSeries,
    );
    expect(week(p), hasLength(2));
    expect(week(p).first.id, first.id);
    expect(week(p).first.start, utc(5, 19));
    expect(week(p).first.task.title, '健身');
    expect(week(p).last.start, utc(7, 20));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    expect(p.summary(DateTime(2026, 10, 5)).completed, 1);
    expect(jsonEncode(p.records.single.toJson()), execution);
  });

  test('all delete scopes cancel only unexecuted plans and retain completed/skipped history', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 7, 21));
    await p.saveTask(scheduled(repeat: Repeat.daily));
    final task = p.tasks.single;
    final items = week(p);
    await p.complete(items[0]);
    await p.skip(items[1]);
    await p.deleteTask(
      task,
      occurrence: items[2],
      scope: EditScope.thisOccurrence,
    );
    expect(week(p), hasLength(6));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 6);
    await p.deleteTask(
      task,
      occurrence: items[4],
      scope: EditScope.thisAndFuture,
    );
    expect(week(p), hasLength(3));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 3);
    await p.deleteTask(task);
    expect(p.tasks.single.archivedAt, isNotNull);
    expect(p.inbox, isEmpty);
    expect(week(p), hasLength(2));
    final summary = p.summary(DateTime(2026, 10, 5));
    expect(summary.planned, 2);
    expect(summary.completed, 1);
    expect(summary.skipped, 1);
    expect(summary.completionRate, .5);
    expect(p.records, hasLength(2));
    final restored = Planner.memory();
    await restored.restoreJson(p.exportJson());
    expect(restored.records, hasLength(2));
    expect(restored.summary(DateTime(2026, 10, 5)).planned, 2);
    await restored.undoRecord(restored.records.first);
    expect(restored.records, hasLength(1));
    expect(
      week(restored),
      hasLength(1),
    ); // Undo does not resurrect deleted definitions.
  });

  test('pending earlier occurrences retain their version snapshot after future metadata edit', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled(repeat: Repeat.daily));
    final task = p.tasks.single;
    final boundary = week(p)[2];
    await p.saveTask(
      scheduled(title: '未来', day: 7, repeat: Repeat.daily, category: '学习'),
      taskId: task.id,
      occurrence: boundary,
      scope: EditScope.thisAndFuture,
    );
    expect(week(p).take(2).map((o) => o.task.title), everyElement('健身'));
    expect(week(p).skip(2).map((o) => o.task.title), everyElement('未来'));
    await p.complete(week(p).first);
    expect(p.records.single.task.category, '健身');
  });

  test('DST gap advances to first valid wall time and fold chooses first occurrence', () async {
    expect(
      Recurrence.resolve(DateTime.utc(2026, 3, 8, 2, 30), 'America/New_York'),
      DateTime.utc(2026, 3, 8, 7),
    );
    expect(
      Recurrence.resolve(DateTime.utc(2026, 11, 1, 1, 30), 'America/New_York'),
      DateTime.utc(2026, 11, 1, 5, 30),
    );
    final p = Planner.memory(timezone: 'America/New_York');
    await p.saveTask(
      TaskDraft(
        title: '墙钟',
        start: DateTime.utc(2026, 3, 7, 2, 30),
        repeat: Repeat.daily,
        timezone: 'America/New_York',
      ),
    );
    final items = p.occurrences(
      DateTime.utc(2026, 3, 7),
      DateTime.utc(2026, 3, 10),
    );
    expect(items.map((o) => o.start), [
      DateTime.utc(2026, 3, 7, 7, 30),
      DateTime.utc(2026, 3, 8, 7),
      DateTime.utc(2026, 3, 9, 6, 30),
    ]);
    await p.setTimezone('Asia/Shanghai');
    expect(p.rules.single.timezone, 'America/New_York');
    expect(
      p
          .occurrences(DateTime.utc(2026, 3, 7), DateTime.utc(2026, 3, 10))
          .map((o) => o.start),
      items.map((o) => o.start),
    );
  });

  test('DST fold daily expansion has one stable instance and actual duration is elapsed time', () async {
    final p = Planner.memory(timezone: 'America/New_York');
    await p.saveTask(
      TaskDraft(
        title: '重复钟点',
        start: DateTime.utc(2026, 11, 1, 1, 30),
        durationMinutes: 120,
        repeat: Repeat.daily,
        timezone: 'America/New_York',
      ),
    );
    final items = p.occurrences(
      DateTime.utc(2026, 11, 1),
      DateTime.utc(2026, 11, 2),
    );
    expect(items, hasLength(1));
    expect(items.single.start, DateTime.utc(2026, 11, 1, 5, 30));
    expect(items.single.end, DateTime.utc(2026, 11, 1, 7, 30));
  });

  test('planned-week boundary is original rule-zone Monday, not UTC or postponed week', () async {
    final p = Planner.memory(timezone: 'Asia/Tokyo');
    await p.saveTask(
      TaskDraft(
        title: '日本周一零点',
        start: utc(5),
        timezone: 'Asia/Tokyo',
        repeat: Repeat.none,
      ),
    );
    final occurrence = p.occurrences(utc(4), utc(6)).single;
    expect(occurrence.originalStart, utc(4, 15));
    expect(p.summary(DateTime(2026, 9, 28)).planned, 0);
    expect(p.summary(DateTime(2026, 10, 5)).planned, 1);
    await p.postpone(occurrence, utc(12, 15));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 1);
    expect(p.summary(DateTime(2026, 10, 12)).planned, 0);
  });

  test('actual execution uses a half-open local calendar week and snapshot categories', () async {
    var now = DateTime(2026, 10, 5);
    final p = Planner.memory(clock: () => now);
    await p.saveTask(const TaskDraft(title: '周界', category: '学习'));
    await p.completeTask(p.tasks.single);
    expect(p.summary(DateTime(2026, 9, 28)).actualCompleted, 0);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 1);
    await p.saveTask(const TaskDraft(title: '末秒', category: '健身'));
    now = DateTime(2026, 10, 12).subtract(const Duration(microseconds: 1));
    await p.completeTask(p.inbox.single);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 2);
    await p.saveTask(const TaskDraft(title: '下周', category: '社交'));
    now = DateTime(2026, 10, 12);
    await p.completeTask(p.inbox.single);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 2);
    expect(p.summary(DateTime(2026, 10, 12)).actualCompleted, 1);
    expect(p.summary(DateTime(2026, 10, 5)).categoryCounts, {'学习': 1, '健身': 1});
  });

  test('backup round-trip includes overrides, versions, inbox history, settings and archived history', () async {
    final p = Planner.memory(clock: () => DateTime(2026, 10, 7, 22));
    await p.saveTask(scheduled(repeat: Repeat.daily));
    final task = p.tasks.single;
    await p.postpone(week(p).first, utc(12, 20));
    await p.skip(week(p)[1]);
    await p.saveTask(
      scheduled(title: '单次', day: 7, hour: 21),
      taskId: task.id,
      occurrence: week(p)[1],
      scope: EditScope.thisOccurrence,
    );
    await p.saveTask(const TaskDraft(title: '未排期历史', category: '其他'));
    await p.completeTask(p.inbox.single);
    await p.setTimezone('Asia/Shanghai');
    final source = p.exportJson();
    final restored = Planner.memory();
    await restored.saveTask(const TaskDraft(title: '必须被完整替换'));
    await restored.restoreJson(source);
    expect(restored.exportJson(), source);
    expect(restored.timezone, 'Asia/Shanghai');
    expect(restored.tasks.any((t) => t.title == '必须被完整替换'), isFalse);
    expect(week(restored).map((o) => o.id), week(p).map((o) => o.id));
    expect(
      restored.summary(DateTime(2026, 10, 5)).planned,
      p.summary(DateTime(2026, 10, 5)).planned,
    );
    expect(
      restored.summary(DateTime(2026, 10, 5)).actualCompleted,
      p.summary(DateTime(2026, 10, 5)).actualCompleted,
    );
  });

  test('invalid backup types, identities, relations and duplicate executions never replace old state', () async {
    final p = Planner.memory();
    await p.saveTask(scheduled());
    await p.complete(week(p).first);
    await p.postpone(week(p).last, utc(7, 20));
    final original = p.exportJson();
    final mutations = <void Function(Map<String, dynamic>)>[
      (m) => m['schemaVersion'] = 99,
      (m) => (m['settings'] as Map)['timezone'] = 'No/SuchZone',
      (m) => (m['tasks'] as List).first['durationMinutes'] = '60',
      (m) => (m['tasks'] as List).first.remove('archivedAt'),
      (m) => (m['tasks'] as List).add((m['tasks'] as List).first),
      (m) => (m['rules'] as List).first['taskId'] = 'missing',
      (m) => (m['rules'] as List).first['seriesId'] = 'missing',
      (m) => (m['rules'] as List).first['weekdays'] = [1, 1],
      (m) => (m['overrides'] as List).first['id'] = 'wrong-override',
      (m) => (m['overrides'] as List).first['ruleId'] = 'missing',
      (m) => (m['overrides'] as List).first['cancelled'] = 'false',
      (m) => (m['records'] as List).first['occurrenceId'] = 'wrong',
      (m) => (m['records'] as List).first['originalStart'] = utc(
        6,
        19,
      ).toIso8601String(),
      (m) => (m['records'] as List).first['plannedEnd'] = utc(
        5,
        18,
      ).toIso8601String(),
      (m) => (m['records'] as List).first['timezone'] = 'Asia/Tokyo',
      (m) {
        final duplicate = Map<String, dynamic>.from(
          (m['records'] as List).first as Map,
        );
        duplicate['id'] = 'another-record';
        (m['records'] as List).add(duplicate);
      },
      (m) =>
          (m['records'] as List).first['task']['category'] = 'missing-category',
    ];
    for (final mutate in mutations) {
      final candidate = jsonDecode(original) as Map<String, dynamic>;
      mutate(candidate);
      expect(() => p.restoreJson(jsonEncode(candidate)), throwsFormatException);
      expect(p.exportJson(), original);
    }
    expect(() => p.restoreJson('{invalid'), throwsFormatException);
    expect(p.exportJson(), original);
  });

  test('mutations serialize persistence and publish only successfully committed snapshots', () async {
    final firstWrite = Completer<void>();
    var calls = 0;
    final writes = <String>[];
    final p = Planner.memory(
      persist: (source) async {
        calls++;
        if (calls == 1) await firstWrite.future;
        writes.add(source);
      },
    );
    var notifications = 0;
    p.addListener(() => notifications++);
    final a = p.saveTask(const TaskDraft(title: '先'));
    final b = p.saveTask(const TaskDraft(title: '后'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(p.tasks, isEmpty);
    expect(notifications, 0);
    firstWrite.complete();
    await Future.wait([a, b]);
    expect(calls, 2);
    expect(p.tasks.map((t) => t.title), ['先', '后']);
    expect((jsonDecode(writes[0]) as Map)['tasks'], hasLength(1));
    expect((jsonDecode(writes[1]) as Map)['tasks'], hasLength(2));
    expect(notifications, 2);
  });

  test('failed writes and failed restore are atomic, surfaced, and do not poison the queue', () async {
    var fail = false;
    final p = Planner.memory(
      persist: (_) async {
        if (fail) throw StateError('磁盘写入失败');
      },
    );
    await p.saveTask(const TaskDraft(title: '原数据'));
    final original = p.exportJson();
    var notifications = 0;
    p.addListener(() => notifications++);
    fail = true;
    await expectLater(
      p.saveTask(const TaskDraft(title: '不能假称保存')),
      throwsStateError,
    );
    expect(p.exportJson(), original);
    expect(notifications, 0);
    final another = Planner.memory();
    await another.saveTask(const TaskDraft(title: '替换内容'));
    await expectLater(p.restoreJson(another.exportJson()), throwsStateError);
    expect(p.exportJson(), original);
    fail = false;
    await p.saveTask(const TaskDraft(title: '恢复写入'));
    expect(p.tasks, hasLength(2));
    expect(notifications, 1);
  });

  group('load/reload through the transactional document-store boundary', () {
    late _TestSnapshotStore store;
    const channel = MethodChannel('flutter_timezone');
    setUp(() {
      store = _TestSnapshotStore();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'Asia/Shanghai');
    });
    tearDown(() {
      // No platform database or emulator is needed for these domain tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test('detects timezone once and restart retains executions, moved identity and settings', () async {
      final p = await Planner.load(store: store);
      expect(p.timezone, 'Asia/Shanghai');
      expect(p.timezoneDetectionFallback, isFalse);
      await p.saveTask(scheduled());
      final occurrence = week(p).first;
      await p.postpone(occurrence, utc(7, 20));
      await p.complete(p.occurrences(utc(7, 20), utc(7, 21)).first);
      await p.setTimezone('America/New_York');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'Asia/Tokyo');
      final reloaded = await Planner.load(store: store);
      expect(reloaded.exportJson(), p.exportJson());
      expect(reloaded.timezone, 'America/New_York');
      expect(reloaded.records.single.occurrenceId, occurrence.id);
      expect(await Planner.readStoredJson(store: store), isNotNull);
    });
    test(
      'platform unavailability is explicit UTC and not rediscovered later',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => throw MissingPluginException(),
            );
        final p = await Planner.load(store: store);
        expect(p.timezone, 'UTC');
        expect(p.timezoneDetectionFallback, isTrue);
        final restored = Planner.memory();
        await restored.restoreJson(p.exportJson());
        expect(restored.timezoneDetectionFallback, isTrue);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => 'Asia/Tokyo');
        expect((await Planner.load(store: store)).timezone, 'UTC');
      },
    );
    test('corrupt startup throws without erasing the original recoverable snapshot', () async {
      const source = '{broken-original';
      store.document = source;
      await expectLater(Planner.load(store: store), throwsFormatException);
      expect(await Planner.readStoredJson(store: store), source);
    });
    test('failed initial transaction and later mutation never publish or erase state', () async {
      store.fail = true;
      await expectLater(Planner.load(store: store), throwsStateError);
      expect(store.document, isNull);
      store.fail = false;
      final p = await Planner.load(store: store);
      await p.saveTask(const TaskDraft(title: '已提交'));
      final original = store.document;
      store.fail = true;
      await expectLater(
        p.saveTask(const TaskDraft(title: '失败事务')),
        throwsStateError,
      );
      expect(store.document, original);
      expect(p.tasks.single.title, '已提交');
      store.fail = false;
      final reloaded = await Planner.load(store: store);
      expect(reloaded.tasks.single.title, '已提交');
    });
  });
}
