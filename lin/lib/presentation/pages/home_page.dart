import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/auth_provider.dart';
import '../providers/app_providers.dart';
import '../providers/onboarding_tour_provider.dart';
import '../widgets/onboarding_widgets.dart';
import 'contact_detail_page.dart';
import 'search_page.dart';

/// Relationship command center — the app's home hub.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF6C63FF),
      Color(0xFF00C896),
      Color(0xFFFF6B6B),
      Color(0xFFFFB547),
      Color(0xFF00AEEF),
      Color(0xFFFF6B9D),
    ];
    if (name.isEmpty) return colors.first;
    return colors[name.hashCode.abs() % colors.length];
  }

  void _openContact(BuildContext context, Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContactDetailPage(contact: contact)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final followUpsAsync = ref.watch(upcomingFollowUpsProvider);
    final insightsAsync = ref.watch(insightsSummaryProvider);
    final eventMode = ref.watch(eventModeProvider);
    final name = user?.email.split('@').first ?? 'there';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_greeting()},',
                style: Theme.of(context).textTheme.bodySmall),
            Text(name, style: Theme.of(context).textTheme.displaySmall),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
          _buildNotificationsButton(context, ref),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(contactsProvider);
              ref.invalidate(upcomingFollowUpsProvider);
              ref.invalidate(insightsSummaryProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _buildEventModeBar(context, ref, eventMode),
                _buildFollowUps(context, followUpsAsync),
                _buildNetworkStats(context, insightsAsync),
                const SizedBox(height: 24),
                _buildRecentContacts(context, contactsAsync),
                const SizedBox(height: 24),
                _buildClusters(context, insightsAsync),
              ],
            ),
          ),
          _buildTourOverlays(context, ref),
        ],
      ),
    );
  }

  // -------------------------------------------------------- notifications ---

  Widget _buildNotificationsButton(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);
    final unread = notifsAsync.maybeWhen(
      data: (d) => (d['unread_count'] as int?) ?? 0,
      orElse: () => 0,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => _showNotifications(context, ref),
        ),
        if (unread > 0)
          Positioned(
            top: 10,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: const BoxDecoration(
                color: AppTheme.accentWarm,
                shape: BoxShape.circle,
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, _) {
          final notifsAsync = sheetRef.watch(notificationsProvider);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (_, controller) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Text('Notifications',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .headlineMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await sheetRef
                              .read(apiClientProvider)
                              .markAllNotificationsRead();
                          sheetRef.invalidate(notificationsProvider);
                        },
                        child: const Text('Mark all read'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: notifsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('Couldn\'t load notifications')),
                    data: (d) {
                      final items = (d['data'] as List?) ?? [];
                      if (items.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('You\'re all caught up.'),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: controller,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final n = items[i] as Map;
                          final isRead = n['read'] == true;
                          return ListTile(
                            leading: Icon(
                              isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: isRead
                                  ? AppTheme.textHint
                                  : AppTheme.accentColor,
                            ),
                            title: Text('${n['title'] ?? ''}'),
                            subtitle: n['body'] != null
                                ? Text('${n['body']}')
                                : null,
                            onTap: () async {
                              final id = n['id'];
                              if (id is int) {
                                await sheetRef
                                    .read(apiClientProvider)
                                    .markNotificationRead(id);
                                sheetRef.invalidate(notificationsProvider);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------- event mode ---

  Widget _buildEventModeBar(
      BuildContext context, WidgetRef ref, EventModeState eventMode) {
    if (!eventMode.isActive) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(Icons.event, size: 18),
            label: const Text('Start event mode'),
            onPressed: () => _showStartEventSheet(context, ref),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, color: AppTheme.accentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Event: ${eventMode.eventName} · ${eventMode.captureCount} '
              'capture${eventMode.captureCount == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppTheme.accentColor),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(eventModeProvider.notifier).state =
                const EventModeState(),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }

  void _showStartEventSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start event mode',
                style: Theme.of(sheetContext).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Every contact you capture will be tagged with this event.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Event name',
                hintText: 'e.g. SaaStr Annual 2026',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  ref.read(eventModeProvider.notifier).state = EventModeState(
                    isActive: true,
                    eventName: name,
                  );
                  Navigator.pop(sheetContext);
                },
                child: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- follow-ups ---

  Widget _buildFollowUps(
      BuildContext context, AsyncValue<List<Contact>> followUpsAsync) {
    return followUpsAsync.maybeWhen(
      data: (followUps) {
        if (followUps.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, 'Follow-ups due', badge: followUps.length),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: followUps.take(8).length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final c = followUps[index];
                  return GestureDetector(
                    onTap: () => _openContact(context, c),
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppTheme.accentColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(c.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15),
                              overflow: TextOverflow.ellipsis),
                          if (c.company != null)
                            Text(c.company!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule,
                                  size: 14, color: AppTheme.accentColor),
                              const SizedBox(width: 4),
                              Text('Follow up soon',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.accentColor,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  // -------------------------------------------------------- network stats ---

  Widget _buildNetworkStats(
      BuildContext context, AsyncValue<InsightsSummary> insightsAsync) {
    return insightsAsync.when(
      loading: () => const SizedBox(
        height: 88,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryColor, AppTheme.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statTile('${s.totalContacts}', 'Contacts'),
            _divider(),
            _statTile('${s.followUpsDue}', 'Due'),
            _divider(),
            _statTile('${s.starredContacts}', 'Starred'),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 12)),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 36, color: Colors.white.withOpacity(0.15));

  // ----------------------------------------------------- recent contacts ---

  Widget _buildRecentContacts(
      BuildContext context, AsyncValue<List<Contact>> contactsAsync) {
    return contactsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (contacts) {
        if (contacts.isEmpty) {
          return _emptyHint(context,
              'No contacts yet — record a voice note or use Quick Capture to start your network.');
        }
        final recent = contacts.take(6).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, 'Recent contacts'),
            const SizedBox(height: 12),
            ...recent.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _contactRow(context, c),
                )),
          ],
        );
      },
    );
  }

  Widget _contactRow(BuildContext context, Contact c) {
    final pct = (c.overlapScore * 100).toInt();
    final overlapColor = c.overlapScore >= 0.7
        ? AppTheme.successColor
        : c.overlapScore >= 0.4
            ? AppTheme.warningColor
            : AppTheme.errorColor;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openContact(context, c),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _avatarColor(c.name),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [c.role, c.company]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' • '),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: overlapColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$pct%',
                  style: TextStyle(
                      color: overlapColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------- interest clusters ---

  Widget _buildClusters(
      BuildContext context, AsyncValue<InsightsSummary> insightsAsync) {
    return insightsAsync.maybeWhen(
      data: (s) {
        if (s.clusters.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, 'Top interest clusters'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: s.clusters.take(8).map((cluster) {
                final label = (cluster['interest'] ??
                        cluster['label'] ??
                        cluster['name'] ??
                        '')
                    .toString();
                final count = cluster['count'] ?? cluster['size'];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    count != null ? '$label · $count' : label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  // -------------------------------------------------------------- shared ---

  Widget _sectionHeader(BuildContext context, String title, {int? badge}) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (badge != null && badge > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accentWarm,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ],
      ],
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: AppTheme.accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    )),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------- onboarding tour overlays ---

  Widget _buildTourOverlays(BuildContext context, WidgetRef ref) {
    return Consumer(builder: (context, ref2, _) {
      final tour = ref2.watch(onboardingTourProvider);
      final demoList = ref2.watch(demoContactsProvider);
      final memIndex = ref2.watch(memoryIndexProvider);

      return Stack(children: [
        if (tour.headlineVisible) const HeadlineOverlay(),
        if (!tour.headlineVisible &&
            tour.step.index >= OnboardingTourStep.demoContact.index &&
            demoList.isNotEmpty)
          const DemoContactCard(),
        if (tour.step.index >= OnboardingTourStep.insightShown.index)
          const InsightPanel(
            title: 'You may want to follow up in ~5 days.',
            subtitle:
                'Strong alignment detected — high potential future value.',
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Record someone you met',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Private. Only visible to you.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => RecordingModal.show(context, ref),
                    child: const Text('Record'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!tour.signupCompleted && memIndex >= 1) ...[
          Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.35))),
          const Center(child: SignupGateOverlay()),
        ],
        if (tour.signupCompleted)
          Positioned(
              top: 80,
              left: 16,
              child: Text('Your memory system is now permanent.',
                  style: Theme.of(context).textTheme.bodyLarge)),
        if (tour.signupCompleted)
          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: Dismissible(
              key: const ValueKey('habit-banner'),
              direction: DismissDirection.up,
              onDismissed: (_) {},
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                        child: Text(
                            'After your next meeting, open Linkd and record one sentence about someone you met.')),
                    IconButton(
                        onPressed: () {}, icon: const Icon(Icons.close)),
                  ],
                ),
              ),
            ),
          ),
      ]);
    });
  }
}
