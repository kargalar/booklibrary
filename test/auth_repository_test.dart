import 'package:booklibrary/data/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android uses platform configuration and signs in with the ID token',
    () async {
      final auth = _FakeFirebaseAuth();
      final googleSignIn = _FakeGoogleSignIn();
      final repository = AuthRepository(
        auth: auth,
        mobileGoogleSignIn: googleSignIn,
      );

      await repository.signInWithGoogle();

      expect(googleSignIn.initializeCalls, 1);
      expect(googleSignIn.clientId, isNull);
      expect(googleSignIn.serverClientId, isNull);
      expect(googleSignIn.scopeHint, isEmpty);
      final credential = auth.credential as OAuthCredential;
      expect(credential.providerId, 'google.com');
      expect(credential.idToken, 'google-id-token');
      expect(credential.accessToken, isNull);
    },
  );

  test('repeated Android sign-in initializes Google only once', () async {
    final googleSignIn = _FakeGoogleSignIn();
    final repository = AuthRepository(
      auth: _FakeFirebaseAuth(),
      mobileGoogleSignIn: googleSignIn,
    );

    await repository.signInWithGoogle();
    await repository.signOut();
    await repository.signInWithGoogle();

    expect(googleSignIn.initializeCalls, 1);
    expect(googleSignIn.signOutCalls, 1);
  });

  for (final idToken in <String?>[null, '']) {
    test('missing ID token ($idToken) does not reach Firebase', () async {
      final auth = _FakeFirebaseAuth();
      final repository = AuthRepository(
        auth: auth,
        mobileGoogleSignIn: _FakeGoogleSignIn(idToken: idToken),
      );

      await expectLater(
        repository.signInWithGoogle(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'google-id-token-missing',
          ),
        ),
      );
      expect(auth.credential, isNull);
    });
  }

  test(
    'Google configuration failures propagate instead of becoming cancellation',
    () async {
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'Invalid server client ID.',
      );
      final repository = AuthRepository(
        auth: _FakeFirebaseAuth(),
        mobileGoogleSignIn: _FakeGoogleSignIn(error: error),
      );

      await expectLater(repository.signInWithGoogle(), throwsA(same(error)));
    },
  );

  test(
    'sign-out before Google initialization does not initialize Google',
    () async {
      final googleSignIn = _FakeGoogleSignIn();
      final repository = AuthRepository(
        auth: _FakeFirebaseAuth(),
        mobileGoogleSignIn: googleSignIn,
      );

      await repository.signOut();

      expect(googleSignIn.initializeCalls, 0);
      expect(googleSignIn.signOutCalls, 0);
    },
  );
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  AuthCredential? credential;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    this.credential = credential;
    return _FakeUserCredential();
  }

  @override
  Future<void> signOut() async {}
}

class _FakeUserCredential extends Fake implements UserCredential {}

class _FakeGoogleSignIn extends Fake implements GoogleSignIn {
  _FakeGoogleSignIn({this.idToken = 'google-id-token', this.error});

  final String? idToken;
  final GoogleSignInException? error;
  int initializeCalls = 0;
  int signOutCalls = 0;
  String? clientId;
  String? serverClientId;
  List<String>? scopeHint;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    initializeCalls++;
    this.clientId = clientId;
    this.serverClientId = serverClientId;
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const [],
  }) async {
    this.scopeHint = scopeHint;
    if (error != null) throw error!;
    return _FakeGoogleAccount(idToken);
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}

class _FakeGoogleAccount extends Fake implements GoogleSignInAccount {
  _FakeGoogleAccount(this.idToken);

  final String? idToken;

  @override
  GoogleSignInAuthentication get authentication =>
      GoogleSignInAuthentication(idToken: idToken);
}
