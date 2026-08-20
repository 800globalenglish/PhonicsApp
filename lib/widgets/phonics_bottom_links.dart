import 'package:flutter/material.dart';
import '../models/resource_item.dart';
import '../screens/resource_browser_screen.dart';
import '../screens/phonics_sprint_screen.dart';
import '../screens/splash_screen.dart';
import '../services/api_service.dart';

// ============================================================================
// The same four navigation links (Phonics List / Phonics Quiz / Word Quiz /
// Home), reused at the bottom of every Phonics screen so there's always a
// way out. Each page hides its OWN link (e.g. the sound list doesn't show
// "Phonics List", the Sounds quiz doesn't show "Phonics Quiz") since tapping
// a link to the page you're already on doesn't make sense.
// ============================================================================

class PhonicsBottomLinks extends StatelessWidget {
  final List<ResourceItem> allItems;
  final bool showList;
  final bool showPhonicsQuiz;
  final bool showWordQuiz;
  final VoidCallback? onList; // override the default "List" action if needed

  const PhonicsBottomLinks({
    super.key,
    required this.allItems,
    this.showList = true,
    this.showPhonicsQuiz = true,
    this.showWordQuiz = true,
    this.onList,
  });

  void _defaultOpenList(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResourceBrowserScreen(
          pageId: phonicsPageId,
          screenTitle: 'Phonics',
        ),
      ),
    );
  }

  void _openSprint(BuildContext context, PhonicsSprintMode mode) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PhonicsSprintScreen(allItems: allItems, mode: mode),
      ),
    );
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          if (showList)
            OutlinedButton.icon(
              icon: const Icon(Icons.list),
              label: const Text('Phonics List'),
              onPressed: () => (onList ?? () => _defaultOpenList(context))(),
            ),
          if (showPhonicsQuiz)
            OutlinedButton.icon(
              icon: const Text('🔥', style: TextStyle(fontSize: 16)),
              label: const Text('Phonics Quiz'),
              onPressed: () => _openSprint(context, PhonicsSprintMode.soundsOnly),
            ),
          if (showWordQuiz)
            OutlinedButton.icon(
              icon: const Text('🖼️', style: TextStyle(fontSize: 16)),
              label: const Text('Word Quiz'),
              onPressed: () => _openSprint(context, PhonicsSprintMode.wordsPictures),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.home),
            label: const Text('Home'),
            onPressed: () => _goHome(context),
          ),
        ],
      ),
    );
  }
}
