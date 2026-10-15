import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/models.dart';
import '../core/planner.dart';
import '../core/recurrence.dart';
import 'common.dart';

Future<void> showTaskCreation(
  BuildContext context,
  Planner planner, {
  DateTime? preset,
}) async {
  final schedule = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('收集任务'),
            subtitle: const Text('先记下来，不必决定时间'),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('安排日程'),
            subtitle: const Text('选择时间，放进今日与周日程'),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
        ],
      ),
    ),
  );
  if (schedule == null || !context.mounted) return;
  await showTaskEditor(
    context,
    planner,
    schedule: schedule,
    preset: schedule ? preset : null,
  );
}

Future<void> showTaskEditor(
  BuildContext context,
  Planner planner, {
  Task? task,
  Occurrence? occurrence,
  DateTime? preset,
  bool schedule = false,
  EditScope scope = EditScope.entireSeries,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => TaskEditor(
    planner: planner,
    task: task,
    occurrence: occurrence,
    preset: preset,
    schedule: schedule,
    scope: scope,
  ),
);

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.planner,
    this.task,
    this.occurrence,
    this.preset,
    this.schedule = false,
    required this.scope,
  });
  final Planner planner;
  final Task? task;
  final Occurrence? occurrence;
  final DateTime? preset;
  final bool schedule;
  final EditScope scope;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _notes;
  late final TextEditingController _duration;
  late DateTime _start;
  late final DateTime _initialStart;
  late int _minutes;
  late bool _scheduled;
  late int _color;
  late Repeat _repeat;
  late Set<int> _weekdays;
  late int? _reminder;
  late String _timezone;
  bool _saving = false;
  bool _allowPop = false;

  late TaskDraft _initialDraft;
  bool _dirty = false;
  bool _confirmingClose = false;
  void _markDirty() {
    if (_saving) return;
    setState(() => _dirty = _hasChanges());
  }

  bool _hasChanges() {
    final category = _category.text.trim().isEmpty
        ? '其他'
        : _category.text.trim();
    if (_title.text.trim() != _initialDraft.title ||
        category != _initialDraft.category ||
        _notes.text.trim() != _initialDraft.notes ||
        _color != _initialDraft.color ||
        _minutes != _initialDraft.durationMinutes) {
      return true;
    }
    final wasScheduled = _initialDraft.start != null || widget.schedule;
    if (_scheduled != wasScheduled) return true;
    if (!_scheduled) return false;
    return _start != (_initialDraft.start ?? _initialStart) ||
        _repeat != _initialDraft.repeat ||
        _weekdays.length != _initialDraft.weekdays.length ||
        !_weekdays.containsAll(_initialDraft.weekdays) ||
        _reminder != _initialDraft.reminderMinutes ||
        _timezone != _initialDraft.timezone ||
        int.tryParse(_duration.text) != _initialDraft.durationMinutes;
  }

  Future<void> _requestClose() async {
    if (_saving || _confirmingClose) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _confirmingClose = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('当前表单有尚未保存的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmingClose = false;
    if (discard == true) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.task == null
        ? TaskDraft(
            title: '',
            start: widget.preset == null && !widget.schedule
                ? null
                : _wallInZone(
                    widget.preset ?? DateTime.now(),
                    widget.planner.timezone,
                  ),
            timezone: widget.planner.timezone,
          )
        : widget.planner.draftFor(
            widget.task!,
            occurrence: widget.occurrence,
            scope: widget.scope,
          );
    _initialDraft = draft;
    _title = TextEditingController(text: draft.title);
    _category = TextEditingController(text: draft.category);
    _notes = TextEditingController(text: draft.notes);
    _minutes = draft.durationMinutes;
    _duration = TextEditingController(text: '$_minutes');
    _scheduled = draft.start != null || widget.schedule;
    _start =
        draft.start ??
        _wallInZone(widget.preset ?? DateTime.now(), draft.timezone);
    _initialStart = _start;
    _color = draft.color;
    _repeat = draft.repeat;
    _weekdays = {...draft.weekdays};
    _reminder = draft.reminderMinutes;
    _timezone = draft.timezone;
  }

  static DateTime _wallInZone(DateTime instant, String zone) {
    final local = tz.TZDateTime.from(instant, Recurrence.location(zone));
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }

  DateTime get _end => _wallInZone(
    Recurrence.resolve(_start, _timezone).add(Duration(minutes: _minutes)),
    _timezone,
  );

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_scheduled && _repeat == Repeat.weekly && _weekdays.isEmpty) {
      showError(context, '每周重复至少选择一天');
      return;
    }
    setState(() => _saving = true);
    final success = await perform(
      context,
      () => widget.planner.saveTask(
        TaskDraft(
          title: _title.text.trim(),
          category: _category.text.trim().isEmpty
              ? '其他'
              : _category.text.trim(),
          notes: _notes.text.trim(),
          color: _color,
          durationMinutes: _minutes,
          start: _scheduled ? _start : null,
          repeat: _scheduled ? _repeat : Repeat.none,
          weekdays: _weekdays,
          reminderMinutes: _scheduled ? _reminder : null,
          timezone: _timezone,
        ),
        taskId: widget.task?.id,
        occurrence: widget.occurrence,
        scope: widget.scope,
      ),
      actionLabel: '保存任务',
    );
    if (!mounted) return;
    if (success) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _pickStart() async {
    final value = await pickDateAndTime(context, _start);
    if (value != null && mounted) {
      setState(() {
        _start = value;
        _dirty = _hasChanges();
      });
    }
  }

  Future<void> _pickEnd() async {
    final end = await pickDateAndTime(context, _end);
    if (end == null || !mounted) return;
    final minutes = Recurrence.resolve(
      end,
      _timezone,
    ).difference(Recurrence.resolve(_start, _timezone)).inMinutes;
    if (minutes <= 0) {
      showError(context, '结束必须晚于开始；跨午夜请选下一天的日期');
      return;
    }
    setState(() {
      _minutes = minutes;
      _duration.text = '$minutes';
      _dirty = _hasChanges();
    });
  }

  @override
  Widget build(BuildContext context) {
    final end = _end;
    final scopeText = switch (widget.scope) {
      EditScope.thisOccurrence => '仅本次',
      EditScope.thisAndFuture => '本次及以后',
      EditScope.entireSeries => '整个系列',
    };
    return PopScope(
      canPop: _allowPop || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .88,
          child: AbsorbPointer(
            absorbing: _saving,
            child: SafeArea(
              top: false,
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.task == null
                          ? (_scheduled ? '安排日程' : '收集任务')
                          : (widget.schedule && widget.occurrence == null
                                ? '安排任务'
                                : '编辑任务'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (widget.occurrence != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('编辑范围：$scopeText · 已有执行历史会保留'),
                      ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _title,
                      autofocus: widget.task == null,
                      decoration: InputDecoration(
                        labelText: '任务名称',
                        hintText: _scheduled ? '这段时间想做什么？' : '只填名称即可保存到收集箱',
                      ),
                      maxLength: 120,
                      onChanged: (_) => _markDirty(),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请填写名称'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('安排时间'),
                      subtitle: Text(_scheduled ? '保存后安排到日历' : '仅填写名称即可保存到收集箱'),
                      value: _scheduled,
                      onChanged: (value) => setState(() {
                        _scheduled = value;
                        _dirty = _hasChanges();
                      }),
                    ),
                    if (_scheduled) ...[
                      TextFormField(
                        controller: _duration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '时长（分钟）'),
                        validator: (value) {
                          if (!_scheduled) return null;
                          final number = int.tryParse(value ?? '');
                          return number == null || number <= 0 || number > 10080
                              ? '请输入 1–10080 分钟'
                              : null;
                        },
                        onChanged: (value) {
                          final number = int.tryParse(value);
                          setState(() {
                            if (number != null &&
                                number > 0 &&
                                number <= 10080) {
                              _minutes = number;
                            }
                            _dirty = _hasChanges();
                          });
                        },
                      ),
                    ],
                    if (_scheduled) ...[
                      OutlinedButton.icon(
                        onPressed: _pickStart,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          '开始 ${dateLabel(_start)} ${timeLabel(_start)}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickEnd,
                        icon: const Icon(Icons.schedule),
                        label: Text('结束 ${dateLabel(end)} ${timeLabel(end)}'),
                      ),
                      if (dayStart(end) != dayStart(_start))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '跨午夜 · 同一日程会显示在经过的每一天，打卡只计算一次',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Repeat>(
                        initialValue: _repeat,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '重复'),
                        items: const [
                          DropdownMenuItem(
                            value: Repeat.none,
                            child: Text('不重复'),
                          ),
                          DropdownMenuItem(
                            value: Repeat.daily,
                            child: Text('每天'),
                          ),
                          DropdownMenuItem(
                            value: Repeat.weekly,
                            child: Text('每周'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _repeat = value!;
                          if (_repeat == Repeat.weekly && _weekdays.isEmpty) {
                            _weekdays.add(_start.weekday);
                          }
                          _dirty = _hasChanges();
                        }),
                      ),
                      if (_repeat == Repeat.weekly)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              for (var weekday = 1; weekday <= 7; weekday++)
                                FilterChip(
                                  label: Text('周${weekdayNames[weekday - 1]}'),
                                  selected: _weekdays.contains(weekday),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _weekdays.add(weekday);
                                    } else {
                                      _weekdays.remove(weekday);
                                    }
                                    _dirty = _hasChanges();
                                  }),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _reminder ?? -1,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '本地提醒'),
                        items: [
                          for (final minutes in {
                            ...[-1, 0, 5, 10, 15, 30, 60, 1440],
                            ?_reminder,
                          })
                            DropdownMenuItem(
                              value: minutes,
                              child: Text(
                                minutes == -1
                                    ? '不提醒'
                                    : minutes == 0
                                    ? '开始时'
                                    : '提前 $minutes 分钟',
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _reminder = value == -1 ? null : value;
                          _dirty = _hasChanges();
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '计划时区：$_timezone。重复遵循此时区墙上时间；今日与周日程按设备本地时间展示。提醒能力见设置。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('更多设置'),
                      subtitle: Text(
                        [
                              if (_category.text.isNotEmpty) _category.text,
                              if (_color != 0xff5e8174) '自选颜色',
                              if (_notes.text.isNotEmpty) '含备注',
                            ].isEmpty
                            ? '分类、颜色与备注'
                            : [
                                if (_category.text.isNotEmpty) _category.text,
                                if (_color != 0xff5e8174) '自选颜色',
                                if (_notes.text.isNotEmpty) '含备注',
                              ].join(' · '),
                      ),
                      initiallyExpanded: false,
                      children: [
                        TextFormField(
                          controller: _category,
                          onChanged: (_) => _markDirty(),
                          decoration: const InputDecoration(
                            labelText: '分类',
                            hintText: '选择下方分类或输入自定义名称',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final category in [
                              '健身',
                              '学习',
                              '社交',
                              '生活',
                              '其他',
                            ])
                              ActionChip(
                                label: Text(category),
                                onPressed: () => setState(() {
                                  _category.text = category;
                                  _dirty = _hasChanges();
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('分类颜色'),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final color in [
                              0xff5e8174,
                              0xff6585a8,
                              0xffa6758d,
                              0xffb18145,
                              0xff8074ad,
                              0xffa86262,
                            ])
                              Semantics(
                                label: '选择分类颜色 ${color.toRadixString(16)}',
                                selected: color == _color,
                                button: true,
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _color = color;
                                    _dirty = _hasChanges();
                                  }),
                                  borderRadius: BorderRadius.circular(24),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Color(color),
                                        child: color == _color
                                            ? const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          onChanged: (_) => _markDirty(),
                          decoration: const InputDecoration(
                            labelText: '备注（可选）',
                          ),
                          minLines: 2,
                          maxLines: 6,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? '保存中…' : '保存任务'),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _requestClose,
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
