import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'patient_screens.dart';
import 'shell.dart';

// Comunicaciones por WhatsApp (wa.me): la app abre WhatsApp con el mensaje
// listo y registra el envío. Es donde más sirve: WhatsApp está en el teléfono.

Color _hex(String? hex, Color fallback) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

IconData kindIcon(String? kind) => switch (kind) {
  'recordatorio' => Icons.event_available_outlined,
  'cumpleanos' => Icons.cake_outlined,
  'seguimiento' => Icons.replay,
  'inasistencia' => Icons.person_off_outlined,
  'saldo' => Icons.request_quote_outlined,
  _ => Icons.chat_outlined,
};

/// Nombre corto del tipo, para que las pestañas quepan en el teléfono.
String shortKind(Map<String, dynamic> k) => switch (k.str('key')) {
  'recordatorio' => 'Citas',
  'cumpleanos' => 'Cumpleaños',
  'seguimiento' => 'Controles',
  'inasistencia' => 'No vinieron',
  'saldo' => 'Saldos',
  _ => k.str('label') ?? '',
};

/// «Para enviar hoy»: recordatorios, cumpleaños, controles, inasistencias y
/// saldos, con el mensaje listo. «Enviar» abre WhatsApp y lo deja registrado.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// Recordatorios de las citas de mañana (lo normal) o de hoy.
  bool _today = false;
  String? _kind;
  int _version = 0;

  /// Enviados en esta pantalla (mientras se recarga la lista).
  final _sentNow = <String>{};

  Future<void> _send(Map<String, dynamic> row) async {
    await openExternal(context, row.str('whatsapp_url')!);
    if (!mounted) return;
    setState(() => _sentNow.add(row.str('key')!));
    try {
      await context.session.api.post('/communications/send', {
        'kind': row.str('kind'),
        'patient_id': row.obj('patient')?.integer('id'),
        'message': row.str('message'),
        'appointment_id': ?row.integer('appointment_id'),
        'followup_id': ?row.integer('followup_id'),
      });
    } on ApiException catch (e) {
      if (mounted) showError(context, 'WhatsApp se abrió, pero no se pudo registrar el envío: ${e.message}');
    }
  }

  Future<void> _done(Map<String, dynamic> row) async {
    try {
      await context.session.api.post('/followups/${row.integer('followup_id')}/status', {'status': 'hecho'});
      if (!mounted) return;
      showDone(context, 'Control marcado como hecho.');
      setState(() => _version++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = context.watch<Session>().profile!.can('communications.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Para enviar hoy')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_today-$_version'),
        load: () => context.session.api.get('/communications/queue', query: {'dia': _today ? 'hoy' : null}),
        builder: (context, data, reload) {
          final kinds = data.list('kinds');
          final rowsByKind = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
          // Por defecto, el primer tipo con algo pendiente.
          final kind = kinds.any((k) => k.str('key') == _kind)
              ? _kind!
              : (kinds.firstWhere((k) => (k.integer('pending') ?? 0) > 0, orElse: () => kinds.isEmpty ? const {} : kinds.first).str('key') ?? '');
          final rows = [for (final r in (rowsByKind[kind] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
          final current = kinds.where((k) => k.str('key') == kind).firstOrNull;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    for (final k in kinds)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(kindIcon(k.str('key')), size: 18, color: _hex(k.str('color'), Colors.teal)),
                          label: Text((k.integer('pending') ?? 0) > 0 ? '${shortKind(k)} · ${k.integer('pending')}' : shortKind(k)),
                          selected: k.str('key') == kind,
                          onSelected: (_) => setState(() => _kind = k.str('key')),
                        ),
                      ),
                  ],
                ),
              ),
              if (kind == 'recordatorio')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Citas de mañana')),
                      ButtonSegment(value: true, label: Text('Citas de hoy')),
                    ],
                    selected: {_today},
                    onSelectionChanged: (v) => setState(() => _today = v.first),
                  ),
                ),
              SectionTitle(
                current == null
                    ? 'Nada por enviar'
                    : '${current.str('label')} · ${(current.integer('pending') ?? 0) == 0 ? 'todo enviado' : '${current.integer('pending')} por enviar'}',
              ),
              if (rows.isEmpty)
                EmptyState(
                  icon: Icons.mark_chat_read_outlined,
                  message: (data.integer('pending') ?? 0) == 0 ? 'No hay nada por enviar hoy. ¡Al día!' : 'Nada en esta lista.',
                )
              else
                for (final row in rows)
                  _MessageCard(
                    row: row,
                    color: _hex(current?.str('color'), Theme.of(context).colorScheme.primary),
                    sentNow: _sentNow.contains(row.str('key')),
                    onSend: canSend && row.str('whatsapp_url') != null ? () => _send(row) : null,
                    onDone: canSend && row.integer('followup_id') != null ? () => _done(row) : null,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatefulWidget {
  const _MessageCard({required this.row, required this.color, required this.sentNow, this.onSend, this.onDone});

  final Map<String, dynamic> row;
  final Color color;
  final bool sentNow;
  final VoidCallback? onSend;
  final VoidCallback? onDone;

  @override
  State<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<_MessageCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final patient = row.obj('patient') ?? const {};
    final sent = row.obj('sent');
    final wasSent = widget.sentNow || sent != null;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: patient.integer('id')!))),
                    child: Text(patient.str('full_name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                if (wasSent)
                  StatusChip(widget.sentNow ? 'Enviado ahora' : 'Enviado ${fmtTime(parseCompanyTimeOrNull(sent?.str('at')))}', tone: 'success'),
              ],
            ),
            Text(row.str('detail') ?? '', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: widget.color.withValues(alpha: .07), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  row.str('message') ?? '',
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onDone != null)
                  TextButton.icon(onPressed: widget.onDone, icon: const Icon(Icons.check, size: 18), label: const Text('Hecho')),
                const SizedBox(width: 4),
                if (row.str('whatsapp_url') == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sin celular', style: TextStyle(color: muted)),
                  )
                else
                  (wasSent ? OutlinedButton.icon : FilledButton.icon)(
                    onPressed: widget.onSend,
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(wasSent ? 'Enviar de nuevo' : 'Enviar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La fecha y hora de la API (hora de la clínica), o null.
DateTime? parseCompanyTimeOrNull(String? iso) => {'at': iso}.date('at');

// ── Controles programados ──────────────────────────────────────────────────

class FollowupsScreen extends StatefulWidget {
  const FollowupsScreen({super.key});

  @override
  State<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends State<FollowupsScreen> {
  String _status = 'pendiente';
  int _version = 0;

  static const _labels = {'pendiente': 'Pendientes', 'hecho': 'Hechos', 'descartado': 'Descartados'};

  Future<void> _set(Map<String, dynamic> f, String status) async {
    try {
      await context.session.api.post('/followups/${f.integer('id')}/status', {'status': status});
      if (!mounted) return;
      showDone(context, switch (status) {
        'hecho' => 'Control marcado como hecho.',
        'descartado' => 'Control descartado.',
        _ => 'Control otra vez pendiente.',
      });
      setState(() => _version++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().profile!.can('communications.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Controles')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_status-$_version'),
        load: () => context.session.api.get('/followups', query: {'estado': _status}),
        builder: (context, data, reload) {
          final counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
          final items = data.list('data');
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    for (final MapEntry(key: k, value: label) in _labels.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('$label · ${counts[k] ?? 0}'),
                          selected: _status == k,
                          onSelected: (_) => setState(() => _status = k),
                        ),
                      ),
                  ],
                ),
              ),
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.event_repeat,
                  message: _status == 'pendiente'
                      ? 'No hay controles pendientes. Prográmalos desde la ficha del paciente o al cerrar una consulta.'
                      : 'Nada en esta lista.',
                )
              else
                for (final f in items) FollowupTile(followup: f, onStatus: canEdit ? (s) => _set(f, s) : null, showPatient: true),
            ],
          );
        },
      ),
    );
  }
}

class FollowupTile extends StatelessWidget {
  const FollowupTile({super.key, required this.followup, this.onStatus, this.showPatient = false});

  final Map<String, dynamic> followup;
  final ValueChanged<String>? onStatus;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final f = followup;
    final pending = f.str('status') == 'pendiente';
    final overdue = f.flag('overdue');
    final due = DateTime.tryParse(f.str('due_date') ?? '');
    final patient = f.obj('patient');
    final color = toneColor(context, pending ? (overdue ? 'danger' : 'info') : (f.str('status') == 'hecho' ? 'success' : null));

    return Card(
      margin: showPatient ? const EdgeInsets.fromLTRB(16, 0, 16, 8) : const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: showPatient && patient != null
            ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: patient.integer('id')!)))
            : null,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(pending ? Icons.event_repeat : (f.str('status') == 'hecho' ? Icons.check : Icons.close), color: color, size: 20),
        ),
        title: Text(showPatient ? (patient?.str('full_name') ?? '') : (f.str('reason') ?? '')),
        subtitle: Text(
          [
            if (showPatient) f.str('reason'),
            pending
                ? (overdue ? 'vencido desde el ${fmtShortDate(due)}' : 'para el ${fmtShortDate(due)}')
                : '${f.str('status_label')} · era el ${fmtShortDate(due)}',
            if ((f.str('notes') ?? '').isNotEmpty) f.str('notes'),
          ].whereType<String>().join(' · '),
          style: overdue && pending ? TextStyle(color: color, fontWeight: FontWeight.w600) : null,
        ),
        trailing: onStatus == null
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: onStatus,
                itemBuilder: (_) => pending
                    ? const [PopupMenuItem(value: 'hecho', child: Text('Hecho')), PopupMenuItem(value: 'descartado', child: Text('Descartar'))]
                    : const [PopupMenuItem(value: 'pendiente', child: Text('Volver a pendiente'))],
              ),
      ),
    );
  }
}

/// Programar un control (limpieza en 6 meses, retiro de puntos…). Aparece en
/// «Para enviar hoy» el día que vence. Devuelve true si se programó.
Future<bool> scheduleFollowup(BuildContext context, {required int patientId, int? consultationId}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScheduleSheet(patientId: patientId, consultationId: consultationId),
  );
  return r ?? false;
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.patientId, this.consultationId});

  final int patientId;
  final int? consultationId;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  List<String> _reasons = const [];
  List<Map<String, dynamic>> _quick = const [];
  String? _in;
  DateTime? _date;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.session.api
        .get('/followups', query: {'patient_id': '${widget.patientId}'})
        .then((r) {
          if (!mounted) return;
          setState(() {
            _reasons = [for (final x in (r['reasons'] as List? ?? const [])) '$x'];
            _quick = r.list('quick');
            _in = _quick.where((q) => q.str('label') == '6 meses').firstOrNull?.str('in');
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Escribe o elige el motivo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.api.post('/patients/${widget.patientId}/followups', {
        'reason': _reason.text.trim(),
        if (_date != null) 'due_date': isoDate(_date!) else 'in': _in,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'consultation_id': ?widget.consultationId,
      });
      if (!mounted) return;
      showDone(context, 'Control programado: aparecerá en «Para enviar hoy» el día que toque.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Programar control', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in _reasons)
                    ChoiceChip(label: Text(r), selected: _reason.text == r, onSelected: (_) => setState(() => _reason.text = r)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const Text('¿Cuándo?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in _quick)
                    ChoiceChip(
                      label: Text('En ${q.str('label')}'),
                      selected: _date == null && _in == q.str('in'),
                      onSelected: (_) => setState(() {
                        _in = q.str('in');
                        _date = null;
                      }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(_date == null ? 'Otra fecha' : fmtDate(_date)),
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date ?? now.add(const Duration(days: 30)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365 * 3)),
                      );
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.event_repeat),
                label: const Text('Programar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los controles pendientes del paciente (en su ficha), con «Programar».
class PatientFollowupsCard extends StatefulWidget {
  const PatientFollowupsCard({super.key, required this.patientId});

  final int patientId;

  @override
  State<PatientFollowupsCard> createState() => _PatientFollowupsCardState();
}

class _PatientFollowupsCardState extends State<PatientFollowupsCard> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.session.api.get('/followups', query: {'patient_id': '${widget.patientId}'});
      if (mounted) setState(() => _items = r.list('data'));
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().profile!.can('communications.create');
    final items = _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Controles',
          trailing: canCreate
              ? TextButton.icon(
                  onPressed: () async {
                    if (await scheduleFollowup(context, patientId: widget.patientId)) _load();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Programar'),
                )
              : null,
        ),
        if (items == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          const Card(
            child: ListTile(leading: Icon(Icons.event_repeat), title: Text('Sin controles pendientes.')),
          )
        else
          for (final f in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: FollowupTile(
                followup: f,
                onStatus: canCreate
                    ? (s) async {
                        await context.session.api.post('/followups/${f.integer('id')}/status', {'status': s});
                        _load();
                      }
                    : null,
              ),
            ),
      ],
    );
  }
}
