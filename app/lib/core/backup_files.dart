import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'planner.dart';

class BackupFiles {
  static Future<bool> export(Planner planner) =>
      _save(planner.exportJson(), 'rhythm');

  static Future<bool> exportRaw() async {
    final source = await Planner.readStoredJson();
    if (source == null) throw StateError('没有可导出的本地数据');
    return _save(source, 'rhythm-recovery');
  }

  static Future<bool> _save(String source, String prefix) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final result = await FilePicker.saveFile(
      fileName: '$prefix-$stamp.json',
      bytes: Uint8List.fromList(utf8.encode(source)),
      mimeType: 'application/json',
      dialogTitle: '导出 Rhythm 备份',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    return result != null;
  }

  /// Reading is non-destructive. UI must obtain explicit replace confirmation
  /// before passing this text to Planner.restoreJson.
  static Future<String?> read() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择 Rhythm JSON 备份',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }
}
