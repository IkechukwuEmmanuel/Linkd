import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import '../providers/auth_provider.dart';
import '../widgets/connection_thread.dart';
import '../widgets/memory_card.dart';

/// Full-screen contact detail — a kept "memory card" with relationship context.
///
/// Shows relationship strength (the [ConnectionThread]) at the top of the card.
/// It does NOT show match-strength overlap circles — that lives only in list
/// rows. These are intentionally different screens answering different questions.
class ContactDetailPage extends ConsumerStatefulWidget {
  final Contact contact;

  const ContactDetailPage({super.key, required this.contact});

  @override
  ConsumerState<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends ConsumerState<ContactDetailPage> {
  late Contact _contact;
  bool _isEditing = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _companyCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _nameCtrl = TextEditingController(text: _contact.name);
    _companyCtrl = TextEditingController(text: _contact.company ?? '');
    _roleCtrl = TextEditingController(text: _contact.role ?? '');
    _emailCtrl = TextEditingController(text: _contact.email ?? '');
    _phoneCtrl = TextEditingController(text: _contact.phone ?? '');
    _notesCtrl = TextEditingController(text: _contact.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _roleCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- actions ---

  Future<void> _toggleStar() async {
    try {
      final updated = await ref.read(apiClientProvider).toggleStar(_contact.id);
      if (!mounted) return;
      setState(() => _contact = updated);
      ref.invalidate(contactsProvider);
    } catch (e) {
      _showError('couldn\'t update star: $e');
    }
  }

  Future<void> _markFollowUpComplete() async {
    try {
      final updated =
          await ref.read(apiClientProvider).markFollowUpComplete(_contact.id);
      if (!mounted) return;
      setState(() => _contact = updated);
      ref.invalidate(upcomingFollowUpsProvider);
      ref.invalidate(contactsProvider);
    } catch (e) {
      _showError('couldn\'t mark complete: $e');
    }
  }

  Future<void> _saveChanges() async {
    try {
      final updated =
          await ref.read(apiClientProvider).updateContact(_contact.id, {
        'name': _nameCtrl.text,
        'company': _companyCtrl.text,
        'role': _roleCtrl.text,
        'email': _emailCtrl.text,
        'phone': _phoneCtrl.text,
        'notes': _notesCtrl.text,
      });
      if (!mounted) return;
      setState(() {
        _contact = updated;
        _isEditing = false;
      });
      ref.invalidate(contactsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('contact updated')),
      );
    } catch (e) {
      _showError('couldn\'t save changes: $e');
    }
  }

  Future<void> _deleteContact() async {
    try {
      await ref.read(apiClientProvider).deleteContact(_contact.id);
      ref.invalidate(contactsProvider);
      ref.invalidate(upcomingFollowUpsProvider);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showError('couldn\'t delete contact: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ UI ---

  @override
  Widget build(BuildContext context) {
    final tokens = MossTokens.of(context);
    final roleCompany = [_contact.role, _contact.company]
        .where((s) => s != null && s.isNotEmpty)
        .join(' at ');

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              _contact.isStarred ? Icons.star : Icons.star_border,
              color: _contact.isStarred ? tokens.tierModerate : null,
            ),
            onPressed: _toggleStar,
          ),
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit_outlined),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          // The kept note — relationship thread above the name.
          MemoryCard(
            header: ConnectionThread(
              strength: _contact.relationshipStrength,
              themInitial: _contact.name,
            ),
            name: _contact.name,
            secondaryLine: roleCompany.isNotEmpty ? roleCompany : null,
            body: _contact.eventName != null
                ? 'met at ${_contact.eventName}'
                : null,
            sharedGround: _contact.overlapPoints,
          ),
          const SizedBox(height: 24),

          if (_contact.summary != null) ...[
            _sectionTitle('summary'),
            const SizedBox(height: 8),
            _panel(child: Text(
              _contact.summary!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: tokens.textSecondary, height: 1.6),
            )),
            const SizedBox(height: 20),
          ],

          if (_contact.interests.isNotEmpty) ...[
            _sectionTitle('their interests'),
            const SizedBox(height: 8),
            _tagWrap(_contact.interests, tokens.tierModerate),
            const SizedBox(height: 20),
          ],

          if (_contact.opportunities.isNotEmpty) ...[
            _sectionTitle('opportunities'),
            const SizedBox(height: 8),
            ..._contact.opportunities.map((opp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_outward,
                          size: 16, color: tokens.tierModerate),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(opp,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.4)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 20),
          ],

          if (_contact.followUpDraft != null) ...[
            _sectionTitle('suggested follow-up'),
            const SizedBox(height: 8),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_contact.followUpDraft!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _contact.followUpDraft!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('copy'),
                      ),
                      const SizedBox(width: 8),
                      if (!_contact.followUpCompleted)
                        ElevatedButton.icon(
                          onPressed: _markFollowUpComplete,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('mark done'),
                        )
                      else
                        Text('completed',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: tokens.tierStrong)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_contact.email != null ||
              _contact.phone != null ||
              _contact.linkedinUrl != null) ...[
            _sectionTitle('contact info'),
            const SizedBox(height: 8),
            _panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (_contact.email != null)
                    _infoRow(Icons.email_outlined, 'email', _contact.email!),
                  if (_contact.phone != null)
                    _infoRow(Icons.phone_outlined, 'phone', _contact.phone!),
                  if (_contact.linkedinUrl != null)
                    _infoRow(Icons.link, 'linkedin', _contact.linkedinUrl!),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_contact.interactions != null &&
              _contact.interactions!.isNotEmpty) ...[
            _sectionTitle('interaction timeline'),
            const SizedBox(height: 8),
            ..._contact.interactions!.map((interaction) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.cardSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          color: tokens.tierStrong,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatInteractionType(
                                  interaction.interactionType),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            if (interaction.content != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  interaction.content!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (interaction.recordedAt != null)
                        Text(_formatDate(interaction.recordedAt!),
                            style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                )),
            const SizedBox(height: 20),
          ],

          if (_isEditing) ...[
            _sectionTitle('edit contact'),
            const SizedBox(height: 8),
            _editField('name', _nameCtrl),
            _editField('company', _companyCtrl),
            _editField('role', _roleCtrl),
            _editField('email', _emailCtrl),
            _editField('phone', _phoneCtrl),
            _editField('notes', _notesCtrl, maxLines: 4),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveChanges,
                child: const Text('save changes'),
              ),
            ),
            const SizedBox(height: 20),
          ],

          Center(
            child: TextButton(
              onPressed: _confirmDelete,
              child: Text('delete contact',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: tokens.danger)),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- pieces ---

  Widget _sectionTitle(String title) =>
      Text(title, style: Theme.of(context).textTheme.headlineSmall);

  Widget _panel({required Widget child, EdgeInsets? padding}) {
    final tokens = MossTokens.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: child,
    );
  }

  Widget _tagWrap(List<String> tags, Color color) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .map((t) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(t,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: color)),
              ))
          .toList(),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final tokens = MossTokens.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: tokens.tierStrong),
      title: Text(value, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(label, style: Theme.of(context).textTheme.labelSmall),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    );
  }

  Widget _editField(String label, TextEditingController ctrl,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _confirmDelete() {
    final tokens = MossTokens.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('delete contact?'),
        content: Text(
            'remove ${_contact.name} from your contacts? this cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteContact();
            },
            child: Text('delete', style: TextStyle(color: tokens.danger)),
          ),
        ],
      ),
    );
  }

  String _formatInteractionType(String type) {
    switch (type) {
      case 'initial_capture':
        return 'initial capture';
      case 'follow_up_completed':
        return 'follow-up completed';
      case 'voice_note':
        return 'voice note';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) return 'today';
      if (diff.inDays == 1) return 'yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }
}
