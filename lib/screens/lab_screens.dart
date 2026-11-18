import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'patient_screens.dart';
import 'shell.dart';

// Laboratorio: los trabajos en curso, atrasados y por instalar; avanzar su
// estado (llegó, instalado, devolver para ajuste) y la orden nueva desde la
// ficha. El pago al laboratorio sigue en la web.

String _tone(String? color) => switch (color) {
  'info' || 'primary' => 'info',
  'warning' => 'warning',
  'success' => 'success',
  'danger' => 'danger',
  _ => 'dark',
};

class LabOrdersScreen extends StatefulWidget {
  const LabOrdersScreen({super.key});

  @override
  State<LabOrdersScreen> createState() => _LabOrdersScreenState();
}

class _LabOrdersScreenState extends State<LabOrdersScreen> {
  String _filter = 'activos';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().profile!.can('lab_orders.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Laboratorio')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                final p = await Navigator.of(
                  context,
                ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PatientSearchScreen(picking: true)));
                if (p == null || !context.mounted) return;
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => LabOrderFormScreen(patientId: p.integer('id')!, patientName: p.str('full_name') ?? ''),
                  ),
                );
                if (created == true) setState(() => _version++);
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva orden'),
            )
          : null,
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_filter-$_version'),
        load: () => context.session.api.get('/lab-orders', query: {'filter': _filter}),
        builder: (context, data, reload) {
          final orders = data.list('data');
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    for (final f in data.list('filters'))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${f.str('label')} · ${f.integer('count') ?? 0}'),
                          selected: _filter == f.str('key'),
                          onSelected: (_) => setState(() => _filter = f.str('key')!),
                        ),
                      ),
                  ],
                ),
              ),
              if (orders.isEmpty)
                const EmptyState(icon: Icons.diamond_outlined, message: 'No hay trabajos en esta lista.')
              else
                for (final o in orders)
                  LabOrderTile(
                    order: o,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabOrderScreen(id: o.integer('id')!)));
                      reload();
                    },
                  ),
            ],
          );
        },
      ),
    );
  }
}

class LabOrderTile extends StatelessWidget {
  const LabOrderTile({super.key, required this.order, this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final late = o.flag('late');
    final due = DateTime.tryParse(o.str('due_at') ?? '');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.obj('patient')?.str('full_name') ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusChip(o.str('status_label') ?? '', tone: _tone(o.str('status_color'))),
                ],
              ),
              const SizedBox(height: 2),
              Text(o.str('summary') ?? ''),
              const SizedBox(height: 4),
              Text(
                [
                  o.str('code'),
                  o.str('lab'),
                  if (due != null) (late ? 'atrasado: era para el ${fmtShortDate(due)}' : 'entrega ${fmtShortDate(due)}'),
                  if ((o.integer('returns_count') ?? 0) > 0) 'devuelto ${o.integer('returns_count')}×',
                ].whereType<String>().join(' · '),
                style: TextStyle(color: late ? toneColor(context, 'danger') : muted, fontWeight: late ? FontWeight.w600 : null, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El trabajo con su recorrido y lo que se puede hacer ahora.
class LabOrderScreen extends StatefulWidget {
  const LabOrderScreen({super.key, required this.id});

  final int id;

  @override
  State<LabOrderScreen> createState() => _LabOrderScreenState();
}

class _LabOrderScreenState extends State<LabOrderScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  bool _busy = false;

  Future<void> _move(Map<String, dynamic> next) async {
    final status = next.str('status')!;
    String? note;
    // Devolver para ajuste o cancelar: se pide el motivo (queda en el historial).
    if (status == 'cancelado' || status == 'en_proceso') {
      note = await askText(
        context,
        title: next.str('label')!,
        label: status == 'cancelado' ? 'Motivo' : '¿Qué hay que ajustar?',
        action: next.str('label')!,
      );
      if (note == null) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.session.api.post('/lab-orders/${widget.id}/status', {'status': status, 'note': ?note});
      if (!mounted) return;
      showDone(context, switch (status) {
        'recibido' => 'Llegó del laboratorio: agenda al paciente para instalarlo.',
        'instalado' => 'Trabajo instalado.',
        'en_proceso' => 'Devuelto al laboratorio para ajuste.',
        'cancelado' => 'Orden cancelada.',
        _ => 'Estado actualizado.',
      });
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().profile!.can('lab_orders.edit');

    return Scaffold(
      appBar: AppBar(title: const Text('Orden de laboratorio')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/lab-orders/${widget.id}'),
        builder: (context, o, reload) {
          final next = o.list('next');
          final due = DateTime.tryParse(o.str('due_at') ?? '');
          final rows = <(String, String?)>[
            ('Laboratorio', o.str('lab')),
            ('Pieza(s)', o.str('teeth')),
            ('Material', o.str('material')),
            ('Color', o.str('shade')),
            ('Profesional', o.str('professional')),
            ('Enviado', fmtDate(DateTime.tryParse(o.str('sent_at') ?? ''))),
            ('Entrega', due == null ? null : fmtDate(due)),
            ('Del plan', o.obj('plan_item') == null ? null : '${o.obj('plan_item')!.str('name')} (${o.obj('plan_item')!.str('plan')})'),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
                            child: Text(o.str('work') ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          StatusChip(o.str('status_label') ?? '', tone: _tone(o.str('status_color'))),
                        ],
                      ),
                      InkWell(
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientScreen(id: o.obj('patient')!.integer('id')!))),
                        child: Text(o.obj('patient')?.str('full_name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(o.str('code') ?? '', style: Theme.of(context).textTheme.bodySmall),
                      if (o.flag('late'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Atrasado: era para el ${fmtShortDate(due)}.',
                            style: TextStyle(color: toneColor(context, 'danger'), fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (final (label, value) in rows)
                        if (value != null && value.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                                Expanded(
                                  child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if ((o.str('instructions') ?? '').isNotEmpty)
                Card(
                  child: ListTile(title: const Text('Indicaciones al laboratorio'), subtitle: Text(o.str('instructions')!)),
                ),
              if (canEdit && next.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final (i, n) in next.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: n.str('status') == 'cancelado'
                        ? TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: toneColor(context, 'danger')),
                            onPressed: _busy ? null : () => _move(n),
                            icon: const Icon(Icons.close),
                            label: Text(n.str('label') ?? ''),
                          )
                        : (i == 0 ? FilledButton.icon : OutlinedButton.icon)(
                            style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(48))),
                            onPressed: _busy ? null : () => _move(n),
                            icon: Icon(switch (n.str('status')) {
                              'recibido' => Icons.move_to_inbox_outlined,
                              'instalado' => Icons.check_circle_outline,
                              _ => Icons.replay,
                            }),
                            label: Text(n.str('label') ?? ''),
                          ),
                  ),
              ],
              SectionTitle('Recorrido · ${o.list('log').length}'),
              Card(
                child: Column(
                  children: [
                    for (final l in o.list('log'))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.timeline, size: 20),
                        title: Text(l.str('from') == null ? l.str('to') ?? '' : '${l.str('from')} → ${l.str('to')}'),
                        subtitle: Text(
                          [fmtDateTime(l.date('at')), l.str('user'), l.str('note')].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Orden nueva para el laboratorio (desde la ficha del paciente o la lista).
class LabOrderFormScreen extends StatefulWidget {
  const LabOrderFormScreen({super.key, required this.patientId, required this.patientName});

  final int patientId;
  final String patientName;

  @override
  State<LabOrderFormScreen> createState() => _LabOrderFormScreenState();
}

class _LabOrderFormScreenState extends State<LabOrderFormScreen> {
  Map<String, dynamic>? _options;
  Object? _error;
  int? _lab;
  int? _professional;
  int? _planItem;
  String _workType = 'corona';
  String? _material;
  String? _shade;
  DateTime? _due;
  final _teeth = TextEditingController();
  final _instructions = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teeth.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await context.session.api.get('/lab-orders/options', query: {'patient_id': '${widget.patientId}'});
      if (!mounted) return;
      final used = [for (final x in (o['used_labs'] as List? ?? const [])) x as int];
      final labs = o.list('labs');
      setState(() {
        _options = o;
        _lab = (labs.where((l) => used.contains(l.integer('id'))).firstOrNull ?? labs.firstOrNull)?.integer('id');
        _professional = o.integer('default_professional');
        _due = DateTime.now().add(const Duration(days: 7));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (_lab == null) {
      showError(context, 'Elige el laboratorio. Si no hay ninguno, regístralo como proveedor en la web.');
      return;
    }
    setState(() => _busy = true);
    try {
      final o = await context.session.api.post('/lab-orders', {
        'patient_id': widget.patientId,
        'supplier_id': _lab,
        'personal_id': ?_professional,
        'treatment_plan_item_id': ?_planItem,
        'work_type': _workType,
        if (_teeth.text.trim().isNotEmpty) 'teeth': _teeth.text.trim(),
        'material': ?_material,
        'shade': ?_shade,
        if (_due != null) 'due_at': isoDate(_due!),
        if (_instructions.text.trim().isNotEmpty) 'instructions': _instructions.text.trim(),
      });
      if (!mounted) return;
      showDone(context, 'Orden ${o.str('code')} enviada: ${o.str('summary')}.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips(List<String> values, String? selected, ValueChanged<String?> onChanged) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final v in values) ChoiceChip(label: Text(v), selected: selected == v, onSelected: (on) => setState(() => onChanged(on ? v : null))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final o = _options;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Orden de laboratorio'),
            Text(widget.patientName, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: _error != null
          ? ListView(
              children: [ErrorState(error: _error!, onRetry: _load)],
            )
          : o == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _lab,
                  decoration: const InputDecoration(labelText: 'Laboratorio'),
                  items: [for (final l in o.list('labs')) DropdownMenuItem(value: l.integer('id'), child: Text(l.str('name') ?? ''))],
                  onChanged: (v) => setState(() => _lab = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _workType,
                  decoration: const InputDecoration(labelText: 'Trabajo'),
                  items: [for (final w in o.list('work_types')) DropdownMenuItem(value: w.str('key'), child: Text(w.str('label') ?? ''))],
                  onChanged: (v) => setState(() => _workType = v ?? 'corona'),
                ),
                if (o.list('plan_items').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    isExpanded: true,
                    initialValue: _planItem,
                    decoration: const InputDecoration(labelText: 'Del plan de tratamiento (opcional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('—')),
                      for (final i in o.list('plan_items'))
                        DropdownMenuItem<int?>(
                          value: i.integer('id'),
                          child: Text('${i.str('name')}${i.integer('tooth') == null ? '' : ' · ${i.integer('tooth')}'} (${i.str('plan')})'),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _planItem = v;
                      final tooth = o.list('plan_items').where((i) => i.integer('id') == v).firstOrNull?.integer('tooth');
                      if (tooth != null && _teeth.text.isEmpty) _teeth.text = '$tooth';
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _teeth,
                  decoration: const InputDecoration(labelText: 'Pieza(s)', hintText: 'Ej.: 16 o 14-16'),
                ),
                const SectionTitle('Material'),
                _chips([for (final m in (o['materials'] as List? ?? const [])) '$m'], _material, (v) => _material = v),
                const SectionTitle('Color (guía VITA)'),
                _chips([for (final s in (o['shades'] as List? ?? const [])) '$s'], _shade, (v) => _shade = v),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Entrega'),
                  subtitle: Text(_due == null ? 'Sin fecha' : fmtDate(_due)),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _due ?? now.add(const Duration(days: 7)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 180)),
                    );
                    if (d != null) setState(() => _due = d);
                  },
                ),
                if (o.list('professionals').isNotEmpty)
                  DropdownButtonFormField<int?>(
                    isExpanded: true,
                    initialValue: _professional,
                    decoration: const InputDecoration(labelText: 'Profesional'),
                    items: [
                      for (final p in o.list('professionals')) DropdownMenuItem<int?>(value: p.integer('id'), child: Text(p.str('name') ?? '')),
                    ],
                    onChanged: (v) => setState(() => _professional = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructions,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Indicaciones al laboratorio (opcional)'),
                ),
              ],
            ),
      bottomNavigationBar: o == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar al laboratorio'),
                ),
              ),
            ),
    );
  }
}
