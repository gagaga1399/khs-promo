import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_config.dart';

/// Результат операции входа: сообщение для пользователя или [error].
class AuthOutcome {
  final bool ok;
  final String? error;
  const AuthOutcome.ok() : ok = true, error = null;
  const AuthOutcome.fail(this.error) : ok = false;
}

/// Вход в аккаунт: логин/пароль и кнопка Google.
///
/// Сервис живёт всегда, даже если Firebase недоступен: в этом случае
/// [available] = false, а экран входа объясняет, что делать. Приложение при
/// этом работает как обычно — задачи, читалка и синхронизация с ПК не
/// зависят от аккаунта.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  fa.FirebaseAuth? _auth;
  StreamSubscription<fa.User?>? _sub;
  fa.User? _user;
  bool _available = false;
  bool _busy = false;
  String? _lastError;

  bool get available => _available;
  bool get busy => _busy;
  String? get lastError => _lastError;
  fa.User? get user => _user;
  bool get signedIn => _user != null;
  String? get email => _user?.email;
  String? get displayName => _user?.displayName;

  /// Google доступен, только если в консоли включён провайдер.
  bool get googleAvailable => _available && KhsFirebase.googleReady;

  /// Вызывается один раз при старте. Не бросает: любая ошибка Firebase
  /// превращается в [available] = false.
  Future<void> start() async {
    if (_available || _sub != null) return;
    try {
      await Firebase.initializeApp(options: KhsFirebase.options);
      _auth = fa.FirebaseAuth.instance;
      _available = true;
      _sub = _auth!.authStateChanges().listen(
            (u) {
              _user = u;
              notifyListeners();
            },
            onError: (_) {
              _available = false;
              notifyListeners();
            },
          );
    } catch (e) {
      _available = false;
      debugPrint('Firebase init failed: $e');
    }
    notifyListeners();
  }

  Future<AuthOutcome> signIn(String email, String password) =>
      _guard(() => _auth!.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  Future<AuthOutcome> register(String email, String password) =>
      _guard(() => _auth!.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  Future<AuthOutcome> signInWithGoogle() async {
    if (!googleAvailable) {
      return const AuthOutcome.fail(
        'Вход через Google ещё не включён в консоли Firebase',
      );
    }
    return _guard(() async {
      final signIn = GoogleSignIn.instance;
      // Один и тот же веб-клиент: на Windows это clientId, на Android —
      // serverClientId. Поэтому передаём оба.
      await signIn.initialize(
        clientId: KhsFirebase.googleClientId,
        serverClientId: KhsFirebase.googleClientId,
      );
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google не вернул токен входа');
      }
      final credential = fa.GoogleAuthProvider.credential(idToken: idToken);
      return _auth!.signInWithCredential(credential);
    });
  }

  Future<void> signOut() async {
    try {
      await _auth?.signOut();
      final signIn = GoogleSignIn.instance;
      if (KhsFirebase.googleReady) await signIn.signOut();
    } catch (_) {}
    _user = null;
    notifyListeners();
  }

  /// Обёртка: прячет ошибки Firebase в человеческий текст и следит за
  /// [busy], чтобы кнопки не дублировали запросы.
  Future<AuthOutcome> _guard(
    Future<fa.UserCredential> Function() action,
  ) async {
    if (!_available || _auth == null) {
      return const AuthOutcome.fail(
        'Вход временно недоступен: нет связи с Firebase',
      );
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      _user = _auth?.currentUser;
      return const AuthOutcome.ok();
    } on fa.FirebaseAuthException catch (e) {
      _lastError = _message(e);
      return AuthOutcome.fail(_lastError!);
    } catch (e) {
      _lastError = 'Не удалось войти: $e';
      return AuthOutcome.fail(_lastError!);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Коды Firebase переводим на русский: пользователю они ничего не говорят.
  static String _message(fa.FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Некорректный адрес почты',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Неверная почта или пароль',
        'email-already-in-use' => 'Такой аккаунт уже есть — войдите в него',
        'weak-password' => 'Пароль слишком простой: минимум 6 символов',
        'too-many-requests' => 'Слишком много попыток. Попробуйте позже',
        'network-request-failed' => 'Нет связи с интернетом',
        'operation-not-allowed' =>
          'Этот способ входа ещё не включён в консоли Firebase',
        _ => 'Не удалось войти: ${e.message ?? e.code}',
      };
}
