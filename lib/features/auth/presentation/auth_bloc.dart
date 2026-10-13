import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/auth_repository.dart';

sealed class AuthEvent {
  const AuthEvent();
}

final class AuthGoogleSignInRequested extends AuthEvent {
  const AuthGoogleSignInRequested();
}

final class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});

  final String email;
  final String password;
}

final class AuthRegistrationRequested extends AuthEvent {
  const AuthRegistrationRequested({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

final class AuthPasswordResetRequested extends AuthEvent {
  const AuthPasswordResetRequested(this.email);

  final String email;
}

enum AuthStatus { idle, loading, failure }

final class AuthState {
  const AuthState({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.infoMessage,
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? infoMessage;

  bool get isLoading => status == AuthStatus.loading;
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.repository}) : super(const AuthState()) {
    on<AuthGoogleSignInRequested>(_signInWithGoogle);
    on<AuthSignInRequested>(_signIn);
    on<AuthRegistrationRequested>(_register);
    on<AuthPasswordResetRequested>(_resetPassword);
  }

  final AuthGateway repository;

  Future<void> _signInWithGoogle(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _run(emit, repository.signInWithGoogle);
  }

  Future<void> _signIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _run(
      emit,
      () => repository.signIn(event.email.trim(), event.password),
    );
  }

  Future<void> _register(
    AuthRegistrationRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _run(
      emit,
      () => repository.register(event.email.trim(), event.password),
    );
  }

  Future<void> _resetPassword(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _run(
      emit,
      () => repository.resetPassword(event.email.trim()),
      successMessage: 'A password reset email has been sent.',
    );
  }

  Future<void> _run(
    Emitter<AuthState> emit,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await action();
      emit(AuthState(infoMessage: successMessage));
    } catch (error) {
      if (_isGoogleCancellation(error)) {
        emit(const AuthState());
        return;
      }
      emit(
        AuthState(status: AuthStatus.failure, errorMessage: _messageFor(error)),
      );
    }
  }

  bool _isGoogleCancellation(Object error) =>
      error is FirebaseAuthException &&
      error.code == 'google-sign-in-cancelled';

  String _messageFor(Object error) {
    if (error is FirebaseAuthException && error.message != null) {
      return error.message!;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
