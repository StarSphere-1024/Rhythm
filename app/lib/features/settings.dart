import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/backup_files.dart';
import '../core/models.dart';
import '../core/planner.dart';
import '../core/recurrence.dart';
import '../core/reminders.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.planner,
    required this.reminders,
  });
  final Planner planner;
  final ReminderService reminders;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await perform(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() async {
    final saved = await BackupFiles.export(widget.planner);
    if (saved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('完整备份已导出')));
    }
  }

  Future<void> _import() async {
    final source = await BackupFiles.read();
    if (source == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RestoreConfirmation(planner: widget.planner),
    );
    if (confirmed != true || !mounted) return;
    await widget.planner.restoreJson(source);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已完整恢复数据；日程与回顾已更新')));
    }
  }

  Future<void> _timezone() async {
    final zone = await showDialog<String>(
      context: context,
      builder: (context) => _TimezonePicker(current: widget.planner.timezone),
    );
    if (zone != null) await widget.planner.setTimezone(zone);
  }

  Future<void> _saveRoutinePreferences(RoutinePreferences preferences) =>
      _action(() => widget.planner.saveRoutinePreferences(preferences));

  Future<void> _pickRoutineTarget(RoutineType type) async {
    final preferences = widget.planner.routinePreferences;
    final isBedtime = type == RoutineType.bedtime;
    final current = isBedtime
        ? preferences.bedtimeMinutes
        : preferences.wakeTimeMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (current ?? (isBedtime ? 22 * 60 : 7 * 60)) ~/ 60,
        minute: (current ?? (isBedtime ? 22 * 60 : 7 * 60)) % 60,
      ),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    final bedtimeMinutes = isBedtime ? minutes : preferences.bedtimeMinutes;
    final wakeTimeMinutes = isBedtime ? preferences.wakeTimeMinutes : minutes;
    final equalTargets =
        bedtimeMinutes != null && bedtimeMinutes == wakeTimeMinutes;
    await _saveRoutinePreferences(
      RoutinePreferences(
        bedtimeMinutes: bedtimeMinutes,
        wakeTimeMinutes: wakeTimeMinutes,
        foldSleep:
            preferences.foldSleep &&
            bedtimeMinutes != null &&
            wakeTimeMinutes != null &&
            !equalTargets,
        bedtimeCheckInEnabled: preferences.bedtimeCheckInEnabled,
        wakeTimeCheckInEnabled: preferences.wakeTimeCheckInEnabled,
      ),
    );
    if (equalTargets && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('入睡与起床目标相同，请更正；不会按全天睡眠处理。')));
    }
  }

  Future<void> _clearRoutineTarget(RoutineType type) {
    final preferences = widget.planner.routinePreferences;
    final bedtimeMinutes = type == RoutineType.bedtime
        ? null
        : preferences.bedtimeMinutes;
    final wakeTimeMinutes = type == RoutineType.wakeTime
        ? null
        : preferences.wakeTimeMinutes;
    return _saveRoutinePreferences(
      RoutinePreferences(
        bedtimeMinutes: bedtimeMinutes,
        wakeTimeMinutes: wakeTimeMinutes,
        foldSleep:
            preferences.foldSleep &&
            bedtimeMinutes != null &&
            wakeTimeMinutes != null &&
            bedtimeMinutes != wakeTimeMinutes,
        bedtimeCheckInEnabled: preferences.bedtimeCheckInEnabled,
        wakeTimeCheckInEnabled: preferences.wakeTimeCheckInEnabled,
      ),
    );
  }

  DateTime _nearestTargetDate(RoutineType type, String deviceTimezone) {
    final preferences = widget.planner.routinePreferences;
    final minutes = type == RoutineType.bedtime
        ? preferences.bedtimeMinutes
        : preferences.wakeTimeMinutes;
    if (minutes == null) return DateTime.now();
    final now = DateTime.now().toUtc();
    final localNow = tz.TZDateTime.from(
      now,
      Recurrence.location(deviceTimezone),
    );
    var closest = DateTime(localNow.year, localNow.month, localNow.day);
    var closestDistance = const Duration(days: 1000);
    for (var offset = -1; offset <= 1; offset++) {
      final day = DateTime(
        localNow.year,
        localNow.month,
        localNow.day + offset,
      );
      final target = Recurrence.resolve(
        DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60),
        deviceTimezone,
      );
      final distance = target.difference(now).abs();
      if (distance < closestDistance) {
        closest = day;
        closestDistance = distance;
      }
    }
    return closest;
  }

  Future<void> _recordRoutine(
    RoutineType type, {
    RoutineRecord? existing,
  }) async {
    final preferences = widget.planner.routinePreferences;
    final minutes = type == RoutineType.bedtime
        ? preferences.bedtimeMinutes
        : preferences.wakeTimeMinutes;
    if (minutes == null || _busy) return;

    late final String deviceTimezone;
    try {
      deviceTimezone = (await FlutterTimezone.getLocalTimezone()).identifier;
      Recurrence.location(deviceTimezone);
    } catch (error) {
      if (mounted) {
        showError(context, error, action: '读取设备时区');
      }
      return;
    }
    if (!mounted) return;

    final initialTargetDate = existing == null
        ? _nearestTargetDate(type, deviceTimezone)
        : DateTime(
            existing.targetDate.year,
            existing.targetDate.month,
            existing.targetDate.day,
          );
    final pickedTargetDate = await showDatePicker(
      context: context,
      initialDate: initialTargetDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (pickedTargetDate == null || !mounted) return;
    final pickedRecordTime = await pickDateAndTime(
      context,
      existing?.recordedAt.toLocal() ?? DateTime.now(),
    );
    if (pickedRecordTime == null || !mounted) return;
    await _action(
      () => widget.planner.recordRoutine(
        type: type,
        targetDate: DateTime.utc(
          pickedTargetDate.year,
          pickedTargetDate.month,
          pickedTargetDate.day,
        ),
        recordedAt: pickedRecordTime.toUtc(),
        timezone: deviceTimezone,
      ),
    );
  }

  Future<void> _undoRoutine(RoutineRecord record) =>
      _action(() => widget.planner.undoRoutine(record));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: AnimatedBuilder(
      animation: Listenable.merge([widget.planner, widget.reminders]),
      builder: (context, _) {
        final preferences = widget.planner.routinePreferences;
        final records = widget.planner.routineRecords.toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('作息', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('常用目标用于周日程显示与作息记录对照；不创建普通任务，也不计入任务统计。'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('常用入睡目标'),
              subtitle: Text(
                preferences.bedtimeMinutes == null
                    ? '未设置'
                    : '${(preferences.bedtimeMinutes! ~/ 60).toString().padLeft(2, '0')}:${(preferences.bedtimeMinutes! % 60).toString().padLeft(2, '0')}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: '设置入睡目标',
                    onPressed: _busy
                        ? null
                        : () => _pickRoutineTarget(RoutineType.bedtime),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (preferences.bedtimeMinutes != null)
                    IconButton(
                      tooltip: '清除入睡目标',
                      onPressed: _busy
                          ? null
                          : () => _clearRoutineTarget(RoutineType.bedtime),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('常用起床目标'),
              subtitle: Text(
                preferences.wakeTimeMinutes == null
                    ? '未设置'
                    : '${(preferences.wakeTimeMinutes! ~/ 60).toString().padLeft(2, '0')}:${(preferences.wakeTimeMinutes! % 60).toString().padLeft(2, '0')}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: '设置起床目标',
                    onPressed: _busy
                        ? null
                        : () => _pickRoutineTarget(RoutineType.wakeTime),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (preferences.wakeTimeMinutes != null)
                    IconButton(
                      tooltip: '清除起床目标',
                      onPressed: _busy
                          ? null
                          : () => _clearRoutineTarget(RoutineType.wakeTime),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('周日程折叠睡眠时段'),
              subtitle: Text(
                preferences.bedtimeMinutes == null ||
                        preferences.wakeTimeMinutes == null ||
                        preferences.bedtimeMinutes ==
                            preferences.wakeTimeMinutes
                    ? '设置不同的入睡与起床目标后可用'
                    : '仅改变显示，不影响任务或作息打卡',
              ),
              value: preferences.foldSleep,
              onChanged:
                  _busy ||
                      preferences.bedtimeMinutes == null ||
                      preferences.wakeTimeMinutes == null ||
                      preferences.bedtimeMinutes == preferences.wakeTimeMinutes
                  ? null
                  : (value) => _saveRoutinePreferences(
                      RoutinePreferences(
                        bedtimeMinutes: preferences.bedtimeMinutes,
                        wakeTimeMinutes: preferences.wakeTimeMinutes,
                        foldSleep: value,
                        bedtimeCheckInEnabled:
                            preferences.bedtimeCheckInEnabled,
                        wakeTimeCheckInEnabled:
                            preferences.wakeTimeCheckInEnabled,
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用入睡打卡'),
              subtitle: const Text('关闭入口不删除已有入睡记录'),
              value: preferences.bedtimeCheckInEnabled,
              onChanged: _busy
                  ? null
                  : (value) => _saveRoutinePreferences(
                      RoutinePreferences(
                        bedtimeMinutes: preferences.bedtimeMinutes,
                        wakeTimeMinutes: preferences.wakeTimeMinutes,
                        foldSleep: preferences.foldSleep,
                        bedtimeCheckInEnabled: value,
                        wakeTimeCheckInEnabled:
                            preferences.wakeTimeCheckInEnabled,
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用起床打卡'),
              subtitle: const Text('关闭入口不删除已有起床记录'),
              value: preferences.wakeTimeCheckInEnabled,
              onChanged: _busy
                  ? null
                  : (value) => _saveRoutinePreferences(
                      RoutinePreferences(
                        bedtimeMinutes: preferences.bedtimeMinutes,
                        wakeTimeMinutes: preferences.wakeTimeMinutes,
                        foldSleep: preferences.foldSleep,
                        bedtimeCheckInEnabled:
                            preferences.bedtimeCheckInEnabled,
                        wakeTimeCheckInEnabled: value,
                      ),
                    ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      _busy ||
                          !preferences.bedtimeCheckInEnabled ||
                          preferences.bedtimeMinutes == null
                      ? null
                      : () => _recordRoutine(RoutineType.bedtime),
                  icon: const Icon(Icons.bedtime_outlined),
                  label: const Text('入睡打卡'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _busy ||
                          !preferences.wakeTimeCheckInEnabled ||
                          preferences.wakeTimeMinutes == null
                      ? null
                      : () => _recordRoutine(RoutineType.wakeTime),
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('起床打卡'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '作息记录 · ${records.length} 条',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (records.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('尚无作息记录'),
                subtitle: Text('记录按作息类型和目标日期分别保存。'),
              ),
            for (final record in records)
              Card(
                child: ListTile(
                  leading: Icon(
                    record.type == RoutineType.bedtime
                        ? Icons.bedtime_outlined
                        : Icons.wb_sunny_outlined,
                  ),
                  title: Text(
                    '${record.type == RoutineType.bedtime ? '入睡' : '起床'} · ${dateLabel(record.targetDate)}',
                  ),
                  subtitle: Text(
                    '记录 ${dateLabel(record.recordedAt.toLocal())} ${timeLabel(record.recordedAt.toLocal())} · '
                    '目标 ${(record.targetMinutes ~/ 60).toString().padLeft(2, '0')}:${(record.targetMinutes % 60).toString().padLeft(2, '0')} · ${record.timezone}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: '更正这次作息记录',
                        onPressed:
                            _busy ||
                                (record.type == RoutineType.bedtime
                                    ? !preferences.bedtimeCheckInEnabled ||
                                          preferences.bedtimeMinutes == null
                                    : !preferences.wakeTimeCheckInEnabled ||
                                          preferences.wakeTimeMinutes == null)
                            ? null
                            : () =>
                                  _recordRoutine(record.type, existing: record),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: '撤销这次作息记录',
                        onPressed: _busy ? null : () => _undoRoutine(record),
                        icon: const Icon(Icons.undo),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('本地提醒', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(widget.reminders.statusText),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || !widget.reminders.supported
                  ? null
                  : () => _action(widget.reminders.requestPermissions),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('检查 / 申请通知与闹钟权限'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || !widget.reminders.supported
                  ? null
                  : () => _action(widget.reminders.sync),
              icon: const Icon(Icons.sync),
              label: const Text('重新调度提醒'),
            ),
            const SizedBox(height: 24),
            Text('数据备份', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '数据只保存在本机。JSON 备份包含任务、分类、规则、单次变更、作息偏好与记录、执行历史。恢复仅支持完整替换，不合并。',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _action(_export),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出完整 JSON 备份'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _action(_import),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('从 JSON 文件恢复'),
            ),
            const SizedBox(height: 24),
            Text('计划时区', style: Theme.of(context).textTheme.titleLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('新计划默认时区'),
              subtitle: Text(widget.planner.timezone),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _action(_timezone),
            ),
            const Text(
              '修改默认时区不会移动已有计划。重复计划遵循规则保存的本地墙上时间；今日与周日程按设备本地时间展示。回顾的计划按规则原时区所在周归属，实际完成按设备本地周归属。夏令时缺失时刻移至第一个有效时刻，重复时刻使用较早的一次。',
            ),
            const SizedBox(height: 12),
            const Text('主题自动跟随系统深浅色；文字大小跟随系统设置。'),
            const SizedBox(height: 24),
            Text('关于节律', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Rhythm · V0.2\n免费、开源、离线优先。无需账号、服务器或网络连接。给规划一点节律，给生活一点留白。',
            ),
            TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Rhythm · 节律',
                applicationVersion: '0.2.0',
              ),
              icon: const Icon(Icons.code),
              label: const Text('开源许可'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        );
      },
    ),
  );
}

class _RestoreConfirmation extends StatefulWidget {
  const _RestoreConfirmation({required this.planner});
  final Planner planner;
  @override
  State<_RestoreConfirmation> createState() => _RestoreConfirmationState();
}

class _RestoreConfirmationState extends State<_RestoreConfirmation> {
  bool _exporting = false;
  String? _result;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('完整替换本地数据？'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '导入会覆盖当前所有任务、日程、单次变更、设置及执行历史，不会合并。建议先导出当前数据。文件若校验失败，原数据保持不变。',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _exporting
                ? null
                : () async {
                    setState(() {
                      _exporting = true;
                      _result = null;
                    });
                    try {
                      final saved = await BackupFiles.export(widget.planner);
                      if (mounted) {
                        setState(
                          () => _result = saved
                              ? '当前数据已导出，可以继续替换。'
                              : '已取消导出，尚未保存备份。',
                        );
                      }
                    } catch (error) {
                      if (mounted) setState(() => _result = '导出失败：$error');
                    } finally {
                      if (mounted) setState(() => _exporting = false);
                    }
                  },
            icon: const Icon(Icons.save_alt),
            label: Text(_exporting ? '导出中…' : '先导出当前数据'),
          ),
          if (_result != null) Text(_result!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _exporting ? null : () => Navigator.pop(context, false),
        child: const Text('取消导入'),
      ),
      FilledButton(
        onPressed: _exporting ? null : () => Navigator.pop(context, true),
        child: const Text('确认覆盖并恢复'),
      ),
    ],
  );
}

class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({required this.current});
  final String current;
  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<_TimezonePicker> {
  String _query = '';
  late final List<String> _zones = tz.timeZoneDatabase.locations.keys.toList()
    ..sort();
  @override
  Widget build(BuildContext context) {
    final zones = _zones
        .where((zone) => zone.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('选择新计划时区', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '搜索 IANA 时区',
                    hintText: '例如 Asia/Shanghai',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: zones.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(zones[index]),
                      trailing: zones[index] == widget.current
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, zones[index]),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
