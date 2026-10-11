import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// A committed whole document, not independently persisted entity fragments.
abstract class SnapshotStore {
  Future<String?> read();
  Future<void> write(String source);
  Future<void> close();
  static Future<SnapshotStore>? _opening;
  static Future<SnapshotStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    if (factory != null || path != null) {
      return _open(factory: factory, path: path);
    }
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<SnapshotStore> _open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    if (factory == null && path == null && kIsWeb) return _WebSnapshotStore();
    if (factory == null &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw UnsupportedError('此平台尚不支持可靠本地数据库；请使用 Android 或 Web');
    }
    final actualFactory = factory ?? databaseFactory;
    final databasePath =
        path ?? '${await actualFactory.getDatabasesPath()}/rhythm.db';
    final database = await actualFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=FULL');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE snapshot ('
            'id INTEGER PRIMARY KEY CHECK (id = 1), content TEXT NOT NULL)',
          );
        },
      ),
    );
    return _SqliteSnapshotStore(
      database,
      cached: factory == null && path == null,
    );
  }
}

class _SqliteSnapshotStore implements SnapshotStore {
  final Database database;
  final bool cached;
  _SqliteSnapshotStore(this.database, {required this.cached});
  @override
  Future<void> close() async {
    await database.close();
    if (cached) SnapshotStore._opening = null;
  }

  @override
  Future<String?> read() async {
    final rows = await database.query(
      'snapshot',
      columns: ['content'],
      where: 'id = ?',
      whereArgs: [1],
    );
    return rows.isEmpty ? null : rows.single['content'] as String;
  }

  @override
  Future<void> write(String source) =>
      database.transaction((transaction) async {
        await transaction.insert('snapshot', {
          'id': 1,
          'content': source,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
}

// Browser storage is explicitly best-effort browser-local storage. Android
// execution history never relies on SharedPreferences' non-durable write API.
class _WebSnapshotStore implements SnapshotStore {
  static const key = 'rhythm.snapshot.v1';
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String source) async {
    await preferences.setString(key, source);
    if (await preferences.getString(key) != source) {
      throw StateError('浏览器未保存数据');
    }
  }

  @override
  Future<void> close() async {
    SnapshotStore._opening = null;
  }
}
