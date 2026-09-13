import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../services/releases.dart';
import 'widgets/version_folder_list.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(Localizations.localeOf(context).languageCode);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('whatsNew'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            strings.t('versionHistoryHint'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          VersionFolderList(releases: khsReleases),
        ],
      ),
    );
  }
}