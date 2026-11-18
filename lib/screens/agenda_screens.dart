import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'consultation_screens.dart';
import 'patient_screens.dart';
import 'shell.dart';

/// Lo que se puede hacer con una cita según su estado (TRANSITIONS de la web).
const appointmentActions = {
  'confirmada': ('Confirmó', Icons.check),
  'en_espera': ('Llegó', Icons.meeting_room_outlined),
  'en_atencion': ('Pasa a atención', Icons.play_arrow),
  'atendida': ('Atendida', Icons.done_all),
  'agendada': ('Volver a agendada', Icons.undo),
  'no_asistio': ('No asistió', Icons.person_off_outlined),
  'cancelada': ('Cancelar cita', Icons.close),
};

/// Agenda: las citas de un día, con flechas, calendario y «solo mis citas».
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = DateUtils.dateOnly(companyNow());
  bool _mine = false;
  int? _professional;
  int _version = 0;

  void _shift(int days) => setState(() => _day = _day.add(Duration(days: days)));

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: companyNow().subtract(const Duration(days: 365)),
      lastDate: companyNow().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _schedule() async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => AppointmentFormScreen(day: _day)));
    if (saved == null) return;
    setState(() {
      _day = DateUtils.dateOnly(saved.date('starts_at') ?? _day);
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_day, companyNow());
    final canCreate = context.watch<Session>().profile!.can('appointments.create');

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(onPressed: _schedule, icon: const Icon(Icons.add), label: const Text('Agendar'))
          : null,
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Agenda'),
        actions: [
          if (!isToday) TextButton(onPressed: () => setState(() => _day = DateUtils.dateOnly(companyNow())), child: const Text('Hoy')),
          IconButton(tooltip: 'Elegir fecha', onPressed: _pick, icon: const Icon(Icons.calendar_today_outlined)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                IconButton(tooltip: 'Día anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: InkWell(
                    onTap: _pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        isToday ? 'Hoy · ${fmtDayLong(_day)}' : fmtDayLong(_day),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                IconButton(tooltip: 'Día siguiente', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('${isoDate(_day)}-$_mine-$_professional-$_version'),
              load: () => context.session.api.get(
                '/appointments',
                query: {'date': isoDate(_day), 'mine': _mine ? '1' : null, 'professional': _professional?.toString()},
              ),
              builder: (context, data, reload) {
                final items = data.list('data');
                final professionals = data.list('professionals');
                final active = items.where((a) => !['cancelada', 'no_asistio'].contains(a.str('status'))).length;
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('Solo mis citas'),
                            selected: _mine,
                            onSelected: (v) => setState(() {
                              _mine = v;
                              if (v) _professional = null;
                            }),
                          ),
                          if (professionals.length > 1)
                            for (final p in professionals)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ChoiceChip(
                                  avatar: CircleAvatar(backgroundColor: _hex(p.str('color')), radius: 6),
                                  label: Text(p.str('name') ?? ''),
                                  selected: _professional == p.integer('id'),
                                  onSelected: (v) => setState(() {
                                    _professional = v ? p.integer('id') : null;
                                    if (v) _mine = false;
                                  }),
                                ),
                              ),
                        ],
                      ),
                    ),
                    if (items.isEmpty)
                      EmptyState(icon: Icons.event_available, message: _mine ? 'No tienes citas este día.' : 'No hay citas este día.')
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          active == 1 ? '1 cita' : '$active citas',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [for (final a in items) AppointmentTile(appointment: a, onChanged: reload)],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Color «#7c3aed» de la API a Color.
Color _hex(String? hex) {
  final value = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return value == null ? Colors.grey : Color(0xFF000000 | value);
}

/// Fila de una cita: hora, paciente, motivo, profesional y estado.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appointment, required this.onChanged, this.showDate = false, this.showPatient = true});

  final Map<String, dynamic> appointment;
  final Future<void> Function() onChanged;
  final bool showDate;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final patient = a.obj('patient') ?? {};
    final pro = a.obj('professional');
    final start = a.date('starts_at');
    final muted = ['cancelada', 'no_asistio'].contains(a.str('status'));
    final alerts = (patient['alerts'] as List?) ?? const [];

    return Opacity(
      opacity: muted ? .55 : 1,
      child: ListTile(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentScreen(id: a.integer('id')!)));
          onChanged();
        },
        leading: Container(
          width: 56,
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: _hex(pro?.str('color')), width: 3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fmtTime(start), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (showDate) Text(fmtShortDate(start), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        title: Row(
          children: [
            if (showPatient && alerts.isNotEmpty) ...[
              Icon(Icons.warning_amber_rounded, size: 16, color: toneColor(context, 'danger')),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(showPatient ? (patient.str('full_name') ?? 'Paciente') : (a.str('title') ?? 'Cita'), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(
          [if (showPatient) a.str('title'), pro?.str('name')].whereType<String>().join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusChip(a.str('status_label') ?? '', tone: a.str('status_color')),
      ),
    );
  }
}

/// Detalle de la cita con las acciones posibles según su estado.
class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key, required this.id});

  final int id;

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  String? _busy;
  Map<String, dynamic>? _appointment;

  Future<void> _setStatus(String status) async {
    String? reason;
    if (status == 'cancelada') {
      reason = await askText(context, title: '¿Cancelar la cita?', label: 'Motivo', action: 'Cancelar cita');
      if (reason == null) return;
    } else if (status == 'no_asistio') {
      if (!await confirm(context, title: '¿Marcar que no asistió?', message: 'La cita quedará como «No asistió».', action: 'Confirmar')) return;
    }
    if (!mounted) return;
    setState(() => _busy = status);
    try {
      await context.session.api.patch('/appointments/${widget.id}/status', {'status': status, 'cancel_reason': ?reason});
      if (mounted) showDone(context, 'Cita: ${appointmentActions[status]?.$1.toLowerCase() ?? status}.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Abre WhatsApp con el recordatorio y lo registra (para no escribir dos veces).
  Future<void> _remind(Map<String, dynamic> a) async {
    final reminder = a.obj('reminder')!;
    await openExternal(context, reminder.str('whatsapp_url')!);
    if (!reminder.flag('log') || !mounted) return;
    try {
      await context.session.api.post('/communications/send', {
        'kind': 'recordatorio',
        'patient_id': a.obj('patient')?.integer('id'),
        'appointment_id': a.integer('id'),
        'message': reminder.str('message'),
      });
      _loader.currentState?.reload();
    } on ApiException {
      // WhatsApp ya se abrió: si no se pudo registrar, no es grave.
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canEdit = profile.can('appointments.edit');
    final current = _appointment;
    final canReschedule = canEdit && current != null && ['agendada', 'confirmada'].contains(current.str('status'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cita'),
        actions: [
          if (canReschedule)
            IconButton(
              tooltip: 'Reprogramar',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () async {
                final saved = await Navigator.of(
                  context,
                ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => AppointmentFormScreen(appointment: current)));
                if (saved != null) _loader.currentState?.reload();
              },
            ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async {
          final a = await context.session.api.get('/appointments/${widget.id}');
          if (mounted) setState(() => _appointment = a);
          return a;
        },
        builder: (context, a, reload) {
          final patient = a.obj('patient') ?? {};
          final next = [for (final s in (a['next_statuses'] as List? ?? [])) '$s'];
          final primary = next.where((s) => !['cancelada', 'no_asistio', 'agendada'].contains(s)).toList();
          final secondary = next.where((s) => ['cancelada', 'no_asistio', 'agendada'].contains(s)).toList();
          final reminder = a.obj('reminder');
          final alerts = patient['alerts'] as List? ?? const [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${fmtTime(a.date('starts_at'))} – ${fmtTime(a.date('ends_at'))}',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          StatusChip(a.str('status_label') ?? '', tone: a.str('status_color')),
                        ],
                      ),
                      Text(fmtDayLong(a.date('starts_at') ?? companyNow())),
                      const SizedBox(height: 12),
                      _Line(Icons.medical_services_outlined, a.str('title') ?? 'Consulta'),
                      _Line(Icons.person_outline, a.obj('professional')?.str('name') ?? 'Sin profesional'),
                      if (a.str('notes') != null) _Line(Icons.sticky_note_2_outlined, a.str('notes')!),
                      if (a.str('cancel_reason') != null) _Line(Icons.info_outline, 'Motivo: ${a.str('cancel_reason')}'),
                      if (a.flag('overbooked')) _Line(Icons.warning_amber_rounded, 'Sobrecupo'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PatientCard(
                patient: patient,
                onTap: profile.can('patients.view')
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: patient.integer('id')!)))
                    : null,
              ),
              if (alerts.isNotEmpty) ...[const SizedBox(height: 8), MedicalAlerts(alerts: alerts)],
              if (profile.canUse('historia_clinica', 'consultations.create') &&
                  (a.integer('consultation_id') != null || ['agendada', 'confirmada', 'en_espera', 'en_atencion'].contains(a.str('status')))) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () async {
                    final existing = a.integer('consultation_id');
                    if (existing != null) {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: existing)));
                    } else {
                      await startConsultation(context, appointmentId: a.integer('id'));
                    }
                    _loader.currentState?.reload();
                  },
                  icon: const Icon(Icons.medical_services_outlined),
                  label: Text(a.integer('consultation_id') != null ? 'Ver consulta' : 'Atender: abrir consulta'),
                ),
              ],
              if (reminder != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: reminder.str('whatsapp_url') == null ? null : () => _remind(a),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(
                    reminder.str('whatsapp_url') == null
                        ? 'Sin celular para recordarle'
                        : (reminder.date('sent_at') != null
                              ? 'Recordar de nuevo (enviado ${fmtDateTime(reminder.date('sent_at'))})'
                              : 'Recordar por WhatsApp'),
                  ),
                ),
              ],
              if (canEdit && next.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final s in primary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy == null ? () => _setStatus(s) : null,
                      icon: _busy == s
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(appointmentActions[s]?.$2),
                      label: Text(appointmentActions[s]?.$1 ?? s),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in secondary)
                      OutlinedButton.icon(
                        onPressed: _busy == null ? () => _setStatus(s) : null,
                        icon: Icon(appointmentActions[s]?.$2),
                        label: Text(appointmentActions[s]?.$1 ?? s),
                      ),
                  ],
                ),
              ],
              if (a.list('history').isNotEmpty) ...[
                const SectionTitle('Historial'),
                Card(
                  child: Column(
                    children: [
                      for (final h in a.list('history'))
                        ListTile(
                          dense: true,
                          title: Text(h.str('description') ?? ''),
                          subtitle: Text([fmtDateTime(h.date('at')), h.str('user')].whereType<String>().join(' · ')),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Agendar una cita nueva o reprogramar una existente: paciente, procedimiento
/// (con su duración), profesional, día y un horario libre.
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, this.day, this.appointment, this.patient});

  final DateTime? day;
  final Map<String, dynamic>? appointment;

  /// Paciente ya elegido (al agendar desde su ficha).
  final Map<String, dynamic>? patient;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  Map<String, dynamic>? _patient;
  int? _professional;
  Map<String, dynamic>? _procedure;
  late DateTime _day;
  int _duration = 30;
  String? _time;
  final _reason = TextEditingController();
  final _notes = TextEditingController();

  List<Map<String, dynamic>> _professionals = [];
  List<Map<String, dynamic>> _procedures = [];
  List<String>? _slots;
  bool _loadingSlots = false;
  bool _saving = false;
  ApiException? _error;

  bool get _editing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    _patient = a?.obj('patient') ?? widget.patient;
    _professional = a?.obj('professional')?.integer('id');
    _procedure = a?.obj('procedure');
    final start = a?.date('starts_at');
    _day = DateUtils.dateOnly(start ?? widget.day ?? companyNow());
    if (DateUtils.dateOnly(companyNow()).isAfter(_day)) _day = DateUtils.dateOnly(companyNow());
    _duration = a?.integer('duration_minutes') ?? 30;
    _time = start == null ? null : fmtTime(start);
    _reason.text = a?.str('reason') ?? '';
    _notes.text = a?.str('notes') ?? '';
    _loadCatalogs();
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final api = context.session.api;
    final profile = context.session.profile!;
    try {
      final agenda = await api.get('/appointments', query: {'date': isoDate(_day)});
      final procedures = profile.can('procedures.view') ? await api.get('/procedures') : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _professionals = agenda.list('professionals');
        _procedures = procedures.list('data');
        _professional ??= _professionals.length == 1 ? _professionals.first.integer('id') : null;
      });
      _loadSlots();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _loadSlots() async {
    if (_professional == null) return;
    setState(() {
      _loadingSlots = true;
      _slots = null;
    });
    try {
      final data = await context.session.api.get(
        '/appointments/slots',
        query: {'personal_id': '$_professional', 'date': isoDate(_day), 'duration': '$_duration'},
      );
      if (!mounted) return;
      final slots = [for (final s in (data['slots'] as List? ?? [])) '$s'];
      setState(() {
        _slots = slots;
        // Al reprogramar se conserva la hora original aunque esté «ocupada» por la misma cita.
        if (_time != null && !slots.contains(_time) && !_editing) _time = null;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pickPatient() async {
    final chosen = await Navigator.of(
      context,
    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PatientSearchScreen(picking: true)));
    if (chosen != null) setState(() => _patient = chosen);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateUtils.dateOnly(companyNow()),
      lastDate: companyNow().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _day = picked);
      _loadSlots();
    }
  }

  Future<void> _save({bool force = false}) async {
    if (_patient == null || _professional == null || _time == null) {
      showError(context, 'Elige paciente, profesional y hora.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'patient_id': _patient!.integer('id'),
      'personal_id': _professional,
      'procedure_id': _procedure?.integer('id'),
      'date': isoDate(_day),
      'time': _time,
      'duration': _duration,
      'reason': _reason.text.trim(),
      'notes': _notes.text.trim(),
      if (force) 'force': true,
    };
    try {
      final api = context.session.api;
      final saved = _editing ? await api.put('/appointments/${widget.appointment!.integer('id')}', body) : await api.post('/appointments', body);
      if (!mounted) return;
      showDone(
        context,
        _editing ? 'Cita reprogramada.' : 'Cita agendada para el ${fmtShortDate(saved.date('starts_at'))} a las ${fmtTime(saved.date('starts_at'))}.',
      );
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Choque de horario: el servidor lo dice; se ofrece agendar igual (sobrecupo).
      final clash = e.fieldErrors.keys.any((k) => k == 'time' || k == 'force');
      if (clash &&
          !force &&
          await confirm(
            context,
            title: 'Horario ocupado',
            message: '${e.fieldErrors.values.first}\n\n¿Agendar igual como sobrecupo?',
            action: 'Agendar igual',
          )) {
        return _save(force: true);
      }
      if (!mounted) return;
      setState(() => _error = e);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Reprogramar cita' : 'Agendar cita')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: _patient == null
                  ? const CircleAvatar(child: Icon(Icons.person_search))
                  : PatientAvatar(name: _patient!.str('full_name') ?? '', alert: (_patient!['alerts'] as List?)?.isNotEmpty ?? false),
              title: Text(_patient?.str('full_name') ?? 'Elegir paciente'),
              subtitle: Text(_patient == null ? 'Busca por nombre, documento o teléfono' : (_patient!.str('code') ?? '')),
              trailing: _editing ? null : const Icon(Icons.chevron_right),
              onTap: _editing ? null : _pickPatient,
            ),
          ),
          if (_error?.field('patient_id') != null) _FieldError(_error!.field('patient_id')!),
          const SizedBox(height: 16),
          if (_procedures.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: _procedure?.integer('id'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Procedimiento (opcional)', prefixIcon: Icon(Icons.medical_services_outlined)),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('Consulta / sin procedimiento')),
                for (final p in _procedures)
                  DropdownMenuItem<int>(
                    value: p.integer('id'),
                    child: Text('${p.str('name')} · ${p.integer('duration_minutes') ?? 30} min', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                setState(() {
                  _procedure = id == null ? null : _procedures.firstWhere((p) => p.integer('id') == id);
                  _duration = _procedure?.integer('duration_minutes') ?? 30;
                });
                _loadSlots();
              },
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _professional,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Profesional',
              prefixIcon: const Icon(Icons.person_outline),
              errorText: _error?.field('personal_id'),
            ),
            items: [for (final p in _professionals) DropdownMenuItem<int>(value: p.integer('id'), child: Text(p.str('name') ?? ''))],
            onChanged: (id) {
              setState(() => _professional = id);
              _loadSlots();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(fmtDayLong(_day)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  initialValue: _duration,
                  decoration: const InputDecoration(labelText: 'Duración'),
                  items: [
                    for (final m in {15, 20, 30, 45, 60, 90, 120, _duration}.toList()..sort()) DropdownMenuItem(value: m, child: Text('$m min')),
                  ],
                  onChanged: (m) {
                    setState(() => _duration = m ?? 30);
                    _loadSlots();
                  },
                ),
              ),
            ],
          ),
          const SectionTitle('Horario'),
          if (_professional == null)
            Text('Elige el profesional para ver sus horarios libres.', style: TextStyle(color: scheme.onSurfaceVariant))
          else if (_loadingSlots)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if ((_slots ?? []).isEmpty && !_editing)
            Text('No hay horarios libres ese día. Prueba otro día u otro profesional.', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in {...?_slots, ?_time}.toList()..sort())
                  ChoiceChip(label: Text(s), selected: _time == s, onSelected: (_) => setState(() => _time = s)),
              ],
            ),
          if (_error?.field('time') != null) _FieldError(_error!.field('time')!),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas internas (opcional)'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(_editing ? 'Guardar cambios' : 'Agendar'),
          ),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
  );
}

/// Sala de espera: quién llegó (y hace cuánto), quién está en atención y
/// quién falta llegar hoy. Se actualiza sola cada 30 segundos.
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  Timer? _timer;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loader.currentState?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _set(Map<String, dynamic> a, String status) async {
    setState(() => _busy = a.integer('id'));
    try {
      await context.session.api.patch('/appointments/${a.integer('id')}/status', {'status': status});
      if (mounted) showDone(context, '${a.obj('patient')?.str('full_name')}: ${appointmentActions[status]?.$1.toLowerCase()}.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().profile!.can('appointments.edit');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Sala de espera')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/appointments', query: {'date': isoDate(companyNow())}),
        builder: (context, data, reload) {
          final items = data.list('data');
          final waiting = items.where((a) => a.str('status') == 'en_espera').toList()
            ..sort((a, b) => (a.date('arrived_at') ?? companyNow()).compareTo(b.date('arrived_at') ?? companyNow()));
          final inCare = items.where((a) => a.str('status') == 'en_atencion').toList();
          final coming = items.where((a) => ['agendada', 'confirmada'].contains(a.str('status'))).toList();

          Widget group(String title, List<Map<String, dynamic>> list, String empty, Widget Function(Map<String, dynamic>)? action) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('$title · ${list.length}'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: list.isEmpty
                      ? ListTile(
                          title: Text(empty, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        )
                      : Column(
                          children: [
                            for (final a in list)
                              ListTile(
                                leading: PatientAvatar(
                                  name: a.obj('patient')?.str('full_name') ?? '',
                                  alert: (a.obj('patient')?['alerts'] as List?)?.isNotEmpty ?? false,
                                ),
                                title: Text(a.obj('patient')?.str('full_name') ?? ''),
                                subtitle: Text(
                                  [
                                    fmtTime(a.date('starts_at')),
                                    a.obj('professional')?.str('name'),
                                    if (a.date('arrived_at') != null && a.str('status') == 'en_espera') 'llegó ${fmtAgo(a.date('arrived_at'))}',
                                  ].whereType<String>().join(' · '),
                                ),
                                trailing: canEdit && action != null
                                    ? (_busy == a.integer('id')
                                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                          : action(a))
                                    : null,
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentScreen(id: a.integer('id')!)));
                                  reload();
                                },
                              ),
                          ],
                        ),
                ),
              ),
            ],
          );

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              group(
                'En atención',
                inCare,
                'Nadie en atención ahora.',
                (a) => TextButton(onPressed: () => _set(a, 'atendida'), child: const Text('Atendida')),
              ),
              group(
                'En sala de espera',
                waiting,
                'Nadie esperando.',
                (a) => FilledButton.tonal(onPressed: () => _set(a, 'en_atencion'), child: const Text('Pasa')),
              ),
              group(
                'Por llegar hoy',
                coming,
                'No hay más citas hoy.',
                (a) => OutlinedButton(onPressed: () => _set(a, 'en_espera'), child: const Text('Llegó')),
              ),
            ],
          );
        },
      ),
    );
  }
}
