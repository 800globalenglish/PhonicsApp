import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/content_package_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/resource_strings.dart';
import '../services/api_service.dart';
import '../services/phonics_language_map.dart';
import 'splash_screen.dart';
import '../widgets/debug_file_label.dart';

class WelcomeDownloadScreen extends StatefulWidget {
  const WelcomeDownloadScreen({super.key});

  @override
  State<WelcomeDownloadScreen> createState() => _WelcomeDownloadScreenState();
}

class _WelcomeDownloadScreenState extends State<WelcomeDownloadScreen> {
  final _service = ContentPackageService.instance;
  bool _isDownloading = false;
  bool _downloadComplete = false;
  bool _downloadFailed = false;
  String _statusMessage = '';
  String _currentStatusCode = '';
  DownloadProgress? _progress;
  int? _knownSizeBytes;

  @override
  void initState() {
    super.initState();
    _statusMessage = ResourceStrings.instance.get('aiadd4012');
    _loadRealSize();
  }

  Future<void> _loadRealSize() async {
    final size = await _service.getRemoteTotalSizeBytes();
    if (mounted) setState(() => _knownSizeBytes = size);
  }

  Future<bool> _isOnWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  String _formatTimeRemaining(double? seconds) {
    if (seconds == null) return ResourceStrings.instance.get('aiadd4001');
    if (seconds < 60) return '${seconds.round()} ${ResourceStrings.instance.get('seconds')}';
    final minutes = (seconds / 60).round();
    return minutes == 1
        ? ResourceStrings.instance.get('aiadd4002')
        : '${ResourceStrings.instance.get('aiadd4003')} $minutes ${ResourceStrings.instance.get('aiadd4004')}';
  }

  String _translateStatus(String code) {
    switch (code) {
      case 'downloading_sounds':
        return ResourceStrings.instance.get('aiadd4077');
      case 'extracting_sounds':
        return ResourceStrings.instance.get('aiadd4078');
      case 'downloading_images':
        return ResourceStrings.instance.get('aiadd4079');
      case 'extracting_images':
        return ResourceStrings.instance.get('aiadd4080');
      default:
        return '';
    }
  }

  Future<void> _startDownload() async {
    final onWifi = await _isOnWifi();

    if (!onWifi) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(ResourceStrings.instance.get('aiadd3913')),
          content: Text(
              '${ResourceStrings.instance.get('aiadd3914')} ${ResourceStrings.instance.get('aiadd3915')} ${ResourceStrings.instance.get('aiadd3916')}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3929'))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd3930'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _isDownloading = true;
      _downloadFailed = false;
      _progress = null;
      _statusMessage = ResourceStrings.instance.get('aiadd4016');
    });

    final success = await _service.downloadAndExtract(
      knownTotalBytes: _knownSizeBytes,
      onStatus: (statusCode) {
        if (mounted) {
          setState(() {
            _currentStatusCode = statusCode;
            _statusMessage = _translateStatus(statusCode);
          });
        }
      },
      onDownloadProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );

    setState(() {
      _isDownloading = false;
      _downloadComplete = success;
      _downloadFailed = !success;
      _statusMessage = success
          ? ResourceStrings.instance.get('aiadd3999')
          : ResourceStrings.instance.get('aiadd4015');
    });

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      final appLanguageCode = prefs.getString('selectedLanguage') ?? 'en-US';
      final languageId = phonicsLanguageIdFor(appLanguageCode);
      // ignore: unawaited_futures
      ApiService().prefetchPhonicsTree(languageId);
    }
  }

  Future<void> _continueAfterDownload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenWelcomeContentDownload', true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _downloadComplete ? Icons.check_circle : Icons.cloud_download_outlined,
                size: 72,
                color: _downloadComplete ? Colors.greenAccent : Colors.white70,
              ),
              const SizedBox(height: 24),
              Text(
                _downloadComplete ? ResourceStrings.instance.get('aiadd3925') : ResourceStrings.instance.get('aiadd3932'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              if (_isDownloading && (_currentStatusCode == 'extracting_sounds' || _currentStatusCode == 'extracting_images')) ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 24),
              ] else if (_isDownloading && _progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress!.percent > 0 ? _progress!.percent : null,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_progress!.megabytesReceived.toStringAsFixed(1)} MB of ${_progress!.totalMegabytes.toStringAsFixed(0)} MB',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ResourceStrings.instance.get('aiadd3931')}: ${_formatTimeRemaining(_progress!.estimatedSecondsRemaining)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),
              ] else if (_isDownloading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 24),
              ],
              if (!_isDownloading)
                if (_downloadComplete)
                  ElevatedButton(
                    onPressed: _continueAfterDownload,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: Text(ResourceStrings.instance.get('aiadd3942')),
                  )
                else
                  ElevatedButton(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: Text(_downloadFailed
                        ? ResourceStrings.instance.get('aiadd4017')
                        : _knownSizeBytes != null
                        ? '${ResourceStrings.instance.get('aiadd4018')} (~${(_knownSizeBytes! / (1024 * 1024)).round()}MB)'
                        : ResourceStrings.instance.get('aiadd4018')),
                  ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'welcome_download_screen.dart'),
    );
  }
}
