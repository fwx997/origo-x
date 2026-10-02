import 'package:flutter/material.dart';

import '../../utils/localization_extension.dart';
import '../../utils/page_style_helper.dart';
import 'floating_navigation_settings_page.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('偏好设置')),
    body: Container(
      decoration: BoxDecoration(
        gradient: PageStyleHelper.backgroundGradient(context),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              key: const ValueKey('preferences-floating-navigation'),
              leading: const Icon(Icons.dock_outlined),
              title: Text(context.l10n.settingsFloatingNavigationTitle),
              subtitle: Text(context.l10n.settingsFloatingNavigationSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FloatingNavigationSettingsPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
