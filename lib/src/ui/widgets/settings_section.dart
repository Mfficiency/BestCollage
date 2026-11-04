import 'package:flutter/material.dart';

/// A foldable card grouping related settings, the same in every Mfficiency
/// app: a bold titleMedium header with an expand_more arrow that toggles the
/// section, the rows below it while open. Plain [Card] of the theme, 4 px
/// between cards. The [sectionKey] anchors scroll-to-section jumps.
class SettingsSection extends StatelessWidget {
  final Key? sectionKey;
  final String title;
  final List<Widget> children;

  /// Folded shut: only the header shows.
  final bool collapsed;

  /// Tapping the header; null = the section can't fold.
  final VoidCallback? onToggle;

  const SettingsSection({
    super.key,
    this.sectionKey,
    required this.title,
    required this.children,
    this.collapsed = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      // Little white space between the foldables (the Card adds 4 px above
      // and below); the other Mfficiency apps use the same.
      margin: const EdgeInsets.only(bottom: 4),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Tooltip(
                      message: collapsed ? 'Expand $title' : 'Collapse $title',
                      child: AnimatedRotation(
                        turns: collapsed ? 0 : 0.5,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.expand_more),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...children,
            if (!collapsed) const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
