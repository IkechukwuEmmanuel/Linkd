import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import '../providers/auth_provider.dart';

/// Full-screen contact detail page with relationship intelligence.
class ContactDetailPage extends ConsumerStatefulWidget {
  final Contact contact;

  const ContactDetailPage({super.key, required this.contact});

  @override
  ConsumerState<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends ConsumerState<ContactDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Contact _contact;
  bool _isEditing = false;

  // Edit controllers
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
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _nameCtrl = TextEditingController(text: _contact.name);
    _companyCtrl = TextEditingController(text: _contact.company ?? '');
    _roleCtrl = TextEditingController(text: _contact.role ?? '');
    _emailCtrl = TextEditingController(text: _contact.email ?? '');
    _phoneCtrl = TextEditingController(text: _contact.phone ?? '');
    _notesCtrl = TextEditingController(text: _contact.notes ?? '');
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _roleCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Color _overlapColor(double score) {
    if (score >= 0.7) return const Color(0xFF00CC88);
    if (score >= 0.4) return const Color(0xFFFFA500);
    return const Color(0xFFEE5A52);
  }

  String _overlapLabel(double score) {
    if (score >= 0.7) return 'Strong Match';
    if (score >= 0.4) return 'Moderate Match';
    return 'Low Match';
  }

  String _strengthLabel(int strength) {
    if (strength >= 8) return 'Very Strong';
    if (strength >= 6) return 'Strong';
    if (strength >= 4) return 'Growing';
    if (strength >= 2) return 'New';
    return 'Just Met';
  }

  // ------------------------------------------------------------- actions ---

  Future<void> _toggleStar() async {
    try {
      final updated = await ref.read(apiClientProvider).toggleStar(_contact.id);
      if (!mounted) return;
      setState(() => _contact = updated);
      ref.invalidate(contactsProvider);
    } catch (e) {
      _showError('Couldn\'t update star: $e');
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
      _showError('Couldn\'t mark complete: $e');
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
        const SnackBar(content: Text('Contact updated!')),
      );
    } catch (e) {
      _showError('Couldn\'t save changes: $e');
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
      _showError('Couldn\'t delete contact: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final overlapColor = _overlapColor(_contact.overlapScore);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            // App Bar with gradient
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                            ),
                            child: Center(
                              child: Text(
                                _contact.name.isNotEmpty ? _contact.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Name and role
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _contact.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_contact.role != null || _contact.company != null)
                                  Text(
                                    [_contact.role, _contact.company]
                                        .where((s) => s != null)
                                        .join(' at '),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 14,
                                    ),
                                  ),
                                if (_contact.eventName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                                        const SizedBox(width: 4),
                                        Text(
                                          _contact.eventName!,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.7),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    _contact.isStarred ? Icons.star : Icons.star_border,
                    color: _contact.isStarred ? Colors.amber : Colors.white,
                  ),
                  onPressed: _toggleStar,
                ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.check : Icons.edit, color: Colors.white),
                  onPressed: () {
                    setState(() => _isEditing = !_isEditing);
                  },
                ),
              ],
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Overlap Score Card
                    _buildOverlapCard(overlapColor),
                    const SizedBox(height: 16),

                    // Relationship Strength
                    _buildStrengthBar(),
                    const SizedBox(height: 20),

                    // Summary
                    if (_contact.summary != null) ...[
                      _buildSectionTitle('Summary'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Text(
                          _contact.summary!,
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Shared Interests / Overlap Points
                    if (_contact.overlapPoints.isNotEmpty) ...[
                      _buildSectionTitle('Shared Interests'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _contact.overlapPoints
                            .map((p) => _buildChip(p, AppTheme.primaryColor))
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Interests
                    if (_contact.interests.isNotEmpty) ...[
                      _buildSectionTitle('Their Interests'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _contact.interests
                            .map((i) => _buildChip(i, AppTheme.secondaryColor))
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Opportunities
                    if (_contact.opportunities.isNotEmpty) ...[
                      _buildSectionTitle('Opportunities'),
                      const SizedBox(height: 8),
                      ...(_contact.opportunities).map((opp) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFFFA500)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(opp, style: const TextStyle(fontSize: 14, height: 1.4)),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 20),
                    ],

                    // Follow-up Draft
                    if (_contact.followUpDraft != null) ...[
                      _buildSectionTitle('Suggested Follow-up'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _contact.followUpDraft!,
                              style: const TextStyle(fontSize: 14, height: 1.5),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _contact.followUpDraft!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Copied to clipboard!')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text('Copy'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!_contact.followUpCompleted)
                                  ElevatedButton.icon(
                                    onPressed: _markFollowUpComplete,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Mark Done'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                  ),
                                if (_contact.followUpCompleted)
                                  Chip(
                                    label: const Text('Completed', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    backgroundColor: AppTheme.secondaryColor,
                                    side: BorderSide.none,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Contact Info
                    if (_contact.email != null || _contact.phone != null || _contact.linkedinUrl != null) ...[
                      _buildSectionTitle('Contact Info'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Column(
                          children: [
                            if (_contact.email != null)
                              _buildInfoRow(Icons.email_outlined, 'Email', _contact.email!),
                            if (_contact.phone != null)
                              _buildInfoRow(Icons.phone_outlined, 'Phone', _contact.phone!),
                            if (_contact.linkedinUrl != null)
                              _buildInfoRow(Icons.link, 'LinkedIn', _contact.linkedinUrl!),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Interaction Timeline
                    if (_contact.interactions != null && _contact.interactions!.isNotEmpty) ...[
                      _buildSectionTitle('Interaction Timeline'),
                      const SizedBox(height: 8),
                      ...(_contact.interactions!).map((interaction) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatInteractionType(interaction.interactionType),
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      if (interaction.content != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            interaction.content!,
                                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (interaction.recordedAt != null)
                                  Text(
                                    _formatDate(interaction.recordedAt!),
                                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                                  ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 20),
                    ],

                    // Notes (editable)
                    if (_isEditing) ...[
                      _buildSectionTitle('Edit Contact'),
                      const SizedBox(height: 8),
                      _buildEditField('Name', _nameCtrl),
                      _buildEditField('Company', _companyCtrl),
                      _buildEditField('Role', _roleCtrl),
                      _buildEditField('Email', _emailCtrl),
                      _buildEditField('Phone', _phoneCtrl),
                      _buildEditField('Notes', _notesCtrl, maxLines: 4),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveChanges,
                          child: const Text('Save Changes'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Delete button
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Contact?'),
                              content: Text('Remove ${_contact.name} from your contacts? This cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteContact();
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        label: const Text('Delete Contact', style: TextStyle(color: Colors.red)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================== Helpers ======================

  Widget _buildOverlapCard(Color overlapColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: overlapColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: overlapColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: overlapColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${(_contact.overlapScore * 100).toInt()}%',
                style: TextStyle(
                  color: overlapColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _overlapLabel(_contact.overlapScore),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: overlapColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Overlap Score — based on shared interests & values',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthBar() {
    final strength = _contact.relationshipStrength;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Relationship Strength', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(
                '${_strengthLabel(strength)} ($strength/10)',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strength / 10,
              backgroundColor: AppTheme.borderColor,
              color: strength >= 7
                  ? AppTheme.secondaryColor
                  : strength >= 4
                      ? const Color(0xFFFFA500)
                      : AppTheme.accentColor,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppTheme.primaryColor),
      title: Text(value, style: const TextStyle(fontSize: 14)),
      subtitle: Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
    );
  }

  Widget _buildEditField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  String _formatInteractionType(String type) {
    switch (type) {
      case 'initial_capture':
        return 'Initial Capture';
      case 'follow_up_completed':
        return 'Follow-up Completed';
      case 'voice_note':
        return 'Voice Note';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }
}
