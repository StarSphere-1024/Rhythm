import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/planner.dart';
import '../core/reminders.dart';
import 'brand_mark.dart';
import 'calendar.dart';
import 'common.dart';
import 'editor.dart';
import 'lists.dart';
import 'settings.dart';

class RhythmShell extends StatefulWidget {
  const RhythmShell({
    super.key,
    required this.planner,
    required this.reminders,
  });
  final Planner planner;
  final ReminderService reminders;
  @override
  State<RhythmShell> createState() => _RhythmShellState();
}

class _RhythmShellState extends State<RhythmShell> {
  int _page = 0;
  DateTime _day = dayStart(DateTime.now());
  DateTime _week = weekStart(DateTime.now());
  DateTime _reviewWeek = weekStart(DateTime.now());
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _createTask(BuildContext context) {
    HapticFeedback.selectionClick();
    final date = switch (_page) {
      0 => _day,
      1 => _week,
      _ => null,
    };
    showTaskCreation(
      context,
      widget.planner,
      preset: date == null
          ? null
          : DateTime(date.year, date.month, date.day, 9),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.planner,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ['今日 · 节律', '周日程', '收集箱', '回顾'][_page],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_page == 3)
            IconButton(
              tooltip: '新建任务',
              icon: const Icon(Icons.add),
              onPressed: () => _createTask(context),
            ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => SettingsPage(
                  planner: widget.planner,
                  reminders: widget.reminders,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(
          index: _page,
          children: [
            TodayView(
              planner: widget.planner,
              date: _day,
              onChanged: (value) => setState(() => _day = value),
              onWeek: () => setState(() {
                _week = weekStart(_day);
                _page = 1;
              }),
            ),
            WeekView(
              planner: widget.planner,
              date: _week,
              onChanged: (value) => setState(() => _week = value),
            ),
            InboxView(planner: widget.planner),
            ReviewView(
              planner: widget.planner,
              date: _reviewWeek,
              onChanged: (value) => setState(() => _reviewWeek = value),
            ),
          ],
        ),
      ),
      floatingActionButton:
          MediaQuery.viewInsetsOf(context).bottom > 0 || _page == 3
          ? null
          : FloatingActionButton.extended(
              tooltip: '新建任务',
              onPressed: () => _createTask(context),
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : NavigationBar(
              selectedIndex: _page,
              labelBehavior: MediaQuery.textScalerOf(context).scale(14) > 24
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (value) {
                HapticFeedback.selectionClick();
                setState(() => _page = value);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: '今日',
                  tooltip: '今日时间轴',
                ),
                NavigationDestination(
                  icon: Icon(Icons.view_week_outlined),
                  selectedIcon: Icon(Icons.view_week),
                  label: '周日程',
                  tooltip: '七日日程视图',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: '收集箱',
                  tooltip: '收集箱',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: '回顾',
                  tooltip: '每周回顾',
                ),
              ],
            ),
    ),
  );
}
