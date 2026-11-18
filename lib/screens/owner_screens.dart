import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/common.dart';
import 'shell.dart';

// Para el dueño: el resumen de cómo va la clínica (las mismas cifras que
// Reportes en la web) y las comisiones: lo que se debe a cada odontólogo,
// pagar la liquidación y «Mis comisiones» de cada uno.

/// Texto con **negritas** (así llegan los «lo más importante» de la API).
class BoldText extends StatelessWidget {
  const BoldText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('**');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (i, part) in parts.indexed)
            TextSpan(
              text: part,
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null,
            ),
        ],
      ),
    );
  }
}

IconData _insightIcon(String? icon) => switch (icon) {
  'bi-graph-up-arrow' => Icons.trending_up,
  'bi-graph-down-arrow' => Icons.trending_down,
  'bi-exclamation-triangle' => Icons.warning_amber_rounded,
  'bi-piggy-bank' => Icons.savings_outlined,
  'bi-trophy' => Icons.emoji_events_outlined,
  'bi-person-x' => Icons.person_off_outlined,
  'bi-clipboard2-pulse' => Icons.medical_services_outlined,
  'bi-clipboard2-check' => Icons.assignment_turned_in_outlined,
  'bi-hourglass' => Icons.hourglass_empty,
  _ => Icons.payments_outlined,
};

/// A qué pantalla de la app lleva cada aviso de «Para revisar hoy».
Section? _attentionSection(String? key) => switch (key) {
  'receivables' => Section.receivables,
  'lab_late' => Section.labOrders,
  'low_stock' || 'expiring' => Section.inventory,
  'followups' => Section.followups,
  'commissions' => Section.commissions,
  _ => null,
};

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  String _preset = 'this_month';

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<Session>().profile!;

    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Cómo va la clínica')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_preset),
        load: () => context.session.api.get('/reports/summary', query: {'preset': _preset}),
        builder: (context, data, reload) {
          final period = data.obj('period') ?? const {};
          final totals = data.obj('totals') ?? const {};
          final deltas = data.obj('deltas') ?? const {};
          final profit = totals.number('profit') ?? 0;
          final small = Theme.of(context).textTheme.bodySmall;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    for (final p in period.list('presets'))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p.str('label') ?? ''),
                          selected: _preset == p.str('key'),
                          onSelected: (_) => setState(() => _preset = p.str('key')!),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  [
                    period.str('label'),
                    if (period.str('previous') != null) 'comparado con ${period.str('previous')}',
                  ].whereType<String>().join(' · '),
                  style: small,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Utilidad estimada', style: small),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            money(context, profit),
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: profit < 0 ? toneColor(context, 'danger') : null),
                          ),
                        ),
                        DeltaChip(deltas.obj('profit'), versus: 'vs. el período anterior'),
                        const Divider(height: 24),
                        _Line('Cobrado', totals.number('income'), delta: deltas.obj('income')),
                        _Line('− Productos e insumos', totals.number('cost')),
                        _Line('− Gastos', totals.number('expenses'), delta: deltas.obj('expenses')),
                        const Divider(height: 16),
                        _Line('= Te queda', profit, bold: true),
                      ],
                    ),
                  ),
                ),
              ),
              _IncomeChart(chart: data.obj('chart') ?? const {}),
              if (data.list('attention').isNotEmpty) ...[
                const SectionTitle('Para revisar hoy'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        for (final a in data.list('attention'))
                          Builder(
                            builder: (context) {
                              final section = _attentionSection(a.str('key'));
                              final reachable = section != null && section.allowedFor(profile);
                              final tone = a.str('tone') == 'critical' ? 'danger' : 'warning';
                              return ListTile(
                                leading: Icon(Icons.circle, size: 12, color: toneColor(context, tone)),
                                title: Text(a.str('text') ?? ''),
                                trailing: reachable ? const Icon(Icons.chevron_right) : null,
                                onTap: reachable ? () => openSection(context, section) : null,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SectionTitle('Lo más importante'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Column(
                    children: [
                      for (final i in data.list('insights'))
                        ListTile(
                          leading: Icon(_insightIcon(i.str('icon')), color: Theme.of(context).colorScheme.primary),
                          title: BoldText(i.str('text') ?? ''),
                        ),
                    ],
                  ),
                ),
              ),
              if (data.list('by_method').isNotEmpty) ...[
                const SectionTitle('Cobrado por método'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in data.list('by_method')) StatusChip('${m.str('label')}: ${money(context, m.number('value'))}', tone: 'info'),
                    ],
                  ),
                ),
              ],
              if ((data.number('receivable') ?? 0) > 0 || (data.number('payable') ?? 0) > 0) ...[
                const SectionTitle('Deudas'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Te deben los pacientes'),
                          subtitle: (data.number('receivable_overdue') ?? 0) > 0
                              ? Text(
                                  '${money(context, data.number('receivable_overdue'))} ya vencido',
                                  style: TextStyle(color: toneColor(context, 'danger')),
                                )
                              : null,
                          trailing: Text(
                            money(context, data.number('receivable')),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          onTap: Section.receivables.allowedFor(profile) ? () => openSection(context, Section.receivables) : null,
                        ),
                        ListTile(
                          title: const Text('Debes a proveedores y laboratorios'),
                          trailing: Text(money(context, data.number('payable')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (data.list('professionals').isNotEmpty) ...[
                const SectionTitle('Producción por profesional'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        for (final p in data.list('professionals'))
                          ListTile(
                            leading: PatientAvatar(name: p.str('name') ?? '', radius: 18),
                            title: Text(p.str('name') ?? ''),
                            subtitle: Text(
                              [
                                '${p.integer('consultations') ?? 0} consultas',
                                '${p.integer('patients') ?? 0} pacientes',
                                if (p.integer('attendance') != null) 'asistencia ${p.integer('attendance')} %',
                              ].join(' · '),
                            ),
                            trailing: Text(money(context, p.number('done')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('Los reportes detallados y el Excel están en la web.', textAlign: TextAlign.center, style: small),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.delta, this.bold = false});

  final String label;
  final double? amount;
  final Map<String, dynamic>? delta;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(context, amount), style: style),
        ],
      ),
    );
  }
}

/// Ingresos y gastos del período, en barras pareadas (sin librerías).
class _IncomeChart extends StatelessWidget {
  const _IncomeChart({required this.chart});

  final Map<String, dynamic> chart;

  @override
  Widget build(BuildContext context) {
    List<double> values(String key) => [for (final v in (chart[key] as List? ?? const [])) (v as num?)?.toDouble() ?? 0];
    final income = values('income');
    final expenses = values('expenses');
    final labels = [for (final l in (chart['labels'] as List? ?? const [])) '$l'];
    if (income.isEmpty || (income.every((v) => v == 0) && expenses.every((v) => v == 0))) return const SizedBox.shrink();
    final incomeColor = toneColor(context, 'info');
    final expenseColor = toneColor(context, 'warning');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Entra y sale'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Column(
                children: [
                  SizedBox(
                    height: 120,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _BarsPainter(income: income, expenses: expenses, incomeColor: incomeColor, expenseColor: expenseColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels.isEmpty ? '' : labels.first,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _Legend(color: incomeColor, label: 'Cobrado'),
                      const SizedBox(width: 12),
                      _Legend(color: expenseColor, label: 'Gastos'),
                      Expanded(
                        child: Text(
                          labels.isEmpty ? '' : labels.last,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.income, required this.expenses, required this.incomeColor, required this.expenseColor});

  final List<double> income;
  final List<double> expenses;
  final Color incomeColor;
  final Color expenseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(income.length, expenses.length);
    if (n == 0) return;
    final top = [...income, ...expenses].fold<double>(0, math.max);
    if (top <= 0) return;
    final slot = size.width / n;
    final bar = math.max(1.0, math.min(10.0, slot * .38));
    final base = Paint()..color = const Color(0x14000000);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), base..strokeWidth = 1);

    void draw(List<double> values, int index, Color color) {
      final paint = Paint()..color = color;
      for (var i = 0; i < values.length; i++) {
        if (values[i] <= 0) continue;
        final h = values[i] / top * (size.height - 2);
        final x = slot * i + slot / 2 + (index == 0 ? -bar : 0);
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, bar, h), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
          paint,
        );
      }
    }

    draw(income, 0, incomeColor);
    draw(expenses, 1, expenseColor);
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.income != income || old.expenses != expenses;
}

// ── Comisiones ─────────────────────────────────────────────────────────────

/// Lo que se debe a cada odontólogo (de cualquier fecha) y pagar su liquidación.
class CommissionsScreen extends StatefulWidget {
  const CommissionsScreen({super.key});

  @override
  State<CommissionsScreen> createState() => _CommissionsScreenState();
}

class _CommissionsScreenState extends State<CommissionsScreen> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: shellMenuButton(context), title: const Text('Comisiones')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_version),
        load: () => context.session.api.get('/commissions/pending'),
        builder: (context, data, reload) {
          final rows = data.list('data');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Comisiones por pagar', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        money(context, data.number('total')),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (rows.isEmpty)
                const EmptyState(icon: Icons.verified_outlined, message: 'No se debe ninguna comisión.')
              else
                for (final r in rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: PatientAvatar(name: r.str('name') ?? ''),
                      title: Text(r.str('name') ?? ''),
                      subtitle: Text(
                        '${r.integer('count') ?? 0} ${(r.integer('count') ?? 0) == 1 ? 'comisión' : 'comisiones'} · desde el ${fmtShortDate(DateTime.tryParse(r.str('since') ?? ''))}',
                      ),
                      trailing: Text(money(context, r.number('total')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfessionalCommissionsScreen(personalId: r.integer('personal_id')!, since: r.str('since')),
                          ),
                        );
                        setState(() => _version++);
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

/// El detalle de un profesional (o el propio, con [mine]) y pagar lo pendiente.
class ProfessionalCommissionsScreen extends StatefulWidget {
  const ProfessionalCommissionsScreen({super.key, this.personalId, this.since, this.mine = false});

  final int? personalId;

  /// Desde cuándo se debe: el detalle muestra desde ahí (para ver todo lo pendiente).
  final String? since;
  final bool mine;

  @override
  State<ProfessionalCommissionsScreen> createState() => _ProfessionalCommissionsScreenState();
}

class _ProfessionalCommissionsScreenState extends State<ProfessionalCommissionsScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Map<String, String?> get _query => widget.since != null && !widget.mine
      ? {'from': widget.since, 'to': isoDate(DateTime.now())}
      : {'from': isoDate(_month), 'to': isoDate(DateTime(_month.year, _month.month + 1, 0))};

  Future<void> _pay(Map<String, dynamic> data) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _SettleSheet(personalId: widget.personalId!, name: data.str('name') ?? '', total: data.number('pending_total') ?? 0, since: widget.since),
    );
    if (r == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canPay = context.watch<Session>().profile!.can('commissions.create') && !widget.mine;

    return Scaffold(
      appBar: AppBar(leading: widget.mine ? shellMenuButton(context) : null, title: Text(widget.mine ? 'Mis comisiones' : 'Comisiones')),
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () => context.session.api.get(widget.mine ? '/me/commissions' : '/commissions/${widget.personalId}', query: _query),
        builder: (context, data, reload) {
          final rows = data.list('data');
          final pending = data.number('pending_total') ?? 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        widget.mine ? 'Te deben (de cualquier fecha)' : 'Se le debe (de cualquier fecha)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(money(context, pending), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              if (canPay && pending > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _pay(data),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('Pagar ${money(context, pending)}'),
                  ),
                ),
              if (widget.mine || widget.since == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Mes anterior',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setState(() => _month = DateTime(_month.year, _month.month - 1));
                          _loader.currentState?.reload();
                        },
                      ),
                      Expanded(
                        child: Text(
                          _monthName(_month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Mes siguiente',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                            ? () {
                                setState(() => _month = DateTime(_month.year, _month.month + 1));
                                _loader.currentState?.reload();
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              SectionTitle(
                'Ganado ${widget.mine || widget.since == null ? 'en el mes' : 'por pagar'} · ${money(context, rows.fold<double>(0, (s, r) => s + (r.number('amount') ?? 0)))}',
              ),
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Sin comisiones en este período.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          title: Text(r.str('description') ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              fmtShortDate(DateTime.tryParse((r.str('earned_at') ?? '').split('T').first)),
                              r.str('patient'),
                              '${r.str('rate')} de ${money(context, r.number('base'))}',
                              r.str('settlement') == null ? 'por pagar' : 'pagada (${r.str('settlement')})',
                            ].whereType<String>().join(' · '),
                          ),
                          trailing: Text(
                            money(context, r.number('amount')),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: r.str('settlement') == null ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
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

String _monthName(DateTime m) {
  const names = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  final n = names[m.month - 1];
  return '${n[0].toUpperCase()}${n.substring(1)} ${m.year}';
}

/// Pagar la liquidación: queda como gasto de personal, desde la caja abierta o una cuenta.
class _SettleSheet extends StatefulWidget {
  const _SettleSheet({required this.personalId, required this.name, required this.total, this.since});

  final int personalId;
  final String name;
  final double total;
  final String? since;

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  Map<String, dynamic>? _options;
  String? _source;
  int? _account;
  int? _session;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.session.api
        .get('/finance/options', query: {'group': 'personal'})
        .then((o) {
          if (!mounted) return;
          setState(() {
            _options = o;
            _source = o.list('open_sessions').isNotEmpty ? 'cash' : o.list('sources').firstOrNull?.str('key');
            _session = o.integer('preferred_session_id');
            _account = o.integer('preferred_account_id');
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.session.api.post('/commissions/${widget.personalId}/settle', {
        'period_start': widget.since ?? isoDate(DateTime(DateTime.now().year, DateTime.now().month)),
        'period_end': isoDate(DateTime.now()),
        'source': _source,
        if (_source == 'cash') 'cash_session_id': _session,
        if (_source == 'account') 'finance_account_id': _account,
      });
      if (!mounted) return;
      showDone(context, 'Liquidación ${r.str('code')} pagada: ${money(context, r.number('total'))} a ${widget.name}.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _options;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagar a ${widget.name}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('${money(context, widget.total)} · queda como gasto de personal', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (o == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (o != null) ...[
              const Text('¿De dónde sale el dinero?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
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
                    ? Text('No hay una caja abierta.', style: TextStyle(color: toneColor(context, 'warning')))
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
            ],
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: toneColor(context, 'danger')))],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: o == null || _busy ? null : _save,
              icon: const Icon(Icons.payments_outlined),
              label: Text('Pagar ${money(context, widget.total)}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Mis comisiones» del odontólogo.
class MyCommissionsScreen extends StatelessWidget {
  const MyCommissionsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProfessionalCommissionsScreen(mine: true);
}
