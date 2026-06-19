import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
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

  // -------------------------------------------------------------- helpers ---

  Color _overlapColor(double score) {
    if (score >= 0.7) return AppTheme.successColor;
    if (score >= 0.4) return AppTheme.warningColor;
    return AppTheme.errorColor;
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

  // ------------------------------------------------------------------ UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Contacts', style: Theme.of(context).textTheme.displaySmall),
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
        backgroundColor: AppTheme.accentColor,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Quick Capture',
            style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name, company, or interest...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textHint),
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
            label: const Text('All'),
            selected: _starredFilter == null,
            onSelected: (_) {
              setState(() => _starredFilter = null);
              _loadContacts();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('⭐ Starred'),
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
              PopupMenuItem(value: 'recent', child: Text('Most Recent')),
              PopupMenuItem(
                  value: 'strength', child: Text('Relationship Strength')),
              PopupMenuItem(value: 'name', child: Text('Name')),
              PopupMenuItem(value: 'overlap', child: Text('Overlap Score')),
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
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildContactCard(_contacts[index]),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text(
              'Couldn\'t load contacts',
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
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline,
                size: 56, color: AppTheme.accentColor),
          ),
          const SizedBox(height: 24),
          Text('No contacts yet',
              style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Record a voice note about someone you meet, and Linkd will create a smart relationship card.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _showQuickCaptureDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add your first contact'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Contact contact) {
    final overlapColor = _overlapColor(contact.overlapScore);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showContactDetail(contact),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _avatarColor(contact.name),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    contact.name.isNotEmpty
                        ? contact.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (contact.isStarred)
                          const Icon(Icons.star,
                              color: Colors.amber, size: 18),
                      ],
                    ),
                    if (contact.company != null || contact.role != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [contact.role, contact.company]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(' • '),
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (contact.eventName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.event,
                              size: 14, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(
                            contact.eventName!,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: overlapColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(contact.overlapScore * 100).toInt()}%',
                  style: TextStyle(
                      color: overlapColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Quick Capture',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'Who did you meet?'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                    labelText: 'Notes', hintText: 'What did you talk about?'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: eventController,
                decoration: const InputDecoration(
                    labelText: 'Event (optional)',
                    hintText: 'Conference, meetup, etc.'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
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
                      try {
                        await ref.read(apiClientProvider).quickCapture(
                              name: nameController.text.trim(),
                              note: noteController.text.trim(),
                              eventName: eventController.text.trim(),
                            );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Contact saved — processing in background...')),
                          );
                          // Give the worker a moment, then refresh.
                          Future.delayed(const Duration(seconds: 2),
                              () => mounted ? _loadContacts() : null);
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Failed to save: $e')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
