import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/auth_provider.dart';
import '../providers/app_providers.dart';
import '../widgets/memory_card.dart';
import '../widgets/overlap_indicator.dart';
import 'contact_detail_page.dart';
import 'contacts_page.dart';
import 'record_interaction_screen.dart';
import 'search_page.dart';

/// The dashboard — deliberately the simplest possible version (Section 7):
/// a greeting, follow-ups due, recent contacts, and one capture entry point.
/// No stats grid, no facet preview, no onboarding-tour overlay (Section 7a).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  // "tuesday evening" — small muted day/time line.
  String _dayLine() {
    const days = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday',
    ];
    final now = DateTime.now();
    final part = now.hour < 12
        ? 'morning'
        : now.hour < 17
            ? 'afternoon'
            : 'evening';
    return '${days[now.weekday - 1]} $part';
  }

  void _openContact(BuildContext context, Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContactDetailPage(contact: contact)),
    );
  }

  void _openCapture(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordInteractionScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final followUpsAsync = ref.watch(upcomingFollowUpsProvider);
    final eventMode = ref.watch(eventModeProvider);
    final theme = Theme.of(context);
    final name = user?.email.split('@').first ?? 'there';

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(contactsProvider);
          ref.invalidate(upcomingFollowUpsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // 1. Greeting — two modest lines, not a hero moment.
            Text(_dayLine(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('welcome back, $name',
                style: theme.textTheme.displaySmall),
            const SizedBox(height: 24),

            if (eventMode.isActive) ...[
              _buildEventModeBar(context, ref, eventMode),
              const SizedBox(height: 24),
            ],

            // 2. Follow-ups due (only when non-empty).
            _buildFollowUps(context, followUpsAsync),

            // 3. Recent.
            _buildRecent(context, contactsAsync),

            const SizedBox(height: 24),

            // 4. Capture entry point.
            _buildCaptureCard(context),

            // Quiet event-mode entry — only when not already in an event, so the
            // feature stays reachable without competing with the two sections.
            if (!eventMode.isActive) ...[
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => _showStartEventSheet(context, ref),
                  child: Text('start event mode →',
                      style: theme.textTheme.bodySmall),
                ),
              ),
            ],
          ],
        ),
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
            Text('start event mode',
                style: Theme.of(sheetContext).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'every contact you capture will be tagged with this event.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'event name',
                hintText: 'e.g. saastr annual 2026',
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
                child: const Text('start'),
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
            _sectionHeader(context, 'follow-ups due'),
            const SizedBox(height: 12),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: followUps.take(10).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final c = followUps[index];
                  final (caption, overdue) = _dueCaption(c.followUpDue);
                  return SizedBox(
                    width: 240,
                    child: MemoryCard(
                      name: c.name,
                      secondaryLine: c.company,
                      urgent: overdue,
                      onTap: () => _openContact(context, c),
                      footer: _dueFooter(context, caption, overdue),
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

  Widget _dueFooter(BuildContext context, String caption, bool overdue) {
    final tokens = MossTokens.of(context);
    return Text(
      caption,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: overdue ? tokens.danger : tokens.tierModerate,
          ),
    );
  }

  /// Returns the urgency caption and whether the follow-up is overdue.
  (String, bool) _dueCaption(String? due) {
    if (due == null) return ('follow up soon', false);
    final parsed = DateTime.tryParse(due);
    if (parsed == null) return ('follow up soon', false);
    final today = DateTime.now();
    final days = DateTime(parsed.year, parsed.month, parsed.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days < 0) return ('overdue', true);
    if (days == 0) return ('due today', false);
    if (days == 1) return ('due tomorrow', false);
    return ('due in $days days', false);
  }

  // -------------------------------------------------------------- recent ---

  Widget _buildRecent(
      BuildContext context, AsyncValue<List<Contact>> contactsAsync) {
    return contactsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (contacts) {
        if (contacts.isEmpty) {
          return _emptyHint(context,
              'no one yet — record someone you met and they\'ll show up here.');
        }
        final recent = contacts.take(5).toList();
        final hasMore = contacts.length > recent.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, 'recent'),
            const SizedBox(height: 12),
            ...recent.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: MemoryCard(
                    name: c.name,
                    secondaryLine: _roleCompany(c),
                    sharedGround: c.overlapPoints,
                    onTap: () => _openContact(context, c),
                    trailing: OverlapIndicator(score: c.overlapScore),
                  ),
                )),
            if (hasMore)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactsPage()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('see all →',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: MossTokens.of(context).tierStrong)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String? _roleCompany(Contact c) {
    final s = [c.role, c.company]
        .where((v) => v != null && v.isNotEmpty)
        .join(' · ');
    return s.isEmpty ? null : s;
  }

  // ------------------------------------------------------- capture entry ---

  Widget _buildCaptureCard(BuildContext context) {
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(2),
      onTap: () => _openCapture(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('record someone you met',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('private, only visible to you',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.tierStrong,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic,
                  color: Theme.of(context).colorScheme.onPrimary, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- shared ---

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.headlineMedium);
  }

  Widget _emptyHint(BuildContext context, String text) {
    final tokens = MossTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.4,
              )),
    );
  }

  // -------------------------------------------------------- notifications ---

  Widget _buildNotificationsButton(BuildContext context, WidgetRef ref) {
    final tokens = MossTokens.of(context);
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
              decoration: BoxDecoration(
                color: tokens.tierModerate,
                shape: BoxShape.circle,
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
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
          final tokens = MossTokens.of(sheetContext);
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
                      Text('notifications',
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
                        child: const Text('mark all read'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: notifsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        const Center(child: Text('couldn\'t load notifications')),
                    data: (d) {
                      final items = (d['data'] as List?) ?? [];
                      if (items.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('you\'re all caught up.'),
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
                                  ? tokens.textSecondary
                                  : tokens.tierStrong,
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
    final tokens = MossTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.tierStrong.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.event, color: tokens.tierStrong, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'event: ${eventMode.eventName} · ${eventMode.captureCount} '
              'capture${eventMode.captureCount == 1 ? '' : 's'}',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: tokens.tierStrong),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(eventModeProvider.notifier).state =
                const EventModeState(),
            child: const Text('end'),
          ),
        ],
      ),
    );
  }
}
