import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// The foundational "kept note" component for anything representing a CONTACT
/// (not a facet — facets use their own language, see [FacetRing]).
///
/// A flat surface with NO border, distinguished from the page only by fill,
/// with a small folded-corner triangle top-right (like a kept paper note) and
/// a deliberately near-square 2px radius. A 3px square-cornered left accent is
/// reserved for cards needing urgent attention (e.g. overdue follow-up); it is
/// not decorative.
class MemoryCard extends StatelessWidget {
  /// Optional content rendered above the name (e.g. a ConnectionThread on the
  /// contact detail card).
  final Widget? header;

  /// Shown in serif (the emotional/editorial moment).
  final String name;

  /// Smaller muted sans line, e.g. "met at SF Tech Week".
  final String? secondaryLine;

  /// Body / note text in sans regular.
  final String? body;

  /// "Shared ground" tags, rendered in moss green after a dotted rule.
  final List<String> sharedGround;
  final String sharedGroundLabel;

  /// Trailing widget on the header row (e.g. an OverlapIndicator or star).
  final Widget? trailing;

  /// Optional footer (e.g. follow-up status), separated by a thin top divider.
  final Widget? footer;

  /// Draws the urgent left accent when true.
  final bool urgent;

  final VoidCallback? onTap;

  const MemoryCard({
    super.key,
    this.header,
    required this.name,
    this.secondaryLine,
    this.body,
    this.sharedGround = const [],
    this.sharedGroundLabel = 'shared ground',
    this.trailing,
    this.footer,
    this.urgent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: CustomPaint(
          // Folded corner + optional left accent painted behind the content.
          painter: _MemoryCardPainter(
            surface: tokens.cardSurface,
            fold: tokens.cardFold,
            accent: urgent ? tokens.danger : null,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(urgent ? 17 : 14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[
                  header!,
                  const SizedBox(height: 14),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.headlineLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (secondaryLine != null &&
                              secondaryLine!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              secondaryLine!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      // Leave room for the folded corner.
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: trailing!,
                      ),
                    ],
                  ],
                ),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    body!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
                if (sharedGround.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SharedGroundRow(
                    label: sharedGroundLabel,
                    tags: sharedGround,
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, thickness: 0.5, color: tokens.border),
                  const SizedBox(height: 10),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `label  ········  tag · tag` — the dotted rule replaces chip borders here.
class _SharedGroundRow extends StatelessWidget {
  final String label;
  final List<String> tags;

  const _SharedGroundRow({required this.label, required this.tags});

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(width: 8),
        Expanded(
          child: CustomPaint(
            size: const Size(double.infinity, 1),
            painter: _DottedRulePainter(color: tokens.dottedRule),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            tags.join(' · '),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.tierStrong,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DottedRulePainter extends CustomPainter {
  final Color color;
  _DottedRulePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dot = 1.0;
    const gap = 3.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dot, y), paint);
      x += dot + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedRulePainter old) => old.color != color;
}

class _MemoryCardPainter extends CustomPainter {
  final Color surface;
  final Color fold;
  final Color? accent;

  _MemoryCardPainter({
    required this.surface,
    required this.fold,
    this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(2);
    final rect = Offset.zero & size;
    final body = RRect.fromRectAndCorners(
      rect,
      topLeft: radius,
      // Top-right corner is squared so the fold reads as a cut.
      bottomLeft: radius,
      bottomRight: radius,
    );
    canvas.drawRRect(body, Paint()..color = surface);

    // Folded-corner triangle, top-right (~14px), in a darker shade.
    const f = 14.0;
    final tri = Path()
      ..moveTo(size.width - f, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, f)
      ..close();
    canvas.drawPath(tri, Paint()..color = fold);

    // Urgent left accent: 3px solid, square corners.
    if (accent != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 3, size.height),
        Paint()..color = accent!,
      );
    }
  }

  @override
  bool shouldRepaint(_MemoryCardPainter old) =>
      old.surface != surface || old.fold != fold || old.accent != accent;
}
