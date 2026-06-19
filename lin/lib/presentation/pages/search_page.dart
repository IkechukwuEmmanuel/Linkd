import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import 'contact_detail_page.dart';

/// Full-screen contact search, opened from the home AppBar.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _openContact(Contact c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContactDetailPage(contact: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search contacts...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: _buildBody(query, resultsAsync),
    );
  }

  Widget _buildBody(String query, AsyncValue<List<Contact>> resultsAsync) {
    if (query.trim().length < 2) {
      return _hint(Icons.search,
          'Search for contacts by name, company, or interest');
    }
    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _hint(Icons.error_outline, 'Search failed: $e'),
      data: (results) {
        if (results.isEmpty) {
          return _hint(Icons.person_search,
              'No contacts found for "${query.trim()}"');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _resultTile(results[index]),
        );
      },
    );
  }

  Widget _resultTile(Contact c) {
    return ListTile(
      tileColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
      leading: CircleAvatar(
        backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15),
        child: Text(
          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: AppTheme.accentColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          [c.role, c.company]
              .where((s) => s != null && s.isNotEmpty)
              .join(' • '),
          if (c.interests.isNotEmpty) c.interests.take(3).join(', '),
        ].where((s) => s.isNotEmpty).join('\n'),
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      isThreeLine: c.interests.isNotEmpty,
      onTap: () => _openContact(c),
    );
  }

  Widget _hint(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
