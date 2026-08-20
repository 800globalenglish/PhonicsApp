import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/resource_strings.dart';
import 'splash_screen.dart';
import 'welcome_download_screen.dart';
import 'welcome_wizard_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/debug_file_label.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();

  bool _isLoading = false;
  String? _errorMessage;

  bool _checkingSession = true;
  String? _cachedUsername;

  @override
  void initState() {
    super.initState();
    _checkForCachedSession();
  }

  // Checks whether there's a previous session on this device that can be
  // resumed without a network call.
  Future<void> _checkForCachedSession() async {
    final hasCached = await _api.hasCachedSession();
    final username = hasCached ? await _api.getSavedUsername() : null;
    if (!mounted) return;
    setState(() {
      _cachedUsername = username;
      _checkingSession = false;
    });
  }

  // Resumes a cached session with no network call at all.
  Future<void> _handleResumeSession() async {
    await _api.resumeOfflineSession();
    if (!mounted) return;
    await _navigateAfterLogin();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _api.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      await _navigateAfterLogin();
    } else {
      setState(() {
        _errorMessage = ResourceStrings.instance.get('aiadd4005');
      });
    }
  }

  // Shared by both a real login and an offline session resume, so the
  // onboarding/routing logic only lives in one place.
  Future<void> _navigateAfterLogin() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenContentDownload = prefs.getBool('hasSeenWelcomeContentDownload') ?? false;

    if (!hasSeenContentDownload) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeDownloadScreen()),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002E52),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Always lands on the Choose Language screen specifically, with
            // the whole stack reset beneath it â€” so there's nothing left to
            // "pop" to if the person then hits back again on THAT screen.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WelcomeWizardScreen()),
                  (route) => false,
            );
          },
        ),
      ),
      body: Center(
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
              const SizedBox(height: 32),
              // Offline resume option, shown only if a cached session exists
              if (_checkingSession)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (_cachedUsername != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: Text('${ResourceStrings.instance.get('aiadd4062')} $_cachedUsername'),
                    onPressed: _handleResumeSession,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(color: Colors.white54)),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                ),
              ],
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: ResourceStrings.instance.get('aiadd3909'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: ResourceStrings.instance.get('aiadd3910'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.orangeAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin,
                  child: Text(ResourceStrings.instance.get('aiadd3953')),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'login_screen.dart'),
    );
  }
}
