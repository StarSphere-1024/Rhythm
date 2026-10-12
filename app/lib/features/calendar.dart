import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/models.dart';
import '../core/planner.dart';
import '../core/recurrence.dart';
import 'common.dart';
import 'detail.dart';
import 'editor.dart';

class TodayView extends StatefulWidget {
  const TodayView({
    super.key,
    required this.planner,
    required this.date,
    required this.onChanged,
    required this.onWeek,
  });
  final Planner planner;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onWeek;
  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  final _scroll = ScrollController();
  final _nowKey = GlobalKey();
  bool _positionedInitially = false;
  Planner get planner => widget.planner;
  DateTime get date => widget.date;
  ValueChanged<DateTime> get onChanged => widget.onChanged;
  VoidCallback get onWeek => widget.onWeek;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureNowVisible() {
    final target = _nowKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: .45,
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  void _jumpNearNow() {
    if (!_scroll.hasClients) return;
    final now = DateTime.now();
    final start = dayStart(now);
    final items = planner.occurrences(start, nextDay(start))
      ..sort((a, b) => a.start.compareTo(b.start));
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => now.isBefore(item.end));
    final index = current < 0 ? items.length - 1 : current;
    _scroll.jumpTo(
      (index * 150.0).clamp(0, _scroll.position.maxScrollExtent).toDouble(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureNowVisible());
  }

  String _routineRecordLabel(RoutineRecord record) {
    final targetWall = DateTime.utc(
      record.targetDate.year,
      record.targetDate.month,
      record.targetDate.day,
      record.targetMinutes ~/ 60,
      record.targetMinutes % 60,
    );
    final targetInstant = Recurrence.resolve(targetWall, record.timezone);
    final difference = record.recordedAt.difference(targetInstant).inMinutes;
    final comparison = difference < 0
        ? '提前${-difference}分'
        : difference > 0
        ? '晚于目标$difference分'
        : '正好';
    final recorded = record.recordedAt.toLocal();
    final targetTime = DateTime(
      2000,
      1,
      1,
      record.targetMinutes ~/ 60,
      record.targetMinutes % 60,
    );
    return '${dateLabel(record.targetDate)} · 目标 ${timeLabel(targetTime)} · 记录 ${dateLabel(recorded)} ${timeLabel(recorded)} · $comparison';
  }

  Future<String?> _deviceTimezone(BuildContext context) async {
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      Recurrence.location(zone);
      return zone;
    } catch (error) {
      if (context.mounted) showError(context, error);
      return null;
    }
  }

  void _returnToNow() {
    final today = dayStart(DateTime.now());
    if (dayStart(date) == today) {
      _jumpNearNow();
    } else {
      onChanged(today);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpNearNow());
      });
    }
  }

  DateTime _nearestTargetDate(int minutes, tz.TZDateTime now) {
    final choices = [
      for (final offset in [-1, 0, 1])
        tz.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day + offset,
          minutes ~/ 60,
          minutes % 60,
        ),
    ];
    final nearest = choices.reduce(
      (a, b) =>
          a.difference(now).inMicroseconds.abs() <=
              b.difference(now).inMicroseconds.abs()
          ? a
          : b,
    );
    return DateTime(nearest.year, nearest.month, nearest.day);
  }

  int? _targetMinutes(RoutineType type) => switch (type) {
    RoutineType.bedtime => planner.routinePreferences.bedtimeMinutes,
    RoutineType.wakeTime => planner.routinePreferences.wakeTimeMinutes,
  };

  Future<void> _checkIn(BuildContext context, RoutineType type) async {
    final target = _targetMinutes(type);
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在作息设置中设置对应目标时间，再进行打卡。')));
      return;
    }
    final zone = await _deviceTimezone(context);
    if (zone == null || !context.mounted) return;
    final now = tz.TZDateTime.now(Recurrence.location(zone));
    final date = _nearestTargetDate(target, now);
    await perform(
      context,
      () => planner.recordRoutine(
        type: type,
        targetDate: DateTime.utc(date.year, date.month, date.day),
        recordedAt: now.toUtc(),
        timezone: zone,
      ),
    );
  }

  Future<void> _editRoutine(BuildContext context, RoutineType type) async {
    final target = _targetMinutes(type);
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在作息设置中设置对应目标时间，再进行补记。')));
      return;
    }
    final zone = await _deviceTimezone(context);
    if (zone == null || !context.mounted) return;
    final now = tz.TZDateTime.now(Recurrence.location(zone));
    final targetDate = _nearestTargetDate(target, now);
    final targetDateSelected = await showDatePicker(
      context: context,
      initialDate: targetDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择目标日期',
    );
    if (targetDateSelected == null || !context.mounted) return;
    final recordedDateSelected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择实际记录日期',
    );
    if (recordedDateSelected == null || !context.mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      helpText: '选择记录时间',
    );
    if (selectedTime == null || !context.mounted) return;
    final recordedWall = DateTime.utc(
      recordedDateSelected.year,
      recordedDateSelected.month,
      recordedDateSelected.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    final recordedAt = Recurrence.resolve(recordedWall, zone);
    Future<bool> save() => perform(
      context,
      () => planner.recordRoutine(
        type: type,
        targetDate: DateTime.utc(
          targetDateSelected.year,
          targetDateSelected.month,
          targetDateSelected.day,
        ),
        recordedAt: recordedAt,
        timezone: zone,
      ),
    );
    if (await save() || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('作息记录未保存'),
        content: Text(
          '已保留目标日期 ${dateLabel(targetDateSelected)} 与记录时间 ${dateLabel(recordedDateSelected)} ${selectedTime.format(context)}。可以重试或关闭。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              if (await save() && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _routineCard(BuildContext context) {
    final prefs = planner.routinePreferences;
    final records = planner.routineRecords;
    Widget entry(RoutineType type, String name, bool enabled) {
      if (!enabled) return const SizedBox.shrink();
      final matching = records.where((record) => record.type == type).toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      final latest = matching.isEmpty ? null : matching.first;
      final targetMinutes = type == RoutineType.bedtime
          ? prefs.bedtimeMinutes
          : prefs.wakeTimeMinutes;
      return Row(
        children: [
          Expanded(
            child: Text(
              latest == null
                  ? '$name · ${targetMinutes == null ? '目标未设置' : '未记录'}'
                  : '$name · ${_routineRecordLabel(latest)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => _checkIn(context, type),
            child: Text('$name打卡'),
          ),
          IconButton(
            tooltip: '补记或更正$name打卡',
            onPressed: () => _editRoutine(context, type),
            icon: const Icon(Icons.edit_calendar_outlined, size: 20),
          ),
          if (latest != null)
            IconButton(
              tooltip: '撤销$name打卡',
              onPressed: () =>
                  perform(context, () => planner.undoRoutine(latest)),
              icon: const Icon(Icons.undo, size: 20),
            ),
        ],
      );
    }

    if (!prefs.bedtimeCheckInEnabled && !prefs.wakeTimeCheckInEnabled) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.nights_stay_outlined, size: 20),
                const SizedBox(width: 8),
                Text('作息打卡', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            entry(RoutineType.bedtime, '入睡', prefs.bedtimeCheckInEnabled),
            entry(RoutineType.wakeTime, '起床', prefs.wakeTimeCheckInEnabled),
          ],
        ),
      ),
    );
  }

  void _positionOnFirstVisit(bool today, List<Occurrence> items) {
    if (!today || items.isEmpty || _positionedInitially) return;
    _positionedInitially = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpNearNow());
  }

  @override
  Widget build(BuildContext context) {
    final start = dayStart(date);
    final end = nextDay(start);
    final items = planner.occurrences(start, end)
      ..sort((a, b) => a.start.compareTo(b.start));
    final now = DateTime.now();
    final today = dayStart(now) == start;
    final currentIndex = today
        ? items.indexWhere(
            (item) => !now.isBefore(item.start) && now.isBefore(item.end),
          )
        : -1;
    _positionOnFirstVisit(today, items);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 100) {
          onChanged(nextDay(date, details.primaryVelocity! < 0 ? 1 : -1));
        }
      },
      child: Column(
        children: [
          DateNavigation(date: date, onChanged: onChanged),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    today
                        ? '${items.length} 项安排 · 现在 ${timeLabel(now)}'
                        : '${items.length} 项安排 · 给行动留一点空间',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: onWeek,
                  icon: const Icon(Icons.view_week_outlined, size: 18),
                  label: const Text('周日程'),
                ),
                TextButton.icon(
                  onPressed: _returnToNow,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('回到现在'),
                ),
              ],
            ),
          ),
          _routineCard(context),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.wb_sunny_outlined,
                    title: '这一天，留白也很好',
                    message: '点击新建安排任务，或从收集箱开始。左右滑动可切换日期。',
                    action: OutlinedButton.icon(
                      onPressed: () => showTaskEditor(
                        context,
                        planner,
                        preset: DateTime(date.year, date.month, date.day, 9),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('安排这一天'),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (today &&
                            (index == 0
                                ? now.isBefore(items[index].start)
                                : !now.isBefore(items[index - 1].end) &&
                                      now.isBefore(items[index].start)))
                          _NowLine(key: _nowKey, now: now),
                        _TimelineCard(
                          key: index == currentIndex ? _nowKey : null,
                          planner: planner,
                          occurrence: items[index],
                          date: start,
                        ),
                      ],
                      if (today && !now.isBefore(items.last.end))
                        _NowLine(key: _nowKey, now: now),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({super.key, required this.now});
  final DateTime now;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '现在 ${timeLabel(now)}',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Theme.of(context).colorScheme.primary)),
      ],
    ),
  );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    super.key,
    required this.planner,
    required this.occurrence,
    required this.date,
  });
  final Planner planner;
  final Occurrence occurrence;
  final DateTime date;
  Future<void> _complete(BuildContext context) async {
    final succeeded = await perform(
      context,
      () => planner.complete(occurrence),
    );
    if (!succeeded || !context.mounted) return;
    final completed = planner.records
        .where((record) => record.occurrenceId == occurrence.id)
        .toList();
    if (completed.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已完成「${occurrence.task.title}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            perform(context, () => planner.undoRecord(completed.first));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clippedStart = occurrence.start.toLocal().isBefore(date);
    final clippedEnd = occurrence.end.toLocal().isAfter(nextDay(date));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showTaskDetail(
            context,
            planner,
            occurrence.task,
            occurrence: occurrence,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Color(occurrence.task.color),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rangeLabel(occurrence),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        occurrence.task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${occurrence.task.category} · ${stateLabel(occurrence)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (clippedStart || clippedEnd)
                        Text(
                          '${clippedStart ? '承接前一天' : ''}${clippedStart && clippedEnd ? ' · ' : ''}${clippedEnd ? '延续到次日' : ''} · 同一实例',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: occurrence.status == null ? '完成打卡' : '查看执行状态',
                  onPressed: () => occurrence.status == null
                      ? _complete(context)
                      : showTaskDetail(
                          context,
                          planner,
                          occurrence.task,
                          occurrence: occurrence,
                        ),
                  icon: Icon(stateIcon(occurrence)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _foldHeight = 48.0;

enum _Zoom { overview, standard, expanded }

class _TimeBand {
  const _TimeBand(this.from, this.until, {this.folded = false});
  final int from;
  final int until;
  final bool folded;
}

class WeekView extends StatefulWidget {
  const WeekView({
    super.key,
    required this.planner,
    required this.date,
    required this.onChanged,
  });
  final Planner planner;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  late final ScrollController _scroll;
  _Zoom _zoom = _Zoom.overview;
  final Set<String> _expanded = {};
  bool _allHours = false;
  DateTime? _selected;
  double _hourGutter = 38;
  double _overviewHourHeight = 18;

  double get _hourHeight => switch (_zoom) {
    _Zoom.overview => _overviewHourHeight,
    _Zoom.standard => 60,
    _Zoom.expanded => 96,
  };

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (weekStart(oldWidget.date) != weekStart(widget.date) &&
        _selected != null &&
        weekStart(_selected!) != weekStart(widget.date)) {
      _selected = null;
    }
  }

  String _key(_TimeBand band) => '${band.from}:${band.until}';

  double _bandExtent(_TimeBand band) =>
      band.folded && !_expanded.contains(_key(band))
      ? _foldHeight
      : (band.until - band.from) / 60 * _hourHeight;

  double _mappedY(int minute, List<_TimeBand> bands) {
    var y = 0.0;
    for (final band in bands) {
      final extent = _bandExtent(band);
      if (minute >= band.until) {
        y += extent;
      } else if (minute <= band.from) {
        return y;
      } else if (band.folded && !_expanded.contains(_key(band))) {
        return y + extent / 2;
      } else {
        return y + (minute - band.from) / 60 * _hourHeight;
      }
    }
    return y;
  }

  double _timeBandHeight(_TimeBand band) => _bandExtent(band);

  double _timeY(int minute, List<_TimeBand> bands) => _mappedY(minute, bands);
  int _minuteAtY(double y, List<_TimeBand> bands) {
    var top = 0.0;
    for (final band in bands) {
      final extent = _bandExtent(band);
      if (y <= top + extent) {
        if (band.folded && !_expanded.contains(_key(band))) {
          return y - top <= extent / 2 ? band.from : band.until;
        }
        final minute = band.from + ((y - top) / _hourHeight * 60).round();
        return minute.clamp(band.from, band.until).toInt();
      }
      top += extent;
    }
    return 1440;
  }

  void _changeScale(VoidCallback change) {
    final before = _bands();
    final anchor = _scroll.hasClients
        ? _minuteAtY(
            _scroll.offset + _scroll.position.viewportDimension / 2,
            before,
          )
        : null;
    setState(change);
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final y = _timeY(anchor, _bands());
        _scroll.jumpTo(
          (y - _scroll.position.viewportDimension / 2)
              .clamp(0, _scroll.position.maxScrollExtent)
              .toDouble(),
        );
      });
    }
  }

  List<_TimeBand> _bands() {
    final prefs = widget.planner.routinePreferences;
    final bedtime = prefs.bedtimeMinutes;
    final wake = prefs.wakeTimeMinutes;
    if (_allHours ||
        !prefs.foldSleep ||
        bedtime == null ||
        wake == null ||
        bedtime == wake) {
      return const [_TimeBand(0, 1440)];
    }
    final folded = bedtime > wake
        ? [
            _TimeBand(0, wake, folded: true),
            _TimeBand(bedtime, 1440, folded: true),
          ]
        : [_TimeBand(bedtime, wake, folded: true)];
    final bands = <_TimeBand>[];
    var cursor = 0;
    for (final sleep in folded.where((band) => band.from < band.until)) {
      if (cursor < sleep.from) bands.add(_TimeBand(cursor, sleep.from));
      bands.add(sleep);
      cursor = sleep.until;
    }
    if (cursor < 1440) bands.add(_TimeBand(cursor, 1440));
    return bands;
  }

  Future<void> _agenda(
    BuildContext context,
    List<Occurrence> occurrences,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '本周全部日程 · ${occurrences.length} 项',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            if (occurrences.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('本周暂无日程。选择空白时间后可在此新建。'),
              ),
            for (final occurrence in occurrences)
              ListTile(
                title: Text(occurrence.task.title),
                subtitle: Text(
                  '${dateLabel(occurrence.start.toLocal())} ${rangeLabel(occurrence)}\n${stateLabel(occurrence)}',
                ),
                leading: Icon(stateIcon(occurrence)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showTaskDetail(
                    context,
                    widget.planner,
                    occurrence.task,
                    occurrence: occurrence,
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = weekStart(widget.date);
    final until = nextDay(start, 7);
    final occurrences = widget.planner.occurrences(start, until);
    final bands = _bands();
    final metrics = Theme.of(context).textTheme.labelSmall;
    _hourGutter = math
        .max(
          38.0,
          TextPainter.computeWidth(
                text: TextSpan(text: '00:00', style: metrics),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              ) +
              4,
        )
        .toDouble();
    final tickEvery = switch (_zoom) {
      _Zoom.overview => 240,
      _Zoom.standard => 120,
      _Zoom.expanded => 60,
    };
    return Column(
      children: [
        DateNavigation(date: start, week: true, onChanged: widget.onChanged),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              for (final zoom in _Zoom.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text(switch (zoom) {
                        _Zoom.overview => '全览',
                        _Zoom.standard => '标准',
                        _Zoom.expanded => '放大',
                      }),
                      selected: _zoom == zoom,
                      onSelected: (_) => _changeScale(() => _zoom = zoom),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.planner.routinePreferences.bedtimeMinutes != null &&
                          widget.planner.routinePreferences.bedtimeMinutes ==
                              widget.planner.routinePreferences.wakeTimeMinutes
                      ? '入睡与起床时间相同，暂不折叠'
                      : '轻触空白选择日期与时间，再点「在此新建」 · 设备本地时间',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: '定位当前时间',
                onPressed: () {
                  widget.onChanged(weekStart(DateTime.now()));
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      final bands = _bands();
                      final minute =
                          DateTime.now().hour * 60 + DateTime.now().minute;
                      _scroll.jumpTo(
                        (_timeY(minute, bands) -
                                _scroll.position.viewportDimension / 2)
                            .clamp(0, _scroll.position.maxScrollExtent)
                            .toDouble(),
                      );
                    }
                  });
                },
                icon: const Icon(Icons.my_location),
              ),
              IconButton(
                tooltip: '本周全部日程',
                onPressed: () => _agenda(context, occurrences),
                icon: const Icon(Icons.format_list_bulleted),
              ),
              if (widget.planner.routinePreferences.foldSleep)
                TextButton(
                  onPressed: () => _changeScale(() => _allHours = !_allHours),
                  child: Text(_allHours ? '按作息折叠' : '完整24小时'),
                ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _hourGutter),
            for (var day = 0; day < 7; day++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 1,
                  ),
                  decoration: BoxDecoration(
                    color: dayStart(DateTime.now()) == nextDay(start, day)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(weekdayNames[day], maxLines: 1),
                      Text('${nextDay(start, day).day}', maxLines: 1),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 ${dateLabel(_selected!)} ${timeLabel(_selected!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => showTaskEditor(
                    context,
                    widget.planner,
                    preset: _selected,
                  ),
                  child: const Text('在此新建'),
                ),
                IconButton(
                  tooltip: '取消选择',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_zoom == _Zoom.overview) {
                final expandedMinutes = bands
                    .where(
                      (band) => !band.folded || _expanded.contains(_key(band)),
                    )
                    .fold<int>(
                      0,
                      (total, band) => total + band.until - band.from,
                    );
                final foldedHeight =
                    bands
                        .where(
                          (band) =>
                              band.folded && !_expanded.contains(_key(band)),
                        )
                        .length *
                    _foldHeight;
                _overviewHourHeight = expandedMinutes == 0
                    ? 8
                    : ((constraints.maxHeight - foldedHeight) /
                              (expandedMinutes / 60))
                          .clamp(8.0, 18.0)
                          .toDouble();
              }
              final gridHeight = bands.fold<double>(
                0,
                (height, band) => height + _timeBandHeight(band),
              );
              return SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: gridHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _hourGutter,
                        height: gridHeight,
                        child: Stack(
                          children: [
                            for (final band in bands)
                              if (band.folded &&
                                  !_expanded.contains(_key(band)))
                                Positioned(
                                  top: _timeY(band.from, bands),
                                  right: 2,
                                  child: Text(
                                    '${_clock(band.from)}–${_clock(band.until)}',
                                    textAlign: TextAlign.right,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                )
                              else
                                for (
                                  var minute =
                                      ((band.from + tickEvery - 1) ~/
                                          tickEvery) *
                                      tickEvery;
                                  minute <= band.until;
                                  minute += tickEvery
                                )
                                  Positioned(
                                    top: _timeY(minute, bands),
                                    left: 0,
                                    right: 2,
                                    child: Text(
                                      _clock(minute),
                                      maxLines: 1,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      for (var day = 0; day < 7; day++)
                        Expanded(
                          child: _DayColumn(
                            key: ValueKey(
                              'week-day-${nextDay(start, day).toIso8601String()}',
                            ),
                            planner: widget.planner,
                            date: nextDay(start, day),
                            items: occurrences.where((occurrence) {
                              final dayStart = nextDay(start, day);
                              return occurrence.start.isBefore(
                                    nextDay(dayStart),
                                  ) &&
                                  occurrence.end.isAfter(dayStart);
                            }).toList(),
                            bands: bands,
                            tickEvery: tickEvery,
                            hourHeight: _hourHeight,
                            selected: _selected,
                            onSelect: (minute) => setState(() {
                              _selected = DateTime(
                                nextDay(start, day).year,
                                nextDay(start, day).month,
                                nextDay(start, day).day,
                                minute ~/ 60,
                                minute % 60,
                              );
                            }),
                            onFoldTap: (band) => _changeScale(() {
                              final key = _key(band);
                              if (!_expanded.add(key)) _expanded.remove(key);
                            }),
                            expanded: _expanded,
                            bandKey: _key,
                            bandHeight: _timeBandHeight,
                            yFor: _timeY,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _Segment {
  _Segment(this.occurrence, this.top, this.bottom);
  final Occurrence occurrence;
  final double top;
  final double bottom;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    super.key,
    required this.planner,
    required this.date,
    required this.items,
    required this.bands,
    required this.tickEvery,
    required this.hourHeight,
    required this.selected,
    required this.onSelect,
    required this.onFoldTap,
    required this.expanded,
    required this.bandKey,
    required this.bandHeight,
    required this.yFor,
  });
  final Planner planner;
  final DateTime date;
  final List<Occurrence> items;
  final List<_TimeBand> bands;
  final int tickEvery;
  final double hourHeight;
  final DateTime? selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<_TimeBand> onFoldTap;
  final Set<String> expanded;
  final String Function(_TimeBand) bandKey;
  final double Function(_TimeBand) bandHeight;
  final double Function(int, List<_TimeBand>) yFor;

  DateTime _local(DateTime value) => value.toLocal();
  int _minute(DateTime value) => value.hour * 60 + value.minute;

  Future<void> _sleepItems(
    BuildContext context,
    _TimeBand band,
    List<Occurrence> matches,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${dateLabel(date)} ${_clock(band.from)}–${_clock(band.until)} 已折叠 · ${matches.length} 项日程',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final occurrence in matches)
            ListTile(
              title: Text(occurrence.task.title),
              subtitle: Text(
                '${rangeLabel(occurrence)} · ${stateLabel(occurrence)}${_dayPart(occurrence).isEmpty ? '' : ' · ${_dayPart(occurrence)}'}',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showTaskDetail(
                  context,
                  planner,
                  occurrence.task,
                  occurrence: occurrence,
                );
              },
            ),
        ],
      ),
    ),
  );

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String _dayPart(Occurrence occurrence) {
    final start = occurrence.start.toLocal();
    final end = occurrence.end.toLocal();
    final previous = start.isBefore(DateTime(date.year, date.month, date.day));
    final next = end.isAfter(nextDay(date));
    if (!previous && !next) return '';
    return '${previous ? '承接前一天' : ''}${previous && next ? ' · ' : ''}${next ? '延续到次日' : ''} · 同一实例';
  }

  void _openGroup(BuildContext context, List<_Segment> group) {
    final occurrences = group
        .map((segment) => segment.occurrence)
        .toSet()
        .toList();
    if (occurrences.length == 1) {
      final occurrence = occurrences.single;
      showTaskDetail(context, planner, occurrence.task, occurrence: occurrence);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final occurrence in occurrences)
              ListTile(
                title: Text(occurrence.task.title),
                subtitle: Text(
                  '${rangeLabel(occurrence)} · ${stateLabel(occurrence)}${_dayPart(occurrence).isEmpty ? '' : ' · ${_dayPart(occurrence)}'}',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showTaskDetail(
                    context,
                    planner,
                    occurrence.task,
                    occurrence: occurrence,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = nextDay(dateStart);
    final height = bands.fold<double>(0, (sum, band) => sum + bandHeight(band));
    final segments = <_Segment>[];
    for (final item in items) {
      final localStart = _local(item.start);
      final localEnd = _local(item.end);
      final clippedStart = localStart.isBefore(dateStart)
          ? dateStart
          : localStart;
      final clippedEnd = localEnd.isAfter(dateEnd) ? dateEnd : localEnd;
      final startMinute = _minute(clippedStart);
      final endMinute = clippedEnd == dateEnd ? 1440 : _minute(clippedEnd);
      for (final band in bands.where(
        (b) => !b.folded || expanded.contains(bandKey(b)),
      )) {
        final from = math.max(band.from, startMinute).toInt();
        final until = math.min(band.until, endMinute).toInt();
        if (from >= until) continue;
        segments.add(_Segment(item, yFor(from, bands), yFor(until, bands)));
      }
    }
    segments.sort((a, b) => a.top.compareTo(b.top));
    final groups = <List<_Segment>>[];
    for (final segment in segments) {
      if (groups.isEmpty ||
          segment.top >=
              groups.last
                  .map((s) => math.max(s.bottom, s.top + 48))
                  .reduce(math.max)) {
        groups.add([segment]);
      } else {
        groups.last.add(segment);
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final band in bands)
            Positioned(
              top: yFor(band.from, bands),
              left: 0,
              right: 0,
              height: bandHeight(band),
              child: band.folded && !expanded.contains(bandKey(band))
                  ? Builder(
                      builder: (context) {
                        final from = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          band.from ~/ 60,
                          band.from % 60,
                        );
                        final until = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          band.until ~/ 60,
                          band.until % 60,
                        );
                        final matches = items
                            .where(
                              (item) =>
                                  item.start.toLocal().isBefore(until) &&
                                  item.end.toLocal().isAfter(from),
                            )
                            .toList();
                        return Semantics(
                          button: true,
                          label:
                              '${dateLabel(date)} ${_clock(band.from)} 至 ${_clock(band.until)} 已折叠，${matches.length} 项相交日程${matches.isEmpty ? '' : '：${matches.map((item) => '${item.task.title}，${stateLabel(item)}').join('；')}'}',
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: InkWell(
                              onTap: () => onFoldTap(band),
                              onLongPress: matches.isEmpty
                                  ? null
                                  : () => _sleepItems(context, band, matches),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.bedtime_outlined,
                                      size: 14,
                                    ),
                                    Text(
                                      matches.isEmpty
                                          ? '已折叠'
                                          : '${matches.length}项',
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : Semantics(
                      button: true,
                      label:
                          '${dateLabel(date)} ${_clock(band.from)} 至 ${_clock(band.until)} 空白时段',
                      hint: '轻触选择此时段起始时间，再点击「在此新建」；长按快速新建。',
                      excludeSemantics: true,
                      onTap: () => onSelect(band.from),
                      onLongPress: () => showTaskEditor(
                        context,
                        planner,
                        preset: DateTime(
                          date.year,
                          date.month,
                          date.day,
                          band.from ~/ 60,
                          band.from % 60,
                        ),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final minute =
                              ((band.from +
                                          details.localPosition.dy /
                                              hourHeight *
                                              60) /
                                      15)
                                  .floor() *
                              15;
                          onSelect(
                            minute.clamp(band.from, band.until - 1).toInt(),
                          );
                        },
                        onLongPressStart: (details) {
                          final minute =
                              ((band.from +
                                          details.localPosition.dy /
                                              hourHeight *
                                              60) /
                                      15)
                                  .floor() *
                              15;
                          showTaskEditor(
                            context,
                            planner,
                            preset: DateTime(
                              date.year,
                              date.month,
                              date.day,
                              minute ~/ 60,
                              minute % 60,
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          for (final band in bands)
            if (!band.folded || expanded.contains(bandKey(band)))
              for (
                var minute =
                    ((band.from + tickEvery - 1) ~/ tickEvery) * tickEvery;
                minute < band.until;
                minute += tickEvery
              )
                Positioned(
                  top: yFor(minute, bands),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
          if (selected != null &&
              selected!.year == date.year &&
              selected!.month == date.month &&
              selected!.day == date.day)
            Positioned(
              top: yFor(selected!.hour * 60 + selected!.minute, bands),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          for (final group in groups)
            Positioned(
              top: group.first.top,
              left: 1,
              right: 1,
              height: math
                  .min(
                    math.max(
                      48.0,
                      group.map((segment) => segment.bottom).reduce(math.max) -
                          group.first.top,
                    ),
                    height - group.first.top,
                  )
                  .toDouble(),
              child: Semantics(
                button: true,
                label: group
                    .map((s) => s.occurrence)
                    .toSet()
                    .map(
                      (occurrence) =>
                          '${occurrence.task.title} ${rangeLabel(occurrence)} ${stateLabel(occurrence)} ${_dayPart(occurrence)}',
                    )
                    .join('；'),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: () => _openGroup(context, group),
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (final segment in group)
                          Positioned(
                            top: segment.top - group.first.top,
                            left: 0,
                            right: 0,
                            height: math
                                .max(1.0, segment.bottom - segment.top)
                                .toDouble(),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(segment.occurrence.task.color)
                                    .withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? .38
                                          : .18,
                                    ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: segment.bottom - segment.top >= 22
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Text(
                                        '${segment.occurrence.status == ExecutionStatus.completed
                                            ? '✓ '
                                            : segment.occurrence.status == ExecutionStatus.skipped
                                            ? '↷ '
                                            : ''}${segment.occurrence.task.title}',
                                        maxLines: 2,
                                        overflow: TextOverflow.clip,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          for (final band in bands.where(
            (b) => b.folded && expanded.contains(bandKey(b)),
          ))
            Positioned(
              top: yFor(band.from, bands),
              left: 0,
              right: 0,
              height: bandHeight(band),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (dayStart(DateTime.now()) == dateStart)
            Positioned(
              top: yFor(
                DateTime.now().hour * 60 + DateTime.now().minute,
                bands,
              ),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
