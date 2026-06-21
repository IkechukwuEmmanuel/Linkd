import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/auth_provider.dart';
import '../widgets/memory_card.dart';
import '../widgets/overlap_indicator.dart';
import 'contact_detail_page.dart';

/// Contacts list page with search, filtering, and quick-capture.
class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _sortBy = 'recent';
  bool? _starredFilter;
  bool _isLoading = false;
  List<Contact> _contacts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContacts());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------- data loading ---

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final apiClient = ref.read(apiClientProvider);
      final contacts = await apiClient.getContacts(
        sort: _sortBy,
        starred: _starredFilter,
      );
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchController.text.trim();
      if (q.isEmpty) {
        _loadContacts();
      } else {
        _searchContacts(q);
      }
      if (mounted) setState(() {}); // refresh clear-button visibility
    });
  }

  Future<void> _searchContacts(String q) async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final results = await apiClient.searchContacts(q);
      if (!mounted) return;
      setState(() {
        _contacts = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------------ UI ---

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('contacts', style: Theme.of(context).textTheme.displaySmall),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterRow(),
          Expanded(child: _buildListArea()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuickCaptureDialog(context),
        backgroundColor: tokens.tierStrong,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('quick capture'),
      ),
    );
  }

  Widget _buildSearchBar() {
    final tokens = MossTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'search by name, company, or interest',
          prefixIcon: Icon(Icons.search, color: tokens.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadContacts();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('all'),
            selected: _starredFilter == null,
            onSelected: (_) {
              setState(() => _starredFilter = null);
              _loadContacts();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('starred'),
            selected: _starredFilter == true,
            onSelected: (selected) {
              setState(() => _starredFilter = selected ? true : null);
              _loadContacts();
            },
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() => _sortBy = value);
              _loadContacts();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'recent', child: Text('most recent')),
              PopupMenuItem(
                  value: 'strength', child: Text('relationship strength')),
              PopupMenuItem(value: 'name', child: Text('name')),
              PopupMenuItem(value: 'overlap', child: Text('overlap score')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState();
    }
    if (_contacts.isEmpty) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: _contacts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildContactCard(_contacts[index]),
      ),
    );
  }

  Widget _buildErrorState() {
    final tokens = MossTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: tokens.textSecondary),
            const SizedBox(height: 16),
            Text(
              'couldn\'t load contacts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadContacts,
              child: const Text('retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final tokens = MossTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('no contacts yet',
                style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 12),
            Text(
              'record a voice note about someone you meet, and linkd will keep a smart relationship card for them.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => _showQuickCaptureDialog(context),
              child: const Text('add your first contact'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(Contact contact) {
    final tokens = MossTokens.of(context);
    final roleCompany = [contact.role, contact.company]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    final overdue =
        contact.followUpDue != null && !contact.followUpCompleted;

    return MemoryCard(
      name: contact.name,
      secondaryLine: roleCompany.isNotEmpty ? roleCompany : null,
      body: contact.eventName != null ? 'met at ${contact.eventName}' : null,
      sharedGround: contact.overlapPoints,
      urgent: overdue,
      onTap: () => _showContactDetail(contact),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact.isStarred) ...[
            Icon(Icons.star, size: 16, color: tokens.tierModerate),
            const SizedBox(width: 6),
          ],
          OverlapIndicator(score: contact.overlapScore),
        ],
      ),
    );
  }

  void _showContactDetail(Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContactDetailPage(contact: contact)),
    ).then((_) => _loadContacts());
  }

  // -------------------------------------------------------- quick capture ---

  void _showQuickCaptureDialog(BuildContext context) {
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    final eventController = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text('quick capture',
              style: Theme.of(dialogContext).textTheme.headlineMedium),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'name', hintText: 'who did you meet?'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                    labelText: 'notes', hintText: 'what did you talk about?'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: eventController,
                decoration: const InputDecoration(
                    labelText: 'event (optional)',
                    hintText: 'conference, meetup, etc.'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty ||
                          noteController.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      // Capture messenger before the async gap.
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref.read(apiClientProvider).quickCapture(
                              name: nameController.text.trim(),
                              note: noteController.text.trim(),
                              eventName: eventController.text.trim(),
                            );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'contact saved — processing in background')),
                          );
                          // Give the worker a moment, then refresh.
                          Future.delayed(const Duration(seconds: 2),
                              () => mounted ? _loadContacts() : null);
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('failed to save: $e')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('save'),
            ),
          ],
        ),
      ),
    );
  }
}
