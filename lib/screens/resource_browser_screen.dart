import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/resource_item.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../services/phonics_language_map.dart';
import 'oral_practice_screen.dart';
import 'phonics_practice_screen.dart';
import '../widgets/debug_file_label.dart';
import '../widgets/phonics_bottom_links.dart';

class ResourceBrowserScreen extends StatefulWidget {
  final int pageId;
  final String screenTitle;
  final int parentId;
  final List<ResourceItem>? preloadedItems;

  const ResourceBrowserScreen({
    super.key,
    required this.pageId,
    required this.screenTitle,
    this.parentId = 0,
    this.preloadedItems,
  });

  @override
  State<ResourceBrowserScreen> createState() => _ResourceBrowserScreenState();
}

class _ResourceBrowserScreenState extends State<ResourceBrowserScreen> {
  List<ResourceItem>? _allItems;
  bool _loading = true;
  bool _loadFailed = false;
  final AudioPlayer _previewPlayer = AudioPlayer();
  int? _currentlyPlayingId;
  bool _isPlayingAll = false;
  final ScrollController _scrollController = ScrollController();

  bool _completedSectionOnTop = false;

  static const _completedPrefsKey = 'phonicsCompletedIds';
  static const _completedOrderPrefsKey = 'phonicsCompletedOrder';
  Set<int> _completedIds = {};
  List<int> _completedOrder = [];

  int? _completionOrderIndex(ResourceItem item) {
    if (item.isFolder) {
      final leaves = _leafDescendants(item.id);
      final indices = leaves.map((l) => _completedOrder.indexOf(l.id)).where((i) => i >= 0);
      if (indices.isEmpty) return null;
      return indices.reduce((a, b) => a > b ? a : b);
    }
    final idx = _completedOrder.indexOf(item.id);
    return idx >= 0 ? idx : null;
  }

  List<ResourceItem> _getWordSiblings() {
    if (_allItems == null) return [];
    final children = _allItems!
        .where((item) => item.parentId == widget.parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return children.where((c) => !c.isFolder).toList();
  }

  Future<void> _playAll() async {
    if (_isPlayingAll) {
      setState(() {
        _isPlayingAll = false;
        _currentlyPlayingId = null;
      });
      await _previewPlayer.stop();
      return;
    }

    final words = _getWordSiblings().where((w) => !_completedIds.contains(w.id)).toList();
    if (words.isEmpty) return;

    setState(() => _isPlayingAll = true);

    for (final item in words) {
      if (!_isPlayingAll || !mounted) break;

      setState(() => _currentlyPlayingId = item.id);

      try {
        final localPath = await ContentPackageService.instance.resolveLocalSoundPath(item.audioUrl);
        final source = localPath != null
            ? DeviceFileSource(localPath)
            : UrlSource('$_soundsBaseUrl/${item.audioUrl}');

        await _previewPlayer.stop();

        final completer = Completer<void>();
        late StreamSubscription sub;
        sub = _previewPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _previewPlayer.play(source);
        await completer.future;
        await sub.cancel();
      } catch (e) {
        // ignore: avoid_print
        print('DEBUG _playAll: failed on ${item.audioUrl}: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isPlayingAll = false;
        _currentlyPlayingId = null;
      });
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCompletedIds();
    if (widget.preloadedItems != null) {
      _allItems = widget.preloadedItems;
      _loading = false;
    } else {
      _loadTree();
    }
  }

  Future<void> _loadCompletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_completedPrefsKey) ?? [];
    final ids = saved.map((s) => int.tryParse(s)).whereType<int>().toSet();
    final savedOrder = prefs.getStringList(_completedOrderPrefsKey) ?? [];
    final order = savedOrder.map((s) => int.tryParse(s)).whereType<int>().toList();
    if (mounted) {
      setState(() {
        _completedIds = ids;
        _completedOrder = order;
      });
    }
  }

  Future<void> _toggleCompleted(int id) async {
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
        _completedOrder.remove(id);
      } else {
        _completedIds.add(id);
        _completedOrder.remove(id);
        _completedOrder.add(id);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedPrefsKey, _completedIds.map((i) => i.toString()).toList());
    await prefs.setStringList(_completedOrderPrefsKey, _completedOrder.map((i) => i.toString()).toList());
  }

  List<ResourceItem> _leafDescendants(int folderId) {
    if (_allItems == null) return [];
    final direct = _allItems!.where((i) => i.parentId == folderId);
    final leaves = <ResourceItem>[];
    for (final child in direct) {
      if (child.isFolder) {
        leaves.addAll(_leafDescendants(child.id));
      } else {
        leaves.add(child);
      }
    }
    return leaves;
  }

  bool _isFolderComplete(int folderId) {
    final leaves = _leafDescendants(folderId);
    if (leaves.isEmpty) return false;
    return leaves.every((l) => _completedIds.contains(l.id));
  }

  Future<void> _loadTree() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    final prefs = await SharedPreferences.getInstance();
    final appLanguageCode = prefs.getString('selectedLanguage') ?? 'en-US';
    final languageId = phonicsLanguageIdFor(appLanguageCode);

    final succeeded = await ApiService().fetchAndCacheResourceTree(pageId: widget.pageId, languageId: languageId);

    if (!mounted) return;

    if (succeeded) {
      final cached = prefs.getString(ApiService.resourceTreeCacheKey(widget.pageId, languageId));
      final decoded = (jsonDecode(cached!) as List).cast<Map<String, dynamic>>();
      setState(() {
        _allItems = decoded.map((json) => ResourceItem.fromJson(json)).toList();
        _loading = false;
      });
      return;
    }

    final cached = prefs.getString(ApiService.resourceTreeCacheKey(widget.pageId, languageId));
    if (cached != null) {
      try {
        final decoded = (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
        setState(() {
          _allItems = decoded.map((json) => ResourceItem.fromJson(json)).toList();
          _loading = false;
        });
        return;
      } catch (e) {
        // ignore: avoid_print
        print('DEBUG _loadTree: cached data corrupt, falling through to error: $e');
      }
    }

    setState(() {
      _loading = false;
      _loadFailed = true;
    });
  }

  String get _imagesBaseUrl => 'https://cdn.800globalenglish.com/content/phonics/images';
  String get _thumbBaseUrl => 'https://cdn.800globalenglish.com/content/phonics/images';
  String get _bannerAssetPath => widget.pageId == 2
      ? 'assets/images/construction_app.png'
      : 'assets/images/restaurant_app.png';
  String get _soundsBaseUrl => 'https://cdn.800globalenglish.com/content/phonics/sounds';

  Future<void> _playPreview(ResourceItem item) async {
    try {
      setState(() => _currentlyPlayingId = item.id);
      await _previewPlayer.stop();

      final localPath = await ContentPackageService.instance.resolveLocalSoundPath(item.audioUrl);
      final source = localPath != null
          ? DeviceFileSource(localPath)
          : UrlSource('$_soundsBaseUrl/${item.audioUrl}');

      await _previewPlayer.play(source);
      _previewPlayer.onPlayerComplete.first.then((_) {
        if (mounted && _currentlyPlayingId == item.id) {
          setState(() => _currentlyPlayingId = null);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _currentlyPlayingId = null);
    }
  }

  void _openFolder(ResourceItem folder) async {
    final directChildren = _allItems!.where((i) => i.parentId == folder.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final hasSubfolders = directChildren.any((c) => c.isFolder);

    if (!hasSubfolders && directChildren.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhonicsPracticeScreen(
            sound: folder,
            words: directChildren,
            allItems: _allItems!,
          ),
        ),
      );
      if (mounted) await _loadCompletedIds();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResourceBrowserScreen(
          pageId: widget.pageId,
          screenTitle: _cleanTitle(folder.title),
          parentId: folder.id,
          preloadedItems: _allItems,
        ),
      ),
    );
    if (mounted) await _loadCompletedIds();
  }

  String _cleanTitle(String raw) => raw.replaceFirst(RegExp(r'^\s*\d+\s*'), '').trim();

  void _openWord(List<ResourceItem> siblingWords, int tappedIndex) {
    final parentSound = _allItems?.firstWhere((i) => i.id == widget.parentId, orElse: () => siblingWords.first);
    final items = siblingWords
        .map((w) => PracticeWordItem(
      title: w.title,
      otherTitle: w.otherTitle,
      imageUrl: w.imageUrl,
      audioUrl: w.audioUrl,
    ))
        .toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OralPracticeScreen(
          categoryTitle: widget.screenTitle,
          items: items,
          initialIndex: tappedIndex,
          pageId: widget.pageId,
          soundAudioUrl: parentSound?.audioUrl ?? '',
        ),
      ),
    );
  }

  void _swapSections() {
    setState(() => _completedSectionOnTop = !_completedSectionOnTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: const DebugFileLabel(fileName: 'resource_browser_screen.dart'),
      );
    }

    if (_loadFailed || _allItems == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  ResourceStrings.instance.get('aiadd4000'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadTree,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: const DebugFileLabel(fileName: 'resource_browser_screen.dart'),
      );
    }

    final rawChildren = _allItems!.where((item) => item.parentId == widget.parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (rawChildren.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: Center(child: Text(ResourceStrings.instance.get('norecordfound'))),
        bottomNavigationBar: const DebugFileLabel(fileName: 'resource_browser_screen.dart'),
      );
    }

    final incompleteChildren = <ResourceItem>[];
    final completedChildren = <ResourceItem>[];
    for (final item in rawChildren) {
      final isDone = item.isFolder ? _isFolderComplete(item.id) : _completedIds.contains(item.id);
      if (isDone) {
        completedChildren.add(item);
      } else {
        incompleteChildren.add(item);
      }
    }
    completedChildren.sort((a, b) {
      final ai = _completionOrderIndex(a) ?? -1;
      final bi = _completionOrderIndex(b) ?? -1;
      return bi.compareTo(ai);
    });

    final wordSiblings = rawChildren.where((c) => !c.isFolder).toList();
    final isRootPhonicsScreen = widget.parentId == 0;

    final topList = _completedSectionOnTop ? completedChildren : incompleteChildren;
    final footerList = _completedSectionOnTop ? incompleteChildren : completedChildren;

    return Scaffold(
      appBar: AppBar(title: Text(widget.screenTitle)),
      body: Column(
        children: [
          if (widget.parentId == 0)
            Image.asset(
              _bannerAssetPath,
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (wordSiblings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(_isPlayingAll ? Icons.stop : Icons.playlist_play),
                  label: Text(_isPlayingAll ? ResourceStrings.instance.get('aiadd4086') : ResourceStrings.instance.get('aiadd4085')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPlayingAll ? Colors.red.shade400 : null,
                  ),
                  onPressed: _playAll,
                ),
              ),
            ),
          Expanded(
            child: topList.isEmpty && !isRootPhonicsScreen
                ? Center(
              child: Text(
                _completedSectionOnTop ? 'Nothing completed yet.' : 'All done!',
                style: const TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              itemCount: topList.length + (isRootPhonicsScreen ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == topList.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PhonicsBottomLinks(
                      allItems: _allItems!,
                      showList: false,
                    ),
                  );
                }
                final item = topList[index];
                return _buildRow(item, wordSiblings);
              },
            ),
          ),
          if (footerList.isNotEmpty)
            _SectionFooterBar(
              isShowingCompleted: !_completedSectionOnTop,
              count: footerList.length,
              summaryTitle: _cleanTitle(footerList.first.title),
              onTap: _swapSections,
            ),
        ],
      ),
      bottomNavigationBar: const DebugFileLabel(fileName: 'resource_browser_screen.dart'),
    );
  }

  Widget _buildRow(ResourceItem item, List<ResourceItem> wordSiblings) {
    final thumbUrl = item.imageUrl.isNotEmpty ? '$_thumbBaseUrl/${item.imageUrl}' : null;
    final fallbackIcon = Icons.spellcheck;

    final isCompleted = item.isFolder ? _isFolderComplete(item.id) : _completedIds.contains(item.id);

    final autoCompletedIcon = Icon(
      isCompleted ? Icons.check_circle : Icons.check_circle_outline,
      color: isCompleted ? Colors.green : Colors.grey.shade300,
    );

    final completedCheckbox = IconButton(
      icon: Icon(
        isCompleted ? Icons.check_circle : Icons.check_circle_outline,
        color: isCompleted ? Colors.green : Colors.grey,
      ),
      tooltip: isCompleted ? 'Mark as not completed' : 'Mark as completed',
      onPressed: () => _toggleCompleted(item.id),
    );

    return ListTile(
      tileColor: isCompleted ? Colors.green.withOpacity(0.06) : null,
      leading: thumbUrl != null
          ? ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          thumbUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            fallbackIcon,
            size: 32,
            color: item.isFolder ? const Color(0xFF800000) : Colors.grey,
          ),
        ),
      )
          : Icon(
        item.isFolder ? fallbackIcon : Icons.text_snippet,
        color: item.isFolder ? const Color(0xFF800000) : null,
      ),
      title: Text(
        _cleanTitle(item.title),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: item.otherTitle.isNotEmpty ? Text(item.otherTitle) : null,
      trailing: item.isFolder
          ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          autoCompletedIcon,
          const Icon(Icons.chevron_right, color: Color(0xFF800000)),
        ],
      )
          : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          completedCheckbox,
          if (_currentlyPlayingId == item.id)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary),
          IconButton(
            icon: const Icon(Icons.mic),
            tooltip: 'Practice',
            onPressed: () {
              final tappedIndex = wordSiblings.indexWhere((w) => w.id == item.id);
              _openWord(wordSiblings, tappedIndex < 0 ? 0 : tappedIndex);
            },
          ),
        ],
      ),
      onTap: () {
        if (item.isFolder) {
          _openFolder(item);
        } else {
          _playPreview(item);
        }
      },
    );
  }
}

class _SectionFooterBar extends StatelessWidget {
  final bool isShowingCompleted;
  final int count;
  final String summaryTitle;
  final VoidCallback onTap;

  const _SectionFooterBar({
    required this.isShowingCompleted,
    required this.count,
    required this.summaryTitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final navColor = Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.primary;
    const color = Colors.white;
    final label = isShowingCompleted ? 'COMPLETE ($count)' : 'NOT COMPLETE ($count)';
    final summaryLabel = isShowingCompleted ? 'Last completed: $summaryTitle' : 'Next up: $summaryTitle';

    return InkWell(
      onTap: onTap,
      child: Container(
        color: navColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Icon(
                isShowingCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 13,
                        color: color,
                      ),
                    ),
                    Text(
                      summaryLabel,
                      style: const TextStyle(fontSize: 12, color: color),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_upward, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
