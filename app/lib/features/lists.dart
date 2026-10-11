import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/planner.dart';
import 'common.dart';
import 'detail.dart';

class InboxView extends StatefulWidget {
  const InboxView({super.key, required this.planner});
  final Planner planner;
  @override
  State<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<InboxView> {
  final _title = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final success = await perform(
      context,
      () => widget.planner.saveTask(
        TaskDraft(title: title, timezone: widget.planner.timezone),
      ),
    );
    if (mounted) {
      setState(() {
        _saving = false;
        if (success) _title.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.planner.inbox;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: '快速收集任务',
                    hintText: '输入名称即可保存',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '保存到收集箱',
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '先收集，再安排',
                  message: '不必立刻决定时间。输入一个名字，让想法有个落脚点。',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final task = items[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          radius: 8,
                          backgroundColor: Color(task.color),
                        ),
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.category} · ${task.durationMinutes} 分钟 · 未排期',
                        ),
                        trailing: IconButton(
                          tooltip: '直接完成 ${task.title}',
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () => perform(
                            context,
                            () => widget.planner.completeTask(task),
                          ),
                        ),
                        onTap: () =>
                            showTaskDetail(context, widget.planner, task),
                      ),
                    );
                  },
                ),
        ),
        if (_saving) const LinearProgressIndicator(),
      ],
    );
  }
}

class ReviewView extends StatefulWidget {
  const ReviewView({
    super.key,
    required this.planner,
    required this.date,
    required this.onChanged,
  });
  final Planner planner;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  String? _category;

  Future<void> _history(
    BuildContext context,
    ExecutionRecord record,
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
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              record.task.title,
              style: Theme.of(sheetContext).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              '${record.task.category} · ${record.status == ExecutionStatus.completed ? '已完成' : '已跳过'}',
            ),
            Text(
              '实际记录：${dateLabel(record.executedAt.toLocal())} ${timeLabel(record.executedAt.toLocal())}',
            ),
            const SizedBox(height: 8),
            Text(
              record.occurrenceId == null
                  ? '未排期完成 · 只计入实际完成次数'
                  : '有排期记录 · 计划统计归属于原计划周',
            ),
            if (record.originalStart != null)
              Text(
                '原计划：${dateLabel(record.originalStart!.toLocal())} ${timeLabel(record.originalStart!.toLocal())}',
              ),
            if (record.task.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SelectableText(record.task.notes),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final success = await perform(
                  sheetContext,
                  () => widget.planner.undoRecord(record),
                );
                if (success && sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
              },
              icon: const Icon(Icons.undo),
              label: Text(
                record.status == ExecutionStatus.completed
                    ? '撤销这条完成记录'
                    : '撤销这条跳过记录',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final summary = widget.planner.summary(weekStart(widget.date));
    final history =
        summary.history
            .where(
              (record) =>
                  _category == null || record.task.category == _category,
            )
            .toList()
          ..sort((a, b) => b.executedAt.compareTo(a.executedAt));
    final categories = {
      ...summary.categoryCounts.keys,
      ...summary.history.map((record) => record.task.category),
    }.toList()..sort();
    return Column(
      children: [
        DateNavigation(
          date: weekStart(widget.date),
          week: true,
          onChanged: (value) {
            setState(() => _category = null);
            widget.onChanged(value);
          },
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text('一周回顾', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('看见已经发生的行动，不为留白评分。'),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(14) > 24
                      ? 1
                      : constraints.maxWidth > 700
                      ? 3
                      : 2;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in {
                        '计划次数': '${summary.planned}',
                        '计划已完成': '${summary.completed}',
                        '计划已跳过': '${summary.skipped}',
                        '计划完成率': summary.completionRate == null
                            ? '无计划'
                            : '${(summary.completionRate! * 100).toStringAsFixed(0)}%',
                        '实际完成次数': '${summary.actualCompleted}',
                      }.entries)
                        SizedBox(
                          width: width,
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.key),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.value,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '计划完成率 = 已完成计划 ÷ 全部计划。跳过计入分母；单次跨周改期仍归原计划周。计划周按规则原时区归属；实际完成按打卡时间计入设备本地周，包含收集箱直接完成。每周均从周一开始。',
              ),
              const SizedBox(height: 24),
              Text(
                '分类 · 实际完成次数',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (categories.isEmpty) const Text('还没有执行记录。'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final category in categories)
                    FilterChip(
                      label: Text(
                        '$category · ${summary.categoryCounts[category] ?? 0} 次',
                      ),
                      selected: _category == category,
                      onSelected: (selected) => setState(
                        () => _category = selected ? category : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '执行历史 · ${history.length} 条',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('本周暂无符合筛选的记录。完成与主动跳过后会出现在这里。'),
                ),
              for (final record in history)
                Card(
                  child: ListTile(
                    leading: Icon(
                      record.status == ExecutionStatus.completed
                          ? Icons.check_circle_outline
                          : Icons.skip_next_outlined,
                    ),
                    title: Text(record.task.title),
                    subtitle: Text(
                      '${record.task.category} · ${record.status == ExecutionStatus.completed ? '已完成' : '已跳过'}${record.occurrenceId == null ? ' · 未排期完成' : ''}\n${dateLabel(record.executedAt.toLocal())} ${timeLabel(record.executedAt.toLocal())}',
                    ),
                    onTap: () => _history(context, record),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
