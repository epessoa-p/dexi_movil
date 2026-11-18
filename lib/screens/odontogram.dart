import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../ui/common.dart';

/// Rojo = hallazgo a tratar · Azul = tratamiento existente o realizado (como en la web).
const odontoRed = Color(0xFFDC3545);
const odontoBlue = Color(0xFF2563EB);

/// Catálogos de `GET /clinical/options`: condiciones, caras, filas FDI, diagnósticos…
class ClinicalCatalog {
  ClinicalCatalog(this.raw)
    : conditions = {for (final c in raw.list('conditions')) c.str('key')!: c},
      surfaces = {for (final s in raw.list('surfaces')) s.str('key')!: s.str('label')!};

  final Map<String, dynamic> raw;
  final Map<String, Map<String, dynamic>> conditions;
  final Map<String, String> surfaces;

  static ClinicalCatalog? _cache;

  /// Se pide una vez por sesión de la app.
  static Future<ClinicalCatalog> load(ApiClient api) async => _cache ??= ClinicalCatalog(await api.get('/clinical/options'));

  static void clear() => _cache = null;

  List<List<int>> rows(String dentition) {
    final rows = raw.obj('rows')?[dentition] as List? ?? const [];
    return [
      for (final r in rows) [for (final t in r as List) t as int],
    ];
  }

  List<Map<String, dynamic>> get diagnoses => raw.list('diagnoses');

  List<Map<String, dynamic>> get professionals => raw.list('professionals');

  /// Condición que marca un procedimiento del tarifario (por su código).
  String? markFor(String? code) => code == null ? null : raw.obj('marks')?[code] as String?;

  Color colorOf(String condition) => conditions[condition]?.str('type') == 'hallazgo' ? odontoRed : odontoBlue;

  String labelOf(String condition) => conditions[condition]?.str('label') ?? condition;
}

/// Qué cara es cada lado del dibujo según la arcada y el lado (la mesial mira a la línea media).
Map<String, String> faceMap(int tooth) {
  final q = tooth ~/ 10;
  final upper = [1, 2, 5, 6].contains(q);
  final right = [1, 4, 5, 8].contains(q);
  return {'top': upper ? 'V' : 'L', 'bottom': upper ? 'L' : 'V', 'left': right ? 'D' : 'M', 'right': right ? 'M' : 'D', 'center': 'O'};
}

bool isUpper(int tooth) => [1, 2, 5, 6].contains(tooth ~/ 10);

/// Dibuja una pieza: 5 caras pintadas según su condición y los símbolos de pieza entera.
class ToothPainter extends CustomPainter {
  ToothPainter({required this.tooth, required this.info, required this.catalog, this.selected = const {}});

  final int tooth;
  final Map<String, dynamic>? info;
  final ClinicalCatalog catalog;
  final Set<String> selected;

  /// Polígonos de cada lado, en un cuadrado de lado [s] (el centro es la cara oclusal).
  static Map<String, Path> shapes(double s) {
    final k = s * .325;
    Path poly(List<Offset> p) => Path()..addPolygon(p, true);
    return {
      'top': poly([Offset.zero, Offset(s, 0), Offset(s - k, k), Offset(k, k)]),
      'bottom': poly([Offset(0, s), Offset(s, s), Offset(s - k, s - k), Offset(k, s - k)]),
      'left': poly([Offset.zero, Offset(k, k), Offset(k, s - k), Offset(0, s)]),
      'right': poly([Offset(s, 0), Offset(s - k, k), Offset(s - k, s - k), Offset(s, s)]),
      'center': Path()..addRect(Rect.fromLTRB(k, k, s - k, s - k)),
    };
  }

  /// La cara (O, M, D, V, L) en ese punto del dibujo, o null.
  static String? surfaceAt(int tooth, Offset p, double s) {
    final faces = faceMap(tooth);
    for (final entry in shapes(s).entries.toList().reversed) {
      if (entry.value.contains(p)) return faces[entry.key];
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final faces = faceMap(tooth);
    final surfaces = (info?['surfaces'] as Map?) ?? const {};
    final whole = [for (final c in (info?['whole'] as List? ?? const [])) '$c'];
    final missing = whole.contains('ausente');
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s > 60 ? 2 : 1
      ..color = const Color(0xFF9AAAB0);

    for (final MapEntry(key: pos, value: path) in shapes(s).entries) {
      final surface = faces[pos]!;
      final condition = surfaces[surface] as String?;
      final fill = Paint()..color = missing ? const Color(0xFFF1F3F4) : Colors.white;
      if (condition != null) {
        final color = catalog.colorOf(condition);
        final outline = catalog.conditions[condition]?.str('symbol') == 'outline';
        fill.color = outline ? color.withValues(alpha: .18) : color;
      }
      canvas.drawPath(path, fill);
      if (selected.contains(surface)) {
        canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .22));
      }
      canvas.drawPath(path, stroke);
    }

    final thick = s > 60 ? 5.0 : 2.5;
    for (final condition in whole) {
      final symbol = catalog.conditions[condition]?.str('symbol');
      final color = catalog.colorOf(condition);
      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round;
      switch (symbol) {
        case 'missing' || 'x':
          canvas.drawLine(Offset(-s * .06, -s * .06), Offset(s * 1.06, s * 1.06), pen);
          canvas.drawLine(Offset(s * 1.06, -s * .06), Offset(-s * .06, s * 1.06), pen);
        case 'ring':
          canvas.drawCircle(Offset(s / 2, s / 2), s * .56, pen..strokeWidth = thick * .8);
        case 'implant':
          canvas.drawRect(Rect.fromLTRB(s * .1, s * .1, s * .9, s * .9), pen..strokeWidth = thick * .8);
        case 'root':
          final up = isUpper(tooth);
          canvas.drawLine(Offset(s / 2, up ? 0 : s), Offset(s / 2, up ? -s * .32 : s * 1.32), pen);
        case 'bar':
          final y = isUpper(tooth) ? s * 1.08 : -s * .08;
          canvas.drawLine(Offset(-s * .1, y), Offset(s * 1.1, y), pen);
        case 'tag':
          final tp = TextPainter(
            text: TextSpan(
              text: condition == 'movilidad' ? 'M' : 'E',
              style: TextStyle(color: color, fontSize: s * .32, fontWeight: FontWeight.w800),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(s - tp.width, isUpper(tooth) ? -tp.height : s));
      }
    }
  }

  @override
  bool shouldRepaint(ToothPainter old) => old.info != info || old.selected != selected || old.tooth != tooth;
}

/// El odontograma completo: filas FDI ajustadas al ancho, con zoom de dos dedos. Al tocar un diente, [onTap].
class OdontogramChart extends StatelessWidget {
  const OdontogramChart({super.key, required this.catalog, required this.state, required this.dentition, required this.onTap});

  final ClinicalCatalog catalog;
  final Map<String, dynamic> state;
  final String dentition;
  final ValueChanged<int> onTap;

  static const _size = 40.0;
  static const _gap = 8.0;
  static const _mid = 14.0;

  @override
  Widget build(BuildContext context) {
    final rows = catalog.rows(dentition);
    final widest = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final width = widest * (_size + _gap) + _mid + 8;

    Widget tooth(int t) {
      final info = state['$t'] as Map<String, dynamic>?;
      final up = isUpper(t);
      final label = Text(
        '$t',
        style: TextStyle(fontSize: 12, fontWeight: (info?['count'] ?? 0) > 0 ? FontWeight.w800 : FontWeight.w500, color: const Color(0xFF44565B)),
      );
      return GestureDetector(
        onTap: () => onTap(t),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _size + _gap,
          child: Column(
            children: [
              if (up) ...[label, const SizedBox(height: 16)],
              if (!up) const SizedBox(height: 4),
              SizedBox.square(
                dimension: _size,
                child: CustomPaint(
                  painter: ToothPainter(tooth: t, info: info, catalog: catalog),
                ),
              ),
              if (!up) ...[const SizedBox(height: 16), label],
              if (up) const SizedBox(height: 4),
            ],
          ),
        ),
      );
    }

    // Toda la boca en dos filas, como en el papel.
    Widget full() => SizedBox(
      width: width,
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final t in row.take(row.length ~/ 2)) tooth(t),
                Container(
                  width: 1,
                  height: _size + 22,
                  color: const Color(0xFFCDD8DB),
                  margin: const EdgeInsets.symmetric(horizontal: _mid / 2),
                ),
                for (final t in row.skip(row.length ~/ 2)) tooth(t),
              ],
            ),
          ],
        ],
      ),
    );

    // En el teléfono, la boca entera deja los dientes de 25 px: imposibles de
    // tocar. Se parte en cuadrantes (derecha del paciente arriba de su izquierda).
    Widget split() {
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      Widget quadrant(String title, Iterable<int> teeth) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
            ),
            Row(children: [for (final t in teeth) tooth(t)]),
          ],
        ),
      );
      return SizedBox(
        width: (widest ~/ 2) * (_size + _gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const Divider(height: 20),
              quadrant(i == 0 ? 'Superior derecha' : 'Inferior derecha', row.take(row.length ~/ 2)),
              quadrant(i == 0 ? 'Superior izquierda' : 'Inferior izquierda', row.skip(row.length ~/ 2)),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth.isFinite && constraints.maxWidth / width < .8;
        return InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: narrow ? split() : full()),
          ),
        );
      },
    );
  }
}

/// Odontograma del paciente con su resumen, la dentición y la hoja de cada pieza.
/// Con [consultationId], lo registrado queda ligado a esa consulta.
class OdontogramPanel extends StatefulWidget {
  const OdontogramPanel({
    super.key,
    required this.api,
    required this.patientId,
    this.editable = false,
    this.consultationId,
    this.initial,
    this.onChanged,
  });

  final ApiClient api;
  final int patientId;
  final bool editable;
  final int? consultationId;

  /// Estado ya cargado (p. ej. dentro de la consulta), para no pedirlo de nuevo.
  final Map<String, dynamic>? initial;
  final VoidCallback? onChanged;

  @override
  State<OdontogramPanel> createState() => _OdontogramPanelState();
}

class _OdontogramPanelState extends State<OdontogramPanel> {
  ClinicalCatalog? _catalog;
  Map<String, dynamic>? _data;
  String? _dentition;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await ClinicalCatalog.load(widget.api);
      final data = widget.initial != null && _data != null ? _data! : await widget.api.get('/patients/${widget.patientId}/odontogram');
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _data = data;
        _dentition ??= data.str('dentition') ?? 'permanente';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    final data = await widget.api.get('/patients/${widget.patientId}/odontogram');
    if (mounted) setState(() => _data = data);
    widget.onChanged?.call();
  }

  Future<void> _openTooth(int tooth) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ToothSheet(
        api: widget.api,
        patientId: widget.patientId,
        tooth: tooth,
        catalog: _catalog!,
        info: (_data?['state'] as Map?)?['$tooth'] as Map<String, dynamic>?,
        editable: widget.editable,
        consultationId: widget.consultationId,
      ),
    );
    // Siempre se recarga: también si se cerró deslizando después de quitar algo.
    if (widget.editable) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final catalog = _catalog;
    final data = _data;
    if (catalog == null || data == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final summary = data.obj('summary') ?? {};
    final findings = summary.integer('findings') ?? 0;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    findings > 0
                        ? TextSpan(
                            text: '$findings ${findings == 1 ? 'hallazgo' : 'hallazgos'}',
                            style: const TextStyle(color: odontoRed, fontWeight: FontWeight.w700),
                          )
                        : const TextSpan(text: 'Sin hallazgos pendientes'),
                    if ((summary.integer('treatments') ?? 0) > 0)
                      TextSpan(text: ' · ${summary.integer('treatments')} ${summary.integer('treatments') == 1 ? 'tratamiento' : 'tratamientos'}'),
                    if ((summary.integer('missing') ?? 0) > 0)
                      TextSpan(text: ' · ${summary.integer('missing')} ${summary.integer('missing') == 1 ? 'ausente' : 'ausentes'}'),
                  ],
                ),
              ),
            ),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'permanente', label: Text('Adulto')),
                ButtonSegment(value: 'temporal', label: Text('Niño')),
              ],
              selected: {_dentition!},
              onSelectionChanged: (v) => setState(() => _dentition = v.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OdontogramChart(catalog: catalog, state: (data['state'] as Map?)?.cast<String, dynamic>() ?? {}, dentition: _dentition!, onTap: _openTooth),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _Legend(color: odontoRed, label: 'Hallazgo'),
            _Legend(color: odontoBlue, label: 'Tratamiento'),
            Text(
              widget.editable ? 'Toca un diente para registrar' : 'Toca un diente para ver su historia',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

/// Hoja de una pieza: el diente grande (se tocan las caras), lo vigente con
/// «Quitar», y registrar un hallazgo o un tratamiento. Devuelve true si cambió algo.
class ToothSheet extends StatefulWidget {
  const ToothSheet({
    super.key,
    required this.api,
    required this.patientId,
    required this.tooth,
    required this.catalog,
    this.info,
    this.editable = false,
    this.consultationId,
  });

  final ApiClient api;
  final int patientId;
  final int tooth;
  final ClinicalCatalog catalog;
  final Map<String, dynamic>? info;
  final bool editable;
  final int? consultationId;

  @override
  State<ToothSheet> createState() => _ToothSheetState();
}

class _ToothSheetState extends State<ToothSheet> {
  final Set<String> _surfaces = {};
  String? _condition;
  Map<String, dynamic>? _detail;
  bool _busy = false;
  bool _changed = false;

  static const _big = 150.0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final d = await widget.api.get('/patients/${widget.patientId}/odontogram/teeth/${widget.tooth}');
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? get _scope => _condition == null ? null : widget.catalog.conditions[_condition]?.str('scope');

  Future<void> _save() async {
    if (_condition == null) return;
    if (_scope == 'cara' && _surfaces.isEmpty) {
      showError(context, 'Toca en el dibujo la cara donde está.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/patients/${widget.patientId}/odontogram', {
        'tooth': widget.tooth,
        'condition': _condition,
        'surfaces': _scope == 'cara' ? _surfaces.toList() : <String>[],
        'consultation_id': ?widget.consultationId,
      });
      if (!mounted) return;
      showDone(context, r.str('message') ?? 'Registrado.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> entry) async {
    if (!await confirm(
      context,
      title: 'Quitar «${entry.str('label')}»',
      message: 'Queda en la historia de la pieza como resuelto.',
      action: 'Quitar',
    )) {
      return;
    }
    try {
      await widget.api.post('/patients/${widget.patientId}/odontogram/${entry.integer('id')}/resolve', {'reason': 'Quitado desde la app'});
      _changed = true;
      await _loadDetail();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final findings = catalog.conditions.values.where((c) => c.str('type') == 'hallazgo').toList();
    final treatments = catalog.conditions.values.where((c) => c.str('type') == 'tratamiento').toList();
    final current = _detail?.list('current') ?? const [];
    final history = _detail?.list('history') ?? const [];

    Widget chip(Map<String, dynamic> c) {
      final key = c.str('key')!;
      final color = catalog.colorOf(key);
      final selected = _condition == key;
      return ChoiceChip(
        label: Text(c.str('label') ?? key),
        selected: selected,
        selectedColor: color.withValues(alpha: .18),
        side: BorderSide(color: color.withValues(alpha: selected ? 1 : .4)),
        labelStyle: TextStyle(color: Color.lerp(color, Colors.black, .2), fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        onSelected: (_) => setState(() {
          _condition = selected ? null : key;
          if (_scope != 'cara') _surfaces.clear();
        }),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pieza ${widget.tooth}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(_detail?.str('name') ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (_changed) TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Listo')),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTapUp: widget.editable && _scope == 'cara'
                  ? (d) {
                      final s = ToothPainter.surfaceAt(widget.tooth, d.localPosition, _big);
                      if (s != null) setState(() => _surfaces.contains(s) ? _surfaces.remove(s) : _surfaces.add(s));
                    }
                  : null,
              child: SizedBox.square(
                dimension: _big,
                child: CustomPaint(
                  painter: ToothPainter(tooth: widget.tooth, info: widget.info, catalog: catalog, selected: _surfaces),
                ),
              ),
            ),
          ),
          if (widget.editable && _scope == 'cara')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final MapEntry(key: k, value: label) in catalog.surfaces.entries)
                    FilterChip(
                      label: Text('$k · ${label.split(' ').first}'),
                      selected: _surfaces.contains(k),
                      onSelected: (v) => setState(() => v ? _surfaces.add(k) : _surfaces.remove(k)),
                    ),
                ],
              ),
            ),
          if (current.isNotEmpty) ...[
            const SectionTitle('Registrado'),
            Card(
              child: Column(
                children: [
                  for (final e in current)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 12, color: e.str('type') == 'hallazgo' ? odontoRed : odontoBlue),
                      title: Text([e.str('label'), e.str('surface_label')].whereType<String>().join(' · ')),
                      subtitle: Text([e.str('date'), e.str('professional'), e.str('consultation')].whereType<String>().join(' · ')),
                      trailing: widget.editable ? IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => _remove(e)) : null,
                    ),
                ],
              ),
            ),
          ],
          if (widget.editable) ...[
            const SectionTitle('Hallazgo'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in findings) chip(c)]),
            const SectionTitle('Tratamiento'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in treatments) chip(c)]),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _condition == null || _busy ? null : _save,
              icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(
                _condition == null
                    ? 'Elige qué registrar'
                    : 'Registrar ${catalog.labelOf(_condition!).toLowerCase()}${_surfaces.isEmpty ? '' : ' (${_surfaces.join()})'}',
              ),
            ),
          ],
          if (history.isNotEmpty) ...[
            const SectionTitle('Historia'),
            for (final e in history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 18),
                title: Text([e.str('label'), e.str('surface_label')].whereType<String>().join(' · ')),
                subtitle: Text('${e.str('date')} → ${e.str('resolved')}${e.str('resolution') == null ? '' : ' · ${e.str('resolution')}'}'),
              ),
          ],
        ],
      ),
    );
  }
}
