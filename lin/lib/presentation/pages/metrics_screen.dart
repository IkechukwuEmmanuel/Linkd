import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../../presentation/providers/app_providers.dart';
import 'personas_screen.dart';

/// Metrics — system-health data (extraction accuracy, counts), not relationship
/// content. Deliberately typography-led, same restrained ledger pattern as the
/// settings screen: no charts, no colored stat cards, no icons.
class MetricsScreen extends ConsumerWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);
    final personasAsync = ref.watch(personasProvider);
    final insightsAsync = ref.watch(insightsSummaryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: metricsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _errorState(context, ref, error),
        data: (metrics) {
          // facets confirmed = strong-tier facets out of the total.
          final personas = personasAsync.asData?.value ?? const [];
          final confirmed = personas.where(facetConfirmed).length;
          final totalFacets = personas.isNotEmpty
              ? personas.length
              : metrics.totalPersonas;
          final people = insightsAsync.asData?.value.totalContacts;

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            children: [
              Text('how it\'s going.', style: theme.textTheme.displayMedium),
              const SizedBox(height: 32),

              _line(context,
                  label: 'people you know',
                  value: people != null ? '$people' : '—'),
              _line(context,
                  label: 'conversations captured',
                  value: '${metrics.totalInteractions}'),
              _line(context,
                  label: 'extraction accuracy',
                  value:
                      '${(metrics.avgExtractionAccuracy * 100).round()}%'),
              _line(context,
                  label: 'facets confirmed',
                  value: '$confirmed of $totalFacets'),
              _line(context,
                  label: 'last capture',
                  value: _relativeTime(metrics.lastInteractionAt)),

              const SizedBox(height: 36),
              Text(
                _insight(context, metrics),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: MossTokens.of(context).textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One ledger row: muted label left, primary value right.
  Widget _line(BuildContext context,
      {required String label, required String value}) {
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: tokens.textSecondary)),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  /// One plain-language closing line — never a list of tips.
  String _insight(BuildContext context, Metrics metrics) {
    if (metrics.totalInteractions == 0) {
      return 'capture your first conversation and your numbers will start to fill in here.';
    }
    if (metrics.approvalRate >= 0.6) {
      return 'your facets are landing — most of what we surface, you keep.';
    }
    return 'the more you capture, the sharper these get.';
  }

  Widget _errorState(BuildContext context, WidgetRef ref, Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('couldn\'t load your numbers',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => ref.invalidate(metricsProvider),
              child: const Text('retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return 'never';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
