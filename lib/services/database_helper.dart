import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/download_item.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'dirxplore_downloads.db');
    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE downloads(
        id TEXT PRIMARY KEY,
        url TEXT,
        fileName TEXT,
        savePath TEXT,
        batchId TEXT,
        batchName TEXT,
        status INTEGER,
        totalBytes INTEGER,
        downloadedBytes INTEGER,
        retryCount INTEGER,
        maxRetries INTEGER DEFAULT 3,
        errorMessage TEXT,
        addedAt TEXT,
        originalUrl TEXT,
        customHeadersJson TEXT,
        mirrorUrlsJson TEXT,
        category INTEGER DEFAULT 7,
        scheduleType INTEGER DEFAULT 0,
        scheduledAt TEXT,
        expectedMd5 TEXT,
        expectedSha1 TEXT,
        expectedSha256 TEXT,
        calculatedMd5 TEXT,
        calculatedSha1 TEXT,
        calculatedSha256 TEXT,
        redirectCount INTEGER DEFAULT 0,
        resolvedUrl TEXT,
        speedLimitKbps INTEGER,
        etag TEXT,
        mimeType TEXT,
        lastModified TEXT,
        contentDisposition TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE downloads ADD COLUMN originalUrl TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE downloads ADD COLUMN maxRetries INTEGER DEFAULT 3');
      await db.execute('ALTER TABLE downloads ADD COLUMN customHeadersJson TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN mirrorUrlsJson TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN category INTEGER DEFAULT 7');
      await db.execute('ALTER TABLE downloads ADD COLUMN scheduleType INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE downloads ADD COLUMN scheduledAt TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN expectedMd5 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN expectedSha1 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN expectedSha256 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN calculatedMd5 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN calculatedSha1 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN calculatedSha256 TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN redirectCount INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE downloads ADD COLUMN resolvedUrl TEXT');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE downloads ADD COLUMN etag TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN mimeType TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN lastModified TEXT');
      await db.execute('ALTER TABLE downloads ADD COLUMN contentDisposition TEXT');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE downloads ADD COLUMN speedLimitKbps INTEGER');
    }
  }

  Future<int> insertDownload(DownloadItem item) async {
    final db = await database;
    return await db.insert(
      'downloads',
      item.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DownloadItem>> getDownloads() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('downloads');
    return List.generate(maps.length, (i) {
      return DownloadItem.fromJson(maps[i]);
    });
  }

  Future<int> updateDownload(DownloadItem item) async {
    final db = await database;
    return await db.update(
      'downloads',
      item.toJson(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteDownload(String id) async {
    final db = await database;
    return await db.delete(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('downloads');
  }
}
