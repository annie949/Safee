import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/file_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }
// Add these methods to DatabaseService class

  static Future<int> getUserStorageUsed(String userId) async {
    final supabase = Supabase.instance.client;
    try {
      final result = await supabase
          .from('user_keys')
          .select('storage_used')
          .eq('user_id', userId)
          .maybeSingle();

      if (result != null && result['storage_used'] != null) {
        return result['storage_used'] as int;
      }
      return 0;
    } catch (e) {
      print('Error getting storage used: $e');
      return 0;
    }
  }

  static Future<int> getUserStorageLimit(String userId) async {
    final supabase = Supabase.instance.client;
    try {
      final result = await supabase
          .from('user_keys')
          .select('storage_limit')
          .eq('user_id', userId)
          .maybeSingle();

      if (result != null && result['storage_limit'] != null) {
        return result['storage_limit'] as int;
      }
      // 10 MB per user (100 users = 1 GB total)
      return 10 * 1024 * 1024; // 10 MB
    } catch (e) {
      print('Error getting storage limit: $e');
      return 10 * 1024 * 1024;
    }
  }

  static Future<void> updateUserStorageUsed(String userId, int newTotal) async {
    final supabase = Supabase.instance.client;
    try {
      // First get the user's email
      final user = supabase.auth.currentUser;
      if (user == null || user.email == null) {
        print('Cannot update storage: user not logged in');
        return;
      }

      // Check if user record exists
      final existing = await supabase
          .from('user_keys')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Update existing record (no need to provide email)
        await supabase
            .from('user_keys')
            .update({'storage_used': newTotal})
            .eq('user_id', userId);
      } else {
        // Insert new record with ALL required fields
        await supabase.from('user_keys').insert({
          'user_id': userId,
          'email': user.email!,
          'storage_used': newTotal,
          'storage_limit': 10 * 1024 * 1024,
          'password_encrypted_key': '', // Temporary, will be updated later
          'recovery_encrypted_key': '', // Temporary, will be updated later
        });
      }
      print('Storage updated: $newTotal bytes for user $userId');
    } catch (e) {
      print('Error updating storage used: $e');
    }
  }
  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'safe_locker.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            encrypted_path TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            category TEXT NOT NULL,
            is_cloud_backed INTEGER NOT NULL DEFAULT 0,
            cloud_path TEXT,
            created_at TEXT NOT NULL,
            is_trashed INTEGER NOT NULL DEFAULT 0,
            trashed_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE activity_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            action TEXT NOT NULL,
            description TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS activity_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              action TEXT NOT NULL,
              description TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE files ADD COLUMN is_trashed INTEGER NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE files ADD COLUMN trashed_at TEXT');
          } catch (_) {}
        }
      },
    );
  }

  // ── Insert file ──────────────────────────────────────────
  static Future<int> insertFile(FileModel file) async {
    final db = await database;
    return db.insert('files', file.toMap());
  }

  // ── Get all files for user (not trashed) ─────────────────
  static Future<List<FileModel>> getFiles(String userId, String sortBy) async {
    final db = await database;
    final maps = await db.query(
      'files',
      where: 'user_id = ? AND is_trashed = 0',
      whereArgs: [userId],
      orderBy: _orderBy(sortBy),
    );
    return maps.map((m) => FileModel.fromMap(m)).toList();
  }

  // ── Get category file counts ─────────────────────────────
  static Future<Map<String, int>> getCategoryFileCounts(String userId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT category, COUNT(*) as count
      FROM files
      WHERE user_id = ? AND is_trashed = 0
      GROUP BY category
    ''', [userId]);
    final counts = <String, int>{};
    for (final row in result) {
      final countValue = row['count'];
      int count = 0;
      if (countValue is int) {
        count = countValue;
      } else if (countValue is num) {
        count = countValue.toInt();
      }
      counts[row['category'] as String] = count;
    }
    return counts;
  }

  // ── Get recent files (not trashed) ───────────────────────
  static Future<List<FileModel>> getRecentFiles(String userId, {int limit = 5}) async {
    final db = await database;
    final maps = await db.query(
      'files',
      where: 'user_id = ? AND is_trashed = 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => FileModel.fromMap(m)).toList();
  }

  // ── Delete all local data for user ───────────────────────
  static Future<void> deleteAllLocalData(String userId) async {
    final db = await database;
    await db.delete('files', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('activity_logs', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ── Get files by category (not trashed) ──────────────────
  static Future<List<FileModel>> getFilesByCategory(
      String userId, String category, String sortBy) async {
    final db = await database;
    final maps = await db.query(
      'files',
      where: 'user_id = ? AND category = ? AND is_trashed = 0',
      whereArgs: [userId, category],
      orderBy: _orderBy(sortBy),
    );
    return maps.map((m) => FileModel.fromMap(m)).toList();
  }

  // ── Move file to trash ───────────────────────────────────
  static Future<void> moveToTrash(int id) async {
    final db = await database;
    await db.update(
      'files',
      {
        'is_trashed': 1,
        'trashed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Restore file from trash ──────────────────────────────
  static Future<void> restoreFromTrash(int id) async {
    final db = await database;
    await db.update(
      'files',
      {'is_trashed': 0, 'trashed_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Permanent delete ─────────────────────────────────────
  static Future<void> deleteFile(int id) async {
    final db = await database;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  // ── Get trashed files (ALL trashed files) ────────────────
  static Future<List<FileModel>> getTrashedFiles(String userId) async {
    final db = await database;
    final maps = await db.query(
      'files',
      where: 'user_id = ? AND is_trashed = 1',
      whereArgs: [userId],
      orderBy: 'trashed_at DESC',
    );
    return maps.map((m) => FileModel.fromMap(m)).toList();
  }

  // ── Get expired trashed files (older than 7 days) ────────
  static Future<List<FileModel>> getExpiredTrashedFiles(String userId) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final maps = await db.query(
      'files',
      where: 'user_id = ? AND is_trashed = 1 AND trashed_at < ?',
      whereArgs: [userId, cutoff],
    );
    return maps.map((m) => FileModel.fromMap(m)).toList();
  }

  // ── Get storage stats (not trashed) ──────────────────────
  static Future<Map<String, int>> getStorageStats(String userId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT category, SUM(size_bytes) as total
      FROM files
      WHERE user_id = ? AND is_trashed = 0
      GROUP BY category
    ''', [userId]);
    final stats = <String, int>{};
    for (final row in result) {
      final totalValue = row['total'];
      int total = 0;
      if (totalValue is int) {
        total = totalValue;
      } else if (totalValue is num) {
        total = totalValue.toInt();
      }
      stats[row['category'] as String] = total;
    }
    return stats;
  }

  // ── Get cloud storage used (not trashed) ─────────────────
  static Future<int> getCloudStorageUsed(String userId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(size_bytes) as total
      FROM files
      WHERE user_id = ? AND is_cloud_backed = 1 AND is_trashed = 0
    ''', [userId]);
    return (result.first['total'] as int?) ?? 0;
  }

  // ── Get total file count (not trashed) ───────────────────
  static Future<int> getTotalFileCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM files WHERE user_id = ? AND is_trashed = 0',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Get trash count (ALL trashed files) ──────────────────
  static Future<int> getTrashCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM files WHERE user_id = ? AND is_trashed = 1',
      [userId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Update file ──────────────────────────────────────────
  static Future<void> updateFile(FileModel file) async {
    final db = await database;
    await db.update('files', file.toMap(), where: 'id = ?', whereArgs: [file.id]);
  }

  // ── Delete all files for user ────────────────────────────
  static Future<void> deleteAllFiles(String userId) async {
    final db = await database;
    await db.delete('files', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ── Get single file ──────────────────────────────────────
  static Future<FileModel?> getFile(int id) async {
    final db = await database;
    final maps = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return FileModel.fromMap(maps.first);
  }

  // ── ACTIVITY LOGS ────────────────────────────────────────
  static Future<void> logActivity({
    required String userId,
    required String action,
    required String description,
  }) async {
    final db = await database;
    await db.insert('activity_logs', {
      'user_id': userId,
      'action': action,
      'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getActivityLogs(
      String userId, {int limit = 100}) async {
    final db = await database;
    return db.query(
      'activity_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  static Future<void> clearActivityLogs(String userId) async {
    final db = await database;
    await db.delete('activity_logs', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ── Helper ───────────────────────────────────────────────
  static String _orderBy(String sortBy) {
    switch (sortBy) {
      case 'name_asc': return 'display_name ASC';
      case 'name_desc': return 'display_name DESC';
      case 'size_desc': return 'size_bytes DESC';
      case 'date_asc': return 'created_at ASC';
      default: return 'created_at DESC';
    }
  }
}
