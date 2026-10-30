import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../services/app_updates.dart';
import '../services/backup_service.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';
import 'widgets/settings_section.dart';
import 'widgets/spacing.dart';

/// Single-page, searchable Settings screen, laid out like every Mfficiency
/// app (Vesta Immo's settings page is the reference):
///  * A pinned header of **section chips** — tap one to smoothly scroll to that
///    section; the active chip follows the scroll position.
///  * A **search** (magnifier in the app bar) that filters every individual
///    setting by title/keyword; tapping a result opens and jumps to its section.
///  * Foldable section cards ([SettingsSection]) with Collapse/Expand all.
///    Order and rows as in every Mfficiency app (the template's
///    docs/CONCEPT.md §5): Appearance first (Theme · Compact mode · Time
///    format · Date format, then the app's own), the app's sections, then
///    Debugging (Send a report · GitHub token), Updates (Check
///    automatically · Check for updates · GitHub token) and Backup & data
///    (Back up everything · Restore from a backup · Backup location ·
///    Automatic backup · Last backup, then the app's own) last. The shared
///    rows are the updates package's tiles.
///
/// Every setting reads and writes [AppSettings]; saving notifies listeners so
/// the theme updates instantly. Export/import use the versioned
/// [BackupService].
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppSettings _s = AppSettings.instance;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tabsHeaderKey = GlobalKey();
  // Every visit starts with all sections collapsed (the same in every
  // Mfficiency app); a header, chip or search result opens one.
  final Set<String> _collapsed = {..._sectionTitles};
  final List<GlobalKey> _sectionKeys = List<GlobalKey>.generate(
    _sectionTitles.length,
    (_) => GlobalKey(),
  );
  static const List<String> _sectionTitles = [
    'Appearance',
    'Collage',
    'Debugging',
    'Updates',
    'Backup & data',
  ];
  int _activeSectionIndex = 0;
  static const double _tabsHeaderHeight = 64;

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Every setting, so search can find it (like Vesta's `_searchIndex`). Section indexes match
  /// [_sectionTitles]; keywords add synonyms users might type.
  static const List<_SearchEntry> _searchEntries = [
    _SearchEntry(
      'Theme (system, light, dark)',
      0,
      'appearance system light dark night colour color mode',
    ),
    _SearchEntry('Compact mode', 0, 'dense density tight spacing small'),
    _SearchEntry('Time format', 0, 'clock am pm 12-hour 24-hour'),
    _SearchEntry('Date format', 0, 'display day month year'),
    _SearchEntry(
      'Minimalist mode',
      0,
      'monochrome calm plain simple no colours underline',
    ),
    _SearchEntry('Export size', 1, 'resolution pixels quality save picture'),
    _SearchEntry('Date stamp on new collages', 1, 'date taken show default'),
    _SearchEntry('Send a report', 2, 'claude bug problem report issue logs fix'),
    _SearchEntry(
      'GitHub token (problem reports)',
      2,
      'token key pat github claude report issue',
    ),
    _SearchEntry(
      'Automatically check for updates',
      3,
      'update upgrade new version install apk download',
    ),
    _SearchEntry(
      'Check for updates',
      3,
      'update upgrade new version install apk download latest',
    ),
    _SearchEntry(
      'GitHub token (updates)',
      3,
      'token key private pat github access',
    ),
    _SearchEntry(
      'Back up everything',
      4,
      'backup full downloads photos collages reinstall uninstall',
    ),
    _SearchEntry(
      'Restore from a backup',
      4,
      'restore backup full downloads reinstall',
    ),
    _SearchEntry('Backup location', 4, 'folder downloads where'),
    _SearchEntry('Automatic backup', 4, 'schedule daily weekly off backup'),
    _SearchEntry('Last backup', 4, 'when backup date'),
    _SearchEntry('Export everything', 4, 'backup save json data settings file'),
    _SearchEntry('Export settings', 4, 'backup save json preferences'),
    _SearchEntry('Import', 4, 'restore backup load json file'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveSectionFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateActiveSectionFromScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSectionFromScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- Persistence helper ---------------------------------------------------

  Future<void> _apply(VoidCallback mutate) async {
    setState(mutate);
    await _s.save(); // persists + notifies listeners (theme refreshes)
  }

  // --- Scroll / section tracking (Vesta's mechanism) ----------------------

  Future<void> _jumpToSection(int index) async {
    // A chip opens its section too: they all start collapsed.
    setState(() {
      _activeSectionIndex = index;
      _collapsed.remove(_sectionTitles[index]);
    });
    await WidgetsBinding.instance.endOfFrame;
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: 0.02,
    );
  }

  /// The active chip is the last section whose top is above the line 24 px
  /// under the pinned header.
  void _updateActiveSectionFromScroll() {
    final tabs =
        _tabsHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    if (tabs == null || !tabs.hasSize) return;
    final line = tabs.localToGlobal(Offset.zero).dy + tabs.size.height + 24;
    var index = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final box =
          _sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy <= line) index = i;
    }
    if (index != _activeSectionIndex && mounted) {
      setState(() => _activeSectionIndex = index);
    }
  }

  // --- Folding --------------------------------------------------------------

  void _toggleSection(int index) => setState(() {
        final title = _sectionTitles[index];
        if (!_collapsed.remove(title)) _collapsed.add(title);
      });

  bool get _anyExpanded => _collapsed.length < _sectionTitles.length;

  void _toggleAll() => setState(() {
        if (_anyExpanded) {
          _collapsed.addAll(_sectionTitles);
        } else {
          _collapsed.clear();
        }
      });

  /// One foldable card; [index] picks title and key from [_sectionTitles].
  Widget _section(int index, List<Widget> children) => SettingsSection(
        sectionKey: _sectionKeys[index],
        title: _sectionTitles[index],
        collapsed: _collapsed.contains(_sectionTitles[index]),
        onToggle: () => _toggleSection(index),
        children: children,
      );

  // --- Search ---------------------------------------------------------------

  List<_SearchEntry> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _searchEntries
        .where(
          (e) => '${e.title} ${e.keywords} ${_sectionTitles[e.sectionIndex]}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
  }

  void _closeSearch() => setState(() {
        _searchActive = false;
        _searchController.clear();
        _searchQuery = '';
      });

  void _openSearchResult(_SearchEntry entry) {
    _closeSearch();
    setState(() => _collapsed.remove(_sectionTitles[entry.sectionIndex]));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToSection(entry.sectionIndex);
    });
  }

  // --- Backups --------------------------------------------------------------

  Future<void> _export({required bool includeData}) async {
    final dir = await getDirectoryPath();
    if (dir == null) {
      _snack('Export canceled');
      return;
    }
    final file = await BackupService.instance.exportToDirectory(
      dir,
      includeData: includeData,
    );
    _snack(file != null ? 'Exported to ${file.path}' : 'Export failed');
  }

  Future<void> _import() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final result = await BackupService.instance.importFile(picked.path);
    if (result.applied) {
      await _s.save(); // persist restored settings + refresh theme
      if (mounted) setState(() {});
    }
    final suffix =
        result.warnings.isEmpty ? '' : ' (${result.warnings.join(' | ')})';
    _snack(result.applied ? 'Import complete$suffix' : 'Import failed$suffix');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Sections -------------------------------------------------------------

  Widget _appearanceSection() => _section(0, [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Expanded(child: Text('Theme')),
              SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    tooltip: 'System',
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    tooltip: 'Light',
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    tooltip: 'Dark',
                  ),
                ],
                selected: {_s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (set) =>
                    _apply(() => _s.themeMode = set.first),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Compact mode'),
          subtitle: const Text(
            'Tighter spacing in lists, menus and every screen',
          ),
          value: _s.compact,
          onChanged: (v) => _apply(() => _s.compact = v),
        ),
        ListTile(
          title: const Text('Time format'),
          subtitle: Text(formatTime(DateTime(2026, 3, 9, 14, 30))),
          trailing: DropdownButton<bool>(
            key: const Key('settings.timeFormat'),
            value: _s.use24HourFormat,
            items: const [
              DropdownMenuItem(value: true, child: Text('24-hour')),
              DropdownMenuItem(value: false, child: Text('12-hour')),
            ],
            onChanged: (v) {
              if (v != null) _apply(() => _s.use24HourFormat = v);
            },
          ),
        ),
        ListTile(
          title: const Text('Date format'),
          subtitle: Text(formatDate(DateTime(2026, 3, 9))),
          trailing: DropdownButton<String>(
            value: _s.dateFormat,
            items: AppSettings.dateFormats
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) {
              if (v != null) _apply(() => _s.dateFormat = v);
            },
          ),
        ),
        SwitchListTile(
          title: const Text('Minimalist mode'),
          subtitle: const Text(
            'Calm monochrome look: no colours, underlines instead of '
            'highlights',
          ),
          value: _s.minimalist,
          onChanged: (v) => _apply(() => _s.minimalist = v),
        ),
      ]);

  Widget _collageSection() => _section(1, [
        ListTile(
          title: const Text('Export size'),
          subtitle: const Text('Long edge of the saved picture'),
          trailing: DropdownButton<int>(
            value: AppSettings.exportSizes.contains(_s.exportLongEdge)
                ? _s.exportLongEdge
                : AppSettings.exportSizes.first,
            items: AppSettings.exportSizes
                .map((px) => DropdownMenuItem(value: px, child: Text('$px px')))
                .toList(),
            onChanged: (v) {
              if (v != null) _apply(() => _s.exportLongEdge = v);
            },
          ),
        ),
        SwitchListTile(
          title: const Text('Date stamp on new collages'),
          subtitle: const Text(
            'Show the date each photo was taken (dd.mm.yy) by default',
          ),
          value: _s.dateStampByDefault,
          onChanged: (v) => _apply(() => _s.dateStampByDefault = v),
        ),
      ]);

  /// Send a report (to Claude) · GitHub token (for the reports).
  Widget _debuggingSection() {
    final reporter = AppUpdates.instance.problemReport;
    return _section(2, [
      ProblemReportSendTile(reporter: reporter),
      ProblemReportSettingsTile(reporter: reporter),
    ]);
  }

  /// Check automatically · Check for updates · GitHub token (read access to
  /// the release repo, needed once it is private).
  Widget _updatesSection() {
    final updates = AppUpdates.instance;
    return _section(3, [
      SwitchListTile(
        secondary: const Icon(Icons.update),
        title: const Text('Automatically check for updates'),
        subtitle: const Text(
          'Checks for a newer version every 15 minutes while the app is '
          'open and downloads it silently in the background; when it is '
          'complete Android asks "Update this app?". Nothing installs '
          'without your tap. Check for updates always works.',
        ),
        value: _s.autoUpdateCheckEnabled,
        onChanged: (v) => _apply(() => _s.autoUpdateCheckEnabled = v),
      ),
      // Checks now; a newer build downloads silently and Android asks
      // "Update this app?" when it is complete. Progress as the subtitle.
      UpdateCheckTile(controller: updates.controller),
      UpdateTokenTile(
        controller: updates.controller,
        repo: AppUpdates.repo,
        readToken: updates.readToken,
        writeToken: updates.writeToken,
        openUrl: AppUpdates.openUrl,
      ),
    ]);
  }

  /// The full backup's five rows (Android only), then the app's own JSON
  /// export and import.
  Widget _dataSection() => _section(4, [
        // Everything (collages, photo copies, settings) as one file in
        // Download/BestCollage/Backups, kept when the app is uninstalled.
        if (AppUpdates.instance.backup case final backup?)
          FullBackupTiles(backup: backup, strings: AppUpdates.backupStrings),
        ListTile(
          leading: const Icon(Icons.file_download),
          title: const Text('Export everything'),
          subtitle: const Text(
            'Settings and data as a JSON file in a folder you pick',
          ),
          onTap: () => _export(includeData: true),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Export settings'),
          subtitle: const Text('Only the settings, as a JSON file'),
          onTap: () => _export(includeData: false),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload),
          title: const Text('Import'),
          subtitle: const Text('Settings and data from an exported JSON file'),
          onTap: _import,
        ),
      ]);

  Widget _buildSearchField() => TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search settings',
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      );

  List<Widget> _buildSearchResultTiles() {
    final results = _searchResults;
    if (results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No settings match your search')),
        ),
      ];
    }
    return results
        .map<Widget>(
          (e) => ListTile(
            title: Text(e.title),
            subtitle: Text(_sectionTitles[e.sectionIndex]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSearchResult(e),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final showSearchResults = _searchActive && _searchQuery.trim().isNotEmpty;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Settings',
        actions: [
          _searchActive
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search settings',
                  onPressed: () => setState(() => _searchActive = true),
                ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeaderDelegate(
              height: _tabsHeaderHeight,
              child: Container(
                key: _tabsHeaderKey,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: _searchActive
                    ? _buildSearchField()
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _sectionTitles.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_sectionTitles[i]),
                                selected: _activeSectionIndex == i,
                                onSelected: (_) => _jumpToSection(i),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: showSearchResults
                        ? _buildSearchResultTiles()
                        : [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _toggleAll,
                                icon: Icon(
                                  _anyExpanded
                                      ? Icons.unfold_less
                                      : Icons.unfold_more,
                                ),
                                label: Text(
                                  _anyExpanded ? 'Collapse all' : 'Expand all',
                                ),
                              ),
                            ),
                            _appearanceSection(),
                            _collageSection(),
                            _debuggingSection(),
                            _updatesSection(),
                            _dataSection(),
                            // Lets the last section scroll to the top.
                            const SizedBox(height: 200),
                          ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A searchable settings entry: title, owning section index, extra keywords.
class _SearchEntry {
  final String title;
  final int sectionIndex;
  final String keywords;
  const _SearchEntry(this.title, this.sectionIndex, [this.keywords = '']);
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  const _TabsHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate old) =>
      old.height != height || old.child != child;
}
