import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/app_providers.dart';
import '../../presentation/providers/onboarding_tour_provider.dart';
import '../../presentation/widgets/onboarding_widgets.dart';

/// Dashboard/Home screen - main hub for the app
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final personasAsync = ref.watch(personasProvider);
    final metricsAsync = ref.watch(metricsProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final followUpsAsync = ref.watch(upcomingFollowUpsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linkd'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to settings
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome section
                  if (user != null) ...[
                    Text(
                      'Welcome back, ${user.email.split('@')[0]}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Quick stats
                  personasAsync.when(
                    data: (personas) => metricsAsync.when(
                      data: (metrics) => _buildStatsSection(context, personas, metrics),
                      loading: () => const CircularProgressIndicator(),
                      error: (err, _) => Text('Error: $err'),
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (err, _) => Text('Error: $err'),
                  ),

                  const SizedBox(height: 32),

                  // Quick action buttons
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildActionCard(
                        context,
                        icon: Icons.mic,
                        title: 'Record\nInteraction',
                        onTap: () {
                          RecordingModal.show(context, ref);
                        },
                      ),
                      _buildActionCard(
                        context,
                        icon: Icons.person,
                        title: 'Manage\nPersonas',
                        onTap: () {
                          // Navigate to personas screen
                        },
                      ),
                      _buildActionCard(
                        context,
                        icon: Icons.bar_chart,
                        title: 'View\nMetrics',
                        onTap: () {
                          // Navigate to metrics screen
                        },
                      ),
                      _buildActionCard(
                        context,
                        icon: Icons.contacts,
                        title: 'View\nContacts',
                        onTap: () {
                          // Navigate to contacts (tab 2)
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Follow-ups Due
                  followUpsAsync.when(
                    data: (followUps) {
                      if (followUps.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Follow-ups Due',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    followUps.length.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 90,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: followUps.take(5).length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final contact = followUps[index];
                                  return Container(
                                    width: 200,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          contact.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (contact.company != null)
                                          Text(
                                            contact.company!,
                                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.schedule, size: 14, color: AppTheme.accentColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Follow up soon',
                                              style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // Recent Contacts
                  contactsAsync.when(
                    data: (contacts) {
                      if (contacts.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recent Contacts',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: contacts.take(3).length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              final overlapPct = (contact.overlapScore * 100).toInt();
                              final overlapColor = contact.overlapScore >= 0.7
                                  ? AppTheme.secondaryColor
                                  : contact.overlapScore >= 0.4
                                      ? const Color(0xFFFFA500)
                                      : AppTheme.accentColor;
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: AppTheme.borderColor),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                  ),
                                  title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    [contact.role, contact.company]
                                        .where((s) => s != null)
                                        .join(' • '),
                                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: overlapColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$overlapPct%',
                                      style: TextStyle(
                                        color: overlapColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // Recent personas preview
                  personasAsync.when(
                    data: (personas) {
                      if (personas.isEmpty) {
                        return Column(
                          children: [
                            Text(
                              'No personas yet',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start by creating personas from your voice pitch or LinkedIn profile',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Personas',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: personas.take(3).length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final persona = personas[index];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                                    child: Text(
                                      persona.label[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(persona.label),
                                  subtitle: Text('Weight: ${persona.weight}/10'),
                                  trailing: Icon(
                                    Icons.trending_up,
                                    color: AppTheme.secondaryColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (err, _) => Text('Error: $err'),
                  ),
                ],
              ),
            ),
          ),

          // Onboarding overlays/widgets
          Consumer(builder: (context, ref2, _) {
            final tour = ref2.watch(onboardingTourProvider);
            final demoList = ref2.watch(demoContactsProvider);
            final memIndex = ref2.watch(memoryIndexProvider);

            return Stack(children: [
              if (tour.headlineVisible) const HeadlineOverlay(),
              if (!tour.headlineVisible && tour.step.index >= OnboardingTourStep.demoContact.index && demoList.isNotEmpty)
                const DemoContactCard(),
              if (tour.step.index >= OnboardingTourStep.insightShown.index)
                const InsightPanel(
                  title: 'You may want to follow up in ~5 days.',
                  subtitle: 'Strong alignment detected — high potential future value.',
                ),
              // Bottom action bar
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Record someone you met', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                              Text('Private. Only visible to you.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => RecordingModal.show(context, ref),
                          child: const Text('Record'),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Memory index', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                            Text(memIndex.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Signup gate
              if (!tour.signupCompleted && memIndex >= 1) ...[
                // dim background
                Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
                const Center(child: SignupGateOverlay()),
              ],
              // Post-signup reinforcement
              if (tour.signupCompleted) Positioned(top: 80, left: 16, child: Text('Your memory system is now permanent.', style: Theme.of(context).textTheme.bodyLarge)),
              // Habit banner
              if (tour.signupCompleted) Positioned(top: 20, left: 16, right: 16, child: Dismissible(
                key: const ValueKey('habit-banner'),
                direction: DismissDirection.up,
                onDismissed: (_) {},
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(child: Text('After your next meeting, open LINKED and record one sentence about someone you met.')),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.close))
                    ],
                  ),
                ),
              )),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, List personas, metrics) {
    return Column(
      children: [
        Row(
          children: [
            _buildStatCard(
              context,
              title: 'Personas',
              value: personas.length.toString(),
              icon: Icons.person,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              context,
              title: 'Interactions',
              value: metrics.totalInteractions.toString(),
              icon: Icons.chat,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard(
              context,
              title: 'Accuracy',
              value: '${(metrics.avgExtractionAccuracy * 100).toStringAsFixed(0)}%',
              icon: Icons.check_circle,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              context,
              title: 'Approval Rate',
              value: '${(metrics.approvalRate * 100).toStringAsFixed(0)}%',
              icon: Icons.thumb_up,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderColor,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
