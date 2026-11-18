import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'communication_screens.dart';
import 'odontogram.dart';
import 'patient_documents.dart';
import 'patient_screens.dart';
import 'sales_screens.dart';
import 'shell.dart';

/// Abre (o retoma) la consulta de una cita o de un paciente y la muestra.
Future<void> startConsultation(BuildContext context, {int? appointmentId, int? patientId}) async {
  try {
    final c = await context.session.api.post('/consultations', {'appointment_id': ?appointmentId, 'patient_id': ?patientId});
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: c.integer('id')!)));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Consultas: quién espera ser atendido ahora y las consultas de hoy, abiertas o mías.
class ConsultationsScreen extends StatefulWidget {
  const ConsultationsScreen({super.key});

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen> {
  String _filter = 'hoy';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().profile!.can('consultations.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Consultas')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_filter-$_version'),
        load: () => context.session.api.get('/consultations', query: {'filter': _filter}),
        builder: (context, data, reload) {
          final waiting = data.list('waiting');
          final items = data.list('data');
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final (key, label) in const [('hoy', 'Hoy'), ('abiertas', 'Abiertas'), ('mias', 'Mías')])
                      ChoiceChip(label: Text(label), selected: _filter == key, onSelected: (_) => setState(() => _filter = key)),
                  ],
                ),
              ),
              if (waiting.isNotEmpty && canCreate) ...[
                SectionTitle('Por atender · ${waiting.length}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final a in waiting)
                          ListTile(
                            leading: PatientAvatar(
                              name: a.obj('patient')?.str('full_name') ?? '',
                              alert: (a.obj('patient')?['alerts'] as List?)?.isNotEmpty ?? false,
                            ),
                            title: Text(a.obj('patient')?.str('full_name') ?? ''),
                            subtitle: Text([fmtTime(a.date('starts_at')), a.str('title'), a.str('status_label')].whereType<String>().join(' · ')),
                            trailing: FilledButton.tonal(
                              onPressed: () async {
                                await startConsultation(context, appointmentId: a.integer('id'));
                                setState(() => _version++);
                              },
                              child: const Text('Atender'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              SectionTitle('Consultas · ${items.length}'),
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.medical_services_outlined,
                  message: switch (_filter) {
                    'abiertas' => 'No hay consultas abiertas.',
                    'mias' => 'No tienes consultas.',
                    _ => 'Todavía no hay consultas hoy.',
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final c in items)
                          ConsultationTile(
                            consultation: c,
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: c.integer('id')!)));
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
    );
  }
}

class ConsultationTile extends StatelessWidget {
  const ConsultationTile({super.key, required this.consultation, this.onTap, this.showPatient = true});

  final Map<String, dynamic> consultation;
  final VoidCallback? onTap;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final open = c.flag('open');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: toneColor(context, open ? 'warning' : 'success').withValues(alpha: .14),
        child: Icon(open ? Icons.edit_note : Icons.verified_outlined, color: toneColor(context, open ? 'warning' : 'success')),
      ),
      title: Text(showPatient ? (c.obj('patient')?.str('full_name') ?? '') : (c.str('reason') ?? 'Consulta')),
      subtitle: Text(
        [
          c.str('code'),
          fmtDateTime(c.date('started_at')),
          c.obj('professional')?.str('name'),
          if (showPatient) c.str('reason'),
        ].whereType<String>().join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusChip(open ? 'Abierta' : 'Cerrada', tone: open ? 'warning' : 'success'),
      onTap: onTap,
    );
  }
}

/// La consulta en el sillón: evaluación, diagnósticos, lo realizado (y el plan) y el odontograma.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, required this.id});

  final int id;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  Map<String, dynamic>? _c;
  ClinicalCatalog? _catalog;
  Object? _error;
  bool _busy = false;

  static const _noteFields = [
    ('reason', 'Motivo de consulta', 1),
    ('history', 'Anamnesis / enfermedad actual', 3),
    ('exam', 'Examen clínico', 3),
    ('plan', 'Plan', 2),
    ('indications', 'Indicaciones para el paciente', 3),
    ('next_visit', 'Próxima visita', 1),
  ];
  final Map<String, TextEditingController> _notes = {for (final f in _noteFields) f.$1: TextEditingController()};
  bool _dirty = false;

  ApiClient get _api => context.session.api;

  @override
  void initState() {
    super.initState();
    for (final c in _notes.values) {
      c.addListener(() => _dirty = true);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.get('/consultations/${widget.id}'), ClinicalCatalog.load(_api)]);
      if (!mounted) return;
      _apply(results[0] as Map<String, dynamic>);
      setState(() => _catalog = results[1] as ClinicalCatalog);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _apply(Map<String, dynamic> c, {bool keepNotes = false}) {
    if (!keepNotes) {
      for (final f in _noteFields) {
        _notes[f.$1]!.text = c.str(f.$1) ?? '';
      }
      _dirty = false;
    }
    setState(() {
      _c = c;
      _error = null;
    });
  }

  /// Ejecuta una acción que devuelve la consulta actualizada.
  Future<bool> _run(Future<Map<String, dynamic>> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      final c = await action();
      if (!mounted) return false;
      _apply(c, keepNotes: true);
      if (done != null) showDone(context, done);
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, String> get _noteValues => {for (final f in _noteFields) f.$1: _notes[f.$1]!.text.trim()};

  Future<void> _saveNotes() async {
    final ok = await _run(() => _api.put('/consultations/${widget.id}', _noteValues), done: 'Consulta guardada.');
    if (ok) _dirty = false;
  }

  Future<void> _close() async {
    if (!await confirm(
      context,
      title: '¿Cerrar y firmar la consulta?',
      message: 'Después ya no se puede editar: solo agregar notas de corrección.',
      action: 'Cerrar consulta',
    )) {
      return;
    }
    final ok = await _run(() => _api.post('/consultations/${widget.id}/close', _noteValues), done: 'Consulta cerrada y firmada.');
    if (!ok || !mounted) return;
    _dirty = false;
    // Al cerrar es cuando se decide el próximo control (limpieza en 6 meses, retiro de puntos…).
    if (_canSchedule &&
        await confirm(
          context,
          title: '¿Programar un control?',
          message: 'Le aparecerá a la clínica en «Para enviar hoy» el día que toque.',
          action: 'Programar',
        )) {
      if (mounted) await _schedule();
    }
  }

  bool get _canSchedule => context.session.profile!.canUse('recordatorios', 'communications.create');

  Future<void> _schedule() async {
    final patientId = _c?.obj('patient')?.integer('id');
    if (patientId != null) await scheduleFollowup(context, patientId: patientId, consultationId: widget.id);
  }

  Future<void> _addendum() async {
    final text = await askText(context, title: 'Nota de corrección', label: 'Nota', action: 'Agregar');
    if (text == null) return;
    await _run(() => _api.post('/consultations/${widget.id}/addendum', {'addendum': text}), done: 'Nota agregada.');
  }

  /// Las indicaciones al paciente por WhatsApp (en lugar de la receta impresa).
  void _shareIndications() {
    final c = _c!;
    final patient = c.obj('patient') ?? {};
    final link = patient.str('whatsapp_link');
    final text = [
      'Hola ${(patient.str('full_name') ?? '').split(' ').first}, estas son tus indicaciones de ${context.session.profile?.company?.name ?? 'la clínica'}:',
      '',
      _notes['indications']!.text.trim(),
      if (_notes['next_visit']!.text.trim().isNotEmpty) '\nPróxima visita: ${_notes['next_visit']!.text.trim()}',
    ].join('\n');
    if (link == null) {
      showError(context, 'El paciente no tiene celular registrado.');
      return;
    }
    openExternal(context, '$link?text=${Uri.encodeComponent(text)}');
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final c = _c;
    final catalog = _catalog;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Consulta')),
        body: ErrorState(error: _error!, onRetry: _load),
      );
    }
    if (c == null || catalog == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Consulta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final open = c.flag('open');
    final canEdit = open && profile.can('consultations.edit');
    final patient = c.obj('patient') ?? {};

    return PopScope(
      canPop: !_dirty || !canEdit,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(context, title: 'Hay cambios sin guardar', message: '¿Salir sin guardar las notas?', action: 'Salir');
        if (leave && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: DefaultTabController(
        length: profile.can('patient_files.view') ? 5 : 4,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.str('full_name') ?? 'Consulta', overflow: TextOverflow.ellipsis),
                Text('${c.str('code')} · ${open ? 'abierta' : 'cerrada'}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Ficha del paciente',
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: patient.integer('id')!))),
              ),
              if (_notes['indications']!.text.trim().isNotEmpty)
                IconButton(tooltip: 'Enviar indicaciones por WhatsApp', icon: const Icon(Icons.chat_outlined), onPressed: _shareIndications),
              if (_canSchedule) IconButton(tooltip: 'Programar control', icon: const Icon(Icons.event_repeat), onPressed: _schedule),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Evaluación'),
                const Tab(text: 'Diagnósticos'),
                const Tab(text: 'Tratamiento'),
                const Tab(text: 'Odontograma'),
                if (profile.can('patient_files.view')) const Tab(text: 'Fotos'),
              ],
            ),
          ),
          bottomNavigationBar: canEdit
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: _busy ? null : _saveNotes,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Guardar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: _busy ? null : _close,
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Cerrar consulta'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          body: TabBarView(
            children: [
              _EvaluationTab(
                consultation: c,
                notes: _notes,
                fields: _noteFields,
                editable: canEdit,
                onAddendum: profile.can('consultations.edit') ? _addendum : null,
              ),
              _DiagnosesTab(consultation: c, catalog: catalog, editable: canEdit, run: _run),
              _TreatmentTab(consultation: c, catalog: catalog, editable: canEdit, run: _run),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  OdontogramPanel(
                    api: _api,
                    patientId: patient.integer('id')!,
                    editable: open && profile.can('odontogram.edit'),
                    consultationId: open ? c.integer('id') : null,
                    initial: c.obj('odontogram'),
                  ),
                ],
              ),
              if (profile.can('patient_files.view'))
                PatientDocuments(patientId: patient.integer('id')!, canUpload: profile.can('patient_files.create')),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvaluationTab extends StatelessWidget {
  const _EvaluationTab({required this.consultation, required this.notes, required this.fields, required this.editable, this.onAddendum});

  final Map<String, dynamic> consultation;
  final Map<String, TextEditingController> notes;
  final List<(String, String, int)> fields;
  final bool editable;
  final VoidCallback? onAddendum;

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final patient = c.obj('patient') ?? {};
    final alerts = patient['alerts'] as List? ?? const [];
    final open = c.flag('open');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (alerts.isNotEmpty) ...[MedicalAlerts(alerts: alerts), const SizedBox(height: 12)],
        if (!open)
          Card(
            color: toneColor(context, 'success').withValues(alpha: .08),
            child: ListTile(
              leading: Icon(Icons.verified_outlined, color: toneColor(context, 'success')),
              title: const Text('Cerrada y firmada'),
              subtitle: Text([fmtDateTime(c.date('closed_at')), c.str('closed_by')].whereType<String>().join(' · ')),
            ),
          ),
        if (!open) const SizedBox(height: 12),
        Text(
          [fmtDateTime(c.date('started_at')), c.obj('professional')?.str('name')].whereType<String>().join(' · '),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final (key, label, lines) in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: editable
                ? TextField(
                    controller: notes[key],
                    minLines: lines,
                    maxLines: lines == 1 ? 1 : 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: label,
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  )
                : (notes[key]!.text.isEmpty ? const SizedBox.shrink() : Fact(label, notes[key]!.text)),
          ),
        if ((c.str('addendum') ?? '').isNotEmpty) ...[
          const SectionTitle('Notas de corrección'),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Text(c.str('addendum')!)),
          ),
        ],
        if (!open && onAddendum != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: onAddendum,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Agregar nota de corrección'),
            ),
          ),
        if (c.list('previous').isNotEmpty) ...[
          const SectionTitle('Consultas anteriores'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final p in c.list('previous'))
                  ConsultationTile(
                    consultation: p,
                    showPatient: false,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsultationScreen(id: p.integer('id')!))),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

typedef _Runner = Future<bool> Function(Future<Map<String, dynamic>> Function() action, {String? done});

class _DiagnosesTab extends StatelessWidget {
  const _DiagnosesTab({required this.consultation, required this.catalog, required this.editable, required this.run});

  final Map<String, dynamic> consultation;
  final ClinicalCatalog catalog;
  final bool editable;
  final _Runner run;

  @override
  Widget build(BuildContext context) {
    final id = consultation.integer('id');
    final items = consultation.list('diagnoses');
    final api = context.session.api;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (items.isEmpty)
          const EmptyState(icon: Icons.fact_check_outlined, message: 'Sin diagnósticos todavía.')
        else
          Card(
            child: Column(
              children: [
                for (final d in items)
                  ListTile(
                    title: Text(d.str('label') ?? ''),
                    subtitle: Text(
                      [
                        d.str('icd'),
                        if (d.integer('tooth') != null) 'pieza ${d.integer('tooth')}${d.str('surfaces') ?? ''}',
                        d.str('notes'),
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: editable
                        ? IconButton(
                            tooltip: 'Quitar',
                            icon: const Icon(Icons.close),
                            onPressed: () => run(() => api.delete('/consultations/$id/diagnoses/${d.integer('id')}'), done: 'Diagnóstico quitado.'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        if (editable) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final body = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _DiagnosisSheet(catalog: catalog),
              );
              if (body != null) await run(() => api.post('/consultations/$id/diagnoses', body), done: 'Diagnóstico agregado.');
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar diagnóstico'),
          ),
        ],
      ],
    );
  }
}

/// Elegir un diagnóstico del catálogo (con buscador), la pieza y notas.
class _DiagnosisSheet extends StatefulWidget {
  const _DiagnosisSheet({required this.catalog});

  final ClinicalCatalog catalog;

  @override
  State<_DiagnosisSheet> createState() => _DiagnosisSheetState();
}

class _DiagnosisSheetState extends State<_DiagnosisSheet> {
  String _q = '';
  String? _code;
  final _label = TextEditingController();
  final _tooth = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _tooth.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.catalog.diagnoses
        .where((d) => _q.isEmpty || '${d.str('label')} ${d.str('icd')}'.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Diagnóstico', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_code == null) ...[
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar (caries, pulpitis, K04…)'),
                onChanged: (v) => setState(() => _q = v),
              ),
              for (final d in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.str('label') ?? ''),
                  subtitle: d.str('icd') == null ? null : Text(d.str('icd')!),
                  onTap: () => setState(() => _code = d.str('key')),
                ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.catalog.diagnoses.firstWhere((d) => d.str('key') == _code).str('label') ?? ''),
                trailing: TextButton(onPressed: () => setState(() => _code = null), child: const Text('Cambiar')),
              ),
              if (_code == 'otro') ...[
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Diagnóstico'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _tooth,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pieza (opcional, FDI: 16, 36, 55…)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.of(context).pop({
                  'code': _code,
                  if (_code == 'otro') 'label': _label.text.trim(),
                  if (_tooth.text.trim().isNotEmpty) 'tooth': int.tryParse(_tooth.text.trim()),
                  if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
                }),
                child: const Text('Agregar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TreatmentTab extends StatelessWidget {
  const _TreatmentTab({required this.consultation, required this.catalog, required this.editable, required this.run});

  final Map<String, dynamic> consultation;
  final ClinicalCatalog catalog;
  final bool editable;
  final _Runner run;

  @override
  Widget build(BuildContext context) {
    final id = consultation.integer('id');
    final items = consultation.list('procedures');
    final planItems = consultation.list('plan_items');
    final api = context.session.api;
    final toBill = consultation.number('to_bill') ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (editable && planItems.isNotEmpty) ...[
          const SectionTitle('Del plan de tratamiento'),
          Card(
            child: Column(
              children: [
                for (final i in planItems)
                  ListTile(
                    title: Text(i.str('name') ?? ''),
                    subtitle: Text(
                      [
                        i.str('plan'),
                        if (i.integer('tooth') != null) 'pieza ${i.integer('tooth')}${i.str('surfaces') ?? ''}',
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () =>
                          run(() => api.post('/consultations/$id/plan-items/${i.integer('id')}'), done: 'Registrado del plan: ${i.str('name')}.'),
                      child: const Text('Hecho hoy'),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SectionTitle('Realizado hoy'),
        if (items.isEmpty)
          const EmptyState(icon: Icons.healing_outlined, message: 'Todavía no se registró lo realizado.')
        else
          Card(
            child: Column(
              children: [
                for (final p in items)
                  ListTile(
                    title: Text(p.str('name') ?? ''),
                    subtitle: Text(
                      [
                        if (p.integer('tooth') != null) 'pieza ${p.integer('tooth')}${p.str('surfaces') ?? ''}',
                        if ((p.integer('quantity') ?? 1) > 1) '× ${p.integer('quantity')}',
                        money(context, p.number('price')),
                        if (p.flag('billed')) 'cobrado',
                      ].join(' · '),
                    ),
                    trailing: editable && !p.flag('billed')
                        ? IconButton(
                            tooltip: 'Quitar',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                run(() => api.delete('/consultations/$id/procedures/${p.integer('id')}'), done: 'Procedimiento quitado.'),
                          )
                        : null,
                  ),
                if (toBill > 0)
                  ListTile(
                    dense: true,
                    title: Text('Por cobrar: ${money(context, toBill)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: context.read<Session>().profile!.canUse('ventas', 'sales.create')
                        ? FilledButton.icon(
                            onPressed: () async {
                              final patientId = consultation.obj('patient')?.integer('id');
                              if (patientId == null) return;
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChargeScreen(patientId: patientId)));
                              await run(() => api.get('/consultations/$id'));
                            },
                            icon: const Icon(Icons.point_of_sale, size: 18),
                            label: const Text('Cobrar'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        if (editable) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final body = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ProcedureSheet(catalog: catalog),
              );
              if (body != null) await run(() => api.post('/consultations/$id/procedures', body), done: 'Registrado: ${body['_name']}.');
            },
            icon: const Icon(Icons.add),
            label: const Text('Registrar procedimiento'),
          ),
        ],
      ],
    );
  }
}

/// Registrar lo realizado: procedimiento del tarifario, pieza, caras y marcarlo en el odontograma.
class ProcedureSheet extends StatefulWidget {
  const ProcedureSheet({super.key, required this.catalog});

  final ClinicalCatalog catalog;

  @override
  State<ProcedureSheet> createState() => _ProcedureSheetState();
}

class _ProcedureSheetState extends State<ProcedureSheet> {
  List<Map<String, dynamic>>? _procedures;
  String _q = '';
  Map<String, dynamic>? _procedure;
  final _tooth = TextEditingController();
  final Set<String> _surfaces = {};
  int _quantity = 1;
  bool _mark = true;

  @override
  void initState() {
    super.initState();
    context.session.api
        .get('/procedures')
        .then((r) {
          if (mounted) setState(() => _procedures = r.list('data'));
        })
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  @override
  void dispose() {
    _tooth.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _procedure!;
    final scope = p.str('applies_to');
    final tooth = int.tryParse(_tooth.text.trim());
    if ((scope == 'pieza' || scope == 'cara') && tooth == null) {
      showError(context, '«${p.str('name')}» se hace en una pieza: escribe cuál.');
      return;
    }
    if (scope == 'cara' && _surfaces.isEmpty) {
      showError(context, 'Marca en qué cara(s).');
      return;
    }
    final mark = widget.catalog.markFor(p.str('code'));
    Navigator.of(context).pop({
      '_name': p.str('name'),
      'procedure_id': p.integer('id'),
      'tooth': ?tooth,
      if (_surfaces.isNotEmpty) 'surfaces': _surfaces.toList(),
      'quantity': _quantity,
      if (_mark && mark != null && tooth != null) 'mark': mark,
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = (_procedures ?? [])
        .where((p) => _q.isEmpty || '${p.str('name')} ${p.str('code')} ${p.str('specialty')}'.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final p = _procedure;
    final scope = p?.str('applies_to');
    final mark = widget.catalog.markFor(p?.str('code'));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Procedimiento realizado', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (p == null) ...[
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en el tarifario'),
                onChanged: (v) => setState(() => _q = v),
              ),
              if (_procedures == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              for (final x in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.str('name') ?? ''),
                  subtitle: Text([x.str('specialty'), x.str('applies_to_label'), money(context, x.number('price'))].whereType<String>().join(' · ')),
                  onTap: () => setState(() => _procedure = x),
                ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([p.str('applies_to_label'), money(context, p.number('price'))].whereType<String>().join(' · ')),
                trailing: TextButton(onPressed: () => setState(() => _procedure = null), child: const Text('Cambiar')),
              ),
              if (scope == 'pieza' || scope == 'cara')
                TextField(
                  controller: _tooth,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Pieza (FDI: 16, 36, 55…)'),
                ),
              if (scope == 'cara') ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final MapEntry(key: k, value: label) in widget.catalog.surfaces.entries)
                      FilterChip(
                        label: Text('$k · ${label.split(' ').first}'),
                        selected: _surfaces.contains(k),
                        onSelected: (v) => setState(() => v ? _surfaces.add(k) : _surfaces.remove(k)),
                      ),
                  ],
                ),
              ],
              if (scope != 'pieza' && scope != 'cara')
                Row(
                  children: [
                    const Text('Cantidad'),
                    const Spacer(),
                    IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove_circle_outline)),
                    Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add_circle_outline)),
                  ],
                ),
              if (mark != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Marcar en el odontograma: ${widget.catalog.labelOf(mark).toLowerCase()}'),
                  value: _mark,
                  onChanged: (v) => setState(() => _mark = v),
                ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _submit,
                child: const Text('Registrar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
