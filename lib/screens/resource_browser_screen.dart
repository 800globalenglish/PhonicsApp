import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/resource_item.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../services/tradelingo_language_map.dart';
import 'oral_practice_screen.dart';

// ============================================================================
// Reusable browser for one industry's resource tree (Restaurant/Household or
// Construction/General). The FULL tree is fetched once via GetResourceTree
// and passed down through every push — drilling into a category is just a
// local filter by parentId, no extra network calls, matching the
// "whole-tree-at-once" design decided earlier.
//
// Tapping a folder pushes another ResourceBrowserScreen one level deeper.
// Tapping a word launches OralPracticeScreen with ALL sibling words at that
// level as the practice list, starting at the tapped word.
// ============================================================================

class ResourceBrowserScreen extends StatefulWidget {
  final int pageId; // 1 = Restaurant/Household, 2 = Construction/General
  final String screenTitle; // shown in the app bar
  final int parentId; // 0 = root of this industry's tree
  final List<ResourceItem>? preloadedItems; // null only on the very first (root) screen

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

  // Same filtering logic used in build() to get this screen's word items —
  // pulled out here so _playAll can use it too without duplicating it
  // inline, and so both stay in sync if the filtering logic ever changes.
  // Puts completed items (checked words, or folders that are fully done)
  // at the bottom of the list, while keeping everything else in its normal
  // sort order. Applied consistently to both folders and words.
  List<ResourceItem> _sortWithCompletedAtBottom(List<ResourceItem> raw) {
    final sorted = [...raw]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final incomplete = <ResourceItem>[];
    final complete = <ResourceItem>[];
    for (final item in sorted) {
      final isDone = item.isFolder ? _isFolderComplete(item.id) : _completedIds.contains(item.id);
      if (isDone) {
        complete.add(item);
      } else {
        incomplete.add(item);
      }
    }
    return [...incomplete, ...complete];
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
      // Already playing - treat this as a stop request.
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
        // keep going to the next word even if one fails
      }
    }

    if (mounted) {
      setState(() {
        _isPlayingAll = false;
        _currentlyPlayingId = null;
      });
    }
  }

  // Persisted locally on the device (SharedPreferences) — a simple set of
  // resource ids the person has marked as "completed", themselves. Works at
  // any level: a whole top category, a subcategory, or an individual word.
  // Shared across both industries under one key since ids are unique across
  // the whole TradeLingo_Resources table regardless of pageId.
  static const _completedPrefsKey = 'tradeLingoCompletedIds';
  Set<int> _completedIds = {};

  @override
  void dispose() {
    _previewPlayer.dispose();
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
    if (mounted) setState(() => _completedIds = ids);
  }

  Future<void> _toggleCompleted(int id) async {
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
      } else {
        _completedIds.add(id);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedPrefsKey, _completedIds.map((i) => i.toString()).toList());
  }

  // Recursively collects every leaf word under a folder, however many
  // levels deep (a category can contain subcategories which contain more
  // subcategories before finally reaching actual words).
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

  // A folder "lights up" automatically once every word underneath it
  // (at any depth) has been manually checked off — this is derived, not
  // stored, so it always reflects the current state of its words.
  bool _isFolderComplete(int folderId) {
    final leaves = _leafDescendants(folderId);
    if (leaves.isEmpty) return false; // nothing to complete yet
    return leaves.every((l) => _completedIds.contains(l.id));
  }

  Future<void> _loadTree() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    // Maps the person's selected app language to TradeLingo's own language
    // id numbering (see tradelingo_language_map.dart).
    final prefs = await SharedPreferences.getInstance();
    final appLanguageCode = prefs.getString('selectedLanguage') ?? 'en-US';
    final languageId = tradeLingoLanguageIdFor(appLanguageCode);

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

    // Live fetch failed (likely offline) - fall back to whatever was cached
    // from the last successful fetch, if anything (including a pre-warm
    // done right after the content package finished downloading).
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

  String get _imagesBaseUrl => 'https://cdn.800globalenglish.com/content/tradelingo/images';
  String get _thumbBaseUrl => 'https://cdn.800globalenglish.com/content/tradelingo/images/tmb';
  // One fixed banner image per industry, shown only on the root screen (not
  // on every drilled-down category). Bundled as a local asset instead of a
  // CDN fetch since these never change and this way they show instantly,
  // even offline, from the very first launch.
  String get _bannerAssetPath => widget.pageId == 2
      ? 'assets/images/construction_app.png'
      : 'assets/images/restaurant_app.png';
  // Sounds always live under the "restaurant" folder regardless of industry —
  // confirmed this matches the web version's own behavior (it hardcodes this
  // same path even on the Construction page). Not industry-aware; this is
  // just where the actual files are.
  String get _soundsBaseUrl => 'https://cdn.800globalenglish.com/content/tradelingo/restaurant/sounds';

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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResourceBrowserScreen(
          pageId: widget.pageId,
          screenTitle: _cleanTitle(folder.title),
          parentId: folder.id,
          preloadedItems: _allItems, // reuse — no re-fetch
        ),
      ),
    );
    // Reload here — words may have been checked off one or more levels
    // deeper, and this screen's copy of the completed-ids list was only
    // loaded once when it first opened, so it wouldn't otherwise know.
    if (mounted) await _loadCompletedIds();
  }

  // Some category titles have a leading number baked right into the text in
  // the database itself (e.g. "15  Materials", " 01  Hand tools - Hammers"),
  // presumably an internal sort/reference number from whoever entered the
  // data. Stripped here for display only — the underlying data is untouched.
  String _cleanTitle(String raw) => raw.replaceFirst(RegExp(r'^\s*\d+\s*'), '').trim();

  void _openWord(List<ResourceItem> siblingWords, int tappedIndex) {
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: const Center(child: CircularProgressIndicator()),
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
      );
    }

    final rawChildren = _allItems!.where((item) => item.parentId == widget.parentId).toList();
    final children = _sortWithCompletedAtBottom(rawChildren);

    final wordSiblings = children.where((c) => !c.isFolder).toList();

    if (children.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: Center(child: Text(ResourceStrings.instance.get('norecordfound'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.screenTitle)),
      body: Column(
        children: [
          // Banner — only on the root screen for this industry, not on
          // every drilled-down category screen.
          if (widget.parentId == 0)
            Image.asset(
              _bannerAssetPath,
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Play All — only shown when this screen actually has words to
          // play (not on a pure category-picker screen with just folders).
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
            child: ListView.builder(
              itemCount: children.length,
              itemBuilder: (context, index) {
                final item = children[index];
                final thumbUrl = item.imageUrl.isNotEmpty ? '$_thumbBaseUrl/${item.imageUrl}' : null;
                final industryIcon = widget.pageId == 2 ? Icons.construction : Icons.restaurant;

                // Folders derive their completion automatically from their words;
                // words are checked off manually by the person.
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
                      // Falls back to the same industry icon shown on the
                      // home screen rather than a "broken image" glyph, since
                      // not every category has a custom photo uploaded yet.
                      errorBuilder: (_, __, ___) => Icon(
                        industryIcon,
                        size: 32,
                        color: item.isFolder ? const Color(0xFF800000) : Colors.grey,
                      ),
                    ),
                  )
                      : Icon(
                    item.isFolder ? industryIcon : Icons.text_snippet,
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
