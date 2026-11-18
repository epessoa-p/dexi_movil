import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

// Inventario en el teléfono: buscar o escanear un producto, ver su existencia
// por consultorio y lotes, registrar entradas, salidas y conteos, y recibir
// la mercadería de una compra. El alta de productos sigue en la web.

String qty(num? n) => n == null ? '—' : (n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2));

/// Abre la cámara y devuelve el primer código leído (o null).
Future<String?> scanCode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _manual() async {
    final code = await askText(context, title: 'Escribir el código', label: 'Código de barras o código interno', action: 'Buscar');
    if (code != null && code.trim().isNotEmpty && mounted) Navigator.of(context).pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código'),
        actions: [
          IconButton(tooltip: 'Linterna', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _controller.toggleTorch),
          IconButton(tooltip: 'Escribir el código', icon: const Icon(Icons.keyboard_outlined), onPressed: _manual),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (code == null || _done) return;
              _done = true;
              Navigator.of(context).pop(code);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Dexi no tiene permiso para usar la cámara. Actívalo en los ajustes del teléfono.'
                      : 'No se pudo abrir la cámara.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Marco de referencia.
          IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 48,
            child: Text('Apunta al código de barras del producto', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// Busca el código en la API y abre el producto; si no existe, lo avisa.
Future<void> openScanned(BuildContext context, String code) async {
  try {
    final p = await context.session.api.get('/products/scan/${Uri.encodeComponent(code)}');
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductScreen(id: p.integer('id')!)));
  } on ApiException catch (e) {
    if (context.mounted) {
      showError(context, e.status == 404 ? 'No hay ningún producto con el código $code. Regístralo en la web con ese código de barras.' : e.message);
    }
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  String _filter = 'todos';
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    await openScanned(context, code);
    setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Inventario'),
        actions: [
          if (profile.canUse('compras', 'purchases.edit'))
            IconButton(
              tooltip: 'Recibir mercadería',
              icon: const Icon(Icons.local_shipping_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPurchasesScreen())),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Escanear')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto, marca o código'),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _term = v.trim()));
              },
            ),
          ),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('$_term-$_filter-$_version'),
              load: () => context.session.api.get('/products', query: {'q': _term.isEmpty ? null : _term, 'filter': _filter}),
              builder: (context, data, reload) {
                final counts = data.obj('counts') ?? const {};
                final items = data.list('data');
                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          for (final (key, label) in [
                            ('todos', 'Todos'),
                            ('bajo', 'Bajo el mínimo · ${counts.integer('low') ?? 0}'),
                            ('vence', 'Por vencer · ${counts.integer('expiring') ?? 0}'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(label: Text(label), selected: _filter == key, onSelected: (_) => setState(() => _filter = key)),
                            ),
                        ],
                      ),
                    ),
                    if (items.isEmpty)
                      EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: switch (_filter) {
                          'bajo' => 'Nada bajo el mínimo.',
                          'vence' => 'No hay lotes vencidos ni por vencer.',
                          _ => 'No se encontraron productos.',
                        },
                      )
                    else
                      for (final p in items)
                        ProductTile(
                          product: p,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductScreen(id: p.integer('id')!)));
                            reload();
                          },
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

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.onTap});

  final Map<String, dynamic> product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final low = p.flag('low');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: toneColor(context, low ? 'danger' : 'info').withValues(alpha: .12),
        child: Icon(Icons.inventory_2_outlined, color: toneColor(context, low ? 'danger' : 'info'), size: 20),
      ),
      title: Text(p.str('label') ?? p.str('name') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text([p.str('category'), p.str('brand')].whereType<String>().join(' · ')),
          if (low) StatusChip('Bajo el mínimo (${qty(p.number('min_stock'))})', tone: 'danger'),
          if (p.flag('expiring')) const StatusChip('Lote por vencer', tone: 'warning'),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            qty(p.number('stock')),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: low ? toneColor(context, 'danger') : null),
          ),
          Text(p.str('unit') ?? '', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// El producto: existencia, por consultorio, lotes y últimos movimientos; entrada, salida y conteo.
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.id});

  final int id;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _move(Map<String, dynamic> product, String kind) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MovementSheet(product: product, kind: kind),
    );
    if (r == null || !mounted) return;
    showDone(
      context,
      '${switch (kind) {
        'entrada' => 'Entrada registrada',
        'salida' => 'Salida registrada',
        _ => 'Conteo registrado',
      }}: quedan ${qty(r.number('stock'))} ${r.str('unit') ?? ''}.',
    );
    _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canMove = context.watch<Session>().profile!.can('inventory.create');

    return Scaffold(
      appBar: AppBar(title: const Text('Producto')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get('/products/${widget.id}'),
        builder: (context, p, reload) {
          final low = p.flag('low');
          final branches = p.list('by_branch');
          final batches = p.list('batches');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.str('label') ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        [p.str('category'), p.str('brand'), p.str('barcode') ?? p.str('code')].whereType<String>().join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            qty(p.number('stock')),
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: low ? toneColor(context, 'danger') : null),
                          ),
                          const SizedBox(width: 6),
                          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p.str('unit') ?? '')),
                          const Spacer(),
                          if ((p.number('min_stock') ?? 0) > 0) StatusChip('Mínimo ${qty(p.number('min_stock'))}', tone: low ? 'danger' : 'success'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (canMove)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      for (final (kind, label, icon) in [
                        ('entrada', 'Entrada', Icons.south_west),
                        ('salida', 'Salida', Icons.north_east),
                        ('ajuste', 'Contar', Icons.fact_check_outlined),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: (kind == 'entrada' ? FilledButton.icon : OutlinedButton.icon)(
                              style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(46))),
                              onPressed: () => _move(p, kind),
                              icon: Icon(icon, size: 18),
                              label: Text(label),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (branches.length > 1) ...[
                const SectionTitle('Por consultorio'),
                Card(
                  child: Column(
                    children: [
                      for (final b in branches)
                        ListTile(
                          dense: true,
                          title: Text(b.str('branch') ?? ''),
                          trailing: Text(qty(b.number('quantity')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ],
              if (batches.isNotEmpty) ...[
                const SectionTitle('Lotes'),
                Card(
                  child: Column(
                    children: [
                      for (final b in batches)
                        ListTile(
                          dense: true,
                          title: Text('Lote ${b.str('lot') ?? 's/n'}${branches.length > 1 ? ' · ${b.str('branch')}' : ''}'),
                          subtitle: Text(
                            b.str('expires_at') == null
                                ? 'Sin vencimiento'
                                : '${b.flag('expired') ? 'Venció' : 'Vence'} el ${fmtDate(DateTime.tryParse(b.str('expires_at')!))}',
                            style: b.flag('expired') || b.flag('expiring')
                                ? TextStyle(color: toneColor(context, b.flag('expired') ? 'danger' : 'warning'), fontWeight: FontWeight.w600)
                                : null,
                          ),
                          trailing: Text(qty(b.number('quantity')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ],
              SectionTitle('Movimientos · ${p.list('movements').length}'),
              if (p.list('movements').isEmpty)
                const Card(child: ListTile(title: Text('Sin movimientos todavía.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final m in p.list('movements'))
                        ListTile(
                          dense: true,
                          leading: Icon(switch (m.str('type')) {
                            'in' || 'transfer_in' => Icons.south_west,
                            'out' || 'transfer_out' => Icons.north_east,
                            _ => Icons.fact_check_outlined,
                          }, size: 20),
                          title: Text('${m.str('type_label')} · ${m.str('reason')}'),
                          subtitle: Text([fmtDateTime(m.date('at')), m.str('user'), m.str('notes')].whereType<String>().join(' · ')),
                          trailing: Text(qty(m.number('quantity')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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

class _MovementSheet extends StatefulWidget {
  const _MovementSheet({required this.product, required this.kind});

  final Map<String, dynamic> product;

  /// entrada | salida | ajuste
  final String kind;

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _quantity = TextEditingController();
  final _lot = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic>? _options;
  String? _reason;
  int? _branch;
  int? _batch;
  DateTime? _expires;
  String? _error;
  bool _busy = false;

  bool get _tracksBatches => widget.product.flag('track_batches');

  List<Map<String, dynamic>> get _batches =>
      widget.product.list('batches').where((b) => _branch == null || b.integer('branch_id') == _branch).toList();

  @override
  void initState() {
    super.initState();
    context.session.api.get('/stock-movements/options').then((o) {
      if (!mounted) return;
      setState(() {
        _options = o;
        _branch = o.integer('default_branch');
      });
    });
  }

  @override
  void dispose() {
    _quantity.dispose();
    _lot.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.replaceAll(',', '.'));
    if (quantity == null || (widget.kind != 'ajuste' && quantity <= 0)) {
      setState(() => _error = widget.kind == 'ajuste' ? 'Escribe cuántos contaste.' : 'Escribe la cantidad.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.session.api.post('/stock-movements', {
        'kind': widget.kind,
        'product_id': widget.product.integer('id'),
        'quantity': quantity,
        'branch_id': ?_branch,
        'reason': ?_reason,
        'product_batch_id': ?_batch,
        if (_lot.text.trim().isNotEmpty) 'lot': _lot.text.trim(),
        if (_expires != null) 'expires_at': isoDate(_expires!),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
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
    final o = _options;
    final reasons = o?.list(widget.kind == 'entrada' ? 'in_reasons' : 'out_reasons') ?? const [];
    final title = switch (widget.kind) {
      'entrada' => 'Entrada',
      'salida' => 'Salida',
      _ => 'Conteo físico',
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
              Text(widget.product.str('label') ?? '', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (o == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (o.list('branches').length > 1) ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _branch,
                    decoration: const InputDecoration(labelText: 'Consultorio'),
                    items: [for (final b in o.list('branches')) DropdownMenuItem(value: b.integer('id'), child: Text(b.str('name') ?? ''))],
                    onChanged: (v) => setState(() {
                      _branch = v;
                      _batch = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.kind != 'ajuste') ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in reasons)
                        ChoiceChip(
                          label: Text(r.str('label') ?? ''),
                          selected: _reason == r.str('key'),
                          onSelected: (_) => setState(() => _reason = r.str('key')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                // Con lotes: la entrada pide el lote y vence; la salida y el conteo, de qué lote.
                if (_tracksBatches && widget.kind == 'entrada') ...[
                  TextField(
                    controller: _lot,
                    decoration: const InputDecoration(labelText: 'Lote'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Vence'),
                    subtitle: Text(_expires == null ? 'Elegir fecha' : fmtDate(_expires)),
                    onTap: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _expires ?? now.add(const Duration(days: 365)),
                        firstDate: now.subtract(const Duration(days: 30)),
                        lastDate: now.add(const Duration(days: 365 * 6)),
                      );
                      if (d != null) setState(() => _expires = d);
                    },
                  ),
                ] else if (_tracksBatches && _batches.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    isExpanded: true,
                    initialValue: _batch,
                    decoration: InputDecoration(
                      labelText: widget.kind == 'ajuste' ? 'Lote que contaste' : 'Lote (si no eliges, el que vence primero)',
                    ),
                    items: [
                      if (widget.kind != 'ajuste') const DropdownMenuItem<int?>(value: null, child: Text('El que vence primero')),
                      for (final b in _batches)
                        DropdownMenuItem<int?>(
                          value: b.integer('id'),
                          child: Text(
                            'Lote ${b.str('lot') ?? 's/n'} · ${qty(b.number('quantity'))}${b.str('expires_at') == null ? '' : ' · vence ${b.str('expires_at')}'}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _batch = v),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.kind == 'ajuste' ? '¿Cuántos hay?' : 'Cantidad',
                    suffixText: widget.product.str('unit'),
                    helperText: widget.kind == 'ajuste' ? 'La existencia queda en lo que contaste; la diferencia se registra como ajuste.' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: o == null || _busy ? null : _save,
                child: Text('Registrar ${title.toLowerCase()}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Recibir mercadería ─────────────────────────────────────────────────────

class PendingPurchasesScreen extends StatelessWidget {
  const PendingPurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recibir mercadería')),
      body: Loader<Map<String, dynamic>>(
        load: () => context.session.api.get('/purchases/pending'),
        builder: (context, data, reload) {
          final items = data.list('data');
          if (items.isEmpty) {
            return ListView(
              children: const [EmptyState(icon: Icons.local_shipping_outlined, message: 'No hay compras por recibir.')],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final p in items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: Text(p.str('supplier') ?? ''),
                    subtitle: Text(
                      '${p.str('code')} · ${p.str('status_label')} · ${p.list('items').where((i) => (i.number('pending') ?? 0) > 0).length} productos por recibir',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReceivePurchaseScreen(purchase: p)));
                      if (done == true) reload();
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

/// Lo que llegó de una compra: cantidad (por defecto, todo lo pendiente) y, si lleva lotes, lote y vencimiento.
class ReceivePurchaseScreen extends StatefulWidget {
  const ReceivePurchaseScreen({super.key, required this.purchase});

  final Map<String, dynamic> purchase;

  @override
  State<ReceivePurchaseScreen> createState() => _ReceivePurchaseScreenState();
}

class _ReceivePurchaseScreenState extends State<ReceivePurchaseScreen> {
  late final List<Map<String, dynamic>> _items = widget.purchase.list('items').where((i) => (i.number('pending') ?? 0) > 0).toList();
  late final Map<int, TextEditingController> _qty = {for (final i in _items) i.integer('id')!: TextEditingController(text: qty(i.number('pending')))};
  late final Map<int, TextEditingController> _lot = {for (final i in _items) i.integer('id')!: TextEditingController()};
  final Map<int, DateTime?> _expires = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._lot.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Escanear un producto lo ubica en la lista (útil con muchas cajas).
  Future<void> _scan() async {
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    final found = _items.where((i) => i.str('barcode') == code).firstOrNull;
    showToast(
      context,
      found == null ? 'Ese código no está en esta compra.' : '${found.str('name')}: pendiente ${qty(found.number('pending'))}.',
      kind: found == null ? ToastKind.error : ToastKind.info,
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.session.api.post('/purchases/${widget.purchase.integer('id')}/receive', {
        'lines': [
          for (final i in _items)
            {
              'item_id': i.integer('id'),
              'quantity': double.tryParse(_qty[i.integer('id')]!.text.replaceAll(',', '.')) ?? 0,
              if (_lot[i.integer('id')]!.text.trim().isNotEmpty) 'lot': _lot[i.integer('id')]!.text.trim(),
              if (_expires[i.integer('id')] != null) 'expires_at': isoDate(_expires[i.integer('id')]!),
            },
        ],
      });
      if (!mounted) return;
      showDone(context, 'Recepción registrada: la mercadería entró al stock.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.purchase.str('supplier') ?? 'Compra'),
            Text(widget.purchase.str('code') ?? '', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Escribe lo que llegó. Si algo no vino, pon 0.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final i in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      'Pedido ${qty(i.number('quantity'))} · recibido ${qty(i.number('received'))} · falta ${qty(i.number('pending'))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _qty[i.integer('id')],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Llegó', isDense: true),
                          ),
                        ),
                        if (i.flag('track_batches')) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _lot[i.integer('id')],
                              decoration: const InputDecoration(labelText: 'Lote', isDense: true),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Vence',
                            icon: Icon(_expires[i.integer('id')] == null ? Icons.event_outlined : Icons.event_available),
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: context,
                                initialDate: now.add(const Duration(days: 365)),
                                firstDate: now,
                                lastDate: now.add(const Duration(days: 365 * 6)),
                              );
                              if (d != null) setState(() => _expires[i.integer('id')!] = d);
                            },
                          ),
                        ],
                      ],
                    ),
                    if (_expires[i.integer('id')] != null)
                      Text('Vence el ${fmtDate(_expires[i.integer('id')])}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.move_to_inbox_outlined),
            label: const Text('Registrar lo que llegó'),
          ),
        ),
      ),
    );
  }
}
