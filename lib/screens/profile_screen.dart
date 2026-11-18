import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

/// Mi perfil: quién soy, en qué clínica estoy, su plan y la suscripción.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final profile = session.profile!;
    final scheme = Theme.of(context).colorScheme;
    final status = profile.subscriptionStatus;
    final tone = switch (status) {
      'active' => 'success',
      'trial' => 'info',
      'grace' => 'warning',
      _ => 'danger',
    };

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Mi perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primary,
                    child: Text(
                      initialsOf(profile.name),
                      style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(profile.email, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Clínica'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: CompanyLogo(url: profile.company?.logoUrl, size: 40),
                  title: Text(profile.company?.name ?? ''),
                  subtitle: Text([profile.company?.address, profile.company?.phone].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                ),
                if (profile.companies.length > 1)
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Cambiar de clínica'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.findAncestorStateOfType<AppShellState>()?.openDrawer(),
                  ),
              ],
            ),
          ),
          const SectionTitle('Plan y suscripción'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(profile.planName == null ? 'Sin plan' : 'Plan ${profile.planName}'),
              subtitle: profile.allowsWrite ? null : const Text('Solo lectura: la suscripción no está vigente. Puedes consultar, pero no registrar.'),
              trailing: profile.subscriptionLabel == null ? null : StatusChip(profile.subscriptionLabel!, tone: tone),
            ),
          ),
          const SectionTitle('Seguridad'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Cambiar contraseña'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: scheme.error),
            onPressed: () async {
              if (await confirm(
                context,
                title: '¿Cerrar sesión?',
                message: 'Tendrás que volver a ingresar tu correo y contraseña.',
                action: 'Cerrar sesión',
              )) {
                await session.logout();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 16),
          Text(
            '${AppConfig.appName} · ${AppConfig.apiUrl.replaceAll('/api/v1', '')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Cambiar la contraseña: pide la actual; las demás sesiones (otros teléfonos o la web con token) se cierran.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  Map<String, String> _errors = const {};
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = const {};
    });
    try {
      final r = await context.session.api.put('/me/password', {
        'current_password': _current.text,
        'password': _new.text,
        'password_confirmation': _confirm.text,
      });
      if (!mounted) return;
      showDone(context, r.str('message') ?? 'Contraseña cambiada.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.fieldErrors.isEmpty) showError(context, e);
      setState(() => _errors = e.fieldErrors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, String field, {String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      errorText: _errors[field],
      suffixIcon: IconButton(
        tooltip: _show ? 'Ocultar' : 'Mostrar',
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _show = !_show),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _current, obscureText: !_show, decoration: deco('Contraseña actual', 'current_password')),
          const SizedBox(height: 12),
          TextField(
            controller: _new,
            obscureText: !_show,
            decoration: deco('Contraseña nueva', 'password', helper: 'Al menos 8 caracteres'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _confirm, obscureText: !_show, decoration: deco('Repite la contraseña nueva', 'password_confirmation')),
          const SizedBox(height: 8),
          Text('Las sesiones abiertas en otros teléfonos se cerrarán; en este sigues dentro.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _save,
            child: const Text('Cambiar contraseña'),
          ),
        ],
      ),
    );
  }
}
