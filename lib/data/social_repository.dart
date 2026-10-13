import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'book_repository.dart';
import 'library_stats.dart';
import 'library_book_snapshot.dart';

String friendLinkId(String first, String second) =>
    first.compareTo(second) < 0 ? '${first}_$second' : '${second}_$first';

String? normalizeUsername(String value) {
  final username = value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
  return RegExp(r'^[a-z0-9._-]{3,20}$').hasMatch(username) ? username : null;
}

const defaultLibraryName = 'My Library';

class PersonalLibrary {
  const PersonalLibrary({required this.id, required this.name});

  final String id;
  final String name;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.username,
    required this.libraryName,
    required this.personalLibraries,
  });

  final String id;
  final String email;
  final String name;
  final String username;
  final String libraryName;
  final List<PersonalLibrary> personalLibraries;

  factory UserProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final email = data['email'] is String ? data['email'] as String : '';
    final name = data['displayName'] is String
        ? data['displayName'] as String
        : '';
    final username = data['username'] is String
        ? data['username'] as String
        : '';
    final libraryName = data['libraryName'] is String
        ? (data['libraryName'] as String).trim()
        : '';
    final resolvedLibraryName = libraryName.isEmpty
        ? defaultLibraryName
        : libraryName;
    final emailName = email.split('@').first.trim();
    return UserProfile(
      id: document.id,
      email: email,
      name: name.trim().isEmpty
          ? emailName.isEmpty
                ? 'Reader'
                : emailName
          : name.trim(),
      username: username.trim(),
      libraryName: resolvedLibraryName,
      personalLibraries: _personalLibraries(
        data['personalLibraries'],
        resolvedLibraryName,
      ),
    );
  }
}

List<PersonalLibrary> _personalLibraries(Object? value, String fallbackName) {
  final libraries = <PersonalLibrary>[];
  if (value is Iterable) {
    for (final item in value) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is String &&
          id.trim().isNotEmpty &&
          name is String &&
          name.trim().isNotEmpty) {
        libraries.add(PersonalLibrary(id: id.trim(), name: name.trim()));
      }
    }
  }
  return libraries.isEmpty
      ? [PersonalLibrary(id: defaultPersonalLibraryId, name: fallbackName)]
      : libraries;
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.fromEmail,
    required this.fromUsername,
    required this.status,
    required this.permission,
  });

  final String id;
  final String fromId;
  final String toId;
  final String fromName;
  final String fromEmail;
  final String fromUsername;
  final String status;
  final String permission;

  factory FriendRequest.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final fromEmail = data['fromEmail'] as String? ?? '';
    final rawName = data['fromName'] as String? ?? '';
    final fromUsername = data['fromUsername'] as String? ?? '';
    return FriendRequest(
      id: document.id,
      fromId: data['fromId'] as String? ?? '',
      toId: data['toId'] as String? ?? '',
      fromName: rawName.trim().isEmpty
          ? fromEmail.split('@').first.trim().isEmpty
                ? 'Reader'
                : fromEmail.split('@').first.trim()
          : rawName.trim(),
      fromEmail: fromEmail,
      fromUsername: fromUsername,
      status: data['status'] as String? ?? 'pending',
      permission: data['permission'] as String? ?? 'read',
    );
  }
}

class BookRating {
  const BookRating({
    required this.userId,
    required this.userName,
    required this.value,
    this.review = '',
  });

  final String userId;
  final String userName;
  final int value;
  final String review;

  factory BookRating.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final rawValue = data['value'];
    final username = data['username'] as String?;
    return BookRating(
      userId: data['userId'] as String? ?? document.id,
      userName: username == null || username.isEmpty
          ? data['userName'] as String? ?? 'Reader'
          : '@$username',
      value: rawValue is int ? rawValue : int.tryParse('$rawValue') ?? 0,
      review: data['review'] is String ? (data['review'] as String).trim() : '',
    );
  }
}

class LoanRequest {
  const LoanRequest({
    required this.id,
    required this.bookId,
    required this.ownerId,
    required this.requesterId,
    required this.requesterName,
    required this.bookTitle,
    required this.status,
  });

  final String id;
  final String bookId;
  final String ownerId;
  final String requesterId;
  final String requesterName;
  final String bookTitle;
  final String status;

  factory LoanRequest.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return LoanRequest(
      id: document.id,
      bookId: data['bookId'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      requesterId: data['requesterId'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? 'Reader',
      bookTitle: data['bookTitle'] as String? ?? 'Book',
      status: data['status'] as String? ?? 'pending',
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final bool read;

  factory AppNotification.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return AppNotification(
      id: document.id,
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? '',
      read: data['read'] == true,
    );
  }
}

class LibraryOwner {
  const LibraryOwner({
    required this.ownerId,
    required this.name,
    required this.username,
    required this.bookId,
  });

  final String ownerId;
  final String name;
  final String username;
  final String bookId;
}

class SocialRepository {
  SocialRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');
  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _links =>
      _firestore.collection('friendLinks');
  CollectionReference<Map<String, dynamic>> get _libraryBooks =>
      _firestore.collection('libraryBooks');
  CollectionReference<Map<String, dynamic>> get _books =>
      _firestore.collection('books');
  CollectionReference<Map<String, dynamic>> get _loanRequests =>
      _firestore.collection('loanRequests');
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  Future<void> ensureProfile(User user) => _users.doc(user.uid).set({
    'email': user.email ?? '',
    'emailNormalized': (user.email ?? '').trim().toLowerCase(),
    'displayName': user.displayName ?? '',
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> setLibraryName(String uid, String value) {
    final name = value.trim();
    if (name.isEmpty) {
      throw const FormatException('Library name cannot be empty.');
    }
    if (name.length > 40) {
      throw const FormatException('Library name cannot exceed 40 characters.');
    }
    return _users.doc(uid).set({
      'libraryName': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setUsername(String uid, String value) async {
    final username = value.trim().replaceFirst(RegExp(r'^@'), '');
    final normalized = normalizeUsername(username);
    if (normalized == null) {
      throw const FormatException(
        'Usernames must be 3–20 characters. Use letters, numbers, periods, underscores, or hyphens.',
      );
    }
    final userReference = _users.doc(uid);
    final usernameReference = _usernames.doc(normalized);
    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userReference);
      final usernameSnapshot = await transaction.get(usernameReference);
      final ownerId = usernameSnapshot.data()?['uid'];
      if (usernameSnapshot.exists && ownerId != uid) {
        throw const FormatException('This username is already taken.');
      }
      final previous = userSnapshot.data()?['usernameNormalized'];
      if (previous is String && previous.isNotEmpty && previous != normalized) {
        transaction.delete(_usernames.doc(previous));
      }
      transaction.set(usernameReference, {
        'uid': uid,
        'username': username,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(userReference, {
        'username': username,
        'usernameNormalized': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<UserProfile?> findByUsername(String value) async {
    final normalized = normalizeUsername(value);
    if (normalized == null) return null;
    final username = await _usernames.doc(normalized).get();
    final uid = username.data()?['uid'];
    return uid is String ? profile(uid) : null;
  }

  Future<UserProfile?> profile(String uid) async {
    final document = await _users.doc(uid).get();
    return document.exists ? UserProfile.fromDocument(document) : null;
  }

  Future<List<PersonalLibrary>> personalLibraries(String uid) async =>
      (await profile(uid))?.personalLibraries ??
      const [
        PersonalLibrary(id: defaultPersonalLibraryId, name: defaultLibraryName),
      ];

  String newPersonalLibraryId() => _users.doc().id;

  Future<void> savePersonalLibraries(
    String uid,
    Iterable<PersonalLibrary> libraries,
  ) {
    final normalized = <PersonalLibrary>[];
    final ids = <String>{};
    for (final library in libraries) {
      final id = library.id.trim();
      final name = library.name.trim();
      if (id.isEmpty || name.isEmpty || name.length > 40 || !ids.add(id)) {
        throw const FormatException('The library name is invalid.');
      }
      normalized.add(PersonalLibrary(id: id, name: name));
    }
    if (normalized.isEmpty) {
      throw const FormatException('You must have at least one library.');
    }
    final home = normalized.firstWhere(
      (library) => library.id == defaultPersonalLibraryId,
      orElse: () => normalized.first,
    );
    return _users.doc(uid).set({
      'personalLibraries': [
        for (final library in normalized)
          {'id': library.id, 'name': library.name},
      ],
      'libraryName': home.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingRequests(String uid) =>
      _requests.where('toId', isEqualTo: uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> friendLinks(String uid) =>
      _links.where('memberIds', arrayContains: uid).snapshots();

  Future<void> sendRequest({
    required String fromId,
    required String fromName,
    required String fromEmail,
    required String fromUsername,
    required UserProfile target,
    String permission = 'read',
  }) {
    if (fromId == target.id) {
      throw const FormatException(
        'You cannot send a friend request to yourself.',
      );
    }
    return _requests.doc('${fromId}_${target.id}').set({
      'fromId': fromId,
      'toId': target.id,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'fromUsername': fromUsername,
      'permission': permission == 'edit' ? 'edit' : 'read',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptRequest(FriendRequest request) async {
    final batch = _firestore.batch();
    batch.update(_requests.doc(request.id), {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_links.doc(friendLinkId(request.fromId, request.toId)), {
      'memberIds': [request.fromId, request.toId],
      'permissions': {request.fromId: 'read', request.toId: request.permission},
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> rejectRequest(String requestId) =>
      _requests.doc(requestId).update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setLibraryPermission({
    required String linkId,
    required String memberId,
    required String permission,
  }) => _links.doc(linkId).update({'permissions.$memberId': permission});

  Stream<LibraryBookSnapshot> books(String ownerId) =>
      BookRepository(firestore: _firestore).watch(ownerId, completedOnly: true);

  Stream<LibraryBookSnapshot> sharedBooks(String ownerId) =>
      BookRepository(firestore: _firestore).watch(ownerId);

  Stream<QuerySnapshot<Map<String, dynamic>>> ratings(String bookId) =>
      _libraryBooks.doc(bookId).collection('ratings').snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> favoriteForUser({
    required String bookId,
    required String userId,
  }) =>
      _libraryBooks.doc(bookId).collection('favorites').doc(userId).snapshots();

  Stream<List<BookRating>> ratingDetails(String bookId) =>
      ratings(bookId).asyncMap(
        (snapshot) => Future.wait(
          snapshot.docs.map((document) async {
            final rating = BookRating.fromDocument(document);
            final user = await profile(rating.userId);
            return BookRating(
              userId: rating.userId,
              value: rating.value,
              review: rating.review,
              userName: user?.username.isNotEmpty == true
                  ? '@${user!.username}'
                  : rating.userName,
            );
          }),
        ),
      );

  Future<double?> ratingAverage(String bookId) async {
    final snapshot = await _libraryBooks
        .doc(bookId)
        .collection('ratings')
        .get();
    final values = snapshot.docs
        .map(BookRating.fromDocument)
        .map((rating) => rating.value)
        .where((value) => value >= 1 && value <= 5)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((total, value) => total + value) / values.length;
  }

  Future<int?> ratingForUser({
    required String bookId,
    required String userId,
  }) async {
    final data =
        (await _libraryBooks
                .doc(bookId)
                .collection('ratings')
                .doc(userId)
                .get())
            .data();
    final value = data?['value'];
    final rating = value is num ? value.toInt() : int.tryParse('$value');
    return rating != null && rating >= 1 && rating <= 5 ? rating : null;
  }

  Future<void> rateBook({
    required String bookId,
    required User user,
    required int value,
    String review = '',
  }) async {
    if (value < 1 || value > 5) {
      throw const FormatException('The rating must be between 1 and 5.');
    }
    final normalizedReview = review.trim();
    if (normalizedReview.length > 2000) {
      throw const FormatException('A review cannot exceed 2,000 characters.');
    }
    final userProfile = await profile(user.uid);
    final username = userProfile?.username.trim();
    final name = user.displayName?.trim();
    return _libraryBooks.doc(bookId).collection('ratings').doc(user.uid).set({
      'userId': user.uid,
      'username': username ?? '',
      'userName': username == null || username.isEmpty
          ? name == null || name.isEmpty
                ? user.email?.split('@').first ?? 'Reader'
                : name
          : '@$username',
      'value': value,
      'review': normalizedReview,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeRating({required String bookId, required String userId}) =>
      _libraryBooks.doc(bookId).collection('ratings').doc(userId).delete();

  Future<void> setFavorite({
    required String bookId,
    required String userId,
    required bool favorite,
  }) {
    final reference = _libraryBooks
        .doc(bookId)
        .collection('favorites')
        .doc(userId);
    return favorite
        ? reference.set({
            'userId': userId,
            'createdAt': FieldValue.serverTimestamp(),
          })
        : reference.delete();
  }

  Future<List<LibraryOwner>> librariesContainingBook(
    String uid,
    Map<String, dynamic> book,
  ) async {
    final owners = <LibraryOwner>[];
    final ownBook = (await sharedBooks(uid).first).docs
        .where(
          (document) =>
              document.data()['wishlist'] != true &&
              isInAnyLibrary(document.data()) &&
              (document.data()['bookId'] == book['bookId'] ||
                  sameBook(document.data(), book)),
        )
        .firstOrNull;
    if (ownBook != null) {
      final ownProfile = await profile(uid);
      final libraryNames = bookLibraryIds(ownBook.data())
          .map(
            (id) => ownProfile?.personalLibraries
                .where((library) => library.id == id)
                .firstOrNull
                ?.name,
          )
          .whereType<String>()
          .toSet()
          .join(', ');
      owners.add(
        LibraryOwner(
          ownerId: uid,
          name: libraryNames.isEmpty
              ? ownProfile?.libraryName ?? defaultLibraryName
              : libraryNames,
          username: ownProfile?.username ?? '',
          bookId: ownBook.id,
        ),
      );
    }
    final links = await friendLinks(uid).first;
    final friendIds = <String>{
      for (final link in links.docs)
        if (link.data()['memberIds'] is Iterable)
          ...link.data()['memberIds'].whereType<String>().where(
            (id) => id != uid,
          ),
    };
    for (final friendId in friendIds) {
      final matching = (await sharedBooks(friendId).first).docs.where(
        (document) =>
            document.data()['wishlist'] != true &&
            isInAnyLibrary(document.data()) &&
            (document.data()['bookId'] == book['bookId'] ||
                sameBook(document.data(), book)),
      );
      final document = matching.firstOrNull;
      if (document == null) continue;
      final friend = await profile(friendId);
      final libraryNames = bookLibraryIds(document.data())
          .map(
            (id) => friend?.personalLibraries
                .where((library) => library.id == id)
                .firstOrNull
                ?.name,
          )
          .whereType<String>()
          .toSet()
          .join(', ');
      owners.add(
        LibraryOwner(
          ownerId: friendId,
          name: libraryNames.isEmpty
              ? friend?.libraryName ?? defaultLibraryName
              : libraryNames,
          username: friend?.username ?? '',
          bookId: document.id,
        ),
      );
    }
    return owners;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingLoanRequests(
    String uid,
  ) => _loanRequests.where('ownerId', isEqualTo: uid).snapshots();

  Future<void> requestLoan({
    required String bookId,
    required String ownerId,
    required String bookTitle,
    required User requester,
  }) async {
    final requesterProfile = await profile(requester.uid);
    final requesterName = requesterProfile?.username.isNotEmpty == true
        ? '@${requesterProfile!.username}'
        : requester.displayName?.trim().isNotEmpty == true
        ? requester.displayName!.trim()
        : requester.email?.split('@').first ?? 'Reader';
    final requestRef = _loanRequests.doc('${bookId}_${requester.uid}');
    await _firestore.runTransaction((transaction) async {
      final relationReference = _libraryBooks.doc(bookId);
      final relationSnapshot = await transaction.get(relationReference);
      final relation = relationSnapshot.data();
      final canonicalId = relation?['bookId'];
      final canonicalSnapshot = canonicalId is String
          ? await transaction.get(_books.doc(canonicalId))
          : null;
      final book = canonicalSnapshot?.data();
      final previous = (await transaction.get(requestRef)).data();
      if (ownerId == requester.uid ||
          relation == null ||
          relation['libraryId'] != ownerId ||
          book == null ||
          relation['wishlist'] == true) {
        throw const FormatException(
          'A loan request cannot be sent for this book.',
        );
      }
      if (hasBorrower(relation)) {
        throw const FormatException('This book is currently on loan.');
      }
      if (previous?['status'] == 'pending') {
        throw const FormatException(
          'You already have a pending request for this book.',
        );
      }
      transaction.set(requestRef, {
        'bookId': bookId,
        'ownerId': ownerId,
        'requesterId': requester.uid,
        'requesterName': requesterName,
        'bookTitle': bookTitle,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_notifications.doc(), {
        'bookId': bookId,
        'requestId': requestRef.id,
        'toId': ownerId,
        'fromId': requester.uid,
        'type': 'loanRequest',
        'title': 'Book loan request',
        'body': '$requesterName wants to borrow “$bookTitle”.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> approveLoanRequest(LoanRequest request) async {
    await _firestore.runTransaction((transaction) async {
      final current = (await transaction.get(_loanRequests.doc(request.id)))
          .data();
      final relationReference = _libraryBooks.doc(request.bookId);
      final relationSnapshot = await transaction.get(relationReference);
      final relation = relationSnapshot.data();
      final canonicalId = relation?['bookId'];
      final bookSnapshot = canonicalId is String
          ? await transaction.get(_books.doc(canonicalId))
          : null;
      final book = bookSnapshot?.data();
      if (current?['status'] != 'pending' ||
          relation == null ||
          relation['libraryId'] != request.ownerId ||
          book == null) {
        throw const FormatException('This request is no longer valid.');
      }
      if (hasBorrower(relation)) {
        throw const FormatException(
          'This book is already on loan; it must be returned first.',
        );
      }
      transaction.update(_loanRequests.doc(request.id), {
        'status': 'approved',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(relationReference, {
        'borrowerId': request.requesterId,
        'borrower': request.requesterName,
        'loanedAt': FieldValue.serverTimestamp(),
        'loanRequestId': request.id,
        'borrowerUserId': request.requesterId,
        'loanDue': null,
        'returnedAt': null,
      });
      transaction.set(_notifications.doc(), {
        'bookId': request.bookId,
        'requestId': request.id,
        'toId': request.requesterId,
        'fromId': request.ownerId,
        'type': 'loanApproved',
        'title': 'Your loan request was approved',
        'body': '“${request.bookTitle}” is now yours.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectLoanRequest(LoanRequest request) =>
      _loanRequests.doc(request.id).update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

  Future<void> nudgeBorrower({
    required String bookId,
    required String ownerId,
    required String borrowerId,
    required String bookTitle,
  }) => _notifications.add({
    'bookId': bookId,
    'toId': borrowerId,
    'fromId': ownerId,
    'type': 'loanReminder',
    'title': 'Book loan reminder',
    'body': 'You have “$bookTitle”. Remember to return it to its owner.',
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> notifications(String uid) =>
      _notifications.where('toId', isEqualTo: uid).snapshots();

  Future<void> markNotificationRead(String id) =>
      _notifications.doc(id).update({'read': true});
}
