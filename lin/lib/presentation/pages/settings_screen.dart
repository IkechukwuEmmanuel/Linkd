import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/auth_provider.dart';
import 'personas_screen.dart';

/// Settings — intentionally the quietest, least decorated screen. Flat list on
/// the page background: no avatar, no colored header band, no icons, no cards.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authNotifierProvider);
    final currentUser = ref.watch(currentUserProvider);
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);

    final email = currentUser?.email ?? 'you';
    final handle = email.contains('@') ? email.split('@').first : email;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings', style: theme.textTheme.displaySmall),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 8),
          Text('$handle · linkd member', style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),

          _row(context, label: 'email', value: email),
          _row(
            context,
            label: 'member since',
            value: _formatDate(currentUser?.createdAt),
          ),
          _row(
            context,
            label: 'your facets',
            value: 'view and confirm',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PersonasScreen()),
            ),
          ),
          _row(
            context,
            label: 'export my data',
            value: 'download everything',
            onTap: () => _exportData(context, ref),
          ),
          _row(
            context,
            label: 'about',
            value: 'version 1.0.0',
            onTap: () => _showAboutDialog(context),
          ),
          _row(
            context,
            label: 'delete my account',
            value: 'permanent',
            valueColor: tokens.danger,
            onTap: () => _showDeleteAccountConfirmation(context, ref),
          ),

          const SizedBox(height: 36),
          GestureDetector(
            onTap: () => _showLogoutConfirmation(context, ref),
            child: Text('log out',
                style: theme.textTheme.bodyLarge?.copyWith(color: tokens.danger)),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: tokens.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyLarge),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor ?? tokens.textSecondary,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: tokens.textSecondary),
            ],
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('log out?'),
        content: const Text('you\'ll need to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () {
              final nav = Navigator.of(context);
              Navigator.pop(dialogContext);
              ref.read(authNotifierProvider.notifier).logout();
              nav.popUntil((route) => route.isFirst);
            },
            child: Text('log out',
                style: TextStyle(color: MossTokens.of(context).danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('preparing your data export...')),
    );
    try {
      final data = await ref.read(apiClientProvider).exportMyData();
      final payload = (data['data'] as Map?) ?? {};
      final contacts = (payload['contacts'] as List?)?.length ?? 0;
      final personas = (payload['personas'] as List?)?.length ?? 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'export ready: $contacts contacts, $personas facets, and your account data.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('export failed: $e')));
    }
  }

  void _showDeleteAccountConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('delete account?'),
        content: const Text(
          'this permanently deletes your account and all associated data '
          '(contacts, facets, recording metadata, notifications). this cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              Navigator.pop(dialogContext);
              try {
                await ref.read(apiClientProvider).deleteMyAccount();
                await ref.read(authNotifierProvider.notifier).logout();
                nav.popUntil((route) => route.isFirst);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('could not delete account: $e')),
                );
              }
            },
            child: Text('delete',
                style: TextStyle(color: MossTokens.of(context).danger)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('about linkd'),
        content: Text(
          'linkd helps you remember the people you meet and find where you '
          'genuinely overlap.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'unknown';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
