import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/languages.dart';
import '../services/resource_strings.dart';
import 'login_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/debug_file_label.dart';

class WelcomeWizardScreen extends StatefulWidget {
  const WelcomeWizardScreen({super.key});

  @override
  State<WelcomeWizardScreen> createState() => _WelcomeWizardScreenState();
}

class _WelcomeWizardScreenState extends State<WelcomeWizardScreen> {
  String _selectedLanguage = 'en-US';

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', _selectedLanguage);
    await prefs.setBool('hasSeenWelcomeWizard', true);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppHeader(height: 60),
              const SizedBox(height: 16),
              Text(
                ResourceStrings.instance.get('phonics'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),
              Text(
                ResourceStrings.instance.get('aiadd3990'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: appLanguages.entries
                      .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text('${appLanguageFlags[e.key] ?? ''} ${e.value}'),
                  ))
                      .toList(),
                  onChanged: (code) async {
                    if (code != null) {
                      await ResourceStrings.instance.load(code);
                      if (!mounted) return;
                      setState(() => _selectedLanguage = code);
                    }
                  },
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ResourceStrings.instance.get('aiadd4020'),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _continue,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: Text(ResourceStrings.instance.get('aiadd3942')),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'welcome_wizard_screen.dart'),
    );
  }
}
