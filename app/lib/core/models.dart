import 'dart:collection';

enum Repeat { none, daily, weekly }

enum EditScope { thisOccurrence, thisAndFuture, entireSeries }

enum ExecutionStatus { completed, skipped }

/// The distinct kinds of self-reported routine check-ins.
enum RoutineType {
  /// A check-in for the intended time to go to sleep.
  bedtime,

  /// A check-in for the intended time to wake up.
  wakeTime,
}

/// The user's reusable routine targets and check-in availability.
class RoutinePreferences {
  /// The usual bedtime in minutes after midnight, or `null` when unconfigured.
  final int? bedtimeMinutes;

  /// The usual wake time in minutes after midnight, or `null` when unconfigured.
  final int? wakeTimeMinutes;

  /// Whether the configured sleep interval is folded in week views.
  final bool foldSleep;

  /// Whether users can create or correct bedtime check-ins.
  final bool bedtimeCheckInEnabled;

  /// Whether users can create or correct wake-time check-ins.
  final bool wakeTimeCheckInEnabled;

  RoutinePreferences({
    this.bedtimeMinutes,
    this.wakeTimeMinutes,
    this.foldSleep = false,
    this.bedtimeCheckInEnabled = true,
    this.wakeTimeCheckInEnabled = true,
  }) {
    if ((bedtimeMinutes != null &&
            (bedtimeMinutes! < 0 || bedtimeMinutes! >= 1440)) ||
        (wakeTimeMinutes != null &&
            (wakeTimeMinutes! < 0 || wakeTimeMinutes! >= 1440)) ||
        (foldSleep &&
            (bedtimeMinutes == null ||
                wakeTimeMinutes == null ||
                bedtimeMinutes == wakeTimeMinutes))) {
      throw ArgumentError('Invalid routine preferences');
    }
  }

  Map<String, dynamic> toJson() => {
    'bedtimeMinutes': bedtimeMinutes,
    'wakeTimeMinutes': wakeTimeMinutes,
    'foldSleep': foldSleep,
    'bedtimeCheckInEnabled': bedtimeCheckInEnabled,
    'wakeTimeCheckInEnabled': wakeTimeCheckInEnabled,
  };

  factory RoutinePreferences.fromJson(Object? value) {
    final map = jsonObject(value);
    jsonRequireFields(map, [
      'bedtimeMinutes',
      'wakeTimeMinutes',
      'foldSleep',
      'bedtimeCheckInEnabled',
      'wakeTimeCheckInEnabled',
    ]);
    int? minutes(String key) =>
        map[key] == null ? null : jsonInt(map, key, max: 1439);
    final bedtime = minutes('bedtimeMinutes');
    final wakeTime = minutes('wakeTimeMinutes');
    final foldSleep = jsonBool(map, 'foldSleep');
    if (foldSleep &&
        (bedtime == null || wakeTime == null || bedtime == wakeTime)) {
      throw const FormatException('无效作息折叠设置');
    }
    return RoutinePreferences(
      bedtimeMinutes: bedtime,
      wakeTimeMinutes: wakeTime,
      foldSleep: foldSleep,
      bedtimeCheckInEnabled: jsonBool(map, 'bedtimeCheckInEnabled'),
      wakeTimeCheckInEnabled: jsonBool(map, 'wakeTimeCheckInEnabled'),
    );
  }
}

/// An immutable snapshot of one self-reported routine check-in.
class RoutineRecord {
  /// The stable identifier of this check-in.
  final String id;

  /// The bedtime or wake-time category of this check-in.
  final RoutineType type;

  /// The target civil date, stored as a UTC-midnight date carrier.
  final DateTime targetDate;

  /// The target wall-clock time in minutes after midnight when recorded.
  final int targetMinutes;

  /// The IANA timezone used to resolve the target time when recorded.
  final String timezone;

  /// The instant at which the user recorded this check-in.
  final DateTime recordedAt;

  RoutineRecord({
    required this.id,
    required this.type,
    required this.targetDate,
    required this.targetMinutes,
    required this.timezone,
    required this.recordedAt,
  }) {
    if (id.isEmpty ||
        !targetDate.isUtc ||
        targetDate.hour != 0 ||
        targetDate.minute != 0 ||
        targetDate.second != 0 ||
        targetDate.millisecond != 0 ||
        targetDate.microsecond != 0 ||
        targetMinutes < 0 ||
        targetMinutes >= 1440 ||
        timezone.isEmpty ||
        !recordedAt.isUtc) {
      throw ArgumentError('Invalid routine record');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'targetDate': targetDate.toIso8601String(),
    'targetMinutes': targetMinutes,
    'timezone': timezone,
    'recordedAt': recordedAt.toIso8601String(),
  };

  factory RoutineRecord.fromJson(Object? value) {
    final map = jsonObject(value);
    jsonRequireFields(map, [
      'id',
      'type',
      'targetDate',
      'targetMinutes',
      'timezone',
      'recordedAt',
    ]);
    final targetDate = jsonDate(map, 'targetDate');
    final recordedAt = jsonDate(map, 'recordedAt');
    if (targetDate.hour != 0 ||
        targetDate.minute != 0 ||
        targetDate.second != 0 ||
        targetDate.millisecond != 0 ||
        targetDate.microsecond != 0) {
      throw const FormatException('无效作息目标日期');
    }
    return RoutineRecord(
      id: jsonString(map, 'id'),
      type: jsonEnum(map, 'type', RoutineType.values),
      targetDate: targetDate,
      targetMinutes: jsonInt(map, 'targetMinutes', max: 1439),
      timezone: jsonString(map, 'timezone'),
      recordedAt: recordedAt,
    );
  }
}

// Backup decoding is deliberately strict: no implicit casts, date repair, or defaults.
Map<String, dynamic> jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('应为 JSON 对象');
  return value;
}

void jsonRequireFields(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (!map.containsKey(key)) throw FormatException('缺少字段 $key');
  }
}

String jsonString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) throw FormatException('无效字段 $key');
  return value;
}

String jsonText(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('无效字段 $key');
  return value;
}

int jsonInt(Map<String, dynamic> map, String key, {int min = 0, int? max}) {
  final value = map[key];
  if (value is! int || value < min || (max != null && value > max)) {
    throw FormatException('无效字段 $key');
  }
  return value;
}

bool jsonBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('无效字段 $key');
  return value;
}

DateTime jsonDate(Map<String, dynamic> map, String key) {
  final text = jsonString(map, key);
  final date = DateTime.tryParse(text);
  if (date == null || !date.isUtc || date.toIso8601String() != text) {
    throw FormatException('无效 UTC 日期 $key');
  }
  return date;
}

DateTime? jsonOptionalDate(Map<String, dynamic> map, String key) =>
    map[key] == null ? null : jsonDate(map, key);
int? jsonReminder(Map<String, dynamic> map) => map['reminderMinutes'] == null
    ? null
    : jsonInt(map, 'reminderMinutes', max: 525600);
T jsonEnum<T extends Enum>(
  Map<String, dynamic> map,
  String key,
  List<T> values,
) {
  final name = jsonString(map, key);
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('无效枚举 $key');
}

class Task {
  final String id, title, category, notes;
  final int color, durationMinutes;
  final DateTime? archivedAt;
  const Task({
    required this.id,
    required this.title,
    this.category = '生活',
    this.notes = '',
    this.color = 0xff5e8174,
    this.durationMinutes = 60,
    this.archivedAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'notes': notes,
    'color': color,
    'durationMinutes': durationMinutes,
    'archivedAt': archivedAt?.toUtc().toIso8601String(),
  };
  factory Task.fromJson(Object? value) {
    final m = jsonObject(value);
    jsonRequireFields(m, [
      'id',
      'title',
      'category',
      'notes',
      'color',
      'durationMinutes',
      'archivedAt',
    ]);
    return Task(
      id: jsonString(m, 'id'),
      title: jsonString(m, 'title'),
      category: jsonString(m, 'category'),
      notes: jsonText(m, 'notes'),
      color: jsonInt(m, 'color', max: 0xffffffff),
      durationMinutes: jsonInt(m, 'durationMinutes', min: 1, max: 10080),
      archivedAt: jsonOptionalDate(m, 'archivedAt'),
    );
  }
}

class TaskDraft {
  final String title, category, notes, timezone;
  final int color, durationMinutes;
  final DateTime? start;
  final Repeat repeat;
  final Set<int> weekdays;
  final int? reminderMinutes;
  const TaskDraft({
    required this.title,
    this.category = '生活',
    this.notes = '',
    this.color = 0xff5e8174,
    this.durationMinutes = 60,
    this.start,
    this.repeat = Repeat.none,
    this.weekdays = const {},
    this.reminderMinutes,
    this.timezone = 'UTC',
  });
}

class ScheduleRule {
  final String id, taskId, timezone, seriesId;
  // UTC DateTime as a wall-component carrier, NOT an instant in timezone.
  final DateTime start;
  // Exclusive original-instant boundary, used for immutable rule versions.
  final DateTime? until;
  final int durationMinutes, version;
  final Repeat repeat;
  final Set<int> weekdays;
  final int? reminderMinutes;
  final bool active;
  final Task task;
  ScheduleRule({
    required this.id,
    required this.taskId,
    required this.timezone,
    required this.start,
    this.until,
    required this.durationMinutes,
    required this.repeat,
    Set<int> weekdays = const {},
    this.reminderMinutes,
    String? seriesId,
    this.version = 1,
    this.active = true,
    required this.task,
  }) : seriesId = seriesId ?? id,
       weekdays = UnmodifiableSetView(Set.of(weekdays));
  ScheduleRule close({DateTime? until, bool? active}) => ScheduleRule(
    id: id,
    taskId: taskId,
    timezone: timezone,
    start: start,
    until: until ?? this.until,
    durationMinutes: durationMinutes,
    repeat: repeat,
    weekdays: weekdays,
    reminderMinutes: reminderMinutes,
    seriesId: seriesId,
    version: version,
    active: active ?? this.active,
    task: task,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'timezone': timezone,
    'start': start.toIso8601String(),
    'until': until?.toIso8601String(),
    'durationMinutes': durationMinutes,
    'repeat': repeat.name,
    'weekdays': weekdays.toList()..sort(),
    'reminderMinutes': reminderMinutes,
    'seriesId': seriesId,
    'version': version,
    'active': active,
    'task': task.toJson(),
  };
  factory ScheduleRule.fromJson(Object? value) {
    final m = jsonObject(value);
    jsonRequireFields(m, [
      'id',
      'taskId',
      'timezone',
      'start',
      'until',
      'durationMinutes',
      'repeat',
      'weekdays',
      'reminderMinutes',
      'seriesId',
      'version',
      'active',
      'task',
    ]);
    final days = m['weekdays'];
    if (days is! List ||
        days.any((d) => d is! int || d < 1 || d > 7) ||
        days.toSet().length != days.length) {
      throw const FormatException('无效重复星期');
    }
    final repeat = jsonEnum(m, 'repeat', Repeat.values);
    if (repeat == Repeat.weekly && days.isEmpty) {
      throw const FormatException('每周须选择星期');
    }
    return ScheduleRule(
      id: jsonString(m, 'id'),
      taskId: jsonString(m, 'taskId'),
      timezone: jsonString(m, 'timezone'),
      start: jsonDate(m, 'start'),
      until: jsonOptionalDate(m, 'until'),
      durationMinutes: jsonInt(m, 'durationMinutes', min: 1, max: 10080),
      repeat: repeat,
      weekdays: days.cast<int>().toSet(),
      reminderMinutes: jsonReminder(m),
      seriesId: jsonString(m, 'seriesId'),
      version: jsonInt(m, 'version', min: 1),
      active: jsonBool(m, 'active'),
      task: Task.fromJson(m['task']),
    );
  }
}

class Occurrence {
  final String id, ruleId, taskId, timezone;
  final Task task;
  final DateTime originalStart, start, end;
  final ExecutionStatus? status;
  final DateTime? executedAt;
  final int? reminderMinutes;
  final bool postponed;
  const Occurrence({
    required this.id,
    required this.ruleId,
    required this.taskId,
    required this.task,
    required this.originalStart,
    required this.start,
    required this.end,
    this.status,
    this.executedAt,
    this.reminderMinutes,
    this.postponed = false,
    required this.timezone,
  });
}

class OccurrenceOverride {
  final String id, ruleId, taskId;
  final DateTime originalStart;
  final DateTime? newStart;
  final bool cancelled;
  final Task? task;
  final int? durationMinutes, reminderMinutes;
  final bool replacesReminder;
  const OccurrenceOverride({
    required this.id,
    required this.ruleId,
    required this.taskId,
    required this.originalStart,
    this.newStart,
    this.cancelled = false,
    this.task,
    this.durationMinutes,
    this.reminderMinutes,
    this.replacesReminder = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'ruleId': ruleId,
    'taskId': taskId,
    'originalStart': originalStart.toIso8601String(),
    'newStart': newStart?.toIso8601String(),
    'cancelled': cancelled,
    'task': task?.toJson(),
    'durationMinutes': durationMinutes,
    'reminderMinutes': reminderMinutes,
    'replacesReminder': replacesReminder,
  };
  factory OccurrenceOverride.fromJson(Object? value) {
    final m = jsonObject(value);
    jsonRequireFields(m, [
      'id',
      'ruleId',
      'taskId',
      'originalStart',
      'newStart',
      'cancelled',
      'task',
      'durationMinutes',
      'reminderMinutes',
      'replacesReminder',
    ]);
    return OccurrenceOverride(
      id: jsonString(m, 'id'),
      ruleId: jsonString(m, 'ruleId'),
      taskId: jsonString(m, 'taskId'),
      originalStart: jsonDate(m, 'originalStart'),
      newStart: jsonOptionalDate(m, 'newStart'),
      cancelled: jsonBool(m, 'cancelled'),
      task: m['task'] == null ? null : Task.fromJson(m['task']),
      durationMinutes: m['durationMinutes'] == null
          ? null
          : jsonInt(m, 'durationMinutes', min: 1, max: 10080),
      reminderMinutes: jsonReminder(m),
      replacesReminder: jsonBool(m, 'replacesReminder'),
    );
  }
}

class ExecutionRecord {
  final String id, taskId;
  final String? occurrenceId, ruleId;
  final DateTime? originalStart;
  final DateTime executedAt;
  final ExecutionStatus status;
  final Task task;
  // Visible-plan snapshot is independent of subsequent rule/override mutation.
  final DateTime? plannedStart, plannedEnd;
  final String? timezone;
  final int? reminderMinutes;
  final bool postponed;
  const ExecutionRecord({
    required this.id,
    required this.taskId,
    this.occurrenceId,
    this.ruleId,
    this.originalStart,
    required this.executedAt,
    required this.status,
    required this.task,
    this.plannedStart,
    this.plannedEnd,
    this.timezone,
    this.reminderMinutes,
    this.postponed = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'occurrenceId': occurrenceId,
    'ruleId': ruleId,
    'originalStart': originalStart?.toIso8601String(),
    'executedAt': executedAt.toIso8601String(),
    'status': status.name,
    'task': task.toJson(),
    'plannedStart': plannedStart?.toIso8601String(),
    'plannedEnd': plannedEnd?.toIso8601String(),
    'timezone': timezone,
    'reminderMinutes': reminderMinutes,
    'postponed': postponed,
  };
  factory ExecutionRecord.fromJson(Object? value) {
    final m = jsonObject(value);
    jsonRequireFields(m, [
      'id',
      'taskId',
      'occurrenceId',
      'ruleId',
      'originalStart',
      'executedAt',
      'status',
      'task',
      'plannedStart',
      'plannedEnd',
      'timezone',
      'reminderMinutes',
      'postponed',
    ]);
    String? optional(String key) => m[key] == null ? null : jsonString(m, key);
    return ExecutionRecord(
      id: jsonString(m, 'id'),
      taskId: jsonString(m, 'taskId'),
      occurrenceId: optional('occurrenceId'),
      ruleId: optional('ruleId'),
      originalStart: jsonOptionalDate(m, 'originalStart'),
      executedAt: jsonDate(m, 'executedAt'),
      status: jsonEnum(m, 'status', ExecutionStatus.values),
      task: Task.fromJson(m['task']),
      plannedStart: jsonOptionalDate(m, 'plannedStart'),
      plannedEnd: jsonOptionalDate(m, 'plannedEnd'),
      timezone: optional('timezone'),
      reminderMinutes: jsonReminder(m),
      postponed: jsonBool(m, 'postponed'),
    );
  }
}

class WeekSummary {
  final int planned, completed, skipped, actualCompleted;
  final double? completionRate;
  final Map<String, int> categoryCounts;
  final List<ExecutionRecord> history;
  WeekSummary({
    required this.planned,
    required this.completed,
    required this.skipped,
    required this.actualCompleted,
    required this.completionRate,
    required Map<String, int> categoryCounts,
    required List<ExecutionRecord> history,
  }) : categoryCounts = Map.unmodifiable(categoryCounts),
       history = List.unmodifiable(history);
}
