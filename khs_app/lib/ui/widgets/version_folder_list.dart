import 'package:flutter/material.dart';

import '../../services/releases.dart';

/// Список версий «как папка с файлами»: у каждой версии — строка-заголовок,
/// по нажатию под ней раскрываются (снизу) изменения этой версии.
/// Сворачивается и разворачивается независимо от соседей.
class VersionFolderList extends StatefulWidget {
  const VersionFolderList({super.key, required this.releases});

  final List<ReleaseInfo> releases;

  @override
  State<VersionFolderList> createState() => _VersionFolderListState();
}

class _VersionFolderListState extends State<VersionFolderList> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    // Последняя (текущая) версия открыта сразу — видно, что новое.
    if (widget.releases.isNotEmpty) _expanded.add(widget.releases.first.version);
  }

  @override
  void didUpdateWidget(VersionFolderList old) {
    super.didUpdateWidget(old);
    if (widget.releases.isNotEmpty) _expanded.add(widget.releases.first.version);
  }

  void _toggle(String version) {
    setState(() {
      if (!_expanded.remove(version)) _expanded.add(version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < widget.releases.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _buildTile(scheme, widget.releases[i]),
        ],
      ],
    );
  }

  Widget _buildTile(ColorScheme scheme, ReleaseInfo release) {
    final hasFeatures =
        release.changes.any((c) => c.type == ChangeType.feature);
    final hasBugfixes = release.changes.any((c) => c.type == ChangeType.bugfix);
    final open = _expanded.contains(release.version);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('release-${release.version}'),
        initiallyExpanded: open,
        onExpansionChanged: (nowOpen) => _toggle(release.version),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 12, right: 4, bottom: 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v${release.version}',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              release.date,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            if (hasFeatures)
              Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
            if (hasFeatures && hasBugfixes) const SizedBox(width: 4),
            if (hasBugfixes)
              Icon(Icons.bug_report, size: 16, color: Colors.orange),
          ],
        ),
        children: [
          for (final entry in release.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconForType(entry.type),
                    size: 16,
                    color: _colorForType(entry.type, scheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(entry.text, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconForType(ChangeType type) {
    return switch (type) {
      ChangeType.feature => Icons.auto_awesome,
      ChangeType.bugfix => Icons.bug_report,
      ChangeType.improvement => Icons.tune,
    };
  }

  static Color _colorForType(ChangeType type, ColorScheme scheme) {
    return switch (type) {
      ChangeType.feature => scheme.primary,
      ChangeType.bugfix => Colors.orange,
      ChangeType.improvement => scheme.onSurfaceVariant,
    };
  }
}