part of 'profile_page.dart';

class _AccessibleLibraryCard extends StatelessWidget {
  const _AccessibleLibraryCard({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.friendId,
    required this.profileFuture,
    required this.booksStream,
    required this.link,
  });

  final SocialRepository repository;
  final String currentUserId;
  final String friendId;
  final Future<UserProfile?> profileFuture;
  final Stream<LibraryBookSnapshot> booksStream;
  final QueryDocumentSnapshot<Map<String, dynamic>> link;

  @override
  Widget build(BuildContext context) {
    final permissions = link.data()['permissions'];
    final permission =
        permissions is Map && permissions[currentUserId] == 'edit'
        ? 'edit'
        : 'read';
    return FutureBuilder<UserProfile?>(
      future: profileFuture,
      builder: (context, profileSnapshot) => StreamBuilder<LibraryBookSnapshot>(
        stream: booksStream,
        builder: (context, bookSnapshot) {
          final profile = profileSnapshot.data;
          final books = bookSnapshot.data?.docs ?? const [];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        (profile?.name ?? 'O').characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(profile?.name ?? 'friend'),
                    subtitle: Text(
                      profile?.username.isNotEmpty == true
                          ? '@${profile!.username}'
                          : profile?.email ?? '',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${books.length} books'),
                        Text(permission == 'edit' ? 'Editing' : 'Access'),
                      ],
                    ),
                  ),
                  if (books.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('He hasn\'t read any books yet.'),
                      ),
                    )
                  else
                    for (final book in books)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.menu_book_rounded),
                        title: Text(book.data()['title'] as String? ?? 'book'),
                        subtitle: Text(book.data()['author'] as String? ?? ''),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FriendBookDetailPage(
                              repository: repository,
                              currentUserId: currentUserId,
                              book: book,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('Dark theme'),
            value: ref.watch(themeControllerProvider).value == ThemeMode.dark,
            onChanged: (_) => ref.read(themeControllerProvider).toggle(),
            secondary: const Icon(Icons.dark_mode_rounded),
          ),
        ),
        if (isDatabaseAdmin(
          platform: defaultTargetPlatform,
          email: LocalIdentity.instance.currentUser?.email,
        )) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDatabasePage(),
              ),
            ),
            icon: const Icon(Icons.storage_rounded),
            label: const Text('Review and manage database'),
          ),
        ],
        const SizedBox(height: 12),
        const ListTile(
          leading: Icon(Icons.phone_android_rounded),
          title: Text(LocalStrings.storageTitle),
          subtitle: Text(LocalStrings.storageDescription),
        ),
      ],
    ),
  );
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      children: const [
        SizedBox(height: 108, child: ImageShimmer(borderRadius: 18)),
        SizedBox(height: 18),
        SizedBox(height: 112, child: ImageShimmer(borderRadius: 18)),
        SizedBox(height: 18),
        SizedBox(height: 150, child: ImageShimmer(borderRadius: 18)),
        SizedBox(height: 18),
        SizedBox(height: 180, child: ImageShimmer(borderRadius: 18)),
      ],
    );
    return embedded ? content : Scaffold(body: content);
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Reload profile'),
      ),
    ),
  );
}
