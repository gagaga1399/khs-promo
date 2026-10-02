import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';

/// Экран аккаунта: вход по почте и паролю, вход кнопкой Google, выход.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService.instance;
  bool _register = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите почту и пароль');
      return;
    }
    final outcome = _register
        ? await _auth.register(email, password)
        : await _auth.signIn(email, password);
    if (!mounted) return;
    setState(() => _error = outcome.ok ? null : outcome.error);
    if (outcome.ok) _password.clear();
  }

  Future<void> _google() async {
    final outcome = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _error = outcome.ok ? null : outcome.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт')),
      body: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) {
          if (!_auth.available) return _unavailable();
          if (_auth.signedIn) return _signedIn();
          return _form();
        },
      ),
    );
  }

  Widget _unavailable() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: _disabled),
            const SizedBox(height: 16),
            const Text(
              'Вход сейчас недоступен: нет связи с Firebase.\n'
              'Приложением можно пользоваться как обычно — задачи и '
              'синхронизация с ПК не требуют аккаунта.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Color get _disabled =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

  Widget _signedIn() {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 34,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Icon(Icons.person,
                size: 38, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            _auth.displayName?.isNotEmpty == true
                ? _auth.displayName!
                : (_auth.email ?? 'Аккаунт'),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Card(
            child: ListenableBuilder(
              listenable: Listenable.merge([state, _auth]),
              builder: (context, _) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.cloudStatus == 'error'
                              ? Icons.cloud_off
                              : Icons.cloud_done_outlined,
                          size: 20,
                          color: state.cloudStatus == 'error'
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _syncCaption(state),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Задачи и заметки синхронизируются между устройствами. '
                      'Файлы книг остаются на этом устройстве.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: state.cloudSyncing
                          ? null
                          : () => state.syncWithCloud(),
                      icon: state.cloudSyncing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        state.cloudSyncing ? 'Синхронизация…' : 'Синхронизировать',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: _auth.busy ? null : _auth.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

  String _syncCaption(AppState state) {
    if (state.cloudSyncing) return 'Синхронизация с облаком…';
    switch (state.cloudStatus) {
      case 'ok':
        final at = state.cloudSyncedAt;
        if (at == null) return 'Синхронизировано';
        final hh = at.hour.toString().padLeft(2, '0');
        final mm = at.minute.toString().padLeft(2, '0');
        return 'Синхронизировано в $hh:$mm';
      case 'error':
        return 'Не удалось связаться с облаком';
      default:
        return 'Ожидает синхронизации';
    }
  }

  Widget _form() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          _register ? 'Создать аккаунт' : 'Вход в аккаунт',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Аккаунт нужен, чтобы задачи и читалка синхронизировались между '
          'устройствами через интернет.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Почта',
            prefixIcon: Icon(Icons.alternate_email),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Пароль',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _auth.busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _auth.busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_register ? 'Создать' : 'Войти'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _auth.busy
              ? null
              : () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
          child: Text(
            _register
                ? 'Уже есть аккаунт? Войти'
                : 'Нет аккаунта? Создать',
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('или', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        _googleButton(dark),
        const SizedBox(height: 10),
        if (!_auth.googleAvailable)
          Text(
            'Вход через Google появится, когда провайдер будет включён в '
            'консоли Firebase.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _googleButton(bool dark) => SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _auth.busy || !_auth.googleAvailable ? null : _google,
          style: OutlinedButton.styleFrom(
            backgroundColor: dark ? const Color(0xFF141416) : Colors.white,
            foregroundColor: dark ? Colors.white : const Color(0xFF202124),
            side: BorderSide(
              color: (dark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.20),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'G',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4285F4),
                ),
              ),
              const SizedBox(width: 10),
              const Text('Войти через Google'),
            ],
          ),
        ),
      );
}
