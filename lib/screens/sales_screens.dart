import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'patient_screens.dart';
import 'shell.dart';

// Cobros en la app: lo pendiente del paciente, cobrar, cuentas por cobrar,
// abonos y recibos por WhatsApp. Las reglas (caja abierta, vuelto solo del
// efectivo, referencia obligatoria, cobrar una sola vez) las aplica la API.

double parseAmount(String s) => double.tryParse(s.replaceAll(',', '.').trim()) ?? 0;

String plainAmount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

double _round(double v) => (v * 100).roundToDouble() / 100;

/// Montos a la derecha de las listas: el ListTile de Material 3 los achica si no se fija el tamaño.
const _amountStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

// ── Pago: método, monto, referencia y caja ─────────────────────────────────

/// Lo que se escribe en un pago. El padre lo crea, lo dibuja con [PaymentFields] y lo libera.
class PaymentInput {
  int? methodId;
  int? sessionId;
  final amount = TextEditingController();
  final reference = TextEditingController();

  /// Efectivo por defecto (es lo más común en el sillón); una sola caja abierta, elegida.
  void init(Map<String, dynamic> options, double suggested) {
    final methods = options.list('payment_methods');
    methodId = (methods.where((m) => m.flag('is_cash')).firstOrNull ?? methods.firstOrNull)?.integer('id');
    final sessions = options.obj('cash')?.list('sessions') ?? const [];
    sessionId = sessions.length == 1 ? sessions.first.integer('id') : null;
    amount.text = suggested > 0 ? plainAmount(suggested) : '';
  }

  Map<String, dynamic>? method(Map<String, dynamic> options) => options.list('payment_methods').where((m) => m.integer('id') == methodId).firstOrNull;

  double get value => parseAmount(amount.text);

  /// Si el cobro necesita una caja abierta y no hay, o hay varias sin elegir, el motivo.
  String? cashProblem(Map<String, dynamic> options) {
    final cash = options.obj('cash');
    if (cash == null || !cash.flag('enabled') || value <= 0) return null;
    final sessions = cash.list('sessions');
    if (sessions.isEmpty) return 'No hay una caja abierta. Ábrela en la web para cobrar.';
    if (sessionId == null) return 'Elige en qué caja entra el cobro.';
    return null;
  }

  Map<String, dynamic> payment() => {
    'payment_method_id': methodId,
    'amount': value,
    if (reference.text.trim().isNotEmpty) 'reference': reference.text.trim(),
  };

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

class PaymentFields extends StatelessWidget {
  const PaymentFields({super.key, required this.options, required this.input, required this.onChanged, this.label = 'Monto que paga'});

  final Map<String, dynamic> options;
  final PaymentInput input;
  final VoidCallback onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final methods = options.list('payment_methods');
    final method = input.method(options);
    final sessions = options.obj('cash')?.list('sessions') ?? const [];
    final problem = input.cashProblem(options);
    final currency = options.str('currency') ?? context.read<Session>().profile?.company?.currencySymbol ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in methods)
              ChoiceChip(
                label: Text(m.str('name') ?? ''),
                selected: input.methodId == m.integer('id'),
                onSelected: (_) {
                  input.methodId = m.integer('id');
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: input.amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: currency.isEmpty ? null : '$currency '),
          onChanged: (_) => onChanged(),
        ),
        if (method != null && method.flag('requires_reference')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: input.reference,
            decoration: InputDecoration(labelText: 'N.º de comprobante de ${method.str('name')}', helperText: 'Obligatorio para este método'),
            onChanged: (_) => onChanged(),
          ),
        ],
        if (sessions.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: input.sessionId,
            decoration: const InputDecoration(labelText: 'Caja'),
            items: [for (final s in sessions) DropdownMenuItem(value: s.integer('id'), child: Text(s.str('name') ?? 'Caja'))],
            onChanged: (v) {
              input.sessionId = v;
              onChanged();
            },
          ),
        ],
        if (problem != null) ...[
          const SizedBox(height: 8),
          Text(
            problem,
            style: TextStyle(color: toneColor(context, 'warning'), fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

// ── Recibo y abono ─────────────────────────────────────────────────────────

/// Muestra el recibo como saldrá en WhatsApp y lo envía.
Future<void> showReceipt(BuildContext context, Map<String, dynamic>? receipt, {String title = 'Recibo'}) async {
  if (receipt == null) return;
  final url = receipt.str('whatsapp_url');
  final outer = context;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
              child: Text(receipt.str('message') ?? '', style: const TextStyle(color: Color(0xFF1F2C34))),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: url == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      openExternal(outer, url);
                    },
              icon: const Icon(Icons.chat_outlined),
              label: Text(url == null ? 'El paciente no tiene celular' : 'Enviar por WhatsApp'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Listo')),
          ],
        ),
      ),
    ),
  );
}

/// Abono a la cuenta del paciente ([path] = /receivables/{id}/pay) o a una venta
/// (/sales/{id}/payments). Devuelve la respuesta de la API, o null si se canceló.
Future<Map<String, dynamic>?> showPaySheet(BuildContext context, {required String title, required double max, required String path}) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaySheet(title: title, max: max, path: path),
    );

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.title, required this.max, required this.path});

  final String title;
  final double max;
  final String path;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _input = PaymentInput();
  Map<String, dynamic>? _options;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.session.api
        .get('/sales/options')
        .then((o) {
          if (!mounted) return;
          _input.init(o, widget.max);
          setState(() => _options = o);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = _input.value;
    if (amount <= 0 || amount > widget.max + .001) {
      setState(() => _error = 'El abono debe ser mayor a cero y no superar ${money(context, widget.max)}.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.session.api.post(widget.path, {..._input.payment(), 'cash_session_id': ?_input.sessionId});
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                'Debe ${money(context, widget.max)}',
                style: TextStyle(color: toneColor(context, 'danger'), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (options == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (options != null)
                PaymentFields(options: options, input: _input, onChanged: () => setState(() {}), label: 'Monto del abono'),
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: options == null || _busy || _input.cashProblem(options) != null ? null : _save,
                icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: Text('Registrar abono de ${money(context, _input.value)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cobrar ─────────────────────────────────────────────────────────────────

/// Cobrar a un paciente: lo realizado viene marcado; lo del plan aún no hecho
/// se puede cobrar por adelantado; lo suelto sale del tarifario. Lo que no se
/// paga queda como saldo.
class ChargeScreen extends StatefulWidget {
  const ChargeScreen({super.key, required this.patientId});

  final int patientId;

  @override
  State<ChargeScreen> createState() => _ChargeScreenState();
}

class _ChargeScreenState extends State<ChargeScreen> {
  Map<String, dynamic>? _options;
  Map<String, dynamic>? _pending;
  Object? _error;
  final _selected = <String>{};
  final _extra = <Map<String, dynamic>>[];
  final _discount = TextEditingController();
  final _pay = PaymentInput();
  bool _amountTouched = false;
  DateTime? _due;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _discount.dispose();
    _pay.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.session.api;
      final results = await Future.wait([api.get('/sales/options'), api.get('/patients/${widget.patientId}/pending')]);
      if (!mounted) return;
      setState(() {
        _options = results[0];
        _pending = results[1];
        _selected
          ..clear()
          ..addAll([
            for (final i in results[1].list('data'))
              if (i.flag('done')) _key(i),
          ]);
        _pay.init(results[0], _total);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _key(Map<String, dynamic> i) => '${i.str('source')}-${i.integer('id')}';

  List<Map<String, dynamic>> get _items => _pending?.list('data') ?? const [];

  double get _subtotal => _round(
    _items.where((i) => _selected.contains(_key(i))).fold<double>(0, (s, i) => s + (i.number('subtotal') ?? 0)) +
        _extra.fold<double>(0, (s, e) => s + (e['unit_price'] as double)),
  );

  double get _discountValue => math.min(parseAmount(_discount.text), _subtotal);

  double get _total => _round(_subtotal - _discountValue);

  /// Al cambiar lo que se cobra, el monto sigue al total mientras no lo hayan escrito a mano.
  void _changed() => setState(() {
    if (!_amountTouched) _pay.amount.text = _total > 0 ? plainAmount(_total) : '';
  });

  Future<void> _addProcedure() async {
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProcedurePicker(),
    );
    if (p == null) return;
    _extra.add({'procedure_id': p.integer('id'), 'description': p.str('name'), 'unit_price': p.number('price') ?? 0});
    _changed();
  }

  Future<void> _save() async {
    final options = _options!;
    final total = _total;
    final amount = _pay.value;
    if (total <= 0) {
      showError(context, 'Elige qué cobrar.');
      return;
    }
    if (amount > total && !(_pay.method(options)?.flag('is_cash') ?? false)) {
      showError(context, 'Solo el efectivo da vuelto: el monto no puede pasar de ${money(context, total)}.');
      return;
    }
    setState(() => _busy = true);
    try {
      final sale = await context.session.api.post('/sales', {
        'patient_id': widget.patientId,
        'items': [
          for (final i in _items)
            if (_selected.contains(_key(i))) {'source': i.str('source'), 'id': i.integer('id')},
          for (final e in _extra) {'source': 'free', ...e},
        ],
        if (_discountValue > 0) 'discount': _discountValue,
        if (amount > 0) 'payments': [_pay.payment()],
        'cash_session_id': ?_pay.sessionId,
        if (_due != null && amount < total) 'due_date': isoDate(_due!),
        if (_extra.isNotEmpty) 'personal_id': ?options.integer('default_professional'),
      });
      if (!mounted) return;
      final balance = sale.number('balance') ?? 0;
      showDone(context, 'Venta ${sale.str('code')} registrada${balance > 0 ? ': queda un saldo de ${money(context, balance)}' : ''}.');
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SaleScreen(id: sale.integer('id')!, offerReceipt: true)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final pending = _pending;
    final patient = pending?.obj('patient');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cobrar'),
            if (patient != null) Text(patient.str('full_name') ?? '', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: _error != null
          ? ListView(
              children: [ErrorState(error: _error!, onRetry: _load)],
            )
          : options == null || pending == null
          ? const Center(child: CircularProgressIndicator())
          : _form(options, pending),
      bottomNavigationBar: options == null || pending == null ? null : _bottom(options),
    );
  }

  Widget _form(Map<String, dynamic> options, Map<String, dynamic> pending) {
    final debt = pending.number('debt') ?? 0;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (debt > 0)
          Card(
            color: toneColor(context, 'warning').withValues(alpha: .1),
            child: ListTile(
              leading: Icon(Icons.info_outline, color: toneColor(context, 'warning')),
              title: Text('Además debe ${money(context, debt)} de ventas anteriores'),
              subtitle: const Text('Ese saldo se abona desde Cuentas por cobrar o la pestaña Pagos.'),
            ),
          ),
        const SectionTitle('Qué se cobra'),
        Card(
          child: Column(
            children: [
              if (_items.isEmpty && _extra.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('No tiene nada pendiente de cobro. Agrega un procedimiento del tarifario.')),
              for (final i in _items)
                ListTile(
                  leading: Checkbox(
                    value: _selected.contains(_key(i)),
                    onChanged: (v) {
                      v == true ? _selected.add(_key(i)) : _selected.remove(_key(i));
                      _changed();
                    },
                  ),
                  title: Text(i.str('name') ?? ''),
                  subtitle: Text(
                    [
                      if (i.integer('tooth') != null) 'pieza ${i.integer('tooth')}${i.str('surfaces') == null ? '' : ' ${i.str('surfaces')}'}',
                      if ((i.integer('quantity') ?? 1) > 1) '× ${i.integer('quantity')}',
                      i.str('source') == 'plan' ? 'plan ${i.str('origin') ?? ''}' : (i.str('origin') ?? ''),
                      if (!i.flag('done')) 'por adelantado',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: Text(money(context, i.number('subtotal')), style: _amountStyle),
                  onTap: () {
                    _selected.contains(_key(i)) ? _selected.remove(_key(i)) : _selected.add(_key(i));
                    _changed();
                  },
                ),
              for (final (n, e) in _extra.indexed)
                ListTile(
                  leading: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.add_circle_outline)),
                  title: Text(e['description'] as String? ?? ''),
                  subtitle: const Text('del tarifario'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(money(context, e['unit_price'] as double), style: _amountStyle),
                      IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _extra.removeAt(n);
                          _changed();
                        },
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.playlist_add)),
                title: const Text('Agregar del tarifario'),
                textColor: Theme.of(context).colorScheme.primary,
                iconColor: Theme.of(context).colorScheme.primary,
                onTap: _addProcedure,
              ),
            ],
          ),
        ),
        const SectionTitle('Pago'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _discount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Descuento (opcional)'),
                  onChanged: (_) => _changed(),
                ),
                const SizedBox(height: 16),
                PaymentFields(options: options, input: _pay, onChanged: () => setState(() => _amountTouched = true)),
                if (_pay.value < _total) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Paga el saldo hasta'),
                    subtitle: Text(_due == null ? 'Sin fecha' : fmtDate(_due)),
                    trailing: _due == null
                        ? null
                        : IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close), onPressed: () => setState(() => _due = null)),
                    onTap: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due ?? now.add(const Duration(days: 7)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Totals(
          rows: [
            ('Subtotal', _subtotal, null),
            if (_discountValue > 0) ('Descuento', -_discountValue, null),
            ('Total', _total, 'bold'),
            ('Paga', math.min(_pay.value, _total), null),
            if (_pay.value > _total) ('Vuelto', _round(_pay.value - _total), 'success'),
            if (_pay.value < _total) ('Queda debiendo', _round(_total - _pay.value), 'danger'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Lo cobrado entra a la caja abierta; el recibo se envía por WhatsApp.', style: TextStyle(color: muted, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _bottom(Map<String, dynamic> options) {
    final paid = math.min(_pay.value, _total);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy || _total <= 0 || _pay.cashProblem(options) != null ? null : _save,
          icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.point_of_sale),
          label: Text(paid > 0 ? 'Cobrar ${money(context, paid)}' : 'Dejar a cuenta ${money(context, _total)}'),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.rows});

  /// (etiqueta, monto, estilo: null | bold | success | danger)
  final List<(String, double, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            for (final (label, amount, style) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: TextStyle(fontWeight: style == null ? FontWeight.w400 : FontWeight.w700)),
                    ),
                    Text(
                      money(context, amount),
                      style: TextStyle(
                        fontWeight: style == null ? FontWeight.w500 : FontWeight.w800,
                        fontSize: style == 'bold' ? 18 : null,
                        color: style == 'success' || style == 'danger' ? toneColor(context, style) : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Buscar un procedimiento del tarifario.
class _ProcedurePicker extends StatefulWidget {
  const _ProcedurePicker();

  @override
  State<_ProcedurePicker> createState() => _ProcedurePickerState();
}

class _ProcedurePickerState extends State<_ProcedurePicker> {
  List<Map<String, dynamic>>? _all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.session.api
        .get('/procedures')
        .then((r) {
          if (mounted) setState(() => _all = r.list('data'));
        })
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = (_all ?? []).where((p) => q.isEmpty || '${p.str('name')} ${p.str('code')} ${p.str('specialty')}'.toLowerCase().contains(q)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en el tarifario'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: _all == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final p = list[i];
                        return ListTile(
                          title: Text(p.str('name') ?? ''),
                          subtitle: Text([p.str('code'), p.str('specialty')].whereType<String>().join(' · ')),
                          trailing: Text(money(context, p.number('price')), style: _amountStyle),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ventas ─────────────────────────────────────────────────────────────────

/// Elige al paciente y abre «Cobrar».
Future<void> chargeSomeone(BuildContext context) async {
  final p = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const PatientSearchScreen(picking: true)));
  if (p == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChargeScreen(patientId: p.integer('id')!)));
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _filter = 'hoy';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Ventas')),
      floatingActionButton: profile.can('sales.create')
          ? FloatingActionButton.extended(
              onPressed: () async {
                await chargeSomeone(context);
                setState(() => _version++);
              },
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Cobrar'),
            )
          : null,
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('$_filter-$_version'),
        load: () => context.session.api.get('/sales', query: {'filter': _filter}),
        builder: (context, data, reload) {
          final filters = (data['filters'] as Map?)?.cast<String, dynamic>() ?? const {};
          final sales = data.list('data');
          final byMethod = data.list('by_method');
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    for (final MapEntry(key: k, value: label) in filters.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text('$label'), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cobrado hoy', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          money(context, data.number('collected_today')),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (byMethod.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final m in byMethod) StatusChip('${m.str('name')}: ${money(context, m.number('amount'))}', tone: 'info')],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SectionTitle('${filters[_filter] ?? 'Ventas'} · ${sales.length}'),
              if (sales.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, message: 'No hay ventas en este filtro.')
              else
                for (final s in sales)
                  SaleTile(
                    sale: s,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleScreen(id: s.integer('id')!)));
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

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale, this.onTap, this.showPatient = true});

  final Map<String, dynamic> sale;
  final VoidCallback? onTap;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final cancelled = sale.flag('cancelled');
    final balance = sale.number('balance') ?? 0;
    final when = sale.date('created_at');
    final title = showPatient ? (sale.obj('patient')?.str('full_name') ?? 'Sin paciente') : (sale.str('code') ?? '');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: toneColor(context, cancelled ? null : (balance > 0 ? 'warning' : 'success')).withValues(alpha: .12),
        child: Icon(
          cancelled ? Icons.block : (balance > 0 ? Icons.hourglass_bottom : Icons.check),
          color: toneColor(context, cancelled ? null : (balance > 0 ? 'warning' : 'success')),
          size: 20,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if (showPatient) sale.str('code'), fmtDateTime(when)].whereType<String>().join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(context, sale.number('total')), style: _amountStyle.copyWith(decoration: cancelled ? TextDecoration.lineThrough : null)),
          if (cancelled)
            Text('Anulada', style: Theme.of(context).textTheme.bodySmall)
          else if (balance > 0)
            Text(
              'debe ${money(context, balance)}',
              style: TextStyle(fontSize: 12, color: toneColor(context, sale.flag('overdue') ? 'danger' : 'warning'), fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// Detalle de la venta: lo cobrado, los pagos, el recibo por WhatsApp, abonar y anular.
class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key, required this.id, this.offerReceipt = false});

  final int id;

  /// Recién cobrada: ofrece mandar el recibo apenas carga.
  final bool offerReceipt;

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  bool _offered = false;

  Future<void> _pay(Map<String, dynamic> s) async {
    final r = await showPaySheet(context, title: 'Abono a ${s.str('code')}', max: s.number('balance') ?? 0, path: '/sales/${widget.id}/payments');
    if (r == null || !mounted) return;
    showDone(context, (r.number('balance') ?? 0) > 0 ? 'Abono registrado.' : 'Abono registrado: la venta quedó pagada.');
    _loader.currentState?.reload();
    await showReceipt(context, r.obj('receipt'));
  }

  Future<void> _cancel(Map<String, dynamic> s) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CancelSheet(sale: s),
    );
    if (r == null || !mounted) return;
    showDone(context, 'Venta ${s.str('code')} anulada: lo atendido vuelve a estar pendiente de cobro.');
    _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(title: const Text('Venta')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/sales/${widget.id}'),
        builder: (context, s, reload) {
          final cancelled = s.flag('cancelled');
          final balance = s.number('balance') ?? 0;
          final receipt = s.obj('receipt');
          if (widget.offerReceipt && !_offered && receipt != null) {
            _offered = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showReceipt(context, receipt, title: 'Venta ${s.str('code')} registrada');
            });
          }
          final (status, tone) = cancelled
              ? ('Anulada', 'dark')
              : balance > 0
              ? (s.flag('overdue') ? 'Vencida' : 'Con saldo', s.flag('overdue') ? 'danger' : 'warning')
              : ('Pagada', 'success');

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
                            child: Text(s.str('code') ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          StatusChip(status, tone: tone),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(s.obj('patient')?.str('full_name') ?? 'Sin paciente', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        [fmtDateTime(s.date('created_at')), s.str('user')].whereType<String>().join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (cancelled)
                Card(
                  color: toneColor(context, 'danger').withValues(alpha: .08),
                  child: ListTile(
                    leading: Icon(Icons.block, color: toneColor(context, 'danger')),
                    title: Text(s.str('cancel_reason') ?? 'Anulada'),
                    subtitle: Text([fmtDateTime(s.date('cancelled_at')), s.str('cancelled_by')].whereType<String>().join(' · ')),
                  ),
                ),
              const SectionTitle('Detalle'),
              Card(
                child: Column(
                  children: [
                    for (final i in s.list('items'))
                      ListTile(
                        title: Text(i.str('description') ?? ''),
                        subtitle: Text(
                          [
                            i.str('origin'),
                            if ((i.number('quantity') ?? 1) != 1) '${plainAmount(i.number('quantity')!)} × ${money(context, i.number('unit_price'))}',
                            if ((i.number('discount') ?? 0) > 0) 'desc. ${money(context, i.number('discount'))}',
                          ].whereType<String>().join(' · '),
                        ),
                        trailing: Text(money(context, i.number('total')), style: _amountStyle),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Totals(
                rows: [
                  if ((s.number('discount') ?? 0) > 0) ...[
                    ('Subtotal', s.number('subtotal') ?? 0, null),
                    ('Descuento', -(s.number('discount') ?? 0), null),
                  ],
                  ('Total', s.number('total') ?? 0, 'bold'),
                  ('Pagado', s.number('paid') ?? 0, null),
                  if (balance > 0) ('Saldo', balance, 'danger'),
                ],
              ),
              if (balance > 0 && s.date('due_date') != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text('Paga el saldo hasta el ${fmtDate(s.date('due_date'))}', style: Theme.of(context).textTheme.bodySmall),
                ),
              SectionTitle('Pagos · ${s.list('payments').length}'),
              if (s.list('payments').isEmpty)
                const Card(child: ListTile(title: Text('Todavía no pagó nada.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final p in s.list('payments'))
                        ListTile(
                          leading: Icon(p.str('kind') == 'abono' ? Icons.savings_outlined : Icons.payments_outlined),
                          title: Text('${p.str('method') ?? ''} · ${money(context, p.number('amount'))}'),
                          subtitle: Text(
                            [
                              p.str('kind') == 'abono' ? 'Abono' : 'Al cobrar',
                              fmtDateTime(p.date('paid_at')),
                              p.str('user'),
                              if (p.str('reference') != null) 'ref. ${p.str('reference')}',
                            ].whereType<String>().join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              if (receipt != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => showReceipt(context, receipt),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Enviar recibo por WhatsApp'),
                ),
              if (!cancelled && balance > 0 && profile.can('receivables.create')) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _pay(s),
                  icon: const Icon(Icons.savings_outlined),
                  label: Text('Registrar abono (debe ${money(context, balance)})'),
                ),
              ],
              if (!cancelled && profile.can('sales.delete')) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: toneColor(context, 'danger')),
                  onPressed: () => _cancel(s),
                  icon: const Icon(Icons.block),
                  label: const Text('Anular venta'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.sale});

  final Map<String, dynamic> sale;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();
  final _pay = PaymentInput();
  Map<String, dynamic>? _options;
  String? _error;
  bool _busy = false;

  double get _paid => widget.sale.number('paid') ?? 0;

  @override
  void initState() {
    super.initState();
    if (_paid > 0) {
      context.session.api.get('/sales/options').then((o) {
        if (!mounted) return;
        _pay.init(o, _paid);
        setState(() => _options = o);
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _pay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el motivo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.session.api.post('/sales/${widget.sale.integer('id')}/cancel', {
        'cancel_reason': _reason.text.trim(),
        if (_paid > 0) 'payment_method_id': _pay.methodId,
        if (_paid > 0) 'cash_session_id': ?_pay.sessionId,
      });
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Anular ${widget.sale.str('code')}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Lo atendido vuelve a quedar pendiente de cobro.'),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
              if (_paid > 0) ...[
                const SizedBox(height: 16),
                Text('Se devuelven ${money(context, _paid)}. ¿Cómo?', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (options == null)
                  const Center(child: CircularProgressIndicator())
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in options.list('payment_methods'))
                        ChoiceChip(
                          label: Text(m.str('name') ?? ''),
                          selected: _pay.methodId == m.integer('id'),
                          onSelected: (_) => setState(() => _pay.methodId = m.integer('id')),
                        ),
                    ],
                  ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: toneColor(context, 'danger')),
                onPressed: _busy || (_paid > 0 && options == null) ? null : _save,
                icon: const Icon(Icons.block),
                label: const Text('Anular venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cuentas por cobrar ─────────────────────────────────────────────────────

/// Quién debe: lo vencido primero, recordar por WhatsApp y abonar.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _remind(Map<String, dynamic> row) async {
    final reminder = row.obj('reminder')!;
    await openExternal(context, reminder.str('whatsapp_url')!);
    if (!mounted || !context.read<Session>().profile!.canUse('recordatorios', 'communications.create')) return;
    try {
      await context.session.api.post('/communications/send', {
        'kind': 'saldo',
        'patient_id': row.obj('patient')?.integer('id'),
        'message': reminder.str('message'),
      });
    } on ApiException {
      // WhatsApp ya se abrió: si no se pudo registrar, no es grave.
    }
  }

  Future<void> _pay(Map<String, dynamic> row) async {
    final patient = row.obj('patient')!;
    final r = await showPaySheet(
      context,
      title: 'Abono de ${patient.str('full_name')}',
      max: row.number('balance') ?? 0,
      path: '/receivables/${patient.integer('id')}/pay',
    );
    if (r == null || !mounted) return;
    showDone(context, 'Abono de ${money(context, r.number('amount'))} registrado.');
    setState(() => _version++);
    await showReceipt(context, r.obj('receipt'));
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canPay = profile.can('receivables.create');

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Cuentas por cobrar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar paciente'),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _term = v.trim()));
              },
            ),
          ),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('$_term-$_version'),
              load: () => context.session.api.get('/receivables', query: {'q': _term.isEmpty ? null : _term}),
              builder: (context, data, reload) {
                final rows = data.list('data');
                final overdue = data.integer('overdue') ?? 0;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Te deben', style: Theme.of(context).textTheme.bodySmall),
                                  Text(
                                    money(context, data.number('total')),
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                            if (overdue > 0) StatusChip(overdue == 1 ? '1 vencido' : '$overdue vencidos', tone: 'danger'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      const EmptyState(icon: Icons.verified_outlined, message: 'Nadie debe. ¡Todo cobrado!')
                    else
                      for (final row in rows) _ReceivableCard(row: row, canPay: canPay, onRemind: () => _remind(row), onPay: () => _pay(row)),
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

class _ReceivableCard extends StatelessWidget {
  const _ReceivableCard({required this.row, required this.canPay, required this.onRemind, required this.onPay});

  final Map<String, dynamic> row;
  final bool canPay;
  final VoidCallback onRemind;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final patient = row.obj('patient') ?? const {};
    final overdue = row.flag('overdue');
    final count = row.integer('count') ?? 0;
    final url = row.obj('reminder')?.str('whatsapp_url');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientAccountScreen(patientId: patient.integer('id')!, name: patient.str('full_name') ?? ''),
              ),
            ),
            leading: PatientAvatar(name: patient.str('full_name') ?? ''),
            title: Text(patient.str('full_name') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${count == 1 ? '1 venta' : '$count ventas'} · desde ${fmtShortDate(row.date('oldest'))}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(context, row.number('balance')),
                  style: _amountStyle.copyWith(fontWeight: FontWeight.w800, color: toneColor(context, overdue ? 'danger' : 'warning')),
                ),
                if (overdue) Text('vencido', style: TextStyle(fontSize: 12, color: toneColor(context, 'danger'))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: url == null ? null : onRemind,
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(url == null ? 'Sin celular' : 'Recordar'),
                  ),
                ),
                if (canPay)
                  Expanded(
                    child: FilledButton.tonalIcon(onPressed: onPay, icon: const Icon(Icons.savings_outlined, size: 18), label: const Text('Abonar')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pagos del paciente ─────────────────────────────────────────────────────

/// La cuenta de un paciente fuera de su ficha (desde Cuentas por cobrar).
class PatientAccountScreen extends StatelessWidget {
  const PatientAccountScreen({super.key, required this.patientId, required this.name});

  final int patientId;
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: PatientPayments(patientId: patientId),
  );
}

/// Pestaña Pagos de la ficha: lo que debe, lo pendiente de cobro y sus ventas.
class PatientPayments extends StatefulWidget {
  const PatientPayments({super.key, required this.patientId});

  final int patientId;

  @override
  State<PatientPayments> createState() => _PatientPaymentsState();
}

class _PatientPaymentsState extends State<PatientPayments> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;
    final canCharge = profile.can('sales.create');
    final canPay = profile.can('receivables.create');
    final api = context.session.api;

    return Loader<Map<String, dynamic>>(
      key: _loader,
      load: () async {
        final sales = await api.get('/sales', query: {'patient_id': '${widget.patientId}'});
        final pending = canCharge ? await api.get('/patients/${widget.patientId}/pending') : null;
        return {'sales': sales, 'pending': ?pending};
      },
      builder: (context, data, reload) {
        final sales = data.obj('sales')!;
        final pending = data.obj('pending');
        final debt = sales.number('debt') ?? 0;
        final toBill = pending?.number('pending_total') ?? 0;
        final pendingCount = pending?.list('data').length ?? 0;
        final big = Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
        final small = Theme.of(context).textTheme.bodySmall;
        final list = sales.list('data');

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Debe', style: small),
                          Text(money(context, debt), style: big?.copyWith(color: debt > 0 ? toneColor(context, 'danger') : null)),
                          Text(debt > 0 ? 'de ventas anteriores' : 'al día', style: small),
                        ],
                      ),
                    ),
                  ),
                ),
                if (pending != null)
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Por cobrar', style: small),
                            Text(money(context, toBill), style: big),
                            Text(pendingCount == 1 ? '1 ítem pendiente' : '$pendingCount ítems pendientes', style: small),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (canCharge)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChargeScreen(patientId: widget.patientId)));
                  _loader.currentState?.reload();
                },
                icon: const Icon(Icons.point_of_sale),
                label: Text(pendingCount > 0 ? 'Cobrar lo pendiente' : 'Cobrar'),
              ),
            if (canPay && debt > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final r = await showPaySheet(context, title: 'Abono a la cuenta', max: debt, path: '/receivables/${widget.patientId}/pay');
                  if (r == null || !context.mounted) return;
                  showDone(context, 'Abono de ${money(context, r.number('amount'))} registrado.');
                  _loader.currentState?.reload();
                  await showReceipt(context, r.obj('receipt'));
                },
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Registrar abono'),
              ),
            ],
            SectionTitle('Ventas · ${list.length}'),
            if (list.isEmpty)
              const EmptyState(icon: Icons.receipt_long_outlined, message: 'Todavía no hay ventas a este paciente.')
            else
              Card(
                child: Column(
                  children: [
                    for (final s in list)
                      SaleTile(
                        sale: s,
                        showPatient: false,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleScreen(id: s.integer('id')!)));
                          _loader.currentState?.reload();
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
