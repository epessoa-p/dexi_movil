import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'agenda_screens.dart';
import 'communication_screens.dart';
import 'lab_screens.dart';
import 'consultation_screens.dart';
import 'odontogram.dart';
import 'patient_documents.dart';
import 'sales_screens.dart';
import 'shell.dart';

/// Pacientes: búsqueda por nombre, documento, teléfono o historia. Con
/// [picking] sirve para elegir un paciente (al agendar) y devuelve su resumen.
class PatientSearchScreen extends StatefulWidget {
  const PatientSearchScreen({super.key, this.picking = false});

  final bool picking;

  @override
  State<PatientSearchScreen> createState() => _PatientSearchScreenState();
}

class _PatientSearchScreenState extends State<PatientSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  bool _alerts = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _term = value.trim()));
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => PatientFormScreen(initialName: _term)));
    if (created == null || !mounted) return;
    if (widget.picking) {
      Navigator.of(context).pop(created);
    } else {
      setState(() => _term = created.str('full_name') ?? '');
      _query.text = _term;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().profile!.can('patients.create');

    return Scaffold(
      appBar: AppBar(leading: widget.picking ? null : shellMenuButton(context), title: Text(widget.picking ? 'Elegir paciente' : 'Pacientes')),
      floatingActionButton: canCreate && !widget.picking
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: widget.picking,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nombre, documento, teléfono o historia',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _query.clear();
                          setState(() => _term = '');
                        },
                      ),
              ),
            ),
          ),
          if (!widget.picking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    avatar: Icon(Icons.warning_amber_rounded, size: 18, color: toneColor(context, 'danger')),
                    label: const Text('Con alertas médicas'),
                    selected: _alerts,
                    onSelected: (v) => setState(() => _alerts = v),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('$_term-$_alerts'),
              load: () => context.session.api.get('/patients', query: {'q': _term, 'alerts': _alerts ? '1' : null}),
              builder: (context, data, reload) {
                final items = data.list('data');
                final total = data.obj('meta')?.integer('total') ?? items.length;
                if (items.isEmpty) {
                  return ListView(
                    children: [
                      EmptyState(
                        icon: Icons.person_search,
                        message: _term.isEmpty ? 'Todavía no hay pacientes.' : 'No encontramos a «$_term».',
                        action: canCreate
                            ? FilledButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.person_add_alt),
                                label: Text(_term.isEmpty ? 'Registrar paciente' : 'Registrar «$_term»'),
                              )
                            : null,
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        total == 1 ? '1 paciente' : '$total pacientes${items.length < total ? ' · se muestran ${items.length}' : ''}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final p in items)
                              PatientTile(
                                patient: p,
                                onTap: () async {
                                  if (widget.picking) {
                                    Navigator.of(context).pop(p);
                                    return;
                                  }
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: p.integer('id')!)));
                                  reload();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
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

class PatientTile extends StatelessWidget {
  const PatientTile({super.key, required this.patient, this.onTap});

  final Map<String, dynamic> patient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final alerts = p['alerts'] as List? ?? const [];
    return ListTile(
      leading: PatientAvatar(name: p.str('full_name') ?? '', alert: alerts.isNotEmpty),
      title: Text(p.str('full_name') ?? ''),
      subtitle: Text(
        [p.str('code'), p.str('age_label'), p.str('phone')].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Tarjeta del paciente con llamar y WhatsApp.
class PatientCard extends StatelessWidget {
  const PatientCard({super.key, required this.patient, this.onTap});

  final Map<String, dynamic> patient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final phone = patient.str('phone');
    final whatsapp = patient.str('whatsapp_link');
    final alerts = patient['alerts'] as List? ?? const [];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              PatientAvatar(name: patient.str('full_name') ?? '', alert: alerts.isNotEmpty),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.str('full_name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      [patient.str('code'), patient.str('age_label'), phone ?? 'Sin teléfono'].whereType<String>().join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (phone != null)
                IconButton.filledTonal(tooltip: 'Llamar', onPressed: () => openExternal(context, 'tel:$phone'), icon: const Icon(Icons.call)),
              if (whatsapp != null)
                IconButton.filledTonal(tooltip: 'WhatsApp', onPressed: () => openExternal(context, whatsapp), icon: const Icon(Icons.chat)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alertas médicas (alergias, embarazo, anticoagulantes…): lo primero que se ve.
class MedicalAlerts extends StatelessWidget {
  const MedicalAlerts({super.key, required this.alerts});

  final List<dynamic> alerts;

  @override
  Widget build(BuildContext context) {
    final danger = toneColor(context, 'danger');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: .07),
        border: Border.all(color: danger.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: danger, size: 20),
              const SizedBox(width: 6),
              Text(
                'Antes de atender',
                style: TextStyle(color: danger, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in alerts)
                if (a is Map) StatusChip('${a['label']}', tone: a['critical'] == true ? 'danger' : 'warning'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ficha del paciente: Resumen y Citas (las demás pestañas llegan con sus módulos).
class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key, required this.id});

  final int id;

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final agenda = profile.canUse('agenda', 'appointments.view');
    final odontogram = profile.canUse('historia_clinica', 'odontogram.view');
    final history = profile.canUse('historia_clinica', 'consultations.view');
    final files = profile.can('patient_files.view');
    final payments = profile.canUse('ventas', 'sales.view');
    final tabs = [
      'Resumen',
      if (odontogram) 'Odontograma',
      if (history) 'Historia',
      if (agenda) 'Citas',
      if (payments) 'Pagos',
      if (files) 'Documentos',
    ];

    return Loader<Map<String, dynamic>>(
      key: _loader,
      load: () => context.session.api.get('/patients/${widget.id}'),
      builder: (context, p, reload) => DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(p.str('full_name') ?? 'Paciente'),
            actions: [
              if (profile.canUse('historia_clinica', 'consultations.create') && p.flag('active'))
                IconButton(
                  tooltip: 'Nueva consulta',
                  icon: const Icon(Icons.medical_services_outlined),
                  onPressed: () => startConsultation(context, patientId: widget.id),
                ),
              if (profile.canUse('laboratorio', 'lab_orders.create') && p.flag('active'))
                IconButton(
                  tooltip: 'Orden de laboratorio',
                  icon: const Icon(Icons.diamond_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LabOrderFormScreen(patientId: widget.id, patientName: p.str('full_name') ?? ''),
                    ),
                  ),
                ),
              if (profile.can('patients.edit'))
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final saved = await Navigator.of(
                      context,
                    ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => PatientFormScreen(patient: p)));
                    if (saved != null) reload();
                  },
                ),
            ],
            bottom: TabBar(
              isScrollable: tabs.length > 3,
              tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
              tabs: [for (final t in tabs) Tab(text: t)],
            ),
          ),
          floatingActionButton: profile.canUse('agenda', 'appointments.create') && p.flag('active')
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentFormScreen(patient: p))),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Agendar'),
                )
              : null,
          body: TabBarView(
            children: [
              RefreshIndicator(
                onRefresh: reload,
                child: _Summary(patient: p),
              ),
              if (odontogram)
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [OdontogramPanel(api: context.session.api, patientId: widget.id, editable: profile.can('odontogram.edit'))],
                ),
              if (history) _PatientHistory(patientId: widget.id),
              if (agenda) _PatientAppointments(patientId: widget.id),
              if (payments) PatientPayments(patientId: widget.id),
              if (files) PatientDocuments(patientId: widget.id, canUpload: profile.can('patient_files.create')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.patient});

  final Map<String, dynamic> patient;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final alerts = p['alerts'] as List? ?? const [];
    final rows = <(IconData, String, String?)>[
      (Icons.badge_outlined, 'Documento', p.str('document')),
      (
        Icons.cake_outlined,
        'Nacimiento',
        p.str('birth_date') == null ? null : '${fmtDate(DateTime.tryParse(p.str('birth_date')!))} · ${p.str('age_label') ?? ''}',
      ),
      (Icons.call_outlined, 'Teléfono', p.str('phone')),
      (Icons.chat_outlined, 'WhatsApp', p.str('whatsapp')),
      (Icons.mail_outline, 'Correo', p.str('email')),
      (Icons.home_outlined, 'Dirección', p.str('address')),
      (Icons.work_outline, 'Ocupación', p.str('occupation')),
      (Icons.health_and_safety_outlined, 'Seguro', p.str('insurance')),
      (Icons.family_restroom, 'Tutor', p.str('guardian_name') == null ? null : '${p.str('guardian_name')} · ${p.str('guardian_phone') ?? ''}'),
      (
        Icons.emergency_outlined,
        'Emergencia',
        p.str('emergency_contact') == null ? null : '${p.str('emergency_contact')} · ${p.str('emergency_phone') ?? ''}',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        PatientCard(patient: p),
        if (alerts.isNotEmpty) ...[const SizedBox(height: 12), MedicalAlerts(alerts: alerts)],
        if (context.read<Session>().profile!.canUse('recordatorios', 'communications.view')) PatientFollowupsCard(patientId: p.integer('id')!),
        const SectionTitle('Datos'),
        Card(
          child: Column(
            children: [
              for (final (icon, label, value) in rows)
                if (value != null && value.trim().isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: Icon(icon),
                    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
                    subtitle: Text(value, style: const TextStyle(fontSize: 15)),
                  ),
            ],
          ),
        ),
        const SectionTitle('Anamnesis'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Fact('Alergias', (p.str('allergies') ?? '').isEmpty ? 'Ninguna registrada' : p.str('allergies')!),
                const SizedBox(height: 10),
                Fact('Medicación', (p.str('medications') ?? '').isEmpty ? 'Ninguna registrada' : p.str('medications')!),
                if (p.str('blood_type') != null) ...[const SizedBox(height: 10), Fact('Grupo sanguíneo', p.str('blood_type')!)],
                if ((p.str('medical_notes') ?? '').isNotEmpty) ...[const SizedBox(height: 10), Fact('Notas médicas', p.str('medical_notes')!)],
                const SizedBox(height: 10),
                Text(
                  p.date('medical_updated_at') == null
                      ? 'Anamnesis sin completar: pregúntale en la próxima visita.'
                      : 'Actualizada el ${fmtDate(p.date('medical_updated_at'))}',
                  style: TextStyle(
                    fontSize: 12,
                    color: p.date('medical_updated_at') == null ? toneColor(context, 'warning') : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((p.str('notes') ?? '').isNotEmpty) ...[
          const SectionTitle('Notas'),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Text(p.str('notes')!)),
          ),
        ],
      ],
    );
  }
}

class _PatientAppointments extends StatelessWidget {
  const _PatientAppointments({required this.patientId});

  final int patientId;

  @override
  Widget build(BuildContext context) {
    final now = companyNow();
    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get(
        '/appointments',
        query: {'patient': '$patientId', 'from': isoDate(now.subtract(const Duration(days: 730))), 'to': isoDate(now.add(const Duration(days: 365)))},
      ),
      builder: (context, data, reload) {
        final items = data.list('data');
        final today = DateUtils.dateOnly(now);
        final upcoming = items.where((a) => !(a.date('starts_at') ?? now).isBefore(today)).toList();
        final past = items.where((a) => (a.date('starts_at') ?? now).isBefore(today)).toList().reversed.toList();
        if (items.isEmpty) {
          return ListView(
            children: const [EmptyState(icon: Icons.event_busy, message: 'Todavía no tiene citas.')],
          );
        }

        Widget block(String title, List<Map<String, dynamic>> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('$title · ${list.length}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final a in list) AppointmentTile(appointment: a, onChanged: reload, showDate: true, showPatient: false)],
                ),
              ),
            ),
          ],
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [if (upcoming.isNotEmpty) block('Próximas', upcoming), if (past.isNotEmpty) block('Anteriores', past)],
        );
      },
    );
  }
}

/// Alta y edición del paciente. Solo nombres y apellidos son obligatorios;
/// un menor de edad necesita un tutor (lo valida el servidor).
class PatientFormScreen extends StatefulWidget {
  const PatientFormScreen({super.key, this.patient, this.initialName});

  final Map<String, dynamic>? patient;

  /// «Registrar "Ana Pérez"» desde una búsqueda sin resultados.
  final String? initialName;

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  String? _documentType;
  String? _gender;
  String? _referral;
  String? _bloodType;
  bool _pregnant = false;
  DateTime? _birth;
  final Set<String> _conditions = {};
  Map<String, dynamic>? _options;
  bool _saving = false;
  ApiException? _error;

  static const _fields = [
    'first_name',
    'last_name',
    'document_number',
    'phone',
    'whatsapp',
    'email',
    'address',
    'occupation',
    'guardian_name',
    'guardian_relationship',
    'guardian_phone',
    'emergency_contact',
    'emergency_phone',
    'referred_by',
    'insurance',
    'allergies',
    'medications',
    'medical_notes',
    'notes',
  ];

  bool get _editing => widget.patient != null;

  bool get _minor => _birth != null && DateTime(_birth!.year + 18, _birth!.month, _birth!.day).isAfter(companyNow());

  @override
  void initState() {
    super.initState();
    final p = widget.patient ?? {};
    for (final f in _fields) {
      _c[f] = TextEditingController(text: p.str(f) ?? '');
    }
    if (!_editing && (widget.initialName ?? '').isNotEmpty) {
      final parts = widget.initialName!.split(' ');
      _c['first_name']!.text = parts.first;
      _c['last_name']!.text = parts.skip(1).join(' ');
    }
    _documentType = p.str('document_type');
    _gender = p.str('gender');
    _referral = p.str('referral_source');
    _bloodType = p.str('blood_type');
    _pregnant = p.flag('pregnant');
    _birth = p.str('birth_date') == null ? null : DateTime.tryParse(p.str('birth_date')!);
    _conditions.addAll([for (final x in (p['conditions'] as List? ?? [])) '$x']);
    context.session.api
        .get('/patients/options')
        .then((o) {
          if (mounted) setState(() => _options = o);
        })
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(companyNow().year - 30),
      firstDate: DateTime(1901),
      lastDate: companyNow(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      for (final f in _fields) f: _c[f]!.text.trim().isEmpty ? null : _c[f]!.text.trim(),
      'document_type': _documentType,
      'gender': _gender,
      'referral_source': _referral,
      'blood_type': _bloodType,
      'pregnant': _pregnant,
      'birth_date': _birth == null ? null : isoDate(_birth!),
      'conditions': _conditions.toList(),
    };
    try {
      final api = context.session.api;
      final saved = _editing ? await api.put('/patients/${widget.patient!.integer('id')}', body) : await api.post('/patients', body);
      if (!mounted) return;
      showDone(context, _editing ? 'Paciente actualizado.' : '${saved.str('full_name')} registrado (${saved.str('code')}).');
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      showError(context, e.fieldErrors.isEmpty ? e : 'Revisa los campos marcados.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _text(
    String field,
    String label, {
    IconData? icon,
    TextInputType? keyboard,
    int lines = 1,
    bool required = false,
    TextCapitalization? caps,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _c[field],
      keyboardType: keyboard,
      maxLines: lines,
      textCapitalization: caps ?? (keyboard == null ? TextCapitalization.sentences : TextCapitalization.none),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: icon == null ? null : Icon(icon),
        errorText: _error?.field(field),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio.' : null : null,
    ),
  );

  Widget _select(String label, String? value, List<Map<String, dynamic>> items, ValueChanged<String?> onChanged, {String field = ''}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.str('key') == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, errorText: _error?.field(field)),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('—')),
        for (final i in items) DropdownMenuItem(value: i.str('key'), child: Text(i.str('label') ?? '')),
      ],
      onChanged: onChanged,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final o = _options;
    final names = TextCapitalization.words;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar paciente' : 'Nuevo paciente')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              // Columna (no ListView): los campos fuera de pantalla siguen vivos y se validan todos.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle('Datos personales'),
                    _text('first_name', 'Nombres', required: true, caps: names),
                    _text('last_name', 'Apellidos', required: true, caps: names),
                    Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: _select('Documento', _documentType, o.list('document_types'), (v) => setState(() => _documentType = v)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _text('document_number', 'Número', keyboard: TextInputType.text)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
                        onPressed: _pickBirth,
                        icon: const Icon(Icons.cake_outlined),
                        label: Text(_birth == null ? 'Fecha de nacimiento' : fmtDate(_birth)),
                      ),
                    ),
                    if (_error?.field('birth_date') != null)
                      Text(_error!.field('birth_date')!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    _select('Sexo', _gender, o.list('genders'), (v) => setState(() => _gender = v)),
                    _text('occupation', 'Ocupación'),
                    const SectionTitle('Contacto'),
                    _text('phone', 'Teléfono / celular', icon: Icons.call_outlined, keyboard: TextInputType.phone),
                    _text('whatsapp', 'WhatsApp (si es otro, con código de país)', icon: Icons.chat_outlined, keyboard: TextInputType.phone),
                    _text('email', 'Correo', icon: Icons.mail_outline, keyboard: TextInputType.emailAddress),
                    _text('address', 'Dirección', icon: Icons.home_outlined),
                    if (_minor) ...[
                      const SectionTitle('Tutor (es menor de edad)'),
                      _text('guardian_name', 'Nombre del tutor *', caps: names),
                      _text('guardian_relationship', 'Parentesco'),
                      _text('guardian_phone', 'Teléfono del tutor *', keyboard: TextInputType.phone),
                    ],
                    const SectionTitle('Anamnesis y alertas'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in o.list('conditions'))
                          FilterChip(
                            label: Text(c.str('label') ?? ''),
                            selected: _conditions.contains(c.str('key')),
                            selectedColor: c.flag('critical') ? toneColor(context, 'danger').withValues(alpha: .18) : null,
                            onSelected: (v) => setState(() => v ? _conditions.add(c.str('key')!) : _conditions.remove(c.str('key'))),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _text('allergies', 'Alergias (medicamentos, látex, anestesia…)', lines: 2),
                    _text('medications', 'Medicación actual', lines: 2),
                    if (_gender != 'M')
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Embarazo'),
                        value: _pregnant,
                        onChanged: (v) => setState(() => _pregnant = v),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        initialValue: _bloodType,
                        decoration: const InputDecoration(labelText: 'Grupo sanguíneo'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('—')),
                          for (final b in (o['blood_types'] as List? ?? [])) DropdownMenuItem(value: '$b', child: Text('$b')),
                        ],
                        onChanged: (v) => setState(() => _bloodType = v),
                      ),
                    ),
                    _text('medical_notes', 'Notas médicas', lines: 2),
                    const SectionTitle('Otros'),
                    _select('¿Cómo nos conoció?', _referral, o.list('referral_sources'), (v) => setState(() => _referral = v)),
                    _text('insurance', 'Seguro o convenio'),
                    _text('emergency_contact', 'Contacto de emergencia', caps: names),
                    _text('emergency_phone', 'Teléfono de emergencia', keyboard: TextInputType.phone),
                    _text('notes', 'Notas', lines: 2),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(_editing ? 'Guardar cambios' : 'Registrar paciente'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Historia clínica: las consultas del paciente con lo diagnosticado y lo realizado.
class _PatientHistory extends StatelessWidget {
  const _PatientHistory({required this.patientId});

  final int patientId;

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () => context.session.api.get('/patients/$patientId/consultations'),
      builder: (context, data, reload) {
        final items = data.list('data');
        if (items.isEmpty) {
          return ListView(
            children: const [EmptyState(icon: Icons.history_edu_outlined, message: 'Todavía no tiene consultas.')],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final c = items[i];
            final lines = [
              for (final d in c.list('diagnoses')) 'Dx: ${d.str('label')}${d.integer('tooth') != null ? ' (${d.integer('tooth')})' : ''}',
              for (final p in c.list('procedures'))
                '✓ ${p.str('name')}${p.integer('tooth') != null ? ' (${p.integer('tooth')}${p.str('surfaces') ?? ''})' : ''}',
            ];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: c.integer('id')!)));
                  reload();
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(fmtDate(c.date('started_at')), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          StatusChip(c.flag('open') ? 'Abierta' : 'Cerrada', tone: c.flag('open') ? 'warning' : 'success'),
                        ],
                      ),
                      Text(
                        [c.str('code'), c.obj('professional')?.str('name')].whereType<String>().join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (c.str('reason') != null) ...[const SizedBox(height: 6), Text(c.str('reason')!)],
                      if (lines.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        for (final l in lines) Text(l, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
