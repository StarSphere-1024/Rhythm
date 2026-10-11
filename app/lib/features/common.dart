import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime nextDay(DateTime date, [int days = 1]) =>
    DateTime(date.year, date.month, date.day + days);
DateTime weekStart(DateTime date) => nextDay(dayStart(date), 1 - date.weekday);
String dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';
String timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String rangeLabel(Occurrence occurrence) {
  final start = occurrence.start.toLocal();
  final end = occurrence.end.toLocal();
  final sameDay = dayStart(start) == dayStart(end);
  return '${timeLabel(start)} – ${sameDay ? '' : '${end.month}/${end.day} '}${timeLabel(end)}';
}

String stateLabel(Occurrence occurrence) {
  if (occurrence.status == ExecutionStatus.completed) return '已完成';
  if (occurrence.status == ExecutionStatus.skipped) return '已跳过';
  final overdue = occurrence.end.isBefore(DateTime.now());
  return '${overdue ? '逾期 · 待执行' : '待执行'}${occurrence.postponed ? ' · 已推迟' : ''}';
}

IconData stateIcon(Occurrence occurrence) => switch (occurrence.status) {
  ExecutionStatus.completed => Icons.check_circle_outline,
  ExecutionStatus.skipped => Icons.skip_next_outlined,
  null => Icons.radio_button_unchecked,
};

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('操作未完成：$error')));
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    HapticFeedback.lightImpact();
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

Future<DateTime?> pickDateAndTime(
  BuildContext context,
  DateTime initial,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<EditScope?> chooseScope(BuildContext context, {required String verb}) =>
    showDialog<EditScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('$verb的作用范围'),
        children: [
          for (final entry in const {
            EditScope.thisOccurrence: '仅本次',
            EditScope.thisAndFuture: '本次及以后',
            EditScope.entireSeries: '整个系列',
          }.entries)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class DateNavigation extends StatelessWidget {
  const DateNavigation({
    super.key,
    required this.date,
    required this.onChanged,
    this.week = false,
  });
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final bool week;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Row(
      children: [
        IconButton(
          tooltip: week ? '上一周' : '上一天',
          onPressed: () => onChanged(nextDay(date, week ? -7 : -1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked != null) onChanged(week ? weekStart(picked) : picked);
            },
            child: Semantics(
              button: true,
              label: '选择日期 ${dateLabel(date)}',
              child: Text(
                week
                    ? '${date.month}/${date.day} – ${nextDay(date, 6).month}/${nextDay(date, 6).day}'
                    : '${date.month}月${date.day}日 周${weekdayNames[date.weekday - 1]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: week ? '下一周' : '下一天',
          onPressed: () => onChanged(nextDay(date, week ? 7 : 1)),
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          onPressed: () => onChanged(
            week ? weekStart(DateTime.now()) : dayStart(DateTime.now()),
          ),
          child: Text(week ? '本周' : '今天', maxLines: 1),
        ),
      ],
    ),
  );
}
