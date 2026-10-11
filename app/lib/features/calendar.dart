import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/planner.dart';
import 'common.dart';
import 'detail.dart';
import 'editor.dart';

class TodayView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final start = dayStart(date);
    final end = nextDay(start);
    final items = planner.occurrences(start, end)
      ..sort((a, b) => a.start.compareTo(b.start));
    final now = DateTime.now();
    final today = dayStart(now) == start;
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
                  label: const Text('周课表'),
                ),
              ],
            ),
          ),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (today &&
                            (index == 0
                                ? now.isBefore(items[index].start)
                                : !now.isBefore(items[index - 1].start) &&
                                      now.isBefore(items[index].start)))
                          _NowLine(now: now),
                        _TimelineCard(
                          planner: planner,
                          occurrence: items[index],
                          date: start,
                        ),
                      ],
                      if (today && !now.isBefore(items.last.start))
                        _NowLine(now: now),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.now});
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
    required this.planner,
    required this.occurrence,
    required this.date,
  });
  final Planner planner;
  final Occurrence occurrence;
  final DateTime date;
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
                      ? perform(context, () => planner.complete(occurrence))
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

const _hourHeight = 80.0;

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
  final _scroll = ScrollController(initialScrollOffset: 7 * _hourHeight);
  (TextStyle?, TextScaler)? _hourMetrics;
  double _hourGutter = 38;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
              '本周全部安排 · ${occurrences.length} 项',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            if (occurrences.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('本周暂无安排。点击课表空白处即可创建。'),
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
    final occurrences = widget.planner.occurrences(start, nextDay(start, 7));
    final metrics = (
      Theme.of(context).textTheme.labelSmall,
      MediaQuery.textScalerOf(context),
    );
    if (_hourMetrics != metrics) {
      _hourMetrics = metrics;
      _hourGutter = math.max(
        38,
        TextPainter.computeWidth(
              text: TextSpan(text: '00:00', style: metrics.$1),
              textDirection: TextDirection.ltr,
              textScaler: metrics.$2,
            ) +
            4,
      );
    }
    return Column(
      children: [
        DateNavigation(date: start, week: true, onChanged: widget.onChanged),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '点击空白创建 · 短时 / 密集安排点击逐项查看 · 设备本地时间',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: '本周全部安排',
                onPressed: () => _agenda(context, occurrences),
                icon: const Icon(Icons.format_list_bulleted),
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
                    vertical: 8,
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
                      Text(
                        weekdayNames[day],
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                      Text(
                        '${nextDay(start, day).day}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * _hourHeight + 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _hourGutter,
                    height: 24 * _hourHeight + 24,
                    child: Stack(
                      children: [
                        for (var hour = 0; hour <= 24; hour++)
                          Positioned(
                            top: hour * _hourHeight,
                            left: 0,
                            right: 2,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var day = 0; day < 7; day++)
                    Expanded(
                      child: _DayColumn(
                        planner: widget.planner,
                        date: nextDay(start, day),
                        items: occurrences
                            .where(
                              (occurrence) =>
                                  occurrence.start.isBefore(
                                    nextDay(start, day + 1),
                                  ) &&
                                  occurrence.end.isAfter(nextDay(start, day)),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Segment {
  _Segment(this.occurrence, this.top, this.bottom);
  final Occurrence occurrence;
  final double top;
  final double bottom;
  int lane = 0;
}

class _Group {
  _Group(this.segments, this.top, this.bottom);
  final List<_Segment> segments;
  final double top;
  double bottom;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.planner,
    required this.date,
    required this.items,
  });
  final Planner planner;
  final DateTime date;
  final List<Occurrence> items;

  double _position(DateTime instant) {
    final local = instant.toLocal();
    if (local.isBefore(date)) return 0;
    if (!local.isBefore(nextDay(date))) return 24 * _hourHeight;
    return (local.hour + local.minute / 60 + local.second / 3600) * _hourHeight;
  }

  Future<void> _picker(
    BuildContext context,
    List<_Segment> segments,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${dateLabel(date)} · ${segments.length} 项密集安排',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final segment in segments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(segment.occurrence.task.color),
                  child: Icon(
                    stateIcon(segment.occurrence),
                    color: Colors.white,
                  ),
                ),
                title: Text(segment.occurrence.task.title),
                subtitle: Text(
                  '${rangeLabel(segment.occurrence)} · ${stateLabel(segment.occurrence)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showTaskDetail(
                    context,
                    planner,
                    segment.occurrence.task,
                    occurrence: segment.occurrence,
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
    final segments = [
      for (final occurrence in items)
        _Segment(
          occurrence,
          _position(occurrence.start),
          _position(occurrence.end),
        ),
    ]..sort((a, b) => a.top.compareTo(b.top));
    final groups = <_Group>[];
    // Merge targets that would collide when enlarged to finger-sized hit areas.
    for (final segment in segments) {
      final targetBottom = math.max(segment.bottom, segment.top + 48);
      if (groups.isEmpty || segment.top >= groups.last.bottom) {
        groups.add(_Group([segment], segment.top, targetBottom));
      } else {
        groups.last.segments.add(segment);
        groups.last.bottom = math.max(groups.last.bottom, targetBottom);
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final now = DateTime.now();
        final currentDay = dayStart(now) == date;
        final border = Theme.of(context).colorScheme.outlineVariant;
        return SizedBox(
          height: 24 * _hourHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final totalMinutes =
                        (details.localPosition.dy / _hourHeight * 60 / 15)
                            .floor() *
                        15;
                    final minutes = totalMinutes.clamp(0, 1425);
                    showTaskEditor(
                      context,
                      planner,
                      preset: DateTime(
                        date.year,
                        date.month,
                        date.day,
                        minutes ~/ 60,
                        minutes % 60,
                      ),
                    );
                  },
                  onLongPressStart: (details) {
                    final minutes =
                        ((details.localPosition.dy / _hourHeight * 60 / 15)
                                    .floor() *
                                15)
                            .clamp(0, 1425);
                    showTaskEditor(
                      context,
                      planner,
                      preset: DateTime(
                        date.year,
                        date.month,
                        date.day,
                        minutes ~/ 60,
                        minutes % 60,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      for (var hour = 0; hour < 24; hour++)
                        Container(
                          height: _hourHeight,
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: border),
                              left: BorderSide(color: border),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              for (final group in groups)
                ..._blocks(context, constraints.maxWidth, group),
              if (currentDay)
                Positioned(
                  top: _position(now),
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
      },
    );
  }

  List<Widget> _blocks(BuildContext context, double width, _Group group) {
    final laneEnds = <double>[];
    for (final segment in group.segments) {
      var lane = laneEnds.indexWhere((end) => end <= segment.top);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(segment.bottom);
      } else {
        laneEnds[lane] = segment.bottom;
      }
      segment.lane = lane;
    }
    final lanes = laneEnds.length;
    final dense =
        group.segments.any((segment) => segment.bottom - segment.top < 48) ||
        (group.segments.length > 1 && width / lanes < 44);
    if (dense) {
      return [
        Positioned(
          top: group.top,
          left: 1,
          right: 1,
          height: math.min(
            math.max(48, group.bottom - group.top),
            24 * _hourHeight - group.top,
          ),
          child: Semantics(
            button: true,
            label:
                '${group.segments.length} 项安排，${group.segments.map((segment) => '${segment.occurrence.task.title} ${rangeLabel(segment.occurrence)}').join('；')}，点击选择任务',
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _picker(context, group.segments),
                child: ClipRect(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Text(
                      '${group.segments.length}项\n${group.segments.map((segment) => segment.occurrence.task.title).join(' / ')}',
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ];
    }
    return [
      for (final segment in group.segments)
        Positioned(
          top: segment.top,
          left: segment.lane * width / lanes + 1,
          width: math.max(1, width / lanes - 2),
          height: math.min(
            math.max(48, segment.bottom - segment.top),
            24 * _hourHeight - segment.top,
          ),
          child: Semantics(
            button: true,
            label:
                '${segment.occurrence.task.title}，${rangeLabel(segment.occurrence)}，${stateLabel(segment.occurrence)}',
            child: Material(
              color: Color(segment.occurrence.task.color).withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .38
                    : .18,
              ),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => showTaskDetail(
                  context,
                  planner,
                  segment.occurrence.task,
                  occurrence: segment.occurrence,
                ),
                child: ClipRect(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Text(
                      '${segment.occurrence.status == ExecutionStatus.completed
                          ? '✓ '
                          : segment.occurrence.status == ExecutionStatus.skipped
                          ? '↷ '
                          : ''}${segment.occurrence.task.title}',
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
