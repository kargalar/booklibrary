import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/providers.dart';
import '../data/book_repository.dart';
import '../data/library_book_snapshot.dart';
import '../data/library_stats.dart';
import '../data/social_repository.dart';
import 'library_page.dart';
import 'social_page.dart';
import 'image_shimmer.dart';
import 'admin_database_page.dart';

part 'profile_components.dart';

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.user});

  final User user;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final repository = SocialRepository();
  late Future<UserProfile?> profileFuture;

  @override
  void initState() {
    super.initState();
    profileFuture = loadProfile();
  }

  Future<UserProfile?> loadProfile() async {
    await repository.ensureProfile(widget.user);
    return repository.profile(widget.user.uid);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile?>(
    future: profileFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProfileLoading();
      }
      if (snapshot.hasError) {
        return _ProfileError(
          onRetry: () => setState(() => profileFuture = loadProfile()),
        );
      }
      final profile = snapshot.data;
      return profile == null || profile.username.isEmpty
          ? UsernameSetupPage(
              user: widget.user,
              onSaved: () async {
                setState(() => profileFuture = loadProfile());
              },
            )
          : const LibraryPage();
    },
  );
}

class UsernameSetupPage extends StatefulWidget {
  const UsernameSetupPage({
    super.key,
    required this.user,
    required this.onSaved,
  });

  final User user;
  final Future<void> Function() onSaved;

  @override
  State<UsernameSetupPage> createState() => _UsernameSetupPageState();
}

class _UsernameSetupPageState extends State<UsernameSetupPage> {
  final repository = SocialRepository();
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  String? error;
  bool busy = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository.setUsername(widget.user.uid, controller.text);
      await widget.onSaved();
    } catch (value) {
      if (mounted) {
        setState(
          () => error = value is FormatException
              ? value.message
              : 'Username could not be registered.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 52,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Let\'s create your profile',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose a username so your friends can find you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: controller,
                          autofocus: true,
                          maxLength: 20,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => save(),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixText: '@',
                            hintText: 'booklover',
                          ),
                          validator: (value) =>
                              normalizeUsername(value ?? '') == null
                              ? 'Use 3-20 characters: a-z, 0-9, period, underscore, or dash.'
                              : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(error!, style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: busy ? null : save,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.uid,
    this.embedded = false,
    this.booksStream,
    this.initialBooks,
    this.onOpenFriends,
  });

  final String uid;
  final bool embedded;
  final Stream<LibraryBookSnapshot>? booksStream;
  final LibraryBookSnapshot? initialBooks;
  final VoidCallback? onOpenFriends;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final repository = SocialRepository();
  final booksRepository = BookRepository();
  final Map<String, Future<int?>> _myRatings = {};
  final Map<String, Future<UserProfile?>> _accessibleProfiles = {};
  final Map<String, Stream<LibraryBookSnapshot>> _accessibleBookStreams = {};
  late final Future<UserProfile?> profileFuture = repository.profile(
    widget.uid,
  );
  late final Stream<LibraryBookSnapshot> _booksStream =
      widget.booksStream ?? booksRepository.watch(widget.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _loanRequestsStream =
      repository.incomingLoanRequests(widget.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsStream =
      repository.notifications(widget.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _friendLinksStream =
      repository.friendLinks(widget.uid);
  String? _readRatingsKey;
  Future<Map<String, int>>? _readRatingsFuture;
  int readingGoal = 0;

  @override
  void initState() {
    super.initState();
    _loadGoal();
  }

  Future<void> _loadGoal() async {
    final preferences = await SharedPreferences.getInstance();
    final goal =
        preferences.getInt(
          'readingGoal.${widget.uid}.${DateTime.now().year}',
        ) ??
        0;
    if (mounted) setState(() => readingGoal = goal);
  }

  Future<void> _setGoal() async {
    var entered = '$readingGoal';
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This year\'s reading goal'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: entered,
            onChanged: (value) => entered = value,
            validator: (value) =>
                int.tryParse(value ?? '') == null ||
                    int.parse(value!) < 0 ||
                    int.parse(value) > 10000
                ? 'Enter a number between 0–10000.'
                : null,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Number of books'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(entered));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value < 0) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      'readingGoal.${widget.uid}.${DateTime.now().year}',
      value,
    );
    if (mounted) setState(() => readingGoal = value);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile?>(
    future: profileFuture,
    builder: (context, profileSnapshot) => StreamBuilder<LibraryBookSnapshot>(
      stream: _booksStream,
      initialData: widget.initialBooks,
      builder: (context, bookSnapshot) {
        final loadingProfile =
            profileSnapshot.connectionState == ConnectionState.waiting &&
            !profileSnapshot.hasData;
        final loadingBooks =
            bookSnapshot.connectionState == ConnectionState.waiting &&
            !bookSnapshot.hasData;
        if (loadingProfile || loadingBooks) {
          return _ProfileLoading(embedded: widget.embedded);
        }
        final docs = bookSnapshot.data?.docs ?? const [];
        final stats = LibraryStats(
          docs.map((book) => book.data()),
          DateTime.now(),
        );
        final profile = profileSnapshot.data;
        final content = ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          children: [
            _profileCard(context, profile),
            const SizedBox(height: 12),
            _goalCard(docs),
            const SizedBox(height: 12),
            _completionCard(stats),
            const SizedBox(height: 12),
            _readingStats(stats, docs),
            const SizedBox(height: 12),
            _loanRequests(),
            const SizedBox(height: 12),
            _notifications(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'My friends and the libraries I can access',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.onOpenFriends != null)
                  TextButton.icon(
                    onPressed: widget.onOpenFriends,
                    icon: const Icon(Icons.groups_rounded),
                    label: const Text('friends'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _accessibleLibraries(),
          ],
        );
        return widget.embedded
            ? content
            : Scaffold(
                appBar: AppBar(
                  title: const Text('Profile'),
                  actions: [
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
                body: content,
              );
      },
    ),
  );

  Widget _goalCard(List<LibraryBookDocument> docs) {
    final year = DateTime.now().year;
    final completedThisYear = docs.where((doc) {
      final value = doc.data()['completedAt'];
      return doc.data()['wishlist'] != true &&
          isCompletedStatus(doc.data()['status']) &&
          value is Timestamp &&
          value.toDate().year == year;
    }).length;
    final progress = readingGoal == 0
        ? 0.0
        : (completedThisYear / readingGoal).clamp(0, 1).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded),
                const SizedBox(width: 8),
                const Expanded(child: Text('This year\'s reading goal')),
                TextButton(onPressed: _setGoal, child: const Text('Set goal')),
              ],
            ),
            Text(
              readingGoal == 0
                  ? 'You haven\'t set a goal yet.'
                  : '$completedThisYear / $readingGoal books',
            ),
            if (readingGoal > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _completionCard(LibraryStats stats) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: stats.completionRate,
                  backgroundColor: scheme.onPrimary.withAlpha(35),
                  valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                ),
                Text(
                  '%${(stats.completionRate * 100).round()}',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${stats.completed} books read · ${stats.reading} currently reading',
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<int?> _myRating(String bookId) => _myRatings.putIfAbsent(
    bookId,
    () => repository.ratingForUser(bookId: bookId, userId: widget.uid),
  );

  Future<Map<String, int>> _loadReadRatings(
    Iterable<LibraryBookDocument> docs,
  ) async {
    final values = await Future.wait(
      docs.map((doc) async {
        final rating = await _myRating(doc.id);
        return rating == null ? null : MapEntry(doc.id, rating);
      }),
    );
    return {
      for (final value in values.whereType<MapEntry<String, int>>())
        value.key: value.value,
    };
  }

  Future<Map<String, int>> _readRatingsFor(Iterable<LibraryBookDocument> docs) {
    final values = docs.toList();
    final key = values.map((doc) => doc.id).join('|');
    if (_readRatingsKey != key) {
      _readRatingsKey = key;
      _readRatingsFuture = _loadReadRatings(values);
    }
    return _readRatingsFuture!;
  }

  Map<String, List<int>> _groupRatings(
    Iterable<LibraryBookDocument> docs,
    Map<String, int> ratings,
    List<String> Function(Map<String, dynamic>) labels,
  ) {
    final grouped = <String, List<int>>{};
    for (final doc in docs) {
      final rating = ratings[doc.id];
      if (rating == null) continue;
      for (final label in labels(doc.data())) {
        grouped.putIfAbsent(label, () => []).add(rating);
      }
    }
    return grouped;
  }

  Widget _readingStats(LibraryStats stats, List<LibraryBookDocument> docs) {
    final readDocs = docs
        .where(
          (doc) =>
              doc.data()['wishlist'] != true &&
              isCompletedStatus(doc.data()['status']),
        )
        .toList();
    return FutureBuilder<Map<String, int>>(
      future: _readRatingsFor(readDocs),
      builder: (context, snapshot) {
        final ratings = snapshot.data ?? const <String, int>{};
        final ratingValues = ratings.values.toList();
        final byGenre = _groupRatings(readDocs, ratings, genresFromBook);
        final byAuthor = _groupRatings(readDocs, ratings, authorsFromBook);
        final average = ratingValues.isEmpty
            ? null
            : ratingValues.reduce((total, value) => total + value) /
                  ratingValues.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My reading statistics',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metric(
                  context,
                  Icons.check_circle_rounded,
                  'what you read',
                  stats.completed,
                ),
                _metric(
                  context,
                  Icons.bookmark_rounded,
                  'you want to read',
                  stats.wishlist,
                ),
                _metric(
                  context,
                  Icons.menu_book_rounded,
                  'What you are reading now',
                  stats.reading,
                ),
                _metric(
                  context,
                  Icons.calendar_month_rounded,
                  'What you read this month',
                  stats.completedThisMonth,
                ),
              ],
            ),
            if (average != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: const Text('Your average score for what you read'),
                  subtitle: Text('${ratingValues.length} books rated'),
                  trailing: Text(
                    '${average.toStringAsFixed(1)} / 5',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              _ratingGroup('Your scores by genre', byGenre),
              _ratingGroup('Scores by authors', byAuthor),
            ],
          ],
        );
      },
    );
  }

  Widget _ratingGroup(String title, Map<String, List<int>> values) {
    if (values.isEmpty) return const SizedBox.shrink();
    final entries = values.entries.toList()
      ..sort(
        (a, b) => _averageRating(b.value).compareTo(_averageRating(a.value)),
      );
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: [
          for (final entry in entries)
            ListTile(
              dense: true,
              title: Text(entry.key),
              trailing: Text(
                '${_averageRating(entry.value).toStringAsFixed(1)} / 5',
              ),
            ),
        ],
      ),
    );
  }

  double _averageRating(List<int> values) =>
      values.reduce((total, value) => total + value) / values.length;

  Widget _loanRequests() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _loanRequestsStream,
    builder: (context, snapshot) {
      final requests =
          snapshot.data?.docs
              .map(LoanRequest.fromDocument)
              .where((request) => request.status == 'pending')
              .toList() ??
          const <LoanRequest>[];
      if (requests.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'loan requests',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final request in requests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(request.bookTitle),
                  subtitle: Text(
                    '${request.requesterName} wants to borrow this book.',
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Decline',
                        onPressed: () => _socialAction(
                          () => repository.rejectLoanRequest(request),
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      IconButton.filled(
                        tooltip: 'Approve',
                        onPressed: () => _socialAction(
                          () => repository.approveLoanRequest(request),
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
      final sorted = [...?snapshot.data?.docs]
        ..sort((a, b) {
          final first = a.data()['createdAt'];
          final second = b.data()['createdAt'];
          return (second is Timestamp ? second.millisecondsSinceEpoch : 0)
              .compareTo(first is Timestamp ? first.millisecondsSinceEpoch : 0);
        });
      final notifications = sorted.map(AppNotification.fromDocument).toList();
      if (notifications.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final notification in notifications.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    notification.read
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                  ),
                  title: Text(notification.title),
                  subtitle: Text(notification.body),
                  onTap: notification.read
                      ? null
                      : () => _socialAction(
                          () =>
                              repository.markNotificationRead(notification.id),
                        ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _profileCard(BuildContext context, UserProfile? profile) {
    final username = profile?.username.trim() ?? '';
    final label = username.isEmpty ? 'Reader' : '@$username';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              child: Text(
                (username.isEmpty ? 'O' : username).characters.first
                    .toUpperCase(),
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _socialAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
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
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    int value,
  ) => SizedBox(
    width: 148,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget
  _accessibleLibraries() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _friendLinksStream,
    builder: (context, snapshot) {
      final links = snapshot.data?.docs ?? const [];
      if (links.isEmpty) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.groups_2_rounded),
            title: const Text('You don\'t have any friends yet.'),
            subtitle: const Text(
              'The libraries you can access when you add a friend appear here.',
            ),
          ),
        );
      }
      return Column(
        children: [
          for (final link in links)
            if (_friendId(link).isNotEmpty)
              _AccessibleLibraryCard(
                key: ValueKey(link.id),
                repository: repository,
                currentUserId: widget.uid,
                friendId: _friendId(link),
                profileFuture: _accessibleProfiles.putIfAbsent(
                  _friendId(link),
                  () => repository.profile(_friendId(link)),
                ),
                booksStream: _accessibleBookStreams.putIfAbsent(
                  _friendId(link),
                  () => repository.sharedBooks(_friendId(link)),
                ),
                link: link,
              ),
        ],
      );
    },
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
