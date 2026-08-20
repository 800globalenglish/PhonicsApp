import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/resource_item.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/phonics_local_db.dart';
import '../widgets/smart_image.dart';
import '../services/sound_feedback.dart';

enum PhonicsQuizMode { wordToSound, soundToWord }

// One question, regardless of mode. For wordToSound: audioUrl is the WORD's
// audio, correctOptionText is the sound's symbol, options are text (sound
// symbols). For soundToWord: audioUrl is the SOUND's audio, options are
// word items shown as images, and the "correct" one is whichever word this
// question is testing.
class _PhonicsQuizQuestion {
  final int testedWordId; // always a word id - what we're logging as correct/wrong
  final String clueAudioUrl;
  final List<ResourceItem> imageOptions; // used only for soundToWord
  final List<String> textOptions; // used only for wordToSound
  final int correctOptionIndex;

  _PhonicsQuizQuestion({
    required this.testedWordId,
    required this.clueAudioUrl,
    this.imageOptions = const [],
    this.textOptions = const [],
    required this.correctOptionIndex,
  });
}

class PhonicsQuizScreen extends StatefulWidget {
  final ResourceItem sound;
  final List<ResourceItem> words; // this sound's own 1-2 words
  final List<ResourceItem> allItems; // full tree - used to source wrong answers
  final PhonicsQuizMode mode;

  const PhonicsQuizScreen({
    super.key,
    required this.sound,
    required this.words,
    required this.allItems,
    required this.mode,
  });

  @override
  State<PhonicsQuizScreen> createState() => _PhonicsQuizScreenState();
}

class _PhonicsQuizScreenState extends State<PhonicsQuizScreen> {
  static const _soundsBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/sounds';
  static const _imagesBaseUrl = 'https://cdn.800globalenglish.com/content/phonics/images';

  final AudioPlayer _player = AudioPlayer();
  late List<_PhonicsQuizQuestion> _questions;
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _answered = false;
  int _lastAutoPlayedIndex = -1;

  final List<int> _correctWordIds = [];
  final List<int> _wrongWordIds = [];

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  List<_PhonicsQuizQuestion> _buildQuestions() {
    final rnd = Random();
    final questions = <_PhonicsQuizQuestion>[];

    if (widget.mode == PhonicsQuizMode.wordToSound) {
      // All OTHER sounds (folders), excluding this one - their titles are
      // the wrong-answer pool.
      final otherSounds = widget.allItems
          .where((i) => i.isFolder && i.id != widget.sound.id)
          .toList();

      for (final word in widget.words) {
        final wrongPool = [...otherSounds]..shuffle(rnd);
        final wrongTitles = wrongPool.take(3).map((s) => s.title).toList();
        final options = [...wrongTitles, widget.sound.title]..shuffle(rnd);
        final correctIndex = options.indexOf(widget.sound.title);

        questions.add(_PhonicsQuizQuestion(
          testedWordId: word.id,
          clueAudioUrl: word.audioUrl,
          textOptions: options,
          correctOptionIndex: correctIndex,
        ));
      }
    } else {
      // Wrong-answer pool: every word EXCEPT this sound's own words.
      final ownWordIds = widget.words.map((w) => w.id).toSet();
      final otherWords = widget.allItems
          .where((i) => !i.isFolder && !ownWordIds.contains(i.id) && i.imageUrl.isNotEmpty)
          .toList();

      for (final word in widget.words) {
        final wrongPool = [...otherWords]..shuffle(rnd);
        final wrongOptions = wrongPool.take(3).toList();
        final options = [...wrongOptions, word]..shuffle(rnd);
        final correctIndex = options.indexWhere((w) => w.id == word.id);

        questions.add(_PhonicsQuizQuestion(
          testedWordId: word.id,
          clueAudioUrl: widget.sound.audioUrl,
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

  void _selectAnswer(int index) {
    if (_answered) return;
    final question = _questions[_currentIndex];
    final isCorrect = index == question.correctOptionIndex;

    setState(() {
      _answered = true;
      _selectedIndex = index;
      if (isCorrect) {
        _correctWordIds.add(question.testedWordId);
      } else {
        _wrongWordIds.add(question.testedWordId);
      }
    });

    isCorrect ? SoundFeedback.playCorrect() : SoundFeedback.playWrong();

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
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final total = _questions.length;
    final correct = _correctWordIds.length;
    final percentage = total == 0 ? 0.0 : (correct / total) * 100;
    final quizTypeKey = widget.mode == PhonicsQuizMode.wordToSound ? 'wordToSound' : 'soundToWord';

    await PhonicsLocalDb.instance.saveResult(
      soundResourceId: widget.sound.id,
      quizType: quizTypeKey,
      totalQuiz: total,
      totalCorrect: correct,
      totalWrong: total - correct,
      correctResourceIds: _correctWordIds,
      wrongResourceIds: _wrongWordIds,
      percentage: percentage,
    );

    // Fire-and-forget - the result is already safe locally either way.
    ApiService().syncPendingPhonicsResults();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Quiz complete'),
        content: Text('Score: ${percentage.toStringAsFixed(0)}%\n($correct out of $total correct)'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(); // quiz screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const Center(child: Text('Not enough content to build a quiz yet.')),
      );
    }

    final question = _questions[_currentIndex];

    if (!_answered && _lastAutoPlayedIndex != _currentIndex) {
      _lastAutoPlayedIndex = _currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playClue(question.clueAudioUrl);
      });
    }

    final isWordToSound = widget.mode == PhonicsQuizMode.wordToSound;

    return Scaffold(
      key: ValueKey(_currentIndex),
      appBar: AppBar(
        title: Text(isWordToSound ? 'Which sound?' : 'Which word?'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Question ${_currentIndex + 1} of ${_questions.length}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            IconButton(
              icon: const Icon(Icons.volume_up, size: 56),
              onPressed: () => _playClue(question.clueAudioUrl),
            ),
            const Text('Tap to listen again'),
            const SizedBox(height: 24),
            Expanded(
              child: isWordToSound
                  ? _buildTextOptions(question)
                  : _buildImageOptions(question),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextOptions(_PhonicsQuizQuestion question) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: List.generate(question.textOptions.length, (index) {
        Color? backgroundColor;
        if (_answered) {
          if (index == question.correctOptionIndex) {
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
          child: Text(question.textOptions[index], style: const TextStyle(fontSize: 22)),
        );
      }),
    );
  }

  Widget _buildImageOptions(_PhonicsQuizQuestion question) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: List.generate(question.imageOptions.length, (index) {
        Color? borderColor;
        if (_answered) {
          if (index == question.correctOptionIndex) {
            borderColor = Colors.green;
          } else if (index == _selectedIndex) {
            borderColor = Colors.red;
          }
        }
        final item = question.imageOptions[index];
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
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