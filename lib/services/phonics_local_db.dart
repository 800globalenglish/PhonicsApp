import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// ============================================================================
// Local offline-first queue for Phonics quiz results, mirroring the pattern
// used by the 800 app's LocalDb (detailed_noun_quiz_results /
// detailed_grammar_quiz_results): every finished quiz is saved locally FIRST
// with synced = 0, then ApiService.syncPendingResults() uploads whatever's
// still unsynced whenever the app has a connection. This means quizzes work
// fully offline - the person always sees their own result immediately, and
// syncing to the server (SubmitPhonicsQuizResult) is a background concern
// that can succeed now, later, or after a retry, without ever blocking or
// losing the local result.
// ============================================================================

class PhonicsLocalDb {
  static final PhonicsLocalDb instance = PhonicsLocalDb._internal();
  static Database? _db;

  PhonicsLocalDb._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'phonics.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE phonics_quiz_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        soundResourceId INTEGER,
        quizType TEXT,
        totalQuiz INTEGER,
        totalCorrect INTEGER,
        totalWrong INTEGER,
        correctResourceIds TEXT,
        wrongResourceIds TEXT,
        percentage REAL,
        completedAt TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');
  }

  // ---------- SAVE (always local-first) ----------

  Future<void> saveResult({
    required int soundResourceId,
    required String quizType,
    required int totalQuiz,
    required int totalCorrect,
    required int totalWrong,
    required List<int> correctResourceIds,
    required List<int> wrongResourceIds,
    required double percentage,
  }) async {
    final db = await database;
    await db.insert(
      'phonics_quiz_results',
      {
        'soundResourceId': soundResourceId,
        'quizType': quizType,
        'totalQuiz': totalQuiz,
        'totalCorrect': totalCorrect,
        'totalWrong': totalWrong,
        'correctResourceIds': correctResourceIds.join(','),
        'wrongResourceIds': wrongResourceIds.join(','),
        'percentage': percentage,
        'completedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      },
    );
  }

  // ---------- SYNC QUEUE ----------

  Future<List<Map<String, dynamic>>> getUnsyncedResults() async {
    final db = await database;
    return await db.query('phonics_quiz_results', where: 'synced = 0');
  }

  Future<void> markResultSynced(int id) async {
    final db = await database;
    await db.update(
      'phonics_quiz_results',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- READING RESULTS (for showing status in the UI) ----------

  // Best (highest) score ever recorded for a given sound, across all
  // attempts - used to show a percentage/checkmark on the sound's row,
  // similar to how the 800 app's quiz hub shows a score per quiz type.
  Future<double?> getBestScoreFor(int soundResourceId, String quizType) async {
    final db = await database;
    final rows = await db.query(
      'phonics_quiz_results',
      where: 'soundResourceId = ? AND quizType = ?',
      whereArgs: [soundResourceId, quizType],
      orderBy: 'percentage DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['percentage'] as double;
  }

  // Every attempt for a sound, most recent first - useful for a history view
  // later, even though the current UI only shows the best score.
  Future<List<Map<String, dynamic>>> getAllResultsFor(int soundResourceId, String quizType) async {
    final db = await database;
    return await db.query(
      'phonics_quiz_results',
      where: 'soundResourceId = ? AND quizType = ?',
      whereArgs: [soundResourceId, quizType],
      orderBy: 'completedAt DESC',
    );
  }

  // Every result row on this device, regardless of sound/quizType/synced
  // status - used as the offline fallback for the "My Results" screen when
  // fetching from the server isn't possible.
  Future<List<Map<String, dynamic>>> getAllResults() async {
    final db = await database;
    return await db.query('phonics_quiz_results');
  }
}
