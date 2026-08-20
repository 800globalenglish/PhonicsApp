import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'phonics_local_db.dart';

// TEMPORARY — pointed at the DEV site while testing SubmitPhonicsQuizResult
// and GetPhonicsProgress, which only exist there so far. Switch this back
// to https://www.800globalenglish.com before shipping to real users.
const String baseUrl = 'https://www.aibiz4u.com';

// Phonics' single top-level page id in Tradelingo_Page / TradeLingo_Resources.
const int phonicsPageId = 6;

class ApiService {
  // ---------- LOGIN ----------

  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/MobileLogin'),
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', data['token']);
          await prefs.setInt('memberId', data['memberId']);
          await prefs.setString('username', username);
          return true;
        }
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG login error: $e');
      return false;
    }
  }

  Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<bool> isLoggedIn() async {
    final token = await getSavedToken();
    if (token == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final loggedOut = prefs.getBool('isLoggedOut') ?? false;
    return !loggedOut;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedOut', true);
  }

  Future<bool> hasCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final username = prefs.getString('username');
    return token != null && username != null;
  }

  Future<void> resumeOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedOut', false);
  }

  // ---------- RESOURCE TREE (sounds/words/images/audio) ----------

  Future<List<Map<String, dynamic>>?> fetchResourceTree({
    required int pageId,
    required int languageId,
  }) async {
    try {
      final token = await getSavedToken();
      // ignore: avoid_print
      print('DEBUG fetchResourceTree: pageId=$pageId languageId=$languageId token=$token');

      final response = await http.get(Uri.parse(
          '$baseUrl/MobileApi/GetResourceTree?pageId=$pageId&languageId=$languageId&token=$token'));

      // ignore: avoid_print
      print('DEBUG fetchResourceTree: statusCode=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
        // ignore: avoid_print
        print('DEBUG fetchResourceTree: server responded but success=false. Message: ${data['message']}');
        return null;
      }

      // ignore: avoid_print
      print('DEBUG fetchResourceTree: non-200 response body: ${response.body}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG fetchResourceTree error: $e');
      return null; // offline - caller should fall back to cached tree if any
    }
  }

  static String resourceTreeCacheKey(int pageId, int languageId) =>
      'cachedResourceTree_${pageId}_$languageId';

  Future<bool> fetchAndCacheResourceTree({
    required int pageId,
    required int languageId,
  }) async {
    final raw = await fetchResourceTree(pageId: pageId, languageId: languageId);
    if (raw == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(resourceTreeCacheKey(pageId, languageId), jsonEncode(raw));
    return true;
  }

  Future<void> prefetchPhonicsTree(int languageId) async {
    await fetchAndCacheResourceTree(pageId: phonicsPageId, languageId: languageId);
  }

  // ---------- PHONICS QUIZ RESULTS (offline-first, synced in background) ----------

  // Submits ONE quiz result row to the server. Called only from within
  // syncPendingPhonicsResults() below - never call this directly from a quiz
  // screen. The quiz screen should always save to PhonicsLocalDb first (so
  // the result is never lost even if offline), then let this sync loop pick
  // it up whenever there's a connection.
  Future<bool> _submitPhonicsResult(Map<String, dynamic> row, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/SubmitPhonicsQuizResult'),
        body: {
          'token': token,
          'soundResourceId': row['soundResourceId'].toString(),
          'quizType': row['quizType'] as String,
          'totalQuiz': row['totalQuiz'].toString(),
          'totalCorrect': row['totalCorrect'].toString(),
          'totalWrong': row['totalWrong'].toString(),
          'correctResourceIds': (row['correctResourceIds'] as String?) ?? '',
          'wrongResourceIds': (row['wrongResourceIds'] as String?) ?? '',
          'getPercentage': row['percentage'].toString(),
        },
      );
      // ignore: avoid_print
      print('DEBUG submitPhonicsResult status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG submitPhonicsResult ERROR: $e');
      return false;
    }
  }

  // Call this after finishing a quiz (result is already saved locally by
  // then), and also opportunistically elsewhere (app resume, Wi-Fi
  // reconnect, etc.) to catch up on anything that couldn't sync earlier.
  // Safe to call anytime - does nothing if there's no token or nothing
  // pending.
  Future<void> syncPendingPhonicsResults() async {
    final token = await getSavedToken();
    if (token == null) {
      // ignore: avoid_print
      print('DEBUG syncPendingPhonicsResults: no saved token, skipping sync');
      return;
    }

    final unsynced = await PhonicsLocalDb.instance.getUnsyncedResults();
    // ignore: avoid_print
    print('DEBUG syncPendingPhonicsResults: found ${unsynced.length} unsynced results');

    for (final row in unsynced) {
      final success = await _submitPhonicsResult(row, token);
      // ignore: avoid_print
      print('DEBUG phonics sync result for soundResourceId=${row['soundResourceId']} quizType=${row['quizType']}: $success');
      if (success) {
        await PhonicsLocalDb.instance.markResultSynced(row['id'] as int);
      }
    }
  }

  // Pulls the member's phonics quiz history down from the server - useful
  // after logging in on a new device, so past results aren't lost even
  // though they only ever lived in the OTHER device's local database.
  // Returns null on failure (offline, etc.) so callers can just skip
  // merging rather than treating it as an error.
  Future<List<Map<String, dynamic>>?> fetchPhonicsProgress() async {
    final token = await getSavedToken();
    if (token == null) return null;

    try {
      final response = await http.get(Uri.parse('$baseUrl/MobileApi/GetPhonicsProgress?token=$token'));
      if (response.statusCode != 200) {
        // ignore: avoid_print
        print('DEBUG fetchPhonicsProgress: status=${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        // ignore: avoid_print
        print('DEBUG fetchPhonicsProgress: server returned success=false');
        return null;
      }

      return List<Map<String, dynamic>>.from(data['results']);
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG fetchPhonicsProgress ERROR: $e');
      return null;
    }
  }
}