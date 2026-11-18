import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

// Reportes en la app: las mismas secciones de la web (Ingresos y egresos,
// Ventas, Pacientes y citas, Profesionales, Inventario) con el mismo período
// y consultorio. El servidor decide qué secciones ve cada rol y quita las
// cifras de dinero a quien no tiene `reports.finance`; la app solo dibuja los
// bloques que llegan (indicadores, gráficos y listas). El Excel sigue en la web.

String fmtQty(num? n) => n == null ? '—' : (n == n.roundToDouble() ? fmtNumber(n.toInt()) : n.toStringAsFixed(2));

String formatValue(BuildContext context, num? value, String? format) => switch (format) {
  'money' => money(context, value),
  'percent' => value == null ? '—' : '${value.round()} %',
  _ => fmtQty(value),
};

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _meta;
  Object? _error;
  String? _section;
  String _preset = 'this_month';
  int? _branch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final meta = await context.session.api.get('/reports');
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _section = meta.list('sections').where((s) => s.str('key') != 'resumen').firstOrNull?.str('key');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final profile = context.watch<Session>().profile!;
    final sections = meta?.list('sections').where((s) => s.str('key') != 'resumen').toList() ?? const [];
    final branches = meta?.list('branches') ?? const [];

    return Scaffold(
      appBar: AppBar(
        leading: shellMenuButton(context),
        title: const Text('Reportes'),
        actions: [
          if (branches.length > 1)
            PopupMenuButton<int?>(
              tooltip: 'Consultorio',
              icon: Icon(_branch == null ? Icons.store_mall_directory_outlined : Icons.store),
              initialValue: _branch,
              onSelected: (v) => setState(() => _branch = v == 0 ? null : v),
              itemBuilder: (_) => [
                const PopupMenuItem<int?>(value: 0, child: Text('Todos los consultorios')),
                for (final b in branches) PopupMenuItem<int?>(value: b.integer('id'), child: Text(b.str('name') ?? '')),
              ],
            ),
        ],
      ),
      body: _error != null
          ? ListView(
              children: [ErrorState(error: _error!, onRetry: _load)],
            )
          : meta == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      // El resumen tiene su propia pantalla («Cómo va la clínica»).
                      if (Section.summary.allowedFor(profile))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.insights_outlined, size: 18),
                            label: const Text('Resumen'),
                            onPressed: () => openSection(context, Section.summary),
                          ),
                        ),
                      for (final s in sections)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(s.str('label') ?? ''),
                            selected: _section == s.str('key'),
                            onSelected: (_) => setState(() => _section = s.str('key')),
                          ),
                        ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      for (final p in meta.list('presets'))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(p.str('label') ?? '', style: const TextStyle(fontSize: 12)),
                            selected: _preset == p.str('key'),
                            onSelected: (_) => setState(() => _preset = p.str('key')!),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _section == null
                      ? const EmptyState(icon: Icons.insights_outlined, message: 'Tu rol solo ve el resumen.')
                      : Loader<Map<String, dynamic>>(
                          key: ValueKey('$_section-$_preset-$_branch'),
                          load: () => context.session.api.get('/reports/$_section', query: {'preset': _preset, 'branch': _branch?.toString()}),
                          builder: (context, data, reload) => ReportBlocks(data: data),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Dibuja una sección: la pregunta, los indicadores, los gráficos y las listas.
class ReportBlocks extends StatelessWidget {
  const ReportBlocks({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final period = data.obj('period') ?? const {};
    final kpis = data.list('kpis');
    final small = Theme.of(context).textTheme.bodySmall;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(data.str('question') ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          [period.str('label'), if (period.str('previous') != null) 'comparado con ${period.str('previous')}'].whereType<String>().join(' · '),
          style: small,
        ),
        if (!data.flag('can_money'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Sin cifras de dinero: tu rol no las ve.', style: small?.copyWith(fontStyle: FontStyle.italic)),
          ),
        const SizedBox(height: 10),
        if (kpis.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in kpis)
                    SizedBox(
                      width: width,
                      child: _Kpi(kpi: k),
                    ),
                ],
              );
            },
          ),
        for (final c in data.list('charts')) _SeriesChart(chart: c),
        for (final l in data.list('lists')) _RankList(list: l),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.kpi});

  final Map<String, dynamic> kpi;

  @override
  Widget build(BuildContext context) {
    final tone = kpi.str('tone');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kpi.str('label') ?? '', style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatValue(context, kpi.number('value'), kpi.str('format')),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tone == null ? null : toneColor(context, tone)),
              ),
            ),
            if (kpi.obj('delta') != null) DeltaChip(kpi.obj('delta'), versus: 'vs. antes'),
            if (kpi.str('hint') != null)
              Text(kpi.str('hint')!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Barras por día o mes (una o dos series), sin librerías.
class _SeriesChart extends StatelessWidget {
  const _SeriesChart({required this.chart});

  final Map<String, dynamic> chart;

  static Color _hex(String? hex, Color fallback) {
    final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
    return v == null ? fallback : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final series = chart.list('series');
    final values = [
      for (final s in series) [for (final v in (s['values'] as List? ?? const [])) (v as num?)?.toDouble() ?? 0.0],
    ];
    final labels = [for (final l in (chart['labels'] as List? ?? const [])) '$l'];
    if (values.every((v) => v.every((x) => x == 0))) return const SizedBox.shrink();
    final colors = [for (final s in series) _hex(s.str('color'), Theme.of(context).colorScheme.primary)];
    final small = Theme.of(context).textTheme.bodySmall;
    final top = values.expand((v) => v).fold<double>(0, math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(chart.str('title') ?? ''),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('máx. ${formatValue(context, top, chart.str('format'))}', style: small),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _BarsPainter(values: values, colors: colors),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(labels.isEmpty ? '' : labels.first, style: small, overflow: TextOverflow.ellipsis),
                    ),
                    for (final (i, s) in series.indexed) ...[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 4),
                      Text(s.str('name') ?? '', style: small),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(labels.isEmpty ? '' : labels.last, style: small, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.values, required this.colors});

  final List<List<double>> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.fold<int>(0, (m, v) => math.max(m, v.length));
    final top = values.expand((v) => v).fold<double>(0, math.max);
    if (n == 0 || top <= 0) return;
    final slot = size.width / n;
    final group = values.length;
    final bar = math.max(1.0, math.min(10.0, slot * .76 / group));
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = const Color(0x14000000));
    for (var s = 0; s < group; s++) {
      final paint = Paint()..color = colors[s];
      for (var i = 0; i < values[s].length; i++) {
        final v = values[s][i];
        if (v <= 0) continue;
        final h = v / top * (size.height - 2);
        final x = slot * i + slot / 2 - bar * group / 2 + bar * s;
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, bar, h), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.values != values;
}

/// Un ranking: cada fila con su valor y una barra de su parte respecto del primero.
class _RankList extends StatelessWidget {
  const _RankList({required this.list});

  final Map<String, dynamic> list;

  @override
  Widget build(BuildContext context) {
    final rows = list.list('rows');
    final format = list.str('format');
    final top = rows.fold<double>(0, (m, r) => math.max(m, r.number('value') ?? 0));
    final color = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(list.str('title') ?? ''),
        Card(
          margin: EdgeInsets.zero,
          child: rows.isEmpty
              ? ListTile(title: Text(list.str('empty') ?? 'Sin datos.', style: Theme.of(context).textTheme.bodyMedium))
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(r.str('label') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatValue(context, r.number('value'), format),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              if (r.str('hint') != null) Text(r.str('hint')!, style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: top > 0 ? (r.number('value') ?? 0) / top : 0,
                                  minHeight: 5,
                                  color: color,
                                  backgroundColor: color.withValues(alpha: .1),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
