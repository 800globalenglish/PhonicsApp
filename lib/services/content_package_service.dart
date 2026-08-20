import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

// ============================================================================
// Phonics' offline content is ONE combined package covering
// industries (Restaurant/Household and Construction/General) â€” not split
// since filenames are unique. It's split into
// two zips (images, sounds) rather than one, mirroring the same pattern the
// original 800 Global English app used for its own content package.
//
// Each zip's internal structure has its folder name at the root â€” i.e.
// images.zip contains an "images/" folder with every file directly inside
// it (no per-category subfolders, no separate tmb â€” same file serves both
// full-size and thumbnail use), and sounds.zip contains a "sounds/" folder
// the same way. Extracting both into the same local folder produces:
//
//   phonics-content/
//       images/
//           (every image file, both industries combined)
//       sounds/
//           (every audio file, both industries combined)
// ============================================================================
const String imagesZipUrl = 'https://cdn.800globalenglish.com/content/app/phonics/images.zip';
const String soundsZipUrl = 'https://cdn.800globalenglish.com/content/app/phonics/sounds.zip';
const String versionUrl = 'https://cdn.800globalenglish.com/content/app/phonics/version.txt';

class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  final double? estimatedSecondsRemaining;

  DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    this.estimatedSecondsRemaining,
  });

  double get percent => totalBytes > 0 ? bytesReceived / totalBytes : 0;
  double get megabytesReceived => bytesReceived / (1024 * 1024);
  double get totalMegabytes => totalBytes / (1024 * 1024);
}

class ContentPackageService {
  static final ContentPackageService instance = ContentPackageService._internal();
  ContentPackageService._internal();

  bool _isContentAvailableLocally = false;
  bool _statusLoadAttempted = false;
  bool get isContentAvailableLocally => _isContentAvailableLocally;

  Future<void> loadLocalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isContentAvailableLocally = prefs.getBool('phonicsContentDownloaded') ?? false;
    _statusLoadAttempted = true;
  }

  // Ensures loadLocalStatus() has run at least once before anything checks
  // _isContentAvailableLocally. Previously this relied on something in the
  // UI (e.g. main.dart or splash screen) remembering to call
  // loadLocalStatus() at app startup â€” if that call was ever missing, this
  // flag would silently stay false forever after a fresh app launch, making
  // every local file lookup wrongly report "not downloaded" even when the
  // content genuinely was downloaded in a previous session.
  Future<void> _ensureStatusLoaded() async {
    if (!_statusLoadAttempted) {
      await loadLocalStatus();
    }
  }

  Future<Directory> _getContentDir() async {
    final dir = await getApplicationSupportDirectory();
    final contentDir = Directory('${dir.path}/phonics-content');
    if (!await contentDir.exists()) {
      await contentDir.create(recursive: true);
    }
    return contentDir;
  }

  // ---------- status ----------

  Future<int?> getRemoteTotalSizeBytes() async {
    try {
      final imagesResponse = await http.head(Uri.parse(imagesZipUrl));
      final soundsResponse = await http.head(Uri.parse(soundsZipUrl));
      final imagesLength = int.tryParse(imagesResponse.headers['content-length'] ?? '');
      final soundsLength = int.tryParse(soundsResponse.headers['content-length'] ?? '');
      if (imagesLength == null || soundsLength == null) return null;
      return imagesLength + soundsLength;
    } catch (e) {
      return null;
    }
  }

  Future<bool> isUpdateAvailable() async {
    try {
      if (!_isContentAvailableLocally) return true; // never downloaded yet

      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt('phonicsContentVersion') ?? 0;

      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode != 200) return false;

      final serverVersion = int.tryParse(response.body.trim()) ?? 0;
      return serverVersion > localVersion;
    } catch (e) {
      return false;
    }
  }

  // ---------- download + extract ----------

  // Public entry point wraps the real attempt in a retry loop â€” a flaky
  // connection can produce a truncated/corrupted zip that only reveals
  // itself once decoding is attempted, so this detects that and silently
  // retries once before giving up for real.
  Future<bool> downloadAndExtract({
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    int? knownTotalBytes,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _downloadAndExtractOnce(
        onDownloadProgress: onDownloadProgress,
        onStatus: onStatus,
        knownTotalBytes: knownTotalBytes,
      );

      if (result) return true;

      if (attempt < maxAttempts) {
        // ignore: avoid_print
        print('DEBUG downloadAndExtract: attempt $attempt failed, retrying...');
        onStatus?.call('retrying');
      }
    }
    return false;
  }

  Future<bool> _downloadAndExtractOnce({
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    int? knownTotalBytes,
  }) async {
    Directory? tempDir;

    try {
      final baseDir = await getApplicationSupportDirectory();
      tempDir = Directory('${baseDir.path}/phonics-content-tmp');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      final combinedTotal = knownTotalBytes ?? await getRemoteTotalSizeBytes() ?? 0;
      int bytesReceivedSoFar = 0;

      await _downloadAndExtractSingleZip(
        url: imagesZipUrl,
        tempDir: tempDir,
        destinationSubfolder: 'images',
        overallTotalBytes: combinedTotal,
        bytesAlreadyCounted: bytesReceivedSoFar,
        onBytesReceivedUpdate: (n) => bytesReceivedSoFar = n,
        onDownloadProgress: onDownloadProgress,
        onStatus: onStatus,
        downloadingStatusCode: 'downloading_images',
        extractingStatusCode: 'extracting_images',
      );

      await _downloadAndExtractSingleZip(
        url: soundsZipUrl,
        tempDir: tempDir,
        destinationSubfolder: 'sounds',
        overallTotalBytes: combinedTotal,
        bytesAlreadyCounted: bytesReceivedSoFar,
        onBytesReceivedUpdate: (n) => bytesReceivedSoFar = n,
        onDownloadProgress: onDownloadProgress,
        onStatus: onStatus,
        downloadingStatusCode: 'downloading_sounds',
        extractingStatusCode: 'extracting_sounds',
      );

      // Both zips extracted successfully - now safe to swap.
      final contentDir = await _getContentDir();
      if (await contentDir.exists()) {
        await contentDir.delete(recursive: true);
      }
      await tempDir.rename(contentDir.path);
      tempDir = null; // renamed successfully - nothing left to clean up

      // ignore: avoid_print
      print('DEBUG extraction complete. Top-level contents of ${contentDir.path}:');
      await for (final entity in contentDir.list()) {
        if (entity is Directory) {
          final count = await entity.list().length;
          // ignore: avoid_print
          print('DEBUG   [folder] ${entity.path} â€” $count items inside');
        } else {
          // ignore: avoid_print
          print('DEBUG   [file] ${entity.path}');
        }
      }

      final versionResponse = await http.get(Uri.parse(versionUrl));
      final newVersion = int.tryParse(versionResponse.body.trim()) ?? 0;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('phonicsContentVersion', newVersion);
      await prefs.setBool('phonicsContentDownloaded', true);

      _isContentAvailableLocally = true;
      onStatus?.call('done');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG downloadAndExtract failed: $e');
      try {
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // best-effort cleanup only
      }
      onStatus?.call('failed');
      return false;
    }
  }

  // Downloads one zip, verifies its size matches what the server promised,
  // decodes it, and extracts it directly into tempDir/destinationSubfolder.
  //
  // IMPORTANT â€” this deliberately ignores whatever internal folder
  // structure the zip itself has. We found (via debug logging) that these
  // particular zips just contain loose files at their root, no "images" or
  // "sounds" wrapper folder inside them â€” so instead of trusting
  // file.name from the archive (which would land everything at the root
  // of tempDir), every extracted file is forced into the correct named
  // subfolder using only its basename. This works regardless of whether
  // the zip has an internal folder, a different one, or none at all.
  Future<void> _downloadAndExtractSingleZip({
    required String url,
    required Directory tempDir,
    required String destinationSubfolder,
    required int overallTotalBytes,
    required int bytesAlreadyCounted,
    required void Function(int totalBytesReceivedSoFar) onBytesReceivedUpdate,
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    required String downloadingStatusCode,
    required String extractingStatusCode,
  }) async {
    onStatus?.call(downloadingStatusCode);
    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    final streamedResponse = await client.send(request);

    if (streamedResponse.statusCode != 200) {
      client.close();
      throw Exception('HTTP ${streamedResponse.statusCode} for $url');
    }

    final thisFileTotal = streamedResponse.contentLength ?? 0;
    final bytesBuilder = BytesBuilder(copy: false);
    int bytesReceivedThisFile = 0;
    final stopwatch = Stopwatch()..start();

    await for (final chunk in streamedResponse.stream) {
      bytesBuilder.add(chunk);
      bytesReceivedThisFile += chunk.length;

      final combinedReceived = bytesAlreadyCounted + bytesReceivedThisFile;
      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      double? estimatedRemaining;
      if (elapsedSeconds > 0.5 && bytesReceivedThisFile > 0 && overallTotalBytes > 0) {
        final bytesPerSecond = bytesReceivedThisFile / elapsedSeconds;
        final remainingBytes = overallTotalBytes - combinedReceived;
        estimatedRemaining = remainingBytes / bytesPerSecond;
      }

      onDownloadProgress?.call(DownloadProgress(
        bytesReceived: combinedReceived,
        totalBytes: overallTotalBytes,
        estimatedSecondsRemaining: estimatedRemaining,
      ));
    }

    client.close();
    stopwatch.stop();

    if (thisFileTotal > 0 && bytesReceivedThisFile != thisFileTotal) {
      throw Exception('Size mismatch for $url: received=$bytesReceivedThisFile expected=$thisFileTotal');
    }

    onBytesReceivedUpdate(bytesAlreadyCounted + bytesReceivedThisFile);
    onStatus?.call(extractingStatusCode);

    final zipBytes = bytesBuilder.takeBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw Exception('Zip decode failed for $url: $e');
    }

    for (final file in archive) {
      if (!file.isFile) continue; // no need to recreate directory entries anymore - we control the structure now
      final basename = file.name.split('/').last;
      if (basename.isEmpty) continue; // skip directory entries that slipped through
      final filePath = '${tempDir.path}/$destinationSubfolder/$basename';
      final outFile = File(filePath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }
  }

  // ---------- resolving local files ----------

  // Given a plain filename, returns the local extracted file path if it's
  // been downloaded and the file exists there, or null if not (caller
  // should fall back to the CDN URL in that case). Same file serves both
  // full-size and thumbnail use â€” there's no separate tmb copy.
  Future<String?> resolveLocalImagePath(String filename) => _resolveLocal('images/$filename');
  Future<String?> resolveLocalThumbPath(String filename) => _resolveLocal('images/$filename');
  Future<String?> resolveLocalSoundPath(String filename) => _resolveLocal('sounds/$filename');

  // Convenience wrapper for SmartImage, which passes a full CDN URL rather
  // than a bare filename â€” just pulls the filename off the end and checks
  // the local images/ folder. Not used for audio (audio playback still
  // hits the CDN directly for now â€” a remaining TODO).
  Future<String?> resolveLocalPath(String url) {
    final filename = url.split('/').last;
    return resolveLocalImagePath(filename);
  }

  Future<String?> _resolveLocal(String relativePath) async {
    await _ensureStatusLoaded();
    if (!_isContentAvailableLocally) {
      // ignore: avoid_print
      print('DEBUG _resolveLocal: content not marked as downloaded, skipping local check for $relativePath');
      return null;
    }
    final contentDir = await _getContentDir();
    final localFile = File('${contentDir.path}/$relativePath');
    final exists = await localFile.exists();
    // ignore: avoid_print
    print('DEBUG _resolveLocal: checked ${localFile.path} â€” exists=$exists');
    return exists ? localFile.path : null;
  }
}
