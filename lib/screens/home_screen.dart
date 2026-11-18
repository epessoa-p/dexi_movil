import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'patient_screens.dart';
import 'shell.dart';

/// Inicio: saludo, la agenda de hoy, lo que requiere atención y (para quien
/// ve dinero) lo cobrado. Todo se lee de un vistazo.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        titleSpacing: 0,
        title: Row(
          children: [
            CompanyLogo(url: profile.company?.logoUrl, size: 32),
            const SizedBox(width: 10),
            Expanded(child: Text(profile.company?.name ?? 'Dexi', overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/dashboard'),
        builder: (context, data, reload) => _HomeBody(data: data, profile: profile, reload: reload),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data, required this.profile, required this.reload});

  final Map<String, dynamic> data;
  final Profile profile;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final today = data.obj('today');
    final alerts = data.list('alerts');
    final finance = data.obj('finance');
    // «Dra. Ana Ruiz» → «Ana»: se saltan los títulos abreviados.
    final firstName = profile.name.split(' ').firstWhere((w) => w.isNotEmpty && !w.endsWith('.'), orElse: () => profile.name);
    final textTheme = Theme.of(context).textTheme;
    final canSchedule = profile.canUse('agenda', 'appointments.create');
    final canRegister = profile.can('patients.create');

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data.str('greeting')}, $firstName', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(fmtDayLong(companyNow()), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (today != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                _Tile(value: today.integer('total') ?? 0, label: 'Citas hoy', icon: Icons.event),
                const SizedBox(width: 8),
                _Tile(value: today.integer('waiting') ?? 0, label: 'En espera', icon: Icons.weekend_outlined, tone: 'warning'),
                const SizedBox(width: 8),
                _Tile(value: today.integer('done') ?? 0, label: 'Atendidas', icon: Icons.done_all, tone: 'success'),
              ],
            ),
          ),
        if (canSchedule || canRegister)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                if (canSchedule)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppointmentFormScreen()));
                        reload();
                      },
                      icon: const Icon(Icons.event_available),
                      label: const Text('Agendar'),
                    ),
                  ),
                if (canSchedule && canRegister) const SizedBox(width: 8),
                if (canRegister)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PatientFormScreen())),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Nuevo paciente'),
                    ),
                  ),
              ],
            ),
          ),
        if (finance != null) _FinanceCard(finance: finance),
        const SectionTitle('Requiere atención'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: alerts.isEmpty
                ? const ListTile(
                    leading: Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text('Todo en orden: nada pendiente'),
                  )
                : Column(children: [for (final a in alerts) AlertTile(alert: a)]),
          ),
        ),
        if (today != null) ...[
          SectionTitle(
            'Lo que sigue hoy',
            trailing: TextButton(onPressed: () => openSection(context, Section.agenda), child: const Text('Ver agenda')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: today.list('next').isEmpty
                  ? const ListTile(leading: Icon(Icons.event_available), title: Text('No quedan citas pendientes hoy'))
                  : Column(
                      children: [for (final a in today.list('next')) AppointmentTile(appointment: a, onChanged: reload)],
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Para quien ve dinero: lo cobrado hoy y en el mes, y lo que le deben.
class _FinanceCard extends StatelessWidget {
  const _FinanceCard({required this.finance});

  final Map<String, dynamic> finance;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final big = Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    final receivable = finance.number('receivable') ?? 0;
    final overdue = finance.number('receivable_overdue') ?? 0;
    final sales = finance.integer('sales_today') ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cobrado hoy', style: small),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(money(context, finance.number('today')), style: big),
                        ),
                        Text(sales == 1 ? '1 venta hoy' : '$sales ventas hoy', style: small),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Este mes', style: small),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(money(context, finance.number('month')), style: big),
                        ),
                        DeltaChip(finance.obj('month_delta')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (receivable > 0) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(Icons.request_quote_outlined, color: toneColor(context, overdue > 0 ? 'danger' : 'warning')),
                title: Text('Te deben ${money(context, receivable)}'),
                subtitle: overdue > 0 ? Text('${money(context, overdue)} ya vencido') : null,
                trailing: Section.receivables.allowedFor(context.read<Session>().profile!) ? const Icon(Icons.chevron_right) : null,
                onTap: Section.receivables.allowedFor(context.read<Session>().profile!) ? () => openSection(context, Section.receivables) : null,
              ),
            ],
            if (Section.summary.allowedFor(context.read<Session>().profile!)) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(Icons.insights_outlined, color: Theme.of(context).colorScheme.primary),
                title: const Text('Ver cómo va la clínica'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openSection(context, Section.summary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, required this.icon, this.tone});

  final int value;
  final String label;
  final IconData icon;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == null ? Theme.of(context).colorScheme.primary : toneColor(context, tone);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una alerta de «requiere atención». Si la app ya tiene esa pantalla, lleva a ella.
class AlertTile extends StatelessWidget {
  const AlertTile({super.key, required this.alert});

  final Map<String, dynamic> alert;

  static Section? sectionFor(String? key) => switch (key) {
    'waiting' => Section.waiting,
    'unconfirmed' => Section.agenda,
    'messages' || 'birthdays' => Section.messages,
    'followups' => Section.followups,
    'lab_late' || 'lab_install' => Section.labOrders,
    'low_stock' || 'expiring' => Section.inventory,
    _ => null,
  };

  static IconData iconFor(String? key) => switch (key) {
    'waiting' => Icons.weekend_outlined,
    'unconfirmed' => Icons.phone_in_talk_outlined,
    'messages' => Icons.chat_outlined,
    'birthdays' => Icons.cake_outlined,
    'followups' => Icons.replay,
    'lab_late' => Icons.diamond_outlined,
    'lab_install' => Icons.move_to_inbox_outlined,
    'low_stock' => Icons.trending_down,
    'expiring' => Icons.hourglass_bottom,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, alert.str('tone'));
    final section = sectionFor(alert.str('key'));
    final reachable = section != null && section.allowedFor(context.read<Session>().profile!);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .14),
        child: Icon(iconFor(alert.str('key')), color: color, size: 20),
      ),
      title: Text(alert.str('title') ?? ''),
      subtitle: alert.str('hint') == null ? null : Text(alert.str('hint')!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '${alert.integer('count')}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          if (reachable) const Icon(Icons.chevron_right),
        ],
      ),
      onTap: reachable ? () => openSection(context, section) : null,
    );
  }
}
