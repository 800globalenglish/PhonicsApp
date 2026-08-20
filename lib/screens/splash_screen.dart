import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'content_download_screen.dart';
import 'resource_browser_screen.dart';
import 'login_screen.dart';
import '../models/resource_item.dart';
import '../services/languages.dart';
import '../services/api_service.dart';
import '../services/phonics_language_map.dart';
import '../widgets/app_header.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import 'help_screen.dart';
import 'phonics_sprint_screen.dart';
import 'phonics_results_screen.dart';
import '../widgets/debug_file_label.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _selectedLanguage = 'en-US';
  String _pendingLanguage = 'en-US';
  String? _username;
  bool _isConfirmingLanguage = false;
  PhonicsSprintMode? _loadingSprintMode;
  bool _isLoadingResults = false;

  final Map<String, String> _languages = appLanguages;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await ApiService().getSavedUsername();
    if (mounted) setState(() => _username = username);
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selectedLanguage') ?? 'en-US';
    setState(() {
      _selectedLanguage = saved;
      _pendingLanguage = saved;
    });
  }

  Future<void> _confirmLanguageChange() async {
    if (_pendingLanguage == _selectedLanguage) return;

    final code = _pendingLanguage;
    setState(() => _isConfirmingLanguage = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', code);
    await ResourceStrings.instance.load(code);

    if (!mounted) return;
    setState(() {
      _selectedLanguage = code;
      _isConfirmingLanguage = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_languages[code]} ✓')),
    );
  }

  Future<void> _copyShareLink() async {
    if (_username == null) return;
    final link = 'https://$_username.800globalenglish.com';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ResourceStrings.instance.get('aiadd2959')} ${ResourceStrings.instance.get('aiadd2840')} $link')),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ResourceStrings.instance.get('aiadd4083')),
        content: Text(ResourceStrings.instance.get('aiadd4084')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3911'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd4083'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<List<ResourceItem>?> _loadTree() async {
    final languageId = phonicsLanguageIdFor(_selectedLanguage);
    final prefs = await SharedPreferences.getInstance();

    var cached = prefs.getString(ApiService.resourceTreeCacheKey(phonicsPageId, languageId));
    if (cached == null) {
      final succeeded = await ApiService().fetchAndCacheResourceTree(pageId: phonicsPageId, languageId: languageId);
      if (succeeded) {
        cached = prefs.getString(ApiService.resourceTreeCacheKey(phonicsPageId, languageId));
      }
    }

    if (cached == null) return null;

    final decoded = (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
    return decoded.map((json) => ResourceItem.fromJson(json)).toList();
  }

  Future<void> _openSprint(PhonicsSprintMode mode) async {
    setState(() => _loadingSprintMode = mode);
    final items = await _loadTree();
    if (!mounted) return;
    setState(() => _loadingSprintMode = null);

    if (items == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load Phonics content. Check your connection and try again.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhonicsSprintScreen(allItems: items, mode: mode),
      ),
    );
  }

  Future<void> _openResults() async {
    setState(() => _isLoadingResults = true);
    final items = await _loadTree();
    if (!mounted) return;
    setState(() => _isLoadingResults = false);

    if (items == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load Phonics content. Check your connection and try again.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhonicsResultsScreen(allItems: items),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppHeader(height: 60),
                      const SizedBox(height: 16),
                      Text(
                        ResourceStrings.instance.get('phonics'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500),
                      ),
                      if (_username != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${ResourceStrings.instance.get('aiadd2890')}: $_username',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _pendingLanguage,
                                    underline: const SizedBox(),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    items: _languages.entries
                                        .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text('${appLanguageFlags[e.key] ?? ''}  ${e.value}'),
                                    ))
                                        .toList(),
                                    onChanged: (code) {
                                      if (code != null) setState(() => _pendingLanguage = code);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_isConfirmingLanguage)
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                  )
                                else
                                  IconButton.filled(
                                    icon: const Icon(Icons.arrow_forward),
                                    tooltip: 'Apply language',
                                    onPressed: _confirmLanguageChange,
                                  ),
                              ],
                            ),
                            if (_isConfirmingLanguage)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  ResourceStrings.instance.get('aiadd4075'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.spellcheck),
                          label: const Text(
                            'Phonics',
                            style: TextStyle(fontSize: 18),
                          ),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ResourceBrowserScreen(
                                  pageId: phonicsPageId,
                                  screenTitle: 'Phonics',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _loadingSprintMode == PhonicsSprintMode.soundsOnly
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text('🔥', style: TextStyle(fontSize: 18)),
                          label: const Text(
                            'Phonics Quiz',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: (_loadingSprintMode != null || _isLoadingResults)
                              ? null
                              : () => _openSprint(PhonicsSprintMode.soundsOnly),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _loadingSprintMode == PhonicsSprintMode.wordsPictures
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text('🖼️', style: TextStyle(fontSize: 18)),
                          label: const Text(
                            'Word Quiz',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: (_loadingSprintMode != null || _isLoadingResults)
                              ? null
                              : () => _openSprint(PhonicsSprintMode.wordsPictures),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _isLoadingResults
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(Icons.bar_chart),
                          label: const Text(
                            'My Results',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: (_loadingSprintMode != null || _isLoadingResults) ? null : _openResults,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.help_outline),
                          label: Text('${ResourceStrings.instance.get('aiadd2883')} FAQs'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const HelpScreen()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.refresh, color: Colors.grey),
                          label: const Text(
                            'Reset Phonics Progress (testing)',
                            style: TextStyle(color: Colors.grey),
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Reset progress?'),
                                content: const Text(
                                  'This clears every checkmark for all 44 sounds and their words on this device. This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Reset'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.remove('phonicsCompletedIds');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Progress reset.')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_username != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  border: const Border(top: BorderSide(color: Colors.white24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.link, color: Colors.white70, size: 18),
                      label: Text(
                        ResourceStrings.instance.get('aiadd2597'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onPressed: _copyShareLink,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                      label: Text(ResourceStrings.instance.get('aiadd4083'), style: const TextStyle(color: Colors.white70)),
                      onPressed: _handleLogout,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'splash_screen.dart'),
    );
  }
}
