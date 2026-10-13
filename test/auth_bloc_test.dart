import 'package:booklibrary/data/auth_repository.dart';
import 'package:booklibrary/features/auth/presentation/auth_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful sign-in emits loading and idle states', () async {
    final gateway = _FakeAuthGateway();
    final bloc = AuthBloc(repository: gateway);

    final statesFuture = bloc.stream.take(2).toList();
    bloc.add(
      const AuthSignInRequested(
        email: '  reader@example.com ',
        password: 'secret',
      ),
    );
    final states = await statesFuture;

    expect(states.map((state) => state.status), [
      AuthStatus.loading,
      AuthStatus.idle,
    ]);
    expect(gateway.lastEmail, 'reader@example.com');
    await bloc.close();
  });

  test('repository failures are exposed as a failure state', () async {
    final bloc = AuthBloc(
      repository: _FakeAuthGateway(error: StateError('service unavailable')),
    );

    final statesFuture = bloc.stream.take(2).toList();
    bloc.add(const AuthGoogleSignInRequested());
    final states = await statesFuture;

    expect(states.last.status, AuthStatus.failure);
    expect(states.last.errorMessage, 'Bad state: service unavailable');
    await bloc.close();
  });

  test('cancelled Google sign-in does not show an error', () async {
    final bloc = AuthBloc(
      repository: _FakeAuthGateway(
        error: FirebaseAuthException(code: 'google-sign-in-cancelled'),
      ),
    );

    final statesFuture = bloc.stream.take(2).toList();
    bloc.add(const AuthGoogleSignInRequested());
    final states = await statesFuture;

    expect(states.last.status, AuthStatus.idle);
    expect(states.last.errorMessage, isNull);
    await bloc.close();
  });
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({this.error});

  final Object? error;
  String? lastEmail;

  @override
  Stream<User?> get authState => const Stream<User?>.empty();

  @override
  Future<void> signIn(String email, String password) async {
    lastEmail = email;
    _throwIfNeeded();
  }

  @override
  Future<void> register(String email, String password) async =>
      _throwIfNeeded();

  @override
  Future<void> resetPassword(String email) async => _throwIfNeeded();

  @override
  Future<void> signOut() async => _throwIfNeeded();

  @override
  Future<void> signInWithGoogle() async => _throwIfNeeded();

  void _throwIfNeeded() {
    if (error != null) throw error!;
  }
}
