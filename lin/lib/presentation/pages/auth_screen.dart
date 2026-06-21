import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/auth_provider.dart';

/// Authentication — typography-led, no logo/tabs/icon-cards.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _hasCredentials =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  void _requireFields() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('enter your email and password first')),
    );
  }

  Future<void> _signIn() async {
    if (!_hasCredentials) return _requireFields();
    try {
      await ref.read(authNotifierProvider.notifier).signin(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (e) {
      _toast('couldn\'t sign in: $e');
    }
  }

  Future<void> _signUp() async {
    if (!_hasCredentials) return _requireFields();
    try {
      await ref.read(authNotifierProvider.notifier).signup(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (e) {
      _toast('couldn\'t create your account: $e');
    }
  }

  Future<void> _demo() async {
    try {
      await ref.read(authNotifierProvider.notifier).demoSignin();
    } catch (e) {
      _toast('demo unavailable: $e');
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.16),
                Text('who\'s coming in?', style: theme.textTheme.displayLarge),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'email'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'password'),
                ),
                const SizedBox(height: 36),
                if (authState.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _inlineAction(
                    context,
                    label: 'step back in',
                    onTap: _signIn,
                  ),
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: authState.isLoading ? null : _signUp,
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: tokens.textSecondary),
                      children: [
                        const TextSpan(text: 'new here? '),
                        TextSpan(
                          text: 'build your profile',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: tokens.tierStrong),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: authState.isLoading ? null : _demo,
                  child: Text('or just look around',
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineAction(BuildContext context,
      {required String label, required VoidCallback onTap}) {
    final tokens = MossTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(color: tokens.tierStrong),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward, color: tokens.tierStrong, size: 22),
        ],
      ),
    );
  }
}
