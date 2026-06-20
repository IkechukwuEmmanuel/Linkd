import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import '../widgets/facet_ring.dart';
import 'personas_screen.dart';

/// Facet detail — the same growth-ring graphic scaled up, with the evidence
/// behind the facet and (only when unconfirmed) the confirm/dismiss choice.
class FacetDetailScreen extends ConsumerWidget {
  final Persona persona;
  const FacetDetailScreen({super.key, required this.persona});

  String _statusLabel(MatchTier tier) => switch (tier) {
        MatchTier.strong => 'confirmed',
        MatchTier.moderate => 'still forming',
        MatchTier.low => 'fading',
      };

  Future<void> _sendFeedback(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(
        submitFeedbackProvider((
          personaId: persona.id,
          feedbackType: type,
          rating: null,
          notes: null,
        )).future,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(type == 'approved' ? 'kept this facet' : 'dismissed'),
        ),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('something went wrong: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = MossTokens.of(context);
    final tier = facetTier(persona);
    final tierColor = tier.color(tokens);
    final confirmed = facetConfirmed(persona);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          Center(
            child: FacetRing(
              strength: facetStrength(persona),
              tier: tier,
              size: 84,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(persona.label,
                style: Theme.of(context).textTheme.displaySmall),
          ),
          const SizedBox(height: 10),
          Center(child: _statusPill(context, tierColor, _statusLabel(tier))),
          const SizedBox(height: 32),

          Text('why we think this',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _evidenceCard(context, tokens),

          if (!confirmed) ...[
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _sendFeedback(context, ref, 'approved'),
                child: const Text('yes, that\'s me'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _sendFeedback(context, ref, 'rejected'),
                child: const Text('not really'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    );
  }

  Widget _evidenceCard(BuildContext context, MossTokens tokens) {
    final created = persona.createdAt;
    final source = created != null
        ? 'from your profile · ${_relative(created)}'
        : 'from your profile';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: tokens.tierStrong, width: 2),
              ),
            ),
            child: Text(
              facetCaption(persona),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return DateFormat('MMM d, yyyy').format(date);
  }
}
