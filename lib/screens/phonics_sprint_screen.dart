import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/resource_item.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/phonics_local_db.dart';
import '../services/sound_feedback.dart';
import '../widgets/smart_image.dart';
import '../widgets/debug_file_label.dart';
import '../widgets/phonics_bottom_links.dart';

// Two genuinely separate quiz types - NOT mixed together in one session:
//   soundsOnly    - clue is a SOUND's own audio; options are 4 sound
//                   symbols (text). Tests pure sound -> symbol recognition,
//                   no words involved at all.
//   wordsPictures - clue is a WORD's own audio; options are 4 word
//                   pictures. Tests vocabulary recognition, no phonics
//                   symbols involved at all.
enum PhonicsSprintMode { soundsOnly, wordsPictures }

class _SprintQuestion {
  final int testedId; // sound id (soundsOnly) or word id (wordsPictures)
  final int loggedSoundResourceId; // which sound this counts against in the DB
  final String clueAudioUrl;
  final List<String> textOptions; // soundsOnly
  final List<ResourceItem> imageOptions; // wordsPictures
  final int correctOptionIndex;

  _SprintQuestion({
    required this.testedId,
    required this.loggedSoundResourceId,
    required this.clueAudioUrl,
    this.textOptions = const [],
    this.imageOptions = const [],
    required this.correctOptionIndex,
  });
}

class PhonicsSprintScreen extends StatefulWidget {
  final List<ResourceItem> allItems;
  final PhonicsSprintMode mode;
  final int questionCount;

  const PhonicsSprintScreen({
    super.key,
    required this.allItems,
    required this.mode,
    this.questionCount = 10,
  });

  @override
  State<PhonicsSprintScreen> createState() => _PhonicsSprintScreenState();
}

class _PhonicsSprintScreenState extends State<PhonicsSprintScreen> {
  static const _soundsBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/sounds';
  static const _imagesBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/images';
  static const int _timerDuration = 15;

  final AudioPlayer _player = AudioPlayer();
  late List<_SprintQuestion> _questions;
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _answered = false;
  int _lastAutoPlayedIndex = -1;

  int _correctCount = 0;
  int _streak = 0;
  int _bestStreak = 0;

  Timer? _questionTimer;
  int _secondsRemaining = _timerDuration;
  bool _isExpertMode = false;
  int get _effectiveTimerDuration => _isExpertMode ? (_timerDuration / 2).round() : _timerDuration;

  String get _screenTitle =>
      widget.mode == PhonicsSprintMode.soundsOnly ? 'Sounds Sprint' : 'Words & Pictures Sprint';

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions();
    _initDifficultyThenStartTimer();
  }

  Future<void> _initDifficultyThenStartTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isExpert = prefs.getBool('quizExpertMode') ?? false;
    if (mounted) setState(() => _isExpertMode = isExpert);
    _startTimer();
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _startTimer() {
    _questionTimer?.cancel();
    _secondsRemaining = _effectiveTimerDuration;
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (_answered) return;
    setState(() {
      _answered = true;
      _selectedIndex = null;
      _streak = 0;
    });
    SoundFeedback.playWrong();
    _logCurrentQuestion(false);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _nextQuestion();
    });
  }

  List<_SprintQuestion> _buildQuestions() {
    final rnd = Random();
    final questions = <_SprintQuestion>[];
    final usedIds = <int>{};

    if (widget.mode == PhonicsSprintMode.soundsOnly) {
      final sounds = widget.allItems.where((i) => i.isFolder && i.parentId == 0).toList();
      // ignore: avoid_print
      print('DEBUG PhonicsSprintScreen (soundsOnly): pool size = ${sounds.length} (should be 44)');

      var attempts = 0;
      while (questions.length < widget.questionCount && attempts < widget.questionCount * 20) {
        attempts++;
        final candidates = sounds.where((s) => !usedIds.contains(s.id)).toList();
        if (candidates.isEmpty) break;
        final sound = candidates[rnd.nextInt(candidates.length)];

        final wrongPool = sounds.where((s) => s.id != sound.id).toList()..shuffle(rnd);
        if (wrongPool.length < 3) continue;
        final wrongTitles = wrongPool.take(3).map((s) => s.title).toList();
        final options = [...wrongTitles, sound.title]..shuffle(rnd);
        final correctIndex = options.indexOf(sound.title);

        usedIds.add(sound.id);
        questions.add(_SprintQuestion(
          testedId: sound.id,
          loggedSoundResourceId: sound.id,
          clueAudioUrl: sound.audioUrl,
          textOptions: options,
          correctOptionIndex: correctIndex,
        ));
      }
    } else {
      final allWords = widget.allItems.where((i) => !i.isFolder && i.imageUrl.isNotEmpty).toList();
      // ignore: avoid_print
      print('DEBUG PhonicsSprintScreen (wordsPictures): pool size = ${allWords.length} (should be 88)');

      var attempts = 0;
      while (questions.length < widget.questionCount && attempts < widget.questionCount * 20) {
        attempts++;
        final candidates = allWords.where((w) => !usedIds.contains(w.id)).toList();
        if (candidates.isEmpty) break;
        final word = candidates[rnd.nextInt(candidates.length)];

        final wrongPool = allWords.where((w) => w.id != word.id).toList()..shuffle(rnd);
        if (wrongPool.length < 3) continue;
        final wrongOptions = wrongPool.take(3).toList();
        final options = [...wrongOptions, word]..shuffle(rnd);
        final correctIndex = options.indexWhere((w) => w.id == word.id);

        usedIds.add(word.id);
        questions.add(_SprintQuestion(
          testedId: word.id,
          loggedSoundResourceId: word.parentId,
          clueAudioUrl: word.audioUrl,
          imageOptions: options,
          correctOptionIndex: correctIndex,
        ));
      }
    }

    return questions;
  }

  Future<void> _playClue(String audioUrl) async {
    if (audioUrl.isEmpty) return;
    try {
      await _player.stop();
      final localPath = await ContentPackageService.instance.resolveLocalSoundPath(audioUrl);
      if (localPath != null) {
        await _player.play(DeviceFileSource(localPath));
      } else {
        await _player.play(UrlSource('$_soundsBaseUrl/$audioUrl'));
      }
    } catch (e) {
      // ignore
    }
  }

  void _logCurrentQuestion(bool correct) {
    final q = _questions[_currentIndex];
    final quizTypeKey = widget.mode == PhonicsSprintMode.soundsOnly ? 'sprintSoundsOnly' : 'sprintWordsPictures';
    PhonicsLocalDb.instance.saveResult(
      soundResourceId: q.loggedSoundResourceId,
      quizType: quizTypeKey,
      totalQuiz: 1,
      totalCorrect: correct ? 1 : 0,
      totalWrong: correct ? 0 : 1,
      correctResourceIds: correct ? [q.testedId] : [],
      wrongResourceIds: correct ? [] : [q.testedId],
      percentage: correct ? 100 : 0,
    );
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    _questionTimer?.cancel();
    final q = _questions[_currentIndex];
    final isCorrect = index == q.correctOptionIndex;

    setState(() {
      _answered = true;
      _selectedIndex = index;
      if (isCorrect) {
        _correctCount++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    isCorrect ? SoundFeedback.playCorrect() : SoundFeedback.playWrong();

    _logCurrentQuestion(isCorrect);

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _nextQuestion();
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _selectedIndex = null;
      });
      _startTimer();
    } else {
      _finishSprint();
    }
  }

  Future<void> _finishSprint() async {
    // All rows already saved locally per-question as we went - just kick
    // off a sync now that the session is done.
    ApiService().syncPendingPhonicsResults();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sprint complete! 🎉'),
        content: Text(
          'Score: $_correctCount / ${_questions.length}\nBest streak: $_bestStreak 🔥',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              setState(() {
                _questions = _buildQuestions();
                _currentIndex = 0;
                _answered = false;
                _selectedIndex = null;
                _correctCount = 0;
                _streak = 0;
                _bestStreak = 0;
              });
              _startTimer();
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(); // sprint screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer() {
    final isLow = _secondsRemaining <= 3;
    return Column(
      children: [
        Text(
          '$_secondsRemaining',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isLow ? Colors.red : Colors.black87,
          ),
        ),
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            value: _secondsRemaining / _effectiveTimerDuration,
            color: isLow ? Colors.red : Colors.blue,
            backgroundColor: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_screenTitle)),
        body: const Center(child: Text('Not enough content to build a sprint yet.')),
        bottomNavigationBar: const DebugFileLabel(fileName: 'phonics_sprint_screen.dart'),
      );
    }

    final q = _questions[_currentIndex];

    if (!_answered && _lastAutoPlayedIndex != _currentIndex) {
      _lastAutoPlayedIndex = _currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playClue(q.clueAudioUrl);
      });
    }

    return Scaffold(
      key: ValueKey(_currentIndex),
      appBar: AppBar(title: Text(_screenTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question ${_currentIndex + 1} of ${_questions.length}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 4),
                    Text(
                      '$_streak',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTimer(),
            const SizedBox(height: 16),
            IconButton(
              icon: const Icon(Icons.volume_up, size: 56),
              onPressed: () => _playClue(q.clueAudioUrl),
            ),
            const Text('Tap to listen again'),
            const SizedBox(height: 24),
            widget.mode == PhonicsSprintMode.soundsOnly
                ? _buildTextOptions(q)
                : _buildImageOptions(q),
            PhonicsBottomLinks(
              allItems: widget.allItems,
              showPhonicsQuiz: widget.mode != PhonicsSprintMode.soundsOnly,
              showWordQuiz: widget.mode != PhonicsSprintMode.wordsPictures,
            ),
          ],
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'phonics_sprint_screen.dart'),
    );
  }

  Widget _buildTextOptions(_SprintQuestion q) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: List.generate(q.textOptions.length, (index) {
        Color? backgroundColor;
        if (_answered) {
          if (index == q.correctOptionIndex) {
            backgroundColor = Colors.green.shade200;
          } else if (index == _selectedIndex) {
            backgroundColor = Colors.red.shade200;
          }
        }
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _selectAnswer(index),
          child: Text(q.textOptions[index], style: const TextStyle(fontSize: 22)),
        );
      }),
    );
  }

  Widget _buildImageOptions(_SprintQuestion q) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: List.generate(q.imageOptions.length, (index) {
        Color? borderColor;
        if (_answered) {
          if (index == q.correctOptionIndex) {
            borderColor = Colors.green;
          } else if (index == _selectedIndex) {
            borderColor = Colors.red;
          }
        }
        final item = q.imageOptions[index];
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: borderColor != null ? BorderSide(color: borderColor, width: 3) : BorderSide.none,
            ),
          ),
          onPressed: () => _selectAnswer(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SmartImage(
              url: '$_imagesBaseUrl/${item.imageUrl}',
              errorWidget: const Icon(Icons.spellcheck, size: 40, color: Color(0xFF800000)),
            ),
          ),
        );
      }),
    );
  }
}
