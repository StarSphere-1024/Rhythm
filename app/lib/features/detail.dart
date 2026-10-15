import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/planner.dart';
import 'common.dart';
import 'editor.dart';

Future<void> showTaskDetail(
  BuildContext context,
  Planner planner,
  Task task, {
  Occurrence? occurrence,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      _TaskDetail(planner: planner, task: task, occurrence: occurrence),
);

class _TaskDetail extends StatefulWidget {
  const _TaskDetail({
    required this.planner,
    required this.task,
    this.occurrence,
  });
  final Planner planner;
  final Task task;
  final Occurrence? occurrence;
  @override
  State<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<_TaskDetail> {
  bool _busy = false;
  bool get _repeating =>
      widget.occurrence != null &&
      widget.planner.rules.any(
        (rule) =>
            rule.id == widget.occurrence!.ruleId && rule.repeat != Repeat.none,
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final success = await perform(context, action);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _edit({bool schedule = false}) async {
    final scope = _repeating
        ? await chooseScope(context, verb: '编辑')
        : EditScope.entireSeries;
    if (scope == null || !mounted) return;
    final outerContext = Navigator.of(context).context;
    Navigator.pop(context);
    if (outerContext.mounted) {
      await showTaskEditor(
        outerContext,
        widget.planner,
        task: widget.task,
        occurrence: widget.occurrence,
        scope: scope,
        schedule: schedule,
      );
    }
  }

  Future<void> _delete() async {
    final scope = _repeating
        ? await chooseScope(context, verb: '删除')
        : EditScope.entireSeries;
    if (scope == null || !mounted) return;
    final label = switch (scope) {
      EditScope.thisOccurrence => '仅本次日程',
      EditScope.thisAndFuture => '本次及以后的日程',
      EditScope.entireSeries => '整个任务及其所有日程',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除？'),
        content: Text('将删除$label。已有完成与跳过历史仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(
        () => widget.planner.deleteTask(
          widget.task,
          occurrence: widget.occurrence,
          scope: scope,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final occurrence = widget.occurrence;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 12),
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Color(task.color),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭详情',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${task.category} · ${occurrence == null ? task.durationMinutes : occurrence.end.difference(occurrence.start).inMinutes} 分钟',
              ),
              if (occurrence != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${dateLabel(occurrence.start.toLocal())} ${rangeLabel(occurrence)}',
                ),
                const SizedBox(height: 6),
                Text(
                  stateLabel(occurrence),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (occurrence.executedAt != null)
                  Text(
                    '实际记录：${dateLabel(occurrence.executedAt!.toLocal())} ${timeLabel(occurrence.executedAt!.toLocal())}',
                  ),
                Text(
                  '计划时区：${occurrence.timezone}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (occurrence.postponed)
                  Text(
                    '原计划：${dateLabel(occurrence.originalStart.toLocal())} ${timeLabel(occurrence.originalStart.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('尚未安排 · 收集箱'),
                ),
              if (task.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SelectableText(task.notes),
                ),
              const SizedBox(height: 20),
              if (occurrence == null || occurrence.status == null)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => occurrence == null
                              ? widget.planner.completeTask(task)
                              : widget.planner.complete(occurrence),
                        ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(occurrence == null ? '直接完成（未排期）' : '完成打卡'),
                ),
              if (occurrence != null && occurrence.status != null)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.planner.undo(occurrence)),
                  icon: const Icon(Icons.undo),
                  label: Text(
                    occurrence.status == ExecutionStatus.completed
                        ? '撤销完成'
                        : '撤销跳过',
                  ),
                ),
              const SizedBox(height: 8),
              if (occurrence != null && occurrence.status == null) ...[
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final newStart = await pickDateAndTime(
                            context,
                            occurrence.start.toLocal(),
                          );
                          if (newStart != null && mounted) {
                            await _run(
                              () =>
                                  widget.planner.postpone(occurrence, newStart),
                            );
                          }
                        },
                  icon: const Icon(Icons.update),
                  label: const Text('推迟 / 单次改期'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.planner.skip(occurrence)),
                  icon: const Icon(Icons.skip_next_outlined),
                  label: const Text('主动跳过本次'),
                ),
              ],
              if (occurrence == null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _edit(schedule: true),
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('安排时间'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑任务'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
