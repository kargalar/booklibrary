import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as native_google;
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';

const googleDesktopClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
const googleDesktopClientSecret = String.fromEnvironment(
  'GOOGLE_OAUTH_CLIENT_SECRET',
);

abstract interface class AuthGateway {
  Stream<User?> get authState;

  Future<void> signIn(String email, String password);

  Future<void> register(String email, String password);

  Future<void> resetPassword(String email);

  Future<void> signOut();

  Future<void> signInWithGoogle();
}

class AuthRepository implements AuthGateway {
  AuthRepository({
    FirebaseAuth? auth,
    native_google.GoogleSignIn? mobileGoogleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _mobileGoogleSignIn =
           mobileGoogleSignIn ?? native_google.GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final native_google.GoogleSignIn _mobileGoogleSignIn;
  Future<void>? _mobileInitialization;
  static GoogleSignIn? _googleSignIn;

  static GoogleSignIn get _desktopGoogleSignIn =>
      _googleSignIn ??= GoogleSignIn(
        params: const GoogleSignInParams(
          clientId: googleDesktopClientId,
          clientSecret: googleDesktopClientSecret,
          scopes: ['openid', 'profile', 'email'],
        ),
      );

  @override
  Stream<User?> get authState => _auth.authStateChanges();
  @override
  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);
  @override
  Future<void> register(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);
  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (_mobileInitialization != null) await _mobileGoogleSignIn.signOut();
    if (_googleSignIn != null) await _googleSignIn!.signOut();
  }

  @override
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithProvider(GoogleAuthProvider());
      return;
    }

    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) {
      await _signInWithGoogleMobile();
      return;
    }
    if (googleDesktopClientId.isEmpty || googleDesktopClientSecret.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-desktop-config-missing',
        message: 'Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET to enable Google sign-in on Windows.',
      );
    }

    final credentials = await _desktopGoogleSignIn.signInOnline();
    if (credentials == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google sign-in was canceled.',
      );
    }
    final idToken = credentials.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Google authentication did not return an ID token. Check the desktop OAuth configuration.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      accessToken: credentials.accessToken,
      idToken: idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> _signInWithGoogleMobile() async {
    // Android reads its web client ID from google-services.json. Desktop OAuth
    // credentials must not override that platform configuration.
    await (_mobileInitialization ??= _mobileGoogleSignIn.initialize());
    final account = await _mobileGoogleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Google authentication did not return an ID token. Check the mobile OAuth configuration.',
      );
    }
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }
}
