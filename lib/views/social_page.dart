import '../data/local_database.dart';
import '../data/local_identity.dart';

import 'package:flutter/material.dart';

import '../data/library_stats.dart';
import '../data/library_book_snapshot.dart';
import '../data/social_repository.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.uid});

  final String uid;

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  final repository = SocialRepository();
  final usernameController = TextEditingController();
  final Map<String, Future<UserProfile?>> _friendProfiles = {};
  final Map<String, Stream<LibraryBookSnapshot>> _friendBookStreams = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream =
      repository.incomingRequests(widget.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsStream =
      repository.notifications(widget.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _friendLinksStream =
      repository.friendLinks(widget.uid);
  UserProfile? foundUser;
  String? message;
  bool searching = false;
  bool sending = false;
  String libraryPermission = 'read';

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  Future<void> searchUser() async {
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => message = 'Type your friend\'s username.');
      return;
    }
    setState(() {
      searching = true;
      foundUser = null;
      message = null;
    });
    try {
      final result = await repository.findByUsername(username);
      if (!mounted) return;
      setState(() {
        foundUser = result;
        message = result == null
            ? 'No reader registered with this username was found.'
            : null;
      });
    } catch (_) {
      if (mounted) setState(() => message = 'Search failed. Please try again.');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> sendRequest() async {
    final target = foundUser;
    final user = LocalIdentity.instance.currentUser;
    if (target == null || user == null || sending) return;
    setState(() => sending = true);
    try {
      final profile = await repository.profile(user.uid);
      final name = user.displayName?.trim();
      if (profile == null || profile.username.isEmpty) {
        throw const FormatException(
          'First choose a username for your profile.',
        );
      }
      await repository.sendRequest(
        fromId: user.uid,
        fromName: name == null || name.isEmpty
            ? user.email?.split('@').first ?? 'Reader'
            : name,
        fromEmail: user.email ?? '',
        fromUsername: profile.username,
        target: target,
        permission: libraryPermission,
      );
      if (mounted) {
        setState(() {
          foundUser = null;
          message = 'Friend request sent.';
        });
        usernameController.clear();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is FormatException
              ? error.message
              : 'The request could not be sent.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _socialAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException
                ? error.message
                : 'The operation could not be completed. Try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
    children: [
      _addFriendCard(),
      const SizedBox(height: 12),
      _requests(),
      const SizedBox(height: 12),
      _notifications(),
      const SizedBox(height: 12),
      _friends(),
    ],
  );

  Widget _addFriendCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add friend',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Search for your friend\'s username and send a friend request.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: usernameController,
                    keyboardType: TextInputType.text,
                    onSubmitted: (_) => searchUser(),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: '@kullaniciadi',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: searching ? null : searchUser,
                  tooltip: 'Search',
                  icon: searching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Access to my library',
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: libraryPermission,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'read', child: Text('Read only')),
                    DropdownMenuItem(
                      value: 'edit',
                      child: Text('Access and edit'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => libraryPermission = value);
                    }
                  },
                ),
              ),
            ),
            if (foundUser != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(foundUser!.name.characters.first.toUpperCase()),
                ),
                title: Text(foundUser!.name),
                subtitle: Text('@${foundUser!.username} · ${foundUser!.email}'),
                trailing: FilledButton.icon(
                  onPressed: sending ? null : sendRequest,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add'),
                ),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message!,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _requests() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _requestsStream,
    builder: (context, snapshot) {
      final requests =
          snapshot.data?.docs
              .map(FriendRequest.fromDocument)
              .where(
                (request) =>
                    request.toId == widget.uid && request.status == 'pending',
              )
              .toList() ??
          const <FriendRequest>[];
      if (requests.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(Icons.person_add_rounded, 'Pending requests'),
              for (final request in requests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(
                      request.fromName.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(request.fromName),
                  subtitle: Text(
                    request.fromUsername.isEmpty
                        ? request.fromEmail
                        : '@${request.fromUsername}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Decline',
                        onPressed: () => _socialAction(
                          () => repository.rejectRequest(request.id),
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      IconButton.filled(
                        tooltip: 'Accept',
                        onPressed: () => _socialAction(
                          () => repository.acceptRequest(request),
                        ),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _notifications() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _notificationsStream,
    builder: (context, snapshot) {
      final notifications =
          snapshot.data?.docs
              .map(AppNotification.fromDocument)
              .where((notification) => !notification.read)
              .toList() ??
          const <AppNotification>[];
      if (notifications.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(Icons.notifications_active_rounded, 'Notifications'),
              for (final notification in notifications)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    notification.type == 'loanReminder'
                        ? Icons.touch_app_rounded
                        : Icons.notifications_rounded,
                  ),
                  title: Text(notification.title),
                  subtitle: Text(notification.body),
                  trailing: IconButton(
                    tooltip: 'Mark as read',
                    onPressed: () => _socialAction(
                      () => repository.markNotificationRead(notification.id),
                    ),
                    icon: const Icon(Icons.check_rounded),
                  ),
                  onTap: () => _socialAction(
                    () => repository.markNotificationRead(notification.id),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _friends() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _friendLinksStream,
    builder: (context, snapshot) {
      final links = snapshot.data?.docs ?? const [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'your friends',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (links.isEmpty)
            _emptyCard(
              'You haven\'t added any friends yet.',
              'When you add a friend, the books they read will appear here.',
            ),
          for (final link in links)
            if (_friendId(link).isNotEmpty)
              _FriendCard(
                key: ValueKey(link.id),
                repository: repository,
                uid: widget.uid,
                friendId: _friendId(link),
                profileFuture: _friendProfiles.putIfAbsent(
                  _friendId(link),
                  () => repository.profile(_friendId(link)),
                ),
                booksStream: _friendBookStreams.putIfAbsent(
                  _friendId(link),
                  () => repository.books(_friendId(link)),
                ),
                link: link,
              ),
        ],
      );
    },
  );

  Widget _heading(IconData icon, String title) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );

  Widget _emptyCard(String title, String subtitle) => Card(
    child: ListTile(
      leading: const Icon(Icons.groups_2_rounded),
      title: Text(title),
      subtitle: Text(subtitle),
    ),
  );

  String _friendId(QueryDocumentSnapshot<Map<String, dynamic>> link) {
    final members = link.data()['memberIds'];
    return members is Iterable
        ? members.whereType<String>().firstWhere(
            (id) => id != widget.uid,
            orElse: () => '',
          )
        : '';
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    super.key,
    required this.repository,
    required this.uid,
    required this.friendId,
    required this.profileFuture,
    required this.booksStream,
    required this.link,
  });

  final SocialRepository repository;
  final String uid;
  final String friendId;
  final Future<UserProfile?> profileFuture;
  final Stream<LibraryBookSnapshot> booksStream;
  final QueryDocumentSnapshot<Map<String, dynamic>> link;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: profileFuture,
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        return StreamBuilder<LibraryBookSnapshot>(
          stream: booksStream,
          builder: (context, bookSnapshot) {
            final books =
                bookSnapshot.data?.docs
                    .where((book) => isCompletedStatus(book.data()['status']))
                    .toList() ??
                const [];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            ? '@${profile!.username} · ${profile.email}'
                            : profile?.email ?? '',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${link.id}.${(link.data()['permissions'] as Map?)?[friendId]}',
                      ),
                      initialValue:
                          (link.data()['permissions'] as Map?)?[friendId] ==
                              'edit'
                          ? 'edit'
                          : 'read',
                      decoration: const InputDecoration(
                        labelText: 'This person\'s permission in my library',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'read',
                          child: Text('Read only'),
                        ),
                        DropdownMenuItem(
                          value: 'edit',
                          child: Text('Access and edit'),
                        ),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        try {
                          await repository.setLibraryPermission(
                            linkId: link.id,
                            memberId: friendId,
                            permission: value,
                          );
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'The authorization could not be updated.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    if (books.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('He hasn\'t read any books yet.'),
                      )
                    else
                      for (final book in books)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.menu_book_rounded),
                          title: Text(
                            book.data()['title'] as String? ?? 'book',
                          ),
                          subtitle: Text(
                            book.data()['author'] as String? ?? '',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => FriendBookDetailPage(
                                repository: repository,
                                currentUserId: uid,
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
        );
      },
    );
  }
}

class FriendBookDetailPage extends StatelessWidget {
  const FriendBookDetailPage({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.book,
  });

  final SocialRepository repository;
  final String currentUserId;
  final LibraryBookDocument book;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: repository.favoriteForUser(bookId: book.id, userId: currentUserId),
    builder: (context, favoriteSnapshot) => StreamBuilder<List<BookRating>>(
      stream: repository.ratingDetails(book.id),
      builder: (context, snapshot) {
        final ratings = snapshot.data ?? const <BookRating>[];
        final mine = ratings
            .where((rating) => rating.userId == currentUserId)
            .firstOrNull;
        final average = ratings.isEmpty
            ? 0.0
            : ratings.map((rating) => rating.value).reduce((a, b) => a + b) /
                  ratings.length;
        final data = book.data();
        return Scaffold(
          appBar: AppBar(
            title: Text(data['title'] as String? ?? 'book'),
            actions: [
              IconButton(
                tooltip: 'ask for loan',
                onPressed: () => _requestLoan(context, data),
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                data['author'] as String? ?? '',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _librariesCard(context, data),
              const SizedBox(height: 14),
              _ratingCard(
                context,
                ratings,
                mine?.value,
                average,
                favoriteSnapshot.data?.exists == true,
              ),
              const SizedBox(height: 14),
              _entriesCard(
                context,
                'Notes',
                Icons.notes_rounded,
                data['notes'],
              ),
              const SizedBox(height: 14),
              _entriesCard(
                context,
                'quotes',
                Icons.format_quote_rounded,
                data['quotes'],
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _librariesCard(BuildContext context, Map<String, dynamic> data) =>
      FutureBuilder<List<LibraryOwner>>(
        future: repository.librariesContainingBook(currentUserId, data),
        builder: (context, snapshot) {
          final libraries = snapshot.data ?? const <LibraryOwner>[];
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Libraries where it is located',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    )
                  else
                    for (final library in libraries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.library_books_rounded),
                        title: Text(library.name),
                        trailing: library.ownerId == currentUserId
                            ? null
                            : TextButton(
                                onPressed: () => _requestLoanTo(
                                  context,
                                  library,
                                  data['title'] as String? ?? 'book',
                                ),
                                child: const Text('ask for loan'),
                              ),
                      ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _requestLoanTo(
    BuildContext context,
    LibraryOwner library,
    String title,
  ) async {
    final user = LocalIdentity.instance.currentUser;
    if (user == null || library.bookId.isEmpty) return;
    await repository.requestLoan(
      bookId: library.bookId,
      ownerId: library.ownerId,
      bookTitle: title,
      requester: user,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Loan request sent.')));
    }
  }

  Widget _ratingCard(
    BuildContext context,
    List<BookRating> ratings,
    int? mine,
    double average,
    bool isFavorite,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text(
                'Ratings',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: () => _setFavorite(context, !isFavorite),
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? Colors.red : null,
                ),
              ),
              Text(
                ratings.isEmpty
                    ? 'No points yet'
                    : '${average.toStringAsFixed(1)} / 5',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('your score'),
          _stars(context, mine ?? 0, (value) => _rate(context, value)),
          if (mine != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _removeRating(context),
                child: const Text('remove my score'),
              ),
            ),
          if (ratings.isNotEmpty) ...[
            const Divider(),
            for (final rating in ratings)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(rating.userName),
                trailing: Text('⭐ ${rating.value}'),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _stars(BuildContext context, int selected, ValueChanged<int> onTap) =>
      Row(
        children: [
          for (var value = 1; value <= 5; value++)
            IconButton(
              tooltip: '$value stars',
              onPressed: () => onTap(value),
              icon: Icon(
                value <= selected
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: Colors.amber.shade700,
              ),
            ),
        ],
      );

  Future<void> _rate(BuildContext context, int value) async {
    final user = LocalIdentity.instance.currentUser;
    if (user == null) return;
    try {
      await repository.rateBook(bookId: book.id, user: user, value: value);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not save rating.')));
      }
    }
  }

  Future<void> _setFavorite(BuildContext context, bool favorite) async {
    try {
      await repository.setFavorite(
        bookId: book.id,
        userId: currentUserId,
        favorite: favorite,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save favorite.')),
        );
      }
    }
  }

  Future<void> _removeRating(BuildContext context) async {
    try {
      await repository.removeRating(bookId: book.id, userId: currentUserId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Point could not be removed.')),
        );
      }
    }
  }

  Future<void> _requestLoan(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final user = LocalIdentity.instance.currentUser;
    final ownerId = data['ownerId'];
    if (user == null || ownerId is! String) return;
    try {
      await repository.requestLoan(
        bookId: book.id,
        ownerId: ownerId,
        bookTitle: data['title'] as String? ?? 'book',
        requester: user,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Loan request sent.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The loan request could not be sent.')),
        );
      }
    }
  }

  Widget _entriesCard(
    BuildContext context,
    String title,
    IconData icon,
    Object? raw,
  ) {
    final entries = raw is Iterable
        ? raw
              .whereType<String>()
              .where((entry) => entry.trim().isNotEmpty)
              .toList()
        : const <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(
                'No shared content yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('•'),
                  title: Text(entry),
                ),
          ],
        ),
      ),
    );
  }
}
