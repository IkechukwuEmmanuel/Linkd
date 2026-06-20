import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import '../widgets/facet_ring.dart';
import 'facet_detail_screen.dart';

/// Facets describe the user's OWN identity (the personal enrichment profile,
/// expressed as weighted facets). Their visual language is growth rings — never
/// memory cards, overlap circles, or connection threads.

/// 0.0–1.0 confidence/strength for a facet, used to size the ring.
double facetStrength(Persona p) =>
    (p.confidenceScore ?? (p.weight / 10)).clamp(0.0, 1.0);

MatchTier facetTier(Persona p) {
  final s = facetStrength(p);
  if (s >= 0.7) return MatchTier.strong;
  if (s >= 0.4) return MatchTier.moderate;
  return MatchTier.low;
}

bool facetConfirmed(Persona p) => facetTier(p) == MatchTier.strong;

String facetCaption(Persona p) {
  switch (facetTier(p)) {
    case MatchTier.strong:
      return 'strengthened over time';
    case MatchTier.moderate:
      return 'still forming · needs confirmation';
    case MatchTier.low:
      return 'one mention, fading';
  }
}

/// "Your facets" — list view.
class PersonasScreen extends ConsumerWidget {
  const PersonasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personasAsync = ref.watch(personasProvider);
    final tokens = MossTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('your facets',
            style: Theme.of(context).textTheme.displaySmall),
      ),
      body: personasAsync.when(
        data: (personas) {
          if (personas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('no facets yet',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 12),
                    Text(
                      'build your profile from a voice pitch or your linkedin, and your facets will grow here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: personas.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            separatorBuilder: (_, __) =>
                Divider(height: 1, thickness: 0.5, color: tokens.border),
            itemBuilder: (context, index) =>
                _FacetRow(persona: personas[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('error: $err',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

class _FacetRow extends StatelessWidget {
  final Persona persona;
  const _FacetRow({required this.persona});

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FacetDetailScreen(persona: persona),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            FacetRing(
              strength: facetStrength(persona),
              tier: facetTier(persona),
              size: 52,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(persona.label,
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 2),
                  Text(facetCaption(persona),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.textSecondary),
          ],
        ),
      ),
    );
  }
}
