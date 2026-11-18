import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

// Finanzas en el teléfono (ESTRUCTURA_CUENTAS_Y_GASTOS.md): gastos por pestaña
// con el origen del dinero y la foto del comprobante, el control del mes de
// los servicios básicos y las cuentas con su extracto.

const expenseTabs = {'general': 'Generales', 'proveedor': 'Proveedores', 'personal': 'Personal', 'basico': 'Servicios', 'todos': 'Todos'};

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _tab = 'general';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _version = 0;

  String get _from => isoDate(_month);
  String get _to => isoDate(DateTime(_month.year, _month.month + 1, 0));

  Future<void> _new({Map<String, dynamic>? service}) async {
    final group = _tab == 'todos' ? 'general' : _tab;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(group: group, service: service),
      ),
    );
    if (saved == true) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<Session>().profile!.can('expenses.create');
    final monthLabel = fmtMonth(_month);

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Gastos')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Registrar gasto'))
          : null,
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_tab-$_from-$_version'),
        load: () => context.session.api.get('/finance/expenses', query: {'group': _tab, 'from': _from, 'to': _to}),
        builder: (context, data, reload) {
          final items = data.list('data');
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    for (final MapEntry(key: k, value: label) in expenseTabs.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(label), selected: _tab == k, onSelected: (_) => setState(() => _tab = k)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Mes anterior',
                              icon: const Icon(Icons.chevron_left),
                              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                            ),
                            Expanded(
                              child: Text(
                                monthLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Mes siguiente',
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                                  ? () => setState(() => _month = DateTime(_month.year, _month.month + 1))
                                  : null,
                            ),
                          ],
                        ),
                        Text(
                          money(context, data.number('total')),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${data.integer('count') ?? 0} gastos · ${expenseTabs[_tab]!.toLowerCase()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_tab == 'basico')
                _BasicServices(
                  month: _month,
                  onPay: canCreate ? (s) => _new(service: s) : null,
                ),
              SectionTitle('Registrados · ${items.length}'),
              if (items.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, message: 'No hay gastos en este mes.')
              else
                for (final e in items)
                  ExpenseTile(
                    expense: e,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExpenseScreen(id: e.integer('id')!)));
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

String fmtMonth(DateTime m) {
  const names = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  final n = names[m.month - 1];
  return '${n[0].toUpperCase()}${n.substring(1)} ${m.year}';
}

/// Control del mes de los servicios básicos: qué se pagó y qué falta.
class _BasicServices extends StatelessWidget {
  const _BasicServices({required this.month, this.onPay});

  final DateTime month;
  final ValueChanged<Map<String, dynamic>>? onPay;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.session.api.get('/finance/basics', query: {'month': '${month.year}-${month.month.toString().padLeft(2, '0')}'}),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final items = data.list('items');
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('Servicios del mes · ${data.integer('paid') ?? 0} de ${items.length} pagados'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    for (final s in items)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          s.str('status') == 'pagado' ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: toneColor(context, s.str('status') == 'pagado' ? 'success' : 'warning'),
                        ),
                        title: Text(s.obj('category')?.str('name') ?? ''),
                        subtitle: Text(
                          s.str('status') == 'pagado'
                              ? 'Pagado ${money(context, s.number('paid_amount'))}'
                              : [
                                  'Pendiente',
                                  if (s.number('last_amount') != null) 'la última vez ${money(context, s.number('last_amount'))}',
                                ].join(' · '),
                        ),
                        trailing: s.str('status') == 'pendiente' && onPay != null
                            ? TextButton(onPressed: () => onPay!(s.obj('category')!), child: const Text('Pagar'))
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, this.onTap});

  final Map<String, dynamic> expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final cancelled = e.flag('cancelled');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: toneColor(context, cancelled ? null : 'warning').withValues(alpha: .12),
        child: Icon(
          e.str('receipt_path') != null ? Icons.receipt_long : Icons.payments_outlined,
          color: toneColor(context, cancelled ? null : 'warning'),
          size: 20,
        ),
      ),
      title: Text(e.str('concept') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          fmtShortDate(DateTime.tryParse(e.str('spent_at') ?? '')),
          e.obj('category')?.str('name'),
          e.str('source_label'),
          if (cancelled) 'anulado',
        ].whereType<String>().join(' · '),
      ),
      trailing: Text(
        money(context, e.number('amount')),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, decoration: cancelled ? TextDecoration.lineThrough : null),
      ),
    );
  }
}

/// Registrar un gasto de una pestaña: categoría, a quién (proveedor o
/// personal), importe, de dónde sale el dinero y la foto del comprobante.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, required this.group, this.service});

  final String group;

  /// Servicio básico que se paga (desde el control del mes).
  final Map<String, dynamic>? service;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  Map<String, dynamic>? _options;
  Object? _error;
  late String _group = widget.service != null ? 'basico' : widget.group;
  int? _category;
  int? _payee;
  String? _source;
  int? _account;
  int? _session;
  DateTime _date = DateTime.now();
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  final _reference = TextEditingController();
  XFile? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _options = null;
      _error = null;
    });
    try {
      final o = await context.session.api.get('/finance/options', query: {'group': _group});
      if (!mounted) return;
      final sources = o.list('sources');
      setState(() {
        _options = o;
        _category = widget.service?.integer('id') ?? o.integer('default_category_id');
        _payee = null;
        // Por defecto, la caja abierta (lo más común en la clínica); si no hay, la cuenta.
        _source = sources.any((s) => s.str('key') == 'cash') && o.list('open_sessions').isNotEmpty ? 'cash' : sources.firstOrNull?.str('key');
        _session = o.integer('preferred_session_id');
        _account = o.integer('preferred_account_id');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 80);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      showError(context, 'Escribe el importe.');
      return;
    }
    final fields = <String, String>{
      'group': _group,
      if (_category != null) 'expense_category_id': '$_category',
      if (_group == 'proveedor' && _payee != null) 'supplier_id': '$_payee',
      if (_group == 'personal' && _payee != null) 'personal_id': '$_payee',
      if (_concept.text.trim().isNotEmpty) 'concept': _concept.text.trim(),
      'amount': '$amount',
      'spent_at': isoDate(_date),
      'source': _source ?? '',
      if (_source == 'account' && _account != null) 'finance_account_id': '$_account',
      if (_source == 'cash' && _session != null) 'cash_session_id': '$_session',
      if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
    };
    setState(() => _busy = true);
    try {
      final api = context.session.api;
      final photo = _photo;
      final e = photo == null
          ? await api.post('/finance/expenses', fields)
          : await api.upload('/finance/expenses', 'receipt', await photo.readAsBytes(), photo.name, fields: fields);
      if (!mounted) return;
      showDone(context, 'Gasto ${e.str('code')} registrado: ${money(context, e.number('amount'))}.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    final payees = o == null ? const <Map<String, dynamic>>[] : o.list(_group == 'proveedor' ? 'suppliers' : 'personal');

    return Scaffold(
      appBar: AppBar(title: Text(widget.service != null ? 'Pagar ${widget.service!.str('name')}' : 'Registrar gasto')),
      body: _error != null
          ? ListView(
              children: [ErrorState(error: _error!, onRetry: _load)],
            )
          : o == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (widget.service == null)
                  // Chips con scroll: cuatro botones segmentados no caben en un teléfono de 360 px.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final MapEntry(key: k, value: label) in expenseTabs.entries)
                          if (k != 'todos')
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _group == k,
                                onSelected: (_) {
                                  _group = k;
                                  _load();
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                if (_group == 'proveedor' || _group == 'personal') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _payee,
                    decoration: InputDecoration(labelText: _group == 'proveedor' ? 'Proveedor' : 'Persona'),
                    items: [
                      for (final p in payees)
                        DropdownMenuItem(
                          value: p.integer('id'),
                          child: Text(p.str('name') ?? '', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _payee = v),
                  ),
                ],
                if (widget.service == null && o.list('categories').length > 1) ...[
                  SectionTitle(_group == 'basico' ? 'Servicio' : 'Categoría'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in o.list('categories'))
                        ChoiceChip(
                          label: Text(c.str('name') ?? ''),
                          selected: _category == c.integer('id'),
                          onSelected: (_) => setState(() => _category = c.integer('id')),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Importe', prefixText: '${context.session.profile?.company?.currencySymbol ?? ''} '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _concept,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)', hintText: 'Si la dejas vacía se arma sola'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Fecha'),
                  subtitle: Text(fmtDate(_date)),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now,
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                const SectionTitle('¿De dónde sale el dinero?'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in o.list('sources'))
                      ChoiceChip(
                        label: Text(s.str('label') ?? ''),
                        selected: _source == s.str('key'),
                        onSelected: (_) => setState(() => _source = s.str('key')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_source == 'cash')
                  o.list('open_sessions').isEmpty
                      ? Text(
                          'No hay una caja abierta. Ábrela en la web o paga desde una cuenta.',
                          style: TextStyle(color: toneColor(context, 'warning')),
                        )
                      : DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: _session,
                          decoration: const InputDecoration(labelText: 'Caja'),
                          items: [
                            for (final s in o.list('open_sessions'))
                              DropdownMenuItem(
                                value: s.integer('id'),
                                child: Text('${s.str('name')} · hay ${money(context, s.number('expected_cash'))}', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _session = v),
                        ),
                if (_source == 'account')
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _account,
                    decoration: const InputDecoration(labelText: 'Cuenta'),
                    items: [
                      for (final a in o.list('accounts'))
                        DropdownMenuItem(
                          value: a.integer('id'),
                          child: Text('${a.str('name')} · ${money(context, a.number('balance'))}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _account = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reference,
                  decoration: const InputDecoration(labelText: 'N.º de factura o referencia (opcional)'),
                ),
                const SectionTitle('Comprobante'),
                if (_photo == null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Foto de la factura o recibo'),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long, size: 32),
                    title: Text(_photo!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Se sube junto con el gasto'),
                    trailing: IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => setState(() => _photo = null)),
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
                  icon: const Icon(Icons.check),
                  label: const Text('Registrar gasto'),
                ),
              ),
            ),
    );
  }
}

/// El gasto con su comprobante; anular devuelve el dinero a donde salió.
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key, required this.id});

  final int id;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _cancel() async {
    final reason = await askText(context, title: 'Anular gasto', label: 'Motivo', action: 'Anular');
    if (reason == null || !mounted) return;
    try {
      await context.session.api.patch('/finance/expenses/${widget.id}/cancel', {'cancel_reason': reason});
      if (!mounted) return;
      showDone(context, 'Gasto anulado: el dinero volvió a donde salió.');
      _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = context.watch<Session>().profile!.can('expenses.delete');
    final api = context.session.api;

    return Scaffold(
      appBar: AppBar(title: const Text('Gasto')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => api.get('/finance/expenses/${widget.id}'),
        builder: (context, e, reload) {
          final cancelled = e.flag('cancelled');
          final receipt = e.str('receipt_path');
          final rows = <(String, String?)>[
            ('Categoría', e.obj('category')?.str('name')),
            ('A quién', e.str('payee')),
            ('Fecha', fmtDate(DateTime.tryParse(e.str('spent_at') ?? ''))),
            ('Sale de', e.str('source_label')),
            ('Referencia', e.str('reference')),
            ('Registró', e.str('user')),
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
                          Expanded(child: Text(e.str('code') ?? '', style: Theme.of(context).textTheme.bodySmall)),
                          if (cancelled) const StatusChip('Anulado', tone: 'dark'),
                        ],
                      ),
                      Text(e.str('concept') ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        money(context, e.number('amount')),
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, decoration: cancelled ? TextDecoration.lineThrough : null),
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
                              children: [
                                SizedBox(width: 100, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
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
              if (cancelled && e.str('cancel_reason') != null)
                Card(
                  child: ListTile(leading: const Icon(Icons.block), title: Text(e.str('cancel_reason')!)),
                ),
              if (receipt != null) ...[
                const SectionTitle('Comprobante'),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    api.url(receipt),
                    headers: api.authHeaders,
                    errorBuilder: (_, _, _) => const Card(
                      child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Comprobante en PDF: míralo en la web.')),
                    ),
                  ),
                ),
              ],
              if (!cancelled && canDelete) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: toneColor(context, 'danger')),
                  onPressed: _cancel,
                  icon: const Icon(Icons.block),
                  label: const Text('Anular gasto'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Cuentas ────────────────────────────────────────────────────────────────

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Cuentas')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/finance/accounts'),
        builder: (context, data, reload) {
          final accounts = data.list('data').where((a) => a.flag('active')).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo en cuentas', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        money(context, data.number('total')),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (accounts.isEmpty)
                const EmptyState(icon: Icons.account_balance_outlined, message: 'No hay cuentas. Créalas en la web (banco, billetera, caja fuerte…).')
              else
                for (final a in accounts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
                        child: Icon(a.str('type') == 'bank' ? Icons.account_balance : Icons.account_balance_wallet_outlined, size: 20),
                      ),
                      title: Text(a.str('name') ?? ''),
                      subtitle: Text([a.str('type_label'), a.str('bank_name')].whereType<String>().join(' · ')),
                      trailing: Text(money(context, a.number('balance')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AccountScreen(id: a.integer('id')!, accounts: accounts),
                          ),
                        );
                        reload();
                      },
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Extracto de la cuenta (con el saldo después de cada movimiento), ingreso / egreso y transferencia.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.id, required this.accounts});

  final int id;
  final List<Map<String, dynamic>> accounts;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _sheet(String kind) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _AccountMoveSheet(accountId: widget.id, kind: kind, others: widget.accounts.where((a) => a.integer('id') != widget.id).toList()),
    );
    if (r == true) _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canMove = context.watch<Session>().profile!.can('account_movements.create');

    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/finance/accounts/${widget.id}/movements'),
        builder: (context, data, reload) {
          final a = data.obj('account') ?? const {};
          final moves = data.list('data');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        money(context, a.number('balance')),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              if (canMove)
                Row(
                  children: [
                    for (final (kind, label, icon) in [
                      ('ingreso', 'Ingreso', Icons.south_west),
                      ('egreso', 'Egreso', Icons.north_east),
                      if (widget.accounts.length > 1) ('transferencia', 'Transferir', Icons.swap_horiz),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                          child: OutlinedButton.icon(onPressed: () => _sheet(kind), icon: Icon(icon, size: 18), label: Text(label)),
                        ),
                      ),
                  ],
                ),
              SectionTitle('Movimientos · ${moves.length}'),
              if (moves.isEmpty)
                const Card(child: ListTile(title: Text('Sin movimientos.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final m in moves)
                        ListTile(
                          dense: true,
                          title: Text(m.str('concept') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              fmtShortDate(DateTime.tryParse(m.str('occurred_on') ?? '')),
                              m.str('origin_label'),
                              if (m.flag('cancelled')) 'anulado',
                            ].whereType<String>().join(' · '),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(context, m.number('signed_amount')),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: toneColor(context, (m.number('signed_amount') ?? 0) >= 0 ? 'success' : 'danger'),
                                  decoration: m.flag('cancelled') ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              Text('saldo ${money(context, m.number('balance_after'))}', style: Theme.of(context).textTheme.bodySmall),
                            ],
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

class _AccountMoveSheet extends StatefulWidget {
  const _AccountMoveSheet({required this.accountId, required this.kind, required this.others});

  final int accountId;

  /// ingreso | egreso | transferencia
  final String kind;
  final List<Map<String, dynamic>> others;

  @override
  State<_AccountMoveSheet> createState() => _AccountMoveSheetState();
}

class _AccountMoveSheetState extends State<_AccountMoveSheet> {
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  late int? _to = widget.others.firstOrNull?.integer('id');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Escribe el importe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.session.api;
      if (widget.kind == 'transferencia') {
        await api.post('/finance/accounts/${widget.accountId}/transfer', {
          'to_account_id': _to,
          'amount': amount,
          if (_concept.text.trim().isNotEmpty) 'concept': _concept.text.trim(),
        });
      } else {
        await api.post('/finance/accounts/${widget.accountId}/movements', {'type': widget.kind, 'amount': amount, 'concept': _concept.text.trim()});
      }
      if (!mounted) return;
      showDone(context, widget.kind == 'transferencia' ? 'Transferencia registrada.' : 'Movimiento registrado.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      'ingreso' => 'Ingreso a la cuenta',
      'egreso' => 'Egreso de la cuenta',
      _ => 'Transferir a otra cuenta',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (widget.kind == 'transferencia') ...[
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _to,
                  decoration: const InputDecoration(labelText: 'A la cuenta'),
                  items: [
                    for (final a in widget.others)
                      DropdownMenuItem(
                        value: a.integer('id'),
                        child: Text(a.str('name') ?? '', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _to = v),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Importe'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _concept,
                decoration: InputDecoration(labelText: widget.kind == 'transferencia' ? 'Concepto (opcional)' : 'Concepto'),
              ),
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _busy ? null : _save,
                child: const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
