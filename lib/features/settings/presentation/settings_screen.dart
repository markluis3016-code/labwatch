import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_settings.dart';
import '../../authentication/data/auth_repository.dart';
import '../data/settings_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final settingsAsync = ref.watch(appSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isAdmin = user?.isAdmin == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        maxWidth: 860,
        child: ListView(
          children: [
            const PageHeader(
              breadcrumb: 'System',
              title: 'Preferences and configuration',
              subtitle:
                  'Appearance is saved on this device. Operational settings are '
                  'stored in Firestore and apply to authorised monitoring.',
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Appearance',
              subtitle: 'Choose how LabWatch looks on this device',
              child: _AppearanceSelector(
                mode: themeMode == ThemeMode.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
                onChanged: (mode) =>
                    ref.read(themeModeProvider.notifier).setMode(mode),
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Energy-saving alerts',
              subtitle: isAdmin
                  ? 'Configures the in-app monitor for empty laboratories'
                  : 'View only · administrators can change these settings',
              child: settingsAsync.when(
                loading: () => const LoadingState(label: 'Loading settings…'),
                error: (_, __) => ErrorState(
                  message: 'Could not load system settings.',
                  onRetry: () => ref.invalidate(appSettingsProvider),
                ),
                data: (settings) {
                  final draft = _draft ?? settings;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable energy-saving detection'),
                        subtitle: const Text(
                          'Raise an alert when a laboratory is empty, no '
                          'reservation is active, and lights or air '
                          'conditioning remain on.',
                        ),
                        value: draft.energyAlertsEnabled,
                        onChanged: isAdmin
                            ? (value) => setState(
                                  () => _draft = draft.copyWith(
                                    energyAlertsEnabled: value,
                                  ),
                                )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Inactivity threshold: ${draft.energyInactivityMinutes} minutes',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Slider(
                        value: draft.energyInactivityMinutes.toDouble(),
                        min: 1,
                        max: 60,
                        divisions: 59,
                        label: '${draft.energyInactivityMinutes} min',
                        onChanged: isAdmin
                            ? (value) => setState(
                                  () => _draft = draft.copyWith(
                                    energyInactivityMinutes: value.round(),
                                  ),
                                )
                            : null,
                      ),
                      const InfoBanner(
                        text: 'Detection requires LIVE telemetry and an '
                            'authorised admin/staff session running LabWatch. '
                            'For continuous coverage, deploy the recommended '
                            'Cloud Function scheduler. Device shutoff is not '
                            'automatic unless a tested gateway integration is '
                            'configured.',
                        icon: Icons.energy_savings_leaf_outlined,
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed:
                              _saving ? null : () => _save(draft),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Save system settings'),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }

  Future<void> _save(AppSettings settings) async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).save(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System settings saved.')),
      );
      setState(() => _draft = null);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 420;
        final light = _AppearanceCard(
          selected: mode == ThemeMode.light,
          icon: Icons.light_mode_outlined,
          title: 'Light mode',
          subtitle: 'Clean, bright interface for well-lit environments.',
          onTap: () => onChanged(ThemeMode.light),
        );
        final dark = _AppearanceCard(
          selected: mode == ThemeMode.dark,
          icon: Icons.dark_mode_outlined,
          title: 'Dark mode',
          subtitle: 'High-contrast interface for low-light use.',
          onTap: () => onChanged(ThemeMode.dark),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: light),
              const SizedBox(width: 12),
              Expanded(child: dark),
            ],
          );
        }
        return Column(
          children: [light, const SizedBox(height: 12), dark],
        );
      },
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
