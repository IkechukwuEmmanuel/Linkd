import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/app_providers.dart';
import '../../presentation/providers/auth_provider.dart';

/// Screen displaying user metrics, analytics, and AI insights about profiles
class MetricsScreen extends ConsumerWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);
    final personasAsync = ref.watch(personasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        elevation: 0,
        centerTitle: true,
      ),
      body: metricsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('Error loading insights: $error'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => ref.refresh(metricsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (metrics) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _buildMetricCard(
                      context,
                      title: 'Total Interactions',
                      value: metrics.totalInteractions.toString(),
                      icon: Icons.comment,
                      color: AppTheme.primaryColor,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Total Networks',
                      value: metrics.totalPersonas.toString(),
                      icon: Icons.people,
                      color: AppTheme.secondaryColor,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Extraction Accuracy',
                      value:
                          '${(metrics.avgExtractionAccuracy * 100).toStringAsFixed(1)}%',
                      icon: Icons.show_chart,
                      color: Colors.green,
                    ),
                    _buildMetricCard(
                      context,
                      title: 'Approval Rate',
                      value: '${(metrics.approvalRate * 100).toStringAsFixed(1)}%',
                      icon: Icons.thumb_up,
                      color: Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                // AI Insights Section
                Text(
                  'AI Insights About Your Networks',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                personasAsync.when(
                  data: (personas) {
                    if (personas.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Text(
                            'No network profiles yet. Start recording to get AI insights!',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: personas.length,
                      itemBuilder: (context, index) {
                        final persona = personas[index];
                        return _buildProfileInsightCard(
                          context,
                          persona: persona,
                          index: index,
                        );
                      },
                    );
                  },
                  loading: () => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  error: (err, _) => Text('Error loading profiles: $err'),
                ),
                
                const SizedBox(height: 32),
                
                // General Insights
                Text(
                  'Overall Performance',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                _buildDetailCard(
                  context,
                  title: 'Top Performing Network',
                  value: metrics.topPersona ?? 'N/A',
                  subtitle: 'Your most frequently matched profile',
                  icon: Icons.star,
                ),
                const SizedBox(height: 12),
                _buildDetailCard(
                  context,
                  title: 'Average Interaction Length',
                  value:
                      '${(metrics.avgInteractionLength ?? 0).toStringAsFixed(1)}s',
                  subtitle: 'Average duration per recorded interaction',
                  icon: Icons.schedule,
                ),
                const SizedBox(height: 12),
                _buildDetailCard(
                  context,
                  title: 'Last Active',
                  value: _formatDate(metrics.lastInteractionAt),
                  subtitle: 'Time of most recent interaction',
                  icon: Icons.access_time,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInsightCard(
    BuildContext context, {
    required persona,
    required int index,
  }) {
    // Generate AI-powered insights based on persona data
    final insights = _generateAIInsights(persona);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.person,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona.label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 14,
                            color: AppTheme.secondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Confidence: ${((persona.confidenceScore ?? 0) * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // AI Insights
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb,
                        size: 16,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Insights',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...insights.map((insight) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '•',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              insight,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _generateAIInsights(persona) {
    // Generate contextual AI insights based on persona attributes
    final insights = <String>[];
    
    final confidence = (persona.confidenceScore ?? 0) * 100;
    final weight = persona.weight ?? 0;
    
    if (confidence > 80) {
      insights.add('High confidence match - consistently identified in interactions');
    } else if (confidence > 60) {
      insights.add('Moderate confidence - keep recording to strengthen this match');
    } else {
      insights.add('Building this network - record more interactions to improve accuracy');
    }
    
    if (weight > 8) {
      insights.add('Heavily weighted profile - appears frequently in your records');
    } else if (weight > 5) {
      insights.add('Active profile - moderate engagement level');
    }
    
    insights.add('Recommended: Connect with this profile for follow-ups');
    
    return insights;
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: AppTheme.primaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return date.toString().split(' ')[0];
    }
  }
}
