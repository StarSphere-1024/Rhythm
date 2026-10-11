import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';
import 'package:rhythm/core/snapshot_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime _day(int day, [int hour = 0]) => DateTime.utc(2026, 10, day, hour);
TaskDraft _weekly({String title = '健身', int day = 5, int hour = 19}) =>
    TaskDraft(
      title: title,
      category: '健身',
      start: _day(day, hour),
      repeat: Repeat.weekly,
      weekdays: const {1, 3},
      reminderMinutes: 10,
      timezone: 'UTC',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  SnapshotStore? storage;
  var now = DateTime(2026, 10, 5, 21);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rhythm-sqlite-');
    path = '${directory.path}/rhythm.db';
    now = DateTime(2026, 10, 5, 21);
  });
  tearDown(() async {
    await storage?.close();
    storage = null;
    await directory.delete(recursive: true);
  });
  Future<Planner> reopen() async {
    await storage?.close();
    storage = await SnapshotStore.open(factory: databaseFactoryFfi, path: path);
    return Planner.load(store: storage, clock: () => now);
  }

  test('real SQLite close/reopen preserves identity, rule versions, overrides, histories and backup', () async {
    var p = await reopen();
    await p.saveTask(_weekly());
    final task = p.tasks.single;
    final initial = p.occurrences(_day(5), _day(12));
    final monday = initial.first;
    final wednesday = initial.last;
    await p.complete(monday);
    await p.postpone(wednesday, _day(12, 20));
    await p.saveTask(const TaskDraft(title: '整理房间', category: '生活'));
    await p.completeTask(p.inbox.single);
    final future = p.occurrences(_day(14), _day(15)).single;
    await p.saveTask(
      _weekly(title: '未来健身', day: 14, hour: 20),
      taskId: task.id,
      occurrence: future,
      scope: EditScope.thisAndFuture,
    );
    await p.setTimezone('Asia/Shanghai');
    final backup = p.exportJson();
    final originalRecord = jsonEncode(p.records.first.toJson());
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 2);
    p.dispose();
    p = await reopen(); // Closes the real connection and reads a new SQLite connection.
    expect(p.exportJson(), backup);
    expect(jsonEncode(p.records.first.toJson()), originalRecord);
    final moved = p
        .occurrences(_day(12), _day(13))
        .firstWhere((o) => o.id == wednesday.id);
    expect(moved.start, _day(12, 20));
    expect(moved.originalStart, _day(7, 19));
    expect(moved.postponed, isTrue);
    expect(p.rules, hasLength(2));
    expect(p.timezone, 'Asia/Shanghai');
    now = DateTime(2026, 10, 12, 21);
    await p.complete(moved);
    expect(p.summary(DateTime(2026, 10, 5)).completed, 2);
    expect(p.summary(DateTime(2026, 10, 12)).actualCompleted, 1);
    await p.deleteTask(p.tasks.firstWhere((t) => t.id == task.id));
    expect(p.records.where((r) => r.taskId == task.id), hasLength(2));
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    p.dispose();
    p = await reopen();
    expect(p.records.where((r) => r.taskId == task.id), hasLength(2));
    expect(p.tasks.firstWhere((t) => t.id == task.id).archivedAt, isNotNull);
    await p.restoreJson(backup); // Actual SQLite transaction: full replacement.
    expect(p.exportJson(), backup);
    p.dispose();
    p = await reopen();
    expect(p.exportJson(), backup);
    expect(p.summary(DateTime(2026, 10, 5)).planned, 2);
    expect(p.summary(DateTime(2026, 10, 5)).actualCompleted, 2);
    expect(
      p
          .occurrences(_day(12), _day(13))
          .firstWhere((o) => o.id == wednesday.id)
          .status,
      isNull,
    );
    p.dispose();
  });

  test('real SQLite aborted transaction retains prior document and planner can recover', () async {
    final p = await reopen();
    await p.saveTask(const TaskDraft(title: '已提交历史'));
    await p.completeTask(p.inbox.single);
    final before = p.exportJson();
    final rawBefore = await storage!.read();
    final database = await databaseFactoryFfi.openDatabase(path);
    await database.execute(
      'CREATE TRIGGER reject_snapshot BEFORE INSERT ON snapshot '
      "BEGIN SELECT RAISE(ABORT, 'simulated SQLite transaction failure'); END",
    );
    var notified = 0;
    p.addListener(() => notified++);
    await expectLater(
      p.saveTask(const TaskDraft(title: '不可发布')),
      throwsA(isA<DatabaseException>()),
    );
    expect(p.exportJson(), before);
    expect(await storage!.read(), rawBefore);
    expect(notified, 0);
    final replacement = Planner.memory();
    await replacement.saveTask(const TaskDraft(title: '恢复不能假成功'));
    await expectLater(
      p.restoreJson(replacement.exportJson()),
      throwsA(isA<DatabaseException>()),
    );
    expect(p.exportJson(), before);
    expect(await storage!.read(), rawBefore);
    await database.execute('DROP TRIGGER reject_snapshot');
    await p.saveTask(const TaskDraft(title: '失败后仍可提交'));
    expect(notified, 1);
    p.dispose();
    final reloaded = await reopen();
    expect(reloaded.tasks, hasLength(2));
    expect(reloaded.records.single.task.title, '已提交历史');
    replacement.dispose();
    reloaded.dispose();
  });

  test(
    'corrupt real SQLite document is recoverable without startup erasure',
    () async {
      storage = await SnapshotStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      const corrupt = '{original-corrupt-document';
      await storage!.write(corrupt);
      await expectLater(Planner.load(store: storage), throwsFormatException);
      expect(await Planner.readStoredJson(store: storage), corrupt);
      await storage!.close();
      storage = await SnapshotStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await storage!.read(), corrupt);
      final valid = Planner.memory();
      await valid.saveTask(const TaskDraft(title: '用户确认的完整恢复'));
      await storage!.write(valid.exportJson());
      final recovered = await Planner.load(store: storage);
      expect(recovered.tasks.single.title, '用户确认的完整恢复');
      valid.dispose();
      recovered.dispose();
    },
  );
}
