import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../features/auth/presentation/auth_bloc.dart';
import 'profile_page.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => BlocProvider.value(
    value: ref.watch(authBlocProvider),
    child: StreamBuilder<User?>(
      stream: ref.watch(authRepositoryProvider).authState,
      builder: (context, snapshot) => snapshot.data == null
          ? const LoginPage()
          : ProfileGate(user: snapshot.data!),
    ),
  );
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      return Scaffold(
        body: SafeArea(
          child: wide
              ? Row(
                  children: [
                    Expanded(child: _brandPanel(context)),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(40),
                          child: _loginCard(),
                        ),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 48, 22, 30),
                  child: _loginCard(compact: true),
                ),
        ),
      );
    },
  );

  Widget _brandPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -90,
            bottom: -110,
            child: Icon(
              Icons.auto_stories_rounded,
              size: 440,
              color: scheme.onPrimaryContainer.withAlpha(22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LoginLogo(scheme: scheme),
                const Spacer(),
                Text(
                  'Make your reading life\nyour own.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Organize your collection, get into your reading rhythm and always keep your next book with you.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimaryContainer.withAlpha(215),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                const _FeatureLine(
                  icon: Icons.auto_stories_rounded,
                  text: 'All your books in one place',
                ),
                const _FeatureLine(
                  icon: Icons.insights_rounded,
                  text: 'A clear look at reading habits',
                ),
                const _FeatureLine(
                  icon: Icons.sync_rounded,
                  text: 'Sync across devices',
                ),
                const Spacer(),
                Text(
                  'Your personal library, your own rules.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withAlpha(175),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard({bool compact = false}) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              _LoginLogo(scheme: scheme),
              const SizedBox(height: 36),
            ],
            Text(
              'welcome back',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8),
            ),
            const SizedBox(height: 8),
            Text(
              'Continue with your Google account to open your library.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    FilledButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => context.read<AuthBloc>().add(
                              const AuthGoogleSignInRequested(),
                            ),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Continue with Google'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    if (state.isLoading) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.errorMessage!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'When you log in, your books and reading settings are protected by your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        );
      },
    ),
  );
}

class _LoginLogo extends StatelessWidget {
  const _LoginLogo({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.auto_stories_rounded, color: scheme.onPrimary),
      ),
      const SizedBox(width: 12),
      Text(
        'my library',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4),
      ),
    ],
  );
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: scheme.onPrimaryContainer.withAlpha(220),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
