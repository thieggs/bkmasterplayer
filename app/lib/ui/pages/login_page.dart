import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/local/local_setup.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../../l10n/l10n.dart';
import '../widgets/bk_logo.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _local = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _local.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            url: _url.text,
            username: _user.text.trim(),
            password: _pass.text,
            localUrl: _local.text,
          );
    } on SubsonicException catch (e) {
      setState(() => _error = e.isAuthError ? context.l10n.wrongCredentials : e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sem servidor: só as músicas do aparelho.
  Future<void> _useLocal() async {
    final l10n = context.l10n;
    if (!await ensureMusicPermission()) {
      setState(() => _error = l10n.musicPermissionDenied);
      return;
    }
    if (!mounted) return;
    final folder = await chooseMusicFolder(context);
    if (folder == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await runWithScanProgress(context, () => ref.read(sessionProvider.notifier).loginLocal([folder]));
      if (n == 0 && mounted) setState(() => _error = l10n.noLocalSongs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BkLogo(size: 72)),
                    const SizedBox(height: 12),
                    Text(l10n.appTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(l10n.loginSubtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autofillHints: const [AutofillHints.url],
                      decoration: InputDecoration(
                        labelText: l10n.serverUrl,
                        hintText: 'https://musica.exemplo.com',
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.required : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _local,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.localAddress,
                        hintText: 'http://192.168.1.10:4533',
                        helperText: l10n.localAddressHint,
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.home_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _user,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: l10n.username,
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.required : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l10n.connect),
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.loginHint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 20),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l10n.or)),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _useLocal,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.useLocalMusic),
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.useLocalMusicHint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _busy ? null : () => context.push('/jam'),
                      icon: const Icon(Icons.groups_outlined),
                      label: Text(l10n.joinJamNoAccount),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
