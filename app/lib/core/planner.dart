import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'recurrence.dart';
import 'snapshot_store.dart';

class _Snapshot {
  String timezone;
  bool timezoneDetectionFallback;
  final List<String> categories;
  final Map<String, Task> tasks;
  final Map<String, ScheduleRule> rules;
  final Map<String, OccurrenceOverride> overrides;
  final Map<String, ExecutionRecord> records;
  _Snapshot({
    required this.timezone,
    this.timezoneDetectionFallback = false,
    List<String>? categories,
    Map<String, Task>? tasks,
    Map<String, ScheduleRule>? rules,
    Map<String, OccurrenceOverride>? overrides,
    Map<String, ExecutionRecord>? records,
  }) : categories = categories ?? ['健身', '学习', '社交', '生活', '其他'],
       tasks = tasks ?? {},
       rules = rules ?? {},
       overrides = overrides ?? {},
       records = records ?? {};
  _Snapshot copy() => _Snapshot(
    timezone: timezone,
    timezoneDetectionFallback: timezoneDetectionFallback,
    categories: List.of(categories),
    tasks: Map.of(tasks),
    rules: Map.of(rules),
    overrides: Map.of(overrides),
    records: Map.of(records),
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'settings': {
      'timezone': timezone,
      'timezoneDetectionFallback': timezoneDetectionFallback,
    },
    'categories': categories,
    'tasks': tasks.values.map((t) => t.toJson()).toList(),
    'rules': rules.values.map((r) => r.toJson()).toList(),
    'overrides': overrides.values.map((o) => o.toJson()).toList(),
    'records': records.values.map((r) => r.toJson()).toList(),
  };
  factory _Snapshot.decode(String source) {
    final root = jsonObject(jsonDecode(source));
    if (jsonInt(root, 'schemaVersion') != 1) {
      throw const FormatException('不支持的备份版本');
    }
    final settings = jsonObject(root['settings']);
    final zone = jsonString(settings, 'timezone');
    _validZone(zone);
    final categories = root['categories'];
    if (categories is! List ||
        categories.isEmpty ||
        categories.any((c) => c is! String || c.isEmpty) ||
        categories.toSet().length != categories.length) {
      throw const FormatException('无效分类');
    }
    Map<String, T> decodeList<T>(
      String key,
      T Function(Object?) decode,
      String Function(T) id,
    ) {
      final values = root[key];
      if (values is! List) throw FormatException('缺少列表 $key');
      final result = <String, T>{};
      for (final value in values) {
        final item = decode(value);
        if (result.containsKey(id(item))) throw FormatException('重复标识 $key');
        result[id(item)] = item;
      }
      return result;
    }

    final result = _Snapshot(
      timezone: zone,
      timezoneDetectionFallback: jsonBool(
        settings,
        'timezoneDetectionFallback',
      ),
      categories: categories.cast<String>().toList(),
      tasks: decodeList('tasks', Task.fromJson, (t) => t.id),
      rules: decodeList('rules', ScheduleRule.fromJson, (r) => r.id),
      overrides: decodeList(
        'overrides',
        OccurrenceOverride.fromJson,
        (o) => o.id,
      ),
      records: decodeList('records', ExecutionRecord.fromJson, (r) => r.id),
    );
    void validateTask(Task task, String expectedId) {
      if (task.id != expectedId ||
          !result.tasks.containsKey(expectedId) ||
          !result.categories.contains(task.category) ||
          task.title.trim().isEmpty ||
          task.category.trim().isEmpty) {
        throw const FormatException('无效任务关系或快照');
      }
    }

    final seriesVersions = <String>{};
    for (final task in result.tasks.values) {
      validateTask(task, task.id);
    }
    for (final rule in result.rules.values) {
      validateTask(rule.task, rule.taskId);
      _validZone(rule.timezone);
      final series = result.rules[rule.seriesId];
      if (series == null ||
          series.taskId != rule.taskId ||
          series.seriesId != rule.seriesId ||
          series.version != 1 ||
          series.timezone != rule.timezone ||
          rule.task.durationMinutes != rule.durationMinutes ||
          (rule.active && result.tasks[rule.taskId]!.archivedAt != null) ||
          !seriesVersions.add('${rule.seriesId}:${rule.version}')) {
        throw const FormatException('无效规则版本关系');
      }
    }
    final activeRanges = <String, List<(DateTime, DateTime?)>>{};
    for (final rule in result.rules.values.where((r) => r.active)) {
      final first = DateTime.utc(
        rule.start.year,
        rule.start.month,
        rule.start.day,
      );
      DateTime? cutoff;
      if (rule.until != null) {
        final local = tz.TZDateTime.from(
          rule.until!,
          Recurrence.location(rule.timezone),
        );
        cutoff = DateTime.utc(local.year, local.month, local.day);
      }
      final end = rule.repeat == Repeat.none
          ? first.add(const Duration(days: 1))
          : cutoff;
      final effectiveEnd =
          cutoff != null && (end == null || cutoff.isBefore(end))
          ? cutoff
          : end;
      if (effectiveEnd != null && !first.isBefore(effectiveEnd)) continue;
      final prior = activeRanges.putIfAbsent(rule.seriesId, () => []);
      for (final previous in prior) {
        if ((previous.$2 == null || first.isBefore(previous.$2!)) &&
            (effectiveEnd == null || previous.$1.isBefore(effectiveEnd))) {
          throw const FormatException('规则版本生效区间重叠');
        }
      }
      prior.add((first, effectiveEnd));
    }
    void validateOccurrence(
      String id,
      String ruleId,
      String taskId,
      DateTime original,
    ) {
      final rule = result.rules[ruleId];
      if (rule == null ||
          rule.taskId != taskId ||
          id != Recurrence.occurrenceId(ruleId, original) ||
          !Recurrence.belongs(rule, original)) {
        throw const FormatException('无效实例关系');
      }
    }

    for (final override in result.overrides.values) {
      validateOccurrence(
        override.id,
        override.ruleId,
        override.taskId,
        override.originalStart,
      );
      if (override.task != null) validateTask(override.task!, override.taskId);
      if (override.task != null &&
          override.durationMinutes != null &&
          override.task!.durationMinutes != override.durationMinutes) {
        throw const FormatException('单次时长快照不一致');
      }
    }
    final occurrenceRecords = <String>{};
    final inboxRecords = <String>{};
    final executedSeriesDays = <String>{};
    for (final record in result.records.values) {
      validateTask(record.task, record.taskId);
      if (record.occurrenceId == null) {
        if (record.ruleId != null ||
            record.originalStart != null ||
            record.plannedStart != null ||
            record.plannedEnd != null ||
            record.timezone != null ||
            record.reminderMinutes != null ||
            record.postponed ||
            record.status != ExecutionStatus.completed ||
            !inboxRecords.add(record.taskId)) {
          throw const FormatException('无效未排期执行记录');
        }
      } else {
        if (record.ruleId == null ||
            record.originalStart == null ||
            record.plannedStart == null ||
            record.plannedEnd == null ||
            record.timezone == null ||
            !record.plannedEnd!.isAfter(record.plannedStart!) ||
            record.plannedEnd!.difference(record.plannedStart!) !=
                Duration(minutes: record.task.durationMinutes) ||
            record.postponed != (record.plannedStart != record.originalStart) ||
            !occurrenceRecords.add(record.occurrenceId!)) {
          throw const FormatException('无效执行记录快照');
        }
        validateOccurrence(
          record.occurrenceId!,
          record.ruleId!,
          record.taskId,
          record.originalStart!,
        );
        if (record.timezone != result.rules[record.ruleId]!.timezone) {
          throw const FormatException('执行时区关系无效');
        }
        final rule = result.rules[record.ruleId]!;
        final local = tz.TZDateTime.from(
          record.originalStart!,
          Recurrence.location(rule.timezone),
        );
        if (!executedSeriesDays.add(
          '${rule.seriesId}:${local.year}-${local.month}-${local.day}',
        )) {
          throw const FormatException('同系列同一天存在重复执行历史');
        }
      }
    }
    return result;
  }
  static void _validZone(String zone) {
    try {
      Recurrence.location(zone);
    } catch (_) {
      throw FormatException('未知时区 $zone');
    }
  }
}

/// Small offline datasets use ONE versioned JSON document in transactional
/// SQLite on Android (FULL synchronous); Web uses browser-local preferences.
/// Mutations are serialized, persisted before publication, and never acknowledge
/// a failed write. No cascade deletion, generated-instance table, or device-zone
/// dependence is involved. Callers must await mutations and display errors.
class Planner extends ChangeNotifier {
  static const _uuid = Uuid();
  _Snapshot _state;
  final DateTime Function() _clock;
  final Future<void> Function(String)? _persist;
  Future<void> _pending = Future<void>.value();
  Planner._(this._state, this._clock, this._persist);
  factory Planner.memory({
    String timezone = 'UTC',
    DateTime Function()? clock,
    Future<void> Function(String)? persist,
  }) {
    Recurrence.location(timezone);
    return Planner._(
      _Snapshot(timezone: timezone),
      clock ?? DateTime.now,
      persist,
    );
  }
  static Future<String?> readStoredJson({SnapshotStore? store}) async =>
      (store ?? await SnapshotStore.open()).read();
  static Future<Planner> load({
    SnapshotStore? store,
    DateTime Function()? clock,
  }) async {
    Recurrence.initialize();
    final storage = store ?? await SnapshotStore.open();
    final source = await storage.read();
    final _Snapshot state;
    if (source != null) {
      state = _Snapshot.decode(source); // Corruption is surfaced, NEVER erased.
    } else {
      var zone = 'UTC';
      var fallback = false;
      try {
        zone = (await FlutterTimezone.getLocalTimezone()).identifier;
        Recurrence.location(zone);
      } catch (_) {
        zone = 'UTC';
        fallback = true;
      }
      state = _Snapshot(timezone: zone, timezoneDetectionFallback: fallback);
      await storage.write(jsonEncode(state.toJson()));
    }
    return Planner._(state, clock ?? DateTime.now, storage.write);
  }

  String get timezone => _state.timezone;
  bool get timezoneDetectionFallback => _state.timezoneDetectionFallback;
  List<String> get categories => List.unmodifiable(_state.categories);
  List<Task> get tasks => List.unmodifiable(_state.tasks.values);
  List<ScheduleRule> get rules => List.unmodifiable(_state.rules.values);
  List<ExecutionRecord> get records => List.unmodifiable(_state.records.values);
  List<Task> get inbox => _state.tasks.values
      .where(
        (task) =>
            task.archivedAt == null &&
            !_state.rules.values.any(
              (rule) =>
                  rule.taskId == task.id &&
                  rule.active &&
                  (rule.repeat != Repeat.none ||
                      rule.until == null ||
                      Recurrence.resolve(
                        rule.start,
                        rule.timezone,
                      ).isBefore(rule.until!)),
            ) &&
            !_state.records.values.any(
              (r) => r.taskId == task.id && r.occurrenceId == null,
            ),
      )
      .toList();

  Future<void> _mutate(void Function(_Snapshot) change) {
    final action = _pending.then((_) async {
      final next = _state.copy();
      change(next);
      final source = jsonEncode(next.toJson());
      if (_persist != null) await _persist(source);
      _state = next;
      notifyListeners();
    });
    _pending = action.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return action;
  }

  Future<void> setTimezone(String zone) => _mutate((state) {
    Recurrence.location(zone);
    state.timezone = zone;
    state.timezoneDetectionFallback = false;
  });

  static ExecutionRecord? _record(_Snapshot state, String occurrenceId) {
    for (final record in state.records.values) {
      if (record.occurrenceId == occurrenceId) return record;
    }
    return null;
  }

  static Occurrence _fromRecord(ExecutionRecord record) => Occurrence(
    id: record.occurrenceId!,
    ruleId: record.ruleId!,
    taskId: record.taskId,
    task: record.task,
    originalStart: record.originalStart!,
    start: record.plannedStart!,
    end: record.plannedEnd!,
    status: record.status,
    executedAt: record.executedAt,
    reminderMinutes: record.reminderMinutes,
    postponed: record.postponed,
    timezone: record.timezone!,
  );
  static bool _replacedExecution(
    _Snapshot state,
    ScheduleRule rule,
    DateTime original,
  ) {
    final local = tz.TZDateTime.from(
      original,
      Recurrence.location(rule.timezone),
    );
    for (final record in state.records.values) {
      if (record.ruleId == null ||
          record.ruleId == rule.id ||
          state.rules[record.ruleId]?.seriesId != rule.seriesId) {
        continue;
      }
      final old = tz.TZDateTime.from(
        record.originalStart!,
        Recurrence.location(rule.timezone),
      );
      // A series has at most one original occurrence per wall-calendar day.
      // Replacing its version must not create a second plan for an executed day.
      if (old.year == local.year &&
          old.month == local.month &&
          old.day == local.day) {
        return true;
      }
    }
    return false;
  }

  static Occurrence? _effective(
    _Snapshot state,
    ScheduleRule rule,
    DateTime original,
  ) {
    final id = Recurrence.occurrenceId(rule.id, original);
    final record = _record(state, id);
    if (record != null) return _fromRecord(record);
    final override = state.overrides[id];
    if (!Recurrence.isActiveOriginal(rule, original) ||
        override?.cancelled == true ||
        state.tasks[rule.taskId]?.archivedAt != null ||
        _replacedExecution(state, rule, original)) {
      return null;
    }
    final snapshot = override?.task ?? rule.task;
    final duration = override?.durationMinutes ?? rule.durationMinutes;
    final task = snapshot.durationMinutes == duration
        ? snapshot
        : Task(
            id: snapshot.id,
            title: snapshot.title,
            category: snapshot.category,
            notes: snapshot.notes,
            color: snapshot.color,
            durationMinutes: duration,
          );
    final start = override?.newStart ?? original;
    return Occurrence(
      id: id,
      ruleId: rule.id,
      taskId: rule.taskId,
      task: task,
      originalStart: original,
      start: start,
      end: start.add(Duration(minutes: duration)),
      reminderMinutes: override?.replacesReminder == true
          ? override?.reminderMinutes
          : rule.reminderMinutes,
      postponed: override?.newStart != null && override!.newStart != original,
      timezone: rule.timezone,
    );
  }

  static Occurrence _require(_Snapshot state, Occurrence occurrence) {
    final rule = state.rules[occurrence.ruleId];
    if (rule == null ||
        occurrence.taskId != rule.taskId ||
        occurrence.id !=
            Recurrence.occurrenceId(rule.id, occurrence.originalStart) ||
        !Recurrence.belongs(rule, occurrence.originalStart)) {
      throw StateError('日程不存在');
    }
    final current = _effective(state, rule, occurrence.originalStart);
    if (current == null) throw StateError('日程已取消或删除');
    return current;
  }

  List<Occurrence> occurrences(DateTime from, DateTime until) {
    final start = from.toUtc();
    final end = until.toUtc();
    if (!start.isBefore(end)) return [];
    final found = <String, Occurrence>{};
    void add(Occurrence? o) {
      if (o != null && o.start.isBefore(end) && o.end.isAfter(start)) {
        found[o.id] = o;
      }
    }

    for (final rule in _state.rules.values) {
      for (final original in Recurrence.originals(
        rule,
        start,
        end,
        overlap: true,
      )) {
        add(_effective(_state, rule, original));
      }
    }
    // Moved-in occurrences may originate arbitrarily far outside the window.
    for (final override in _state.overrides.values) {
      if (override.newStart != null) {
        add(
          _effective(
            _state,
            _state.rules[override.ruleId]!,
            override.originalStart,
          ),
        );
      }
    }
    // Independent execution snapshots survive all rule cutovers/deletions.
    for (final record in _state.records.values) {
      if (record.occurrenceId != null) add(_fromRecord(record));
    }
    return found.values.toList()..sort((a, b) {
      final time = a.start.compareTo(b.start);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  }

  TaskDraft draftFor(
    Task task, {
    Occurrence? occurrence,
    EditScope scope = EditScope.thisOccurrence,
  }) {
    ScheduleRule? rule;
    if (occurrence != null) {
      rule = _state.rules[occurrence.ruleId];
    } else {
      for (final candidate in _state.rules.values) {
        if (candidate.taskId == task.id &&
            candidate.active &&
            (rule == null || candidate.version > rule.version)) {
          rule = candidate;
        }
      }
    }
    ScheduleRule? root;
    if (scope == EditScope.entireSeries && rule != null) {
      final seriesId = rule.seriesId;
      root = _state.rules[seriesId];
      var latest = rule;
      for (final candidate in _state.rules.values) {
        if (candidate.seriesId == seriesId &&
            candidate.active &&
            candidate.version > latest.version) {
          latest = candidate;
        }
      }
      rule = latest;
    }
    final selected = scope == EditScope.thisOccurrence ? occurrence : null;
    final effective = selected?.task ?? rule?.task ?? task;
    DateTime? start;
    if (selected != null) {
      final local = tz.TZDateTime.from(
        selected.start,
        Recurrence.location(selected.timezone),
      );
      start = DateTime(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
      );
    } else if (occurrence != null &&
        scope == EditScope.thisAndFuture &&
        rule != null) {
      final local = tz.TZDateTime.from(
        occurrence.originalStart,
        Recurrence.location(rule.timezone),
      );
      start = DateTime(
        local.year,
        local.month,
        local.day,
        rule.start.hour,
        rule.start.minute,
      );
    } else if (rule != null) {
      final anchor = root?.start ?? rule.start;
      start = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        rule.start.hour,
        rule.start.minute,
      );
    }
    return TaskDraft(
      title: effective.title,
      category: effective.category,
      notes: effective.notes,
      color: effective.color,
      durationMinutes:
          selected?.task.durationMinutes ??
          rule?.durationMinutes ??
          effective.durationMinutes,
      start: start,
      repeat: rule?.repeat ?? Repeat.none,
      weekdays: rule?.weekdays ?? {},
      reminderMinutes: selected != null
          ? selected.reminderMinutes
          : rule?.reminderMinutes,
      timezone: rule?.timezone ?? timezone,
    );
  }

  static void _validateDraft(TaskDraft draft) {
    if (draft.title.trim().isEmpty ||
        draft.category.trim().isEmpty ||
        draft.durationMinutes < 1 ||
        draft.durationMinutes > 10080 ||
        draft.color < 0 ||
        draft.color > 0xffffffff ||
        (draft.reminderMinutes != null &&
            (draft.reminderMinutes! < 0 || draft.reminderMinutes! > 525600)) ||
        draft.weekdays.any((d) => d < 1 || d > 7) ||
        (draft.start != null &&
            draft.repeat == Repeat.weekly &&
            draft.weekdays.isEmpty)) {
      throw ArgumentError('任务字段或重复规则无效');
    }
    Recurrence.location(draft.timezone);
  }

  static Task _taskDraft(TaskDraft draft, String id) => Task(
    id: id,
    title: draft.title.trim(),
    category: draft.category.trim(),
    notes: draft.notes,
    color: draft.color,
    durationMinutes: draft.durationMinutes,
  );

  Future<void> saveTask(
    TaskDraft draft, {
    String? taskId,
    Occurrence? occurrence,
    EditScope scope = EditScope.entireSeries,
  }) => _mutate((state) {
    _validateDraft(draft);
    final id = taskId ?? occurrence?.taskId ?? _uuid.v4();
    if (taskId != null && !state.tasks.containsKey(id)) {
      throw StateError('任务不存在');
    }
    if (occurrence != null && occurrence.taskId != id) {
      throw StateError('任务实例不匹配');
    }
    final task = _taskDraft(draft, id);
    if (!state.categories.contains(task.category)) {
      state.categories.add(task.category);
    }
    if (occurrence != null && scope == EditScope.thisOccurrence) {
      final current = _require(state, occurrence);
      final previous = state.overrides[current.id];
      state.overrides[current.id] = OccurrenceOverride(
        id: current.id,
        ruleId: current.ruleId,
        taskId: id,
        originalStart: current.originalStart,
        newStart: draft.start == null
            ? previous?.newStart
            : Recurrence.resolve(draft.start!, current.timezone),
        task: task,
        durationMinutes: draft.durationMinutes,
        reminderMinutes: draft.reminderMinutes,
        replacesReminder: true,
      );
      return;
    }
    ScheduleRule? sourceRule;
    if (occurrence != null) {
      _require(state, occurrence);
      sourceRule = state.rules[occurrence.ruleId];
    } else {
      for (final rule in state.rules.values) {
        if (rule.taskId == id &&
            (sourceRule == null || rule.version > sourceRule.version)) {
          sourceRule = rule;
        }
      }
    }
    if (scope == EditScope.thisAndFuture && occurrence == null) {
      throw ArgumentError('本次及以后需要日程实例');
    }
    if (scope == EditScope.thisAndFuture && draft.start != null) {
      final selected = tz.TZDateTime.from(
        occurrence!.originalStart,
        Recurrence.location(sourceRule!.timezone),
      );
      final selectedDay = DateTime.utc(
        selected.year,
        selected.month,
        selected.day,
      );
      final requestedDay = DateTime.utc(
        draft.start!.year,
        draft.start!.month,
        draft.start!.day,
      );
      if (requestedDay.isBefore(selectedDay)) {
        throw ArgumentError('本次及以后不能从本次以前的日期开始；提前单次请使用仅本次');
      }
    }
    final series = sourceRule?.seriesId;
    var version = 0;
    for (final rule in state.rules.values.toList()) {
      if (rule.taskId != id || (series != null && rule.seriesId != series)) {
        continue;
      }
      if (rule.version > version) version = rule.version;
      if (scope == EditScope.thisAndFuture) {
        final boundary = occurrence!.originalStart;
        final until = rule.until == null || boundary.isBefore(rule.until!)
            ? boundary
            : rule.until;
        state.rules[rule.id] = rule.close(until: until);
      } else {
        state.rules[rule.id] = rule.close(active: false);
      }
    }
    state.tasks[id] = task;
    if (draft.start != null) {
      final ruleId = _uuid.v4();
      final zone = sourceRule?.timezone ?? draft.timezone;
      state.rules[ruleId] = ScheduleRule(
        id: ruleId,
        taskId: id,
        timezone: zone,
        start: Recurrence.wall(draft.start!),
        durationMinutes: draft.durationMinutes,
        repeat: draft.repeat,
        weekdays: draft.weekdays,
        reminderMinutes: draft.reminderMinutes,
        seriesId: series ?? ruleId,
        version: version + 1,
        task: task,
      );
    }
  });

  Future<void> deleteTask(
    Task task, {
    Occurrence? occurrence,
    EditScope scope = EditScope.entireSeries,
  }) => _mutate((state) {
    final stored = state.tasks[task.id];
    if (stored == null) throw StateError('任务不存在');
    if (occurrence != null && occurrence.taskId != task.id) {
      throw StateError('任务实例不匹配');
    }
    if (scope != EditScope.entireSeries && occurrence == null) {
      throw ArgumentError('请选择本次日程');
    }
    if (scope == EditScope.thisOccurrence) {
      final current = _require(state, occurrence!);
      state.overrides[current.id] = OccurrenceOverride(
        id: current.id,
        ruleId: current.ruleId,
        taskId: current.taskId,
        originalStart: current.originalStart,
        cancelled: true,
      );
      return;
    }
    if (occurrence != null) _require(state, occurrence);
    final series = occurrence == null
        ? null
        : state.rules[occurrence.ruleId]!.seriesId;
    for (final rule in state.rules.values.toList()) {
      if (rule.taskId != task.id ||
          (series != null && rule.seriesId != series)) {
        continue;
      }
      if (scope == EditScope.thisAndFuture) {
        final boundary = occurrence!.originalStart;
        state.rules[rule.id] = rule.close(
          until: rule.until == null || boundary.isBefore(rule.until!)
              ? boundary
              : rule.until,
        );
      } else {
        state.rules[rule.id] = rule.close(active: false);
      }
    }
    if (scope == EditScope.entireSeries) {
      state.tasks[task.id] = Task(
        id: stored.id,
        title: stored.title,
        category: stored.category,
        notes: stored.notes,
        color: stored.color,
        durationMinutes: stored.durationMinutes,
        archivedAt: _clock().toUtc(),
      );
    }
  });

  Future<void> completeTask(Task task) => _mutate((state) {
    final stored = state.tasks[task.id];
    if (stored == null || stored.archivedAt != null) throw StateError('任务不存在');
    if (state.records.values.any(
      (r) => r.taskId == task.id && r.occurrenceId == null,
    )) {
      return;
    }
    if (state.rules.values.any((r) => r.taskId == task.id && r.active)) {
      throw StateError('排期任务请完成具体日程');
    }
    final record = ExecutionRecord(
      id: _uuid.v4(),
      taskId: task.id,
      executedAt: _clock().toUtc(),
      status: ExecutionStatus.completed,
      task: stored,
    );
    state.records[record.id] = record;
  });
  Future<void> _execute(Occurrence occurrence, ExecutionStatus status) =>
      _mutate((state) {
        final current = _require(state, occurrence);
        final previous = _record(state, current.id);
        if (previous?.status == status) return;
        if (previous != null) state.records.remove(previous.id);
        final record = ExecutionRecord(
          id: previous?.id ?? _uuid.v4(),
          taskId: current.taskId,
          occurrenceId: current.id,
          ruleId: current.ruleId,
          originalStart: current.originalStart,
          executedAt: _clock().toUtc(),
          status: status,
          task: current.task,
          plannedStart: current.start,
          plannedEnd: current.end,
          timezone: current.timezone,
          reminderMinutes: current.reminderMinutes,
          postponed: current.postponed,
        );
        state.records[record.id] = record;
      });
  Future<void> complete(Occurrence occurrence) =>
      _execute(occurrence, ExecutionStatus.completed);
  Future<void> skip(Occurrence occurrence) =>
      _execute(occurrence, ExecutionStatus.skipped);
  Future<void> undo(Occurrence occurrence) => _mutate((state) {
    final record = _record(state, occurrence.id);
    if (record != null) state.records.remove(record.id);
  });
  Future<void> undoRecord(ExecutionRecord record) => _mutate((state) {
    state.records.remove(record.id);
  });
  Future<void> postpone(Occurrence occurrence, DateTime newStart) =>
      _mutate((state) {
        final current = _require(state, occurrence);
        if (current.status != null) throw StateError('请先撤销执行状态再改期');
        final previous = state.overrides[current.id];
        state.overrides[current.id] = OccurrenceOverride(
          id: current.id,
          ruleId: current.ruleId,
          taskId: current.taskId,
          originalStart: current.originalStart,
          newStart: newStart.toUtc(),
          task: previous?.task,
          durationMinutes: previous?.durationMinutes,
          reminderMinutes: previous?.reminderMinutes,
          replacesReminder: previous?.replacesReminder ?? false,
        );
      });

  /// weekStart is a date-component carrier: normalize to its Monday. Planned
  /// ownership uses these calendar dates in EACH rule's anchored timezone;
  /// actual execution uses the device-local calendar-week instants. This keeps
  /// cross-week moves in their original plan week without double counting.
  WeekSummary summary(DateTime weekStart) {
    final monday = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day - (weekStart.weekday - DateTime.monday),
    );
    final sundayEnd = DateTime(monday.year, monday.month, monday.day + 7);
    final planned = <String, Occurrence>{};
    final boundaries = <String, (DateTime, DateTime)>{};
    (DateTime, DateTime) range(String zone) => boundaries.putIfAbsent(
      zone,
      () => (
        Recurrence.resolve(monday, zone),
        Recurrence.resolve(sundayEnd, zone),
      ),
    );
    for (final rule in _state.rules.values) {
      final bounds = range(rule.timezone);
      for (final original in Recurrence.originals(rule, bounds.$1, bounds.$2)) {
        final occurrence = _effective(_state, rule, original);
        if (occurrence != null) planned[occurrence.id] = occurrence;
      }
    }
    for (final record in _state.records.values) {
      if (record.occurrenceId == null) continue;
      final bounds = range(record.timezone!);
      if (!record.originalStart!.isBefore(bounds.$1) &&
          record.originalStart!.isBefore(bounds.$2)) {
        planned[record.occurrenceId!] = _fromRecord(record);
      }
    }
    final history =
        _state.records.values
            .where(
              (r) =>
                  !r.executedAt.isBefore(monday.toUtc()) &&
                  r.executedAt.isBefore(sundayEnd.toUtc()),
            )
            .toList()
          ..sort((a, b) => b.executedAt.compareTo(a.executedAt));
    final counts = <String, int>{};
    var actualCompleted = 0;
    for (final record in history) {
      if (record.status == ExecutionStatus.completed) {
        actualCompleted++;
        counts.update(record.task.category, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final completed = planned.values
        .where((o) => o.status == ExecutionStatus.completed)
        .length;
    final skipped = planned.values
        .where((o) => o.status == ExecutionStatus.skipped)
        .length;
    return WeekSummary(
      planned: planned.length,
      completed: completed,
      skipped: skipped,
      actualCompleted: actualCompleted,
      completionRate: planned.isEmpty ? null : completed / planned.length,
      categoryCounts: counts,
      history: history,
    );
  }

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(_state.toJson());
  Future<void> restoreJson(String source) {
    // Validation finishes before enqueuing replacement, and persistence finishes
    // before publication. Bad schema/relations or storage failure is atomic.
    final restored = _Snapshot.decode(source);
    return _mutate((state) {
      state.timezone = restored.timezone;
      state.timezoneDetectionFallback = restored.timezoneDetectionFallback;
      state.categories
        ..clear()
        ..addAll(restored.categories);
      state.tasks
        ..clear()
        ..addAll(restored.tasks);
      state.rules
        ..clear()
        ..addAll(restored.rules);
      state.overrides
        ..clear()
        ..addAll(restored.overrides);
      state.records
        ..clear()
        ..addAll(restored.records);
    });
  }
}
