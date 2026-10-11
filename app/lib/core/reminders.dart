import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'planner.dart';

const _refreshTask = 'rhythm.reminders.refresh';

@pragma('vm:entry-point')
void reminderDispatcher() {
  Workmanager().executeTask((task, data) async {
    if (task != _refreshTask) return true;
    final planner = await Planner.load();
    final service = ReminderService(planner);
    try {
      await service.initialize(background: true);
      return service.lastError == null;
    } finally {
      service.dispose();
      planner.dispose();
    }
  });
}

/// Rolling 30-day notification window; WorkManager renews it offline each day.
/// Android's boot receiver restores the plugin's already-persisted alarms.
class ReminderService extends ChangeNotifier with WidgetsBindingObserver {
  ReminderService(this.planner);

  final Planner planner;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void> _queue = Future<void>.value();
  bool _ready = false;
  bool _disposed = false;
  bool _observing = false;
  String _status = '正在检查提醒权限';
  String? lastError;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  String get statusText => _status;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize({bool background = false}) async {
    if (!supported) {
      _setStatus('此平台不提供 Android 本地提醒；任务和提醒设置仍可离线保存。');
      return;
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      _ready = true;
      if (!background) {
        planner.addListener(_onChanged);
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
        await Workmanager().initialize(reminderDispatcher);
        await Workmanager().registerPeriodicTask(
          _refreshTask,
          _refreshTask,
          frequency: const Duration(days: 1),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
      await sync();
    } catch (error) {
      _failed(error);
    }
  }

  void _onChanged() => unawaited(sync());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> requestPermissions() async {
    if (!supported) return;
    try {
      await _android!.requestNotificationsPermission();
      // Exact alarms are a separate Android 12+ settings permission, not assumed.
      if (await _android!.areNotificationsEnabled() == true &&
          await _android!.canScheduleExactNotifications() != true) {
        await _android!.requestExactAlarmsPermission();
      }
      await sync();
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> sync() {
    if (!_ready || _disposed) return Future<void>.value();
    // Read the current planner only when this queued operation executes.
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await _schedule();
      } catch (error) {
        _failed(error);
      }
    });
    return _queue;
  }

  Future<void> _schedule() async {
    lastError = null;
    final enabled = await _android!.areNotificationsEnabled() == true;
    final exact = await _android!.canScheduleExactNotifications() == true;
    await _plugin.cancelAll();
    if (!enabled) {
      _setStatus('通知未授权，无法提醒；规划、打卡和历史保存不受影响。');
      return;
    }
    final now = DateTime.now().toUtc();
    final items = planner.occurrences(now, now.add(const Duration(days: 31)));
    var count = 0;
    for (final occurrence in items) {
      final lead = occurrence.reminderMinutes;
      if (lead == null || occurrence.status != null) continue;
      final at = occurrence.start.subtract(Duration(minutes: lead));
      if (!at.isAfter(now) || at.isAfter(now.add(const Duration(days: 30)))) {
        continue;
      }
      final local = occurrence.start.toLocal();
      await _plugin.zonedSchedule(
        id: count++,
        title: occurrence.task.title,
        body:
            '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} · ${occurrence.task.category}',
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'rhythm_plans',
            '计划提醒',
            channelDescription: '本地任务的提前提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: occurrence.id,
      );
    }
    _setStatus(
      exact
          ? '已安排 $count 条提醒（未来 30 天）；每天离线续排，重启恢复。'
          : '精确闹钟未授权，$count 条提醒为非精确提醒，系统可能延迟；可在权限设置开启。',
    );
  }

  void _failed(Object error) {
    lastError = error.toString();
    _setStatus('提醒调度失败：$error。任务数据已保留，可重新授权或重试。');
  }

  void _setStatus(String value) {
    _status = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) {
      planner.removeListener(_onChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
