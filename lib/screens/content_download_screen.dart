import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../services/api_service.dart';
import '../services/phonics_language_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/debug_file_label.dart';

class ContentDownloadScreen extends StatefulWidget {
  const ContentDownloadScreen({super.key});

  @override
  State<ContentDownloadScreen> createState() => _ContentDownloadScreenState();
}

class _ContentDownloadScreenState extends State<ContentDownloadScreen> {
  final _service = ContentPackageService.instance;
  bool _isDownloading = false;
  bool _isChecking = true;
  bool _updateAvailable = false;
  String _statusMessage = '';
  String _currentStatusCode = '';
  DownloadProgress? _progress;
  int? _knownSizeBytes;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _loadRealSize();
  }

  Future<void> _loadRealSize() async {
    final size = await _service.getRemoteTotalSizeBytes();
    if (mounted) setState(() => _knownSizeBytes = size);
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isChecking = true);
    final available = await _service.isUpdateAvailable();
    setState(() {
      _updateAvailable = available;
      _isChecking = false;
      _statusMessage = _service.isContentAvailableLocally
          ? (available
          ? ResourceStrings.instance.get('aiadd3995')
          : ResourceStrings.instance.get('aiadd3996'))
          : ResourceStrings.instance.get('aiadd3997');
    });
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3911'))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd3912'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _isDownloading = true;
      _progress = null;
      _statusMessage = ResourceStrings.instance.get('aiadd3998');
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
      _updateAvailable = false;
      _statusMessage = success
          ? ResourceStrings.instance.get('aiadd3999')
          : ResourceStrings.instance.get('aiadd4000');
    });

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      final appLanguageCode = prefs.getString('selectedLanguage') ?? 'en-US';
      final languageId = phonicsLanguageIdFor(appLanguageCode);
      // ignore: unawaited_futures
      ApiService().prefetchPhonicsTree(languageId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002E52),
        title: Text(
          ResourceStrings.instance.get('aiadd3932'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _service.isContentAvailableLocally ? Icons.check_circle : Icons.cloud_download_outlined,
              size: 64,
              color: _service.isContentAvailableLocally ? Colors.greenAccent : Colors.white70,
            ),
            const SizedBox(height: 24),
            if (_isChecking)
              const CircularProgressIndicator(color: Colors.white)
            else
              SizedBox(
                width: double.infinity,
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            const SizedBox(height: 24),
            if (_isDownloading && (_currentStatusCode == 'extracting_sounds' || _currentStatusCode == 'extracting_images'))
              const CircularProgressIndicator(color: Colors.white)
            else if (_isDownloading && _progress != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress!.percent > 0 ? _progress!.percent : null,
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_progress!.megabytesReceived.toStringAsFixed(1)} MB of ${_progress!.totalMegabytes.toStringAsFixed(0)} MB',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                '${ResourceStrings.instance.get('aiadd3931')}: ${_formatTimeRemaining(_progress!.estimatedSecondsRemaining)}',
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ] else if (_isDownloading)
              const CircularProgressIndicator(color: Colors.white)
            else if (!_isChecking && (_updateAvailable || !_service.isContentAvailableLocally))
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(_knownSizeBytes != null
                      ? '${ResourceStrings.instance.get('aiadd3932')} (~${(_knownSizeBytes! / (1024 * 1024)).round()}MB)'
                      : ResourceStrings.instance.get('aiadd3932')),
                  onPressed: _startDownload,
                ),
          ],
        ),
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'content_download_screen.dart'),

    );
  }
}
