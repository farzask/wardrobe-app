import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/wardrobe/models/wardrobe_item.dart';

/// On-device wardrobe cache.
///
/// PRD §6 requires wardrobe browsing to work offline. The TRD describes no local persistence
/// anywhere — issue #3 in `skills/README.md`. This closes that gap.
///
/// Deliberately a plain mirror of the server rows, not a second source of truth: it is written only
/// from server responses and read only when the network is unavailable or before the first response
/// arrives. There is no local mutation queue, because PRD §6 also says adding items requires
/// connectivity, so there is nothing to queue.
class LocalCache {
  LocalCache._(this._db);

  final Database _db;

  static const _dbName = 'fitcheck_cache.db';
  static const _version = 1;

  static Future<LocalCache> open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        // `payload` holds the whole row as JSON so a new server column does not require a local
        // migration. The extracted columns exist only because they are filtered and sorted on.
        await db.execute('''
          CREATE TABLE wardrobe_items (
            id            TEXT PRIMARY KEY,
            user_id       TEXT NOT NULL,
            category      TEXT NOT NULL,
            occasion      TEXT NOT NULL,
            season        TEXT NOT NULL,
            created_at    TEXT NOT NULL,
            payload       TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX wardrobe_items_user_created ON wardrobe_items (user_id, created_at DESC)',
        );
        await db.execute('''
          CREATE TABLE cache_meta (
            user_id     TEXT PRIMARY KEY,
            synced_at   TEXT NOT NULL
          )
        ''');
      },
    );
    return LocalCache._(db);
  }

  /// Replace this user's cached wardrobe with what the server just returned.
  ///
  /// A full replace rather than an upsert, because an upsert cannot represent deletion: an item
  /// deleted on another device would linger in this cache forever. The wardrobes here are ~150
  /// items (TRD §11), so replacing is cheap and correct.
  Future<void> replaceItems(String userId, List<WardrobeItem> items) async {
    await _db.transaction((txn) async {
      await txn.delete('wardrobe_items', where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('wardrobe_items', {
          'id': item.id,
          'user_id': userId,
          'category': item.category.wire,
          'occasion': item.occasion.wire,
          'season': item.season.wire,
          'created_at': item.createdAt.toUtc().toIso8601String(),
          'payload': jsonEncode(item.toJson()),
        });
      }
      await batch.commit(noResult: true);
      await txn.insert(
        'cache_meta',
        {'user_id': userId, 'synced_at': DateTime.now().toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<WardrobeItem>> readItems(String userId) async {
    final rows = await _db.query(
      'wardrobe_items',
      columns: ['payload'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((r) => WardrobeItem.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>))
        .toList();
  }

  /// When this user's wardrobe was last successfully fetched. Shown on the offline banner, because
  /// "you are offline" is much less useful than "you are offline, this is from an hour ago".
  Future<DateTime?> lastSyncedAt(String userId) async {
    final rows = await _db.query(
      'cache_meta',
      columns: ['synced_at'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['synced_at'] as String)?.toLocal();
  }

  /// Called on sign-out. Leaving one user's wardrobe on a shared device for the next person to see
  /// would defeat the isolation that TRD §9's RLS policies exist to provide.
  Future<void> clear() async {
    await _db.delete('wardrobe_items');
    await _db.delete('cache_meta');
  }

  Future<void> close() => _db.close();
}
