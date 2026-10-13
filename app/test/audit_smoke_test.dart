import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm/core/models.dart';
import 'package:rhythm/core/planner.dart';

void main() {
  test('audit imported extreme rule date', () async {
    String? persisted;
    final p = Planner.memory(persist: (s) async { persisted = s; });
    final root = jsonDecode(p.exportJson()) as Map<String, dynamic>;
    const task = Task(id: 'task', title: 'boundary');
    final rule = ScheduleRule(id: 'rule', taskId: task.id,
      timezone: 'Asia/Shanghai', start: DateTime.fromMillisecondsSinceEpoch(-8640000000000000, isUtc: true),
      durationMinutes: 60, repeat: Repeat.daily, task: task);
    root['tasks'] = [task.toJson()];
    root['rules'] = [rule.toJson()];
    await p.restoreJson(jsonEncode(root));
    print('AUDIT restore accepted; persisted=${persisted != null}');
    try {
      p.occurrences(DateTime.utc(2026, 10, 13), DateTime.utc(2026, 10, 14));
      print('AUDIT query succeeded');
    } catch (e) { print('AUDIT query failed: $e'); }
  });
}
