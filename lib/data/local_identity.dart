import 'dart:convert';

import 'local_database.dart';

class LocalUser {
  const LocalUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoURL,
  });
  factory LocalUser.fromJson(Map<String, dynamic> json) => LocalUser(
    uid: json['uid'] as String,
    email: json['email'] as String?,
    displayName: json['displayName'] as String?,
    photoURL: json['photoURL'] as String?,
  );
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;
}

/// Identity is retained to preserve existing library and reading-position keys.
/// It is a local profile and requires no authentication service.
class LocalIdentity {
  static final instance = LocalIdentity();
  LocalUser? currentUser;

  Future<void> load(LocalDatabase database) async {
    final serialized = await database.setting('user');
    if (serialized == null) throw StateError('The local profile is missing.');
    currentUser = LocalUser.fromJson(
      jsonDecode(serialized) as Map<String, dynamic>,
    );
  }
}
