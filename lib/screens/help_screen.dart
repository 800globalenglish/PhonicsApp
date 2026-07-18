import 'package:flutter/material.dart';
import '../services/resource_strings.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  // Each section: a header key, followed by its list of {question, answer} keys.
  // CHANGED — an item can now be {'answer': key} with NO 'question' — in
  // that case the section's header itself becomes the expandable dropdown
  // trigger, and there's no separate bold header line above it (since the
  // header IS the tappable row now).
  static const List<Map<String, dynamic>> _faqSections = [
    {
      'header': 'aiadd4091', // Subscription & Purchasing
      'items': [
        {'question': 'aiadd4037', 'answer': 'aiadd4038'},
      ],
    },
    {
      'header': 'aiadd4040', // Account & Sharing
      'items': [
        {'question': 'aiadd4041', 'answer': 'aiadd4042'},
      ],
    },
    {
      'header': 'Privacy', // Account & Sharing
      'items': [
        {'question': 'aiadd4041', 'answer': 'aiadd4042'},
      ],
    },
    {
      'header': 'aiadd4044', // Quizzes, Oral Exams & Progress
      'items': [
        {'question': 'aiadd4067', 'answer': 'aiadd4068'},
        {'question': 'aiadd4025', 'answer': 'aiadd4026'},
        {'question': 'aiadd4069', 'answer': 'aiadd4070 aiadd4072'},
      ],
    },

    {
      'header': 'aiadd4092',
      'items': [
        {'answer': 'aiadd4093'},
      ],
    },
    {
      'header': 'aiadd4094',
      'items': [
        {'answer': 'aiadd4095'},
      ],
    },
    {
      'header': 'aiadd4096',
      'items': [
        {'answer': 'aiadd4097'},
      ],
    },
    {
      'header': 'aiadd4098',
      'items': [
        {'answer': 'aiadd4099'},
      ],
    },
    {
      'header': 'aiadd4100',
      'items': [
        {'answer': 'aiadd4101'},
      ],
    },
    {
      'header': 'aiadd4052', // Policies & Copyright
      'items': [
        {'question': 'aiadd4053', 'answer': 'aiadd4060'},
        {'question': 'aiadd4055', 'answer': 'aiadd4056'},
        {'question': 'aiadd4057', 'answer': 'aiadd4058'},
      ],
    },
    {
      'header': 'aiadd4047', // Login & Technical Support
      'items': [
        {'question': 'aiadd4048', 'answer': 'aiadd4049'},
        {'question': 'aiadd4050', 'answer': 'aiadd4051'},
      ],
    },
  ];

  // Joins one or more space-separated resource keys in an answer field into
  // paragraphs, same as before.
  String _resolveAnswer(ResourceStrings rs, String answerField) {
    return answerField.split(' ').map((key) => rs.get(key)).join('\n\n');
  }

  Widget _answerCard(ResourceStrings rs, String answerKey) {
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: Card(
        color: Colors.white.withOpacity(0.08),
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _resolveAnswer(rs, answerKey),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResourceStrings.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002E52),
        title: Text(ResourceStrings.instance.get('aiadd2148')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in _faqSections) ...[
                () {
              final items = (section['items'] as List).cast<Map<String, String>>();
              final headerKey = section['header'] as String;

              // NEW — a section with exactly one item that has NO
              // 'question' key: the header itself becomes the expandable
              // dropdown trigger, its answer is the content. No separate
              // bold header line, no crash from a missing question key.
              if (items.length == 1 && !items.first.containsKey('question')) {
                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: Card(
                    color: Colors.white.withOpacity(0.08),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white70,
                      title: Text(
                        rs.get(headerKey),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _resolveAnswer(rs, items.first['answer']!),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Normal case — bold header, then one ExpansionTile per
              // question/answer pair underneath it.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      rs.get(headerKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...items.map(
                        (faq) => Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Card(
                        color: Colors.white.withOpacity(0.08),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          iconColor: Colors.white,
                          collapsedIconColor: Colors.white70,
                          title: Text(
                            rs.get(faq['question']!),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _resolveAnswer(rs, faq['answer']!),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }(),
          ],
          // Closing note — plain text, not a Q&A, so it isn't wrapped in an ExpansionTile
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 24),
            child: Text(
              rs.get('aiadd4059'),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
