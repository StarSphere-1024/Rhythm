import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/backup_files.dart';
import '../core/planner.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: AnimatedBuilder(
      animation: Listenable.merge([widget.planner, widget.reminders]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          Text('完整备份与恢复', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('数据只保存在本机。JSON 备份包含任务、分类、规则、单次变更、设置和执行历史。恢复仅支持完整替换，不合并。'),
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
          Text('时间与显示', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('新计划默认时区'),
            subtitle: Text(widget.planner.timezone),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _action(_timezone),
          ),
          const Text(
            '修改默认时区不会移动已有计划。重复计划遵循规则保存的本地墙上时间；今日与周课表按设备本地时间展示。回顾的计划按规则原时区所在周归属，实际完成按设备本地周归属。夏令时缺失时刻移至第一个有效时刻，重复时刻使用较早的一次。',
          ),
          const SizedBox(height: 12),
          const Text('主题自动跟随系统深浅色；文字大小跟随系统设置。'),
          const SizedBox(height: 24),
          Text('关于节律', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Rhythm · V0.1\n免费、开源、离线优先。无需账号、服务器或网络连接。给规划一点节律，给生活一点留白。',
          ),
          TextButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Rhythm · 节律',
              applicationVersion: '0.1.0',
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
      ),
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
