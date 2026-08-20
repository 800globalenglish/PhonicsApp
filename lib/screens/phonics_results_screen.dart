import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/resource_item.dart';
import '../services/api_service.dart';
import '../services/phonics_local_db.dart';
import 'phonics_practice_screen.dart';
import '../widgets/debug_file_label.dart';
import '../widgets/phonics_bottom_links.dart';

// ============================================================================
// Shows a 4-column report card: Symbol | Sound (practice completion) |
// Phonics Quiz | Word Quiz. Symbol is a tappable link straight to that
// sound's practice page.
//
// "Sound" reflects PRACTICE completion (the checkmarks from
// PhonicsPracticeScreen - phonicsCompletedIds), NOT quiz accuracy. A sound
// counts as fully practiced only once the sound card itself AND both its
// words have all been passed.
//
// The two quiz columns aggregate every logged question-row per (sound,
// quizType) pair into a single correct/total count, since each quiz
// question is saved as its own row rather than one row per session.
//
// Tries the server first (GetPhonicsProgress via ApiService), so quiz
// results show up correctly even on a fresh install / different device.
// Falls back to the local on-device queue (PhonicsLocalDb) if offline or
// the server call fails.
// ============================================================================

class _SoundStats {
  int correct = 0;
  int total = 0;

  double? get percentage => total == 0 ? null : (correct / total) * 100;
}

class PhonicsResultsScreen extends StatefulWidget {
  final List<ResourceItem> allItems;

  const PhonicsResultsScreen({super.key, required this.allItems});

  @override
  State<PhonicsResultsScreen> createState() => _PhonicsResultsScreenState();
}

class _PhonicsResultsScreenState extends State<PhonicsResultsScreen> {
  static const _completedPrefsKey = 'phonicsCompletedIds';

  bool _loading = true;
  bool _usingLocalFallback = false;
  final Map<int, Map<String, _SoundStats>> _statsBySound = {};
  Set<int> _completedIds = {};

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_completedPrefsKey) ?? [];
    final completedIds = saved.map((s) => int.tryParse(s)).whereType<int>().toSet();

    List<Map<String, dynamic>>? rows = await ApiService().fetchPhonicsProgress();
    var usedFallback = false;

    if (rows == null) {
      rows = await PhonicsLocalDb.instance.getAllResults();
      usedFallback = true;
    }

    _statsBySound.clear();
    for (final row in rows) {
      final soundId = row['soundResourceId'] as int;
      final quizType = row['quizType'] as String;
      final totalQuiz = row['totalQuiz'] as int;
      final totalCorrect = row['totalCorrect'] as int;

      _statsBySound.putIfAbsent(soundId, () => {});
      final stats = _statsBySound[soundId]!.putIfAbsent(quizType, () => _SoundStats());
      stats.total += totalQuiz;
      stats.correct += totalCorrect;
    }

    if (!mounted) return;
    setState(() {
      _completedIds = completedIds;
      _loading = false;
      _usingLocalFallback = usedFallback;
    });
  }

  List<ResourceItem> get _soundsInOrder {
    final sounds = widget.allItems.where((i) => i.isFolder && i.parentId == 0).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sounds;
  }

  List<ResourceItem> _wordsFor(ResourceItem sound) {
    return widget.allItems.where((i) => !i.isFolder && i.parentId == sound.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  bool _isFullyPracticed(ResourceItem sound) {
    if (!_completedIds.contains(sound.id)) return false;
    final words = _wordsFor(sound);
    if (words.isEmpty) return false;
    return words.every((w) => _completedIds.contains(w.id));
  }

  void _openSound(ResourceItem sound) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhonicsPracticeScreen(
          sound: sound,
          words: _wordsFor(sound),
          allItems: widget.allItems,
        ),
      ),
    );
  }

  Widget _buildAccuracyChip(_SoundStats? stats, Color color) {
    if (stats == null || stats.total == 0) {
      return Chip(
        label: const Text('—', style: TextStyle(fontSize: 11)),
        backgroundColor: Colors.grey.shade200,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    final pct = stats.percentage!;
    return Chip(
      label: Text(
        '${pct.toStringAsFixed(0)}% (${stats.correct}/${stats.total})',
        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
      ),
      backgroundColor: color.withOpacity(pct >= 70 ? 1.0 : 0.55),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Results')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_usingLocalFallback)
            Container(
              width: double.infinity,
              color: Colors.amber.shade50,
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Offline — showing results saved on this device only. Some history from other devices may be missing.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Symbol', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(
                  flex: 1,
                  child: Text('Sound', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Phonics Quiz', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Word Quiz', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _soundsInOrder.length,
              itemBuilder: (context, index) {
                final sound = _soundsInOrder[index];
                final soundStats = _statsBySound[sound.id]?['sprintSoundsOnly'];
                final wordStats = _statsBySound[sound.id]?['sprintWordsPictures'];
                final practiced = _isFullyPracticed(sound);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () => _openSound(sound),
                          child: Text(
                            sound.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Icon(
                            practiced ? Icons.check_circle : Icons.check_circle_outline,
                            color: practiced ? Colors.green : Colors.grey.shade300,
                            size: 22,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Center(child: _buildAccuracyChip(soundStats, Colors.orange.shade600)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Center(child: _buildAccuracyChip(wordStats, Colors.deepPurple.shade400)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PhonicsBottomLinks(allItems: widget.allItems),
          ),
        ],
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'phonics_results_screen.dart'),
    );
  }
}

