import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/resource_item.dart';
import '../services/content_package_service.dart';
import '../widgets/smart_image.dart';
import '../widgets/debug_file_label.dart';
import 'phonics_sprint_screen.dart';
import 'splash_screen.dart';

// ============================================================================
// Combined Phonics practice screen: shows one sound (e.g. /b/) together with
// its words (e.g. "bat", "ball") - but only ONE at a time, big and centered.
// Starting with the sound itself, then each word in turn: record, compare,
// Pass. The moment something passes, it collapses into a small text pill in
// a strip at the top (tap it to un-pass and redo), and whatever's next
// grows into the big active card automatically. Once everything's passed,
// a simple "All done!" state shows instead.
//
// The app bar shows a three-part layout: PREVIOUS sound (smaller, left,
// tappable) - CURRENT sound (larger, centered) - NEXT sound (smaller,
// right, tappable). Uses Navigator.pushReplacement so the back stack
// doesn't grow with every hop.
//
// Quiz access lives only on the splash screen - no quiz buttons here.
//
// Checkmarks use the exact same SharedPreferences key/format as
// ResourceBrowserScreen (_completedPrefsKey = 'phonicsCompletedIds'), so the
// parent sound's own checkmark AND its auto-derived "all words done" folder
// checkmark both keep working without any changes there. Completion ORDER
// (_completedOrderPrefsKey = 'phonicsCompletedOrder') is also recorded here,
// so ResourceBrowserScreen's "last completed" footer stays accurate.
// ============================================================================

class PhonicsPracticeScreen extends StatefulWidget {
  final ResourceItem sound;
  final List<ResourceItem> words;
  final List<ResourceItem> allItems;

  const PhonicsPracticeScreen({
    super.key,
    required this.sound,
    required this.words,
    required this.allItems,
  });

  @override
  State<PhonicsPracticeScreen> createState() => _PhonicsPracticeScreenState();
}

class _PhonicsPracticeScreenState extends State<PhonicsPracticeScreen> {
  static const _completedPrefsKey = 'phonicsCompletedIds';
  static const _completedOrderPrefsKey = 'phonicsCompletedOrder';
  static const _soundsBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/sounds';
  static const _imagesBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/images';

  Set<int> _completedIds = {};
  List<int> _completedOrder = [];

  @override
  void initState() {
    super.initState();
    _loadCompletedIds();
  }

  Future<void> _loadCompletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_completedPrefsKey) ?? [];
    final ids = saved.map((s) => int.tryParse(s)).whereType<int>().toSet();
    final savedOrder = prefs.getStringList(_completedOrderPrefsKey) ?? [];
    final order = savedOrder.map((s) => int.tryParse(s)).whereType<int>().toList();
    if (mounted) {
      setState(() {
        _completedIds = ids;
        _completedOrder = order;
      });
    }
  }

  Future<void> _setCompleted(int id, bool completed) async {
    setState(() {
      if (completed) {
        _completedIds.add(id);
        _completedOrder.remove(id); // avoid duplicate entries if re-graded
        _completedOrder.add(id);
      } else {
        _completedIds.remove(id);
        _completedOrder.remove(id);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedPrefsKey, _completedIds.map((i) => i.toString()).toList());
    await prefs.setStringList(_completedOrderPrefsKey, _completedOrder.map((i) => i.toString()).toList());
  }

  // All 44 sounds, in official order - used to figure out what's before/after.
  List<ResourceItem> get _allSoundsInOrder {
    final sounds = widget.allItems.where((i) => i.isFolder && i.parentId == 0).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sounds;
  }

  int get _currentIndex => _allSoundsInOrder.indexWhere((s) => s.id == widget.sound.id);

  ResourceItem? get _previousSound {
    final sounds = _allSoundsInOrder;
    final index = _currentIndex;
    if (index <= 0) return null;
    return sounds[index - 1];
  }

  ResourceItem? get _nextSound {
    final sounds = _allSoundsInOrder;
    final index = _currentIndex;
    if (index < 0 || index >= sounds.length - 1) return null;
    return sounds[index + 1];
  }

  void _goToSound(ResourceItem target) {
    final targetWords = widget.allItems
        .where((i) => !i.isFolder && i.parentId == target.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PhonicsPracticeScreen(
          sound: target,
          words: targetWords,
          allItems: widget.allItems,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previousSound;
    final next = _nextSound;

    // Sound first, then words in order - the sequence someone works through.
    final allThree = [widget.sound, ...widget.words];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: previous != null ? () => _goToSound(previous) : null,
                  child: Row(
                    children: [
                      if (previous != null) const Icon(Icons.arrow_back_ios, size: 12),
                      Flexible(
                        child: Text(
                          previous?.title ?? '',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                widget.sound.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: next != null ? () => _goToSound(next) : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          next?.title ?? '',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      if (next != null) const Icon(Icons.arrow_forward_ios, size: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            for (var i = 0; i < allThree.length; i++) ...[
              _WordPracticeCard(
                key: ValueKey(allThree[i].id),
                word: allThree[i],
                imagesBaseUrl: _imagesBaseUrl,
                soundsBaseUrl: _soundsBaseUrl,
                isCompleted: _completedIds.contains(allThree[i].id),
                onGraded: (passed) => _setCompleted(allThree[i].id, passed),
                onTapCollapsed: () => _setCompleted(allThree[i].id, false),
                isPrimary: allThree[i].id == widget.sound.id,
              ),
              const SizedBox(height: 16),
              const Divider(thickness: 1.5, height: 1),
              const SizedBox(height: 16),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.list),
                  label: const Text('Phonics List'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                OutlinedButton.icon(
                  icon: const Text('🔥', style: TextStyle(fontSize: 16)),
                  label: const Text('Phonics Quiz'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PhonicsSprintScreen(
                          allItems: widget.allItems,
                          mode: PhonicsSprintMode.soundsOnly,
                        ),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Text('🖼️', style: TextStyle(fontSize: 16)),
                  label: const Text('Word Quiz'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PhonicsSprintScreen(
                          allItems: widget.allItems,
                          mode: PhonicsSprintMode.wordsPictures,
                        ),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.home),
                  label: const Text('Home'),
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SplashScreen()),
                        (route) => false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'phonics_practice_screen.dart'),
    );
  }
}

// One item's (sound OR word) card. When not yet passed, shows big and
// centered: title above image (200px for words, no image for the sound,
// whose title renders at 100px). Once passed, shrinks IN PLACE to a small
// tappable row (still part of the normal scroll flow, not moved elsewhere)
// - so scrolling always reveals what's coming next, and tapping a
// collapsed row reopens it for another attempt.
class _WordPracticeCard extends StatefulWidget {
  final ResourceItem word;
  final String imagesBaseUrl;
  final String soundsBaseUrl;
  final bool isCompleted;
  final ValueChanged<bool> onGraded; // true = passed, false = failed
  final VoidCallback onTapCollapsed; // reopen a passed item
  final bool isPrimary; // true for the sound card - 100px text, no image

  const _WordPracticeCard({
    super.key,
    required this.word,
    required this.imagesBaseUrl,
    required this.soundsBaseUrl,
    required this.isCompleted,
    required this.onGraded,
    required this.onTapCollapsed,
    this.isPrimary = false,
  });

  @override
  State<_WordPracticeCard> createState() => _WordPracticeCardState();
}

class _WordPracticeCardState extends State<_WordPracticeCard> {
  final AudioPlayer _myRecordingPlayer = AudioPlayer();
  final AudioPlayer _nativePlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordingPath;
  bool _isComparing = false;
  bool _isPaused = false;
  Completer<void>? _activePlaybackCompleter;

  @override
  void dispose() {
    _isComparing = false;
    _myRecordingPlayer.dispose();
    _nativePlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _playAndWait(AudioPlayer player, Source source) async {
    await player.release();
    final completer = Completer<void>();
    _activePlaybackCompleter = completer;

    late StreamSubscription sub;
    sub = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    await player.play(source);
    await completer.future;
    await sub.cancel();

    if (identical(_activePlaybackCompleter, completer)) {
      _activePlaybackCompleter = null;
    }
  }

  Future<void> _playMyRecordingAndWait() async {
    if (_recordingPath == null) return;
    final file = File(_recordingPath!);
    if (!await file.exists()) return;
    await _playAndWait(_myRecordingPlayer, DeviceFileSource(_recordingPath!));
  }

  Future<Source> _nativeAudioSource() async {
    final localPath = await ContentPackageService.instance.resolveLocalSoundPath(widget.word.audioUrl);
    if (localPath != null) return DeviceFileSource(localPath);
    return UrlSource('${widget.soundsBaseUrl}/${widget.word.audioUrl}');
  }

  Future<void> _playNativeAndWait() async {
    final source = await _nativeAudioSource();
    await _playAndWait(_nativePlayer, source);
  }

  Future<void> _playNativeAudio() async {
    try {
      await _nativePlayer.stop();
      final source = await _nativeAudioSource();
      await _nativePlayer.play(source);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is needed to record.')),
      );
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = widget.word.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final path = '${dir.path}/phonics_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    setState(() {
      _isRecording = true;
      _hasRecording = false;
      _recordingPath = path;
      _isComparing = false;
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _hasRecording = true;
    });
    _startComparisonLoop();
  }

  void _startComparisonLoop() {
    _isComparing = true;
    _isPaused = false;
    _runComparisonLoop();
  }

  Future<void> _runComparisonLoop() async {
    while (_isComparing && mounted) {
      if (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      try {
        await _playMyRecordingAndWait();
      } catch (e) {
        // ignore
      }
      if (!_isComparing || _isPaused || !mounted) continue;
      try {
        await _playNativeAndWait();
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      setState(() => _isPaused = false);
    } else {
      await _myRecordingPlayer.stop();
      await _nativePlayer.stop();
      if (_activePlaybackCompleter != null && !_activePlaybackCompleter!.isCompleted) {
        _activePlaybackCompleter!.complete();
      }
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopComparisonLoop() async {
    _isComparing = false;
    _isPaused = false;
    await _myRecordingPlayer.stop();
    await _nativePlayer.stop();
    if (_activePlaybackCompleter != null && !_activePlaybackCompleter!.isCompleted) {
      _activePlaybackCompleter!.complete();
    }
  }

  Future<void> _grade(bool passed) async {
    await _stopComparisonLoop();
    setState(() {
      _hasRecording = false;
      _recordingPath = null;
    });
    widget.onGraded(passed);
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;

    if (widget.isCompleted) {
      return GestureDetector(
        onTap: widget.onTapCollapsed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                word.title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade700),
              ),
              const Spacer(),
              Text(
                'Tap to redo',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      );
    }

    final titleFontSize = widget.isPrimary ? 60.0 : 28.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          word.title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
        ),
        if (word.otherTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(word.otherTitle, style: const TextStyle(color: Colors.grey)),
          ),
        const SizedBox(height: 8),
        if (!widget.isPrimary && word.imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SmartImage(
              url: '${widget.imagesBaseUrl}/${word.imageUrl}',
              width: 200,
              height: 200,
              errorWidget: const Icon(Icons.spellcheck, size: 80, color: Color(0xFF800000)),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: 56,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: Colors.grey.shade800,
              padding: EdgeInsets.zero,
              elevation: 2,
            ),
            onPressed: _hasRecording ? _togglePause : _playNativeAudio,
            child: Icon(
              _hasRecording && !_isPaused ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_hasRecording)
          ElevatedButton.icon(
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            label: Text(_isRecording ? 'Stop' : 'Record'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording ? Colors.red : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: _isRecording ? _stopRecording : _startRecording,
          ),
        if (_hasRecording) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Fail'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade900,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _grade(false),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Pass'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade100,
                  foregroundColor: Colors.green.shade900,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _grade(true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.mic, size: 18),
            label: const Text('Record again'),
            onPressed: () async {
              await _stopComparisonLoop();
              setState(() {
                _hasRecording = false;
                _recordingPath = null;
              });
            },
          ),
        ],
      ],
    );
  }
}
