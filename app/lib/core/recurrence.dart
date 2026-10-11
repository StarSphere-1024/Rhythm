import 'package:timezone/data/latest.dart' as database;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class Recurrence {
  static bool _initialized = false;
  static final Map<String, List<int>> _offsets = {};
  static void initialize() {
    if (!_initialized) {
      database.initializeTimeZones();
      _initialized = true;
    }
  }

  static tz.Location location(String zone) {
    initialize();
    // tz.UTC is provided separately; the bundled database omits the UTC alias.
    return zone == 'UTC' ? tz.UTC : tz.getLocation(zone);
  }

  static DateTime wall(DateTime date) => date.isUtc
      ? date
      : DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
        );

  /// Wall-clock policy: choose the FIRST instant for a repeated wall time.
  /// For a missing wall time, advance to the first valid wall time (gap end),
  /// not the same minute one hour later. Rules never follow device-zone changes.
  static DateTime resolve(DateTime components, String zone) {
    final place = location(zone);
    final requested = wall(components);
    final offsets = _offsets.putIfAbsent(
      zone,
      () => place.zones
          .map((z) => z.offset.inMilliseconds)
          .toSet()
          .toList(growable: false),
    );
    int? first;
    for (final offset in offsets) {
      final candidateMilliseconds = requested.millisecondsSinceEpoch - offset;
      if (place.timeZone(candidateMilliseconds).offset.inMilliseconds ==
          offset) {
        final candidate = requested.microsecondsSinceEpoch - offset * 1000;
        if (first == null || candidate < first) first = candidate;
      }
    }
    if (first != null) {
      return DateTime.fromMicrosecondsSinceEpoch(first, isUtc: true);
    }
    final target = requested.millisecondsSinceEpoch;
    // Only transitions close enough to cross this local date can create its gap.
    final lower = target - const Duration(days: 2).inMilliseconds;
    final upper = target + const Duration(days: 2).inMilliseconds;
    var low = 0;
    var high = place.transitionAt.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (place.transitionAt[middle] < lower) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (
      var i = low;
      i < place.transitionAt.length && place.transitionAt[i] <= upper;
      i++
    ) {
      final transition = place.transitionAt[i];
      final before =
          transition + place.timeZone(transition - 1).offset.inMilliseconds;
      final after =
          transition + place.timeZone(transition).offset.inMilliseconds;
      if (after > before && target >= before && target < after) {
        return DateTime.fromMillisecondsSinceEpoch(transition, isUtc: true);
      }
    }
    throw ArgumentError('无法解析时区 $zone 的墙钟时间 $components');
  }

  static String occurrenceId(String ruleId, DateTime original) =>
      '$ruleId@${original.toUtc().microsecondsSinceEpoch}';

  static Iterable<DateTime> originals(
    ScheduleRule rule,
    DateTime from,
    DateTime until, {
    bool overlap = false,
  }) sync* {
    if (!rule.active || !from.isBefore(until)) return;
    final place = location(rule.timezone);
    final first = resolve(rule.start, rule.timezone);
    final lower = from.toUtc().subtract(
      Duration(minutes: overlap ? rule.durationMinutes : 0),
    );
    final upper = until.toUtc();
    if (rule.repeat == Repeat.none) {
      if (!first.isBefore(lower) &&
          first.isBefore(upper) &&
          (rule.until == null || first.isBefore(rule.until!))) {
        yield first;
      }
      return;
    }
    final local = tz.TZDateTime.from(lower, place);
    var day = DateTime.utc(local.year, local.month, local.day);
    final anchorDay = DateTime.utc(
      rule.start.year,
      rule.start.month,
      rule.start.day,
    );
    if (day.isBefore(anchorDay)) day = anchorDay;
    final last = tz.TZDateTime.from(upper, place);
    final lastDay = DateTime.utc(
      last.year,
      last.month,
      last.day,
    ).add(const Duration(days: 1));
    final seen = <int>{};
    while (day.isBefore(lastDay)) {
      if (rule.repeat == Repeat.daily || rule.weekdays.contains(day.weekday)) {
        final original = resolve(
          DateTime.utc(
            day.year,
            day.month,
            day.day,
            rule.start.hour,
            rule.start.minute,
            rule.start.second,
            rule.start.millisecond,
            rule.start.microsecond,
          ),
          rule.timezone,
        );
        if (!original.isBefore(first) &&
            !original.isBefore(lower) &&
            original.isBefore(upper) &&
            (rule.until == null || original.isBefore(rule.until!)) &&
            seen.add(original.microsecondsSinceEpoch)) {
          yield original;
        }
      }
      day = day.add(const Duration(days: 1));
    }
  }

  // Relation validation uses the immutable original definition, even when a
  // version has since been disabled/truncated, without expanding previous years.
  static bool belongs(ScheduleRule rule, DateTime original) {
    if (!original.isUtc) return false;
    final local = tz.TZDateTime.from(original, location(rule.timezone));
    final first = resolve(rule.start, rule.timezone);
    if (original.isBefore(first)) return false;
    if (rule.repeat == Repeat.none) return original == first;
    for (final delta in [0, -1]) {
      final day = DateTime.utc(local.year, local.month, local.day + delta);
      if (rule.repeat == Repeat.weekly &&
          !rule.weekdays.contains(day.weekday)) {
        continue;
      }
      final expected = resolve(
        DateTime.utc(
          day.year,
          day.month,
          day.day,
          rule.start.hour,
          rule.start.minute,
          rule.start.second,
          rule.start.millisecond,
          rule.start.microsecond,
        ),
        rule.timezone,
      );
      if (expected == original) return true;
    }
    return false;
  }

  static bool isActiveOriginal(ScheduleRule rule, DateTime original) =>
      rule.active &&
      (rule.until == null || original.isBefore(rule.until!)) &&
      belongs(rule, original);
}
