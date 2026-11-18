import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/report_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

Map<String, dynamic> reportsMeta({bool money = false}) => {
  'sections': [
    if (money) {'key': 'resumen', 'label': 'Resumen', 'question': '¿Cómo va la clínica?'},
    if (money) {'key': 'finanzas', 'label': 'Ingresos y egresos', 'question': '¿Cuánto dinero entró?'},
    {'key': 'pacientes', 'label': 'Pacientes y citas', 'question': '¿Cuántos pacientes atendimos?'},
    {'key': 'inventario', 'label': 'Inventario', 'question': '¿Qué hay y qué necesita atención?'},
  ],
  'can_money': money,
  'presets': [
    {'key': 'this_month', 'label': 'Este mes'},
    {'key': 'last_month', 'label': 'Mes pasado'},
  ],
  'branches': [
    {'id': 1, 'name': 'Central'},
  ],
};

Map<String, dynamic> clinicReport({bool money = false}) => {
  'section': 'pacientes',
  'label': 'Pacientes y citas',
  'question': '¿Cuántos pacientes atendimos, cuántos faltaron y cuántos aceptan su presupuesto?',
  'can_money': money,
  'period': {'preset': 'this_month', 'label': '1 – 18 nov. 2026', 'previous': '1 – 18 oct. 2026'},
  'kpis': [
    {
      'label': 'Consultas',
      'value': 42,
      'format': 'count',
      'delta': {'pct': 12, 'direction': 'up', 'tone': 'good'},
      'hint': '35 pacientes',
    },
    {'label': 'Asistencia', 'value': 92, 'format': 'percent', 'hint': '46 vinieron · 4 faltaron'},
  ],
  'charts': [
    {
      'title': 'Consultas por día',
      'format': 'count',
      'labels': ['1 nov', '2 nov', '3 nov'],
      'series': [
        {
          'name': 'Consultas',
          'color': '#0E9F9A',
          'values': [3, 0, 5],
        },
      ],
    },
  ],
  'lists': [
    {
      'title': 'Diagnósticos más frecuentes',
      'format': 'count',
      'empty': 'Sin datos.',
      'rows': [
        {'label': 'Caries de la dentina', 'value': 14, 'share': 40},
        {'label': 'Gingivitis', 'value': 6, 'share': 17},
      ],
    },
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('reportes: el rol sin dinero ve sus secciones y cambia de una a otra', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final asked = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/reports')) return json(reportsMeta());
      asked.add('${path.split('/').last}?${request.url.queryParameters['preset']}');
      return json({...clinicReport(), 'section': path.split('/').last});
    });
    final session = sessionWith(client, permissions: ['reports.view'], features: ['estadisticas']);

    await tester.pumpWidget(app(session, const ReportsScreen()));
    await tester.pumpAndSettle();

    // Sin reports.finance: ni el resumen ni las secciones de dinero.
    expect(find.text('Resumen'), findsNothing);
    expect(find.text('Ingresos y egresos'), findsNothing);
    expect(find.text('Sin cifras de dinero: tu rol no las ve.'), findsOneWidget);
    expect(find.text('92 %'), findsOneWidget);
    expect(find.text('Caries de la dentina'), findsOneWidget);
    expect(find.textContaining('12 % vs. antes'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Inventario'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Inventario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes pasado'));
    await tester.pumpAndSettle();
    expect(asked, ['pacientes?this_month', 'inventario?this_month', 'inventario?last_month']);
  });

  testWidgets('reportes: con dinero, los montos llevan la moneda', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/reports')) return json(reportsMeta(money: true));
      return json({
        ...clinicReport(money: true),
        'section': 'finanzas',
        'kpis': [
          {'label': 'Cobrado', 'value': 4795, 'format': 'money'},
        ],
        'lists': [],
        'charts': [],
      });
    });
    final session = sessionWith(client, permissions: ['reports.view', 'reports.finance'], features: ['estadisticas', 'ventas']);

    await tester.pumpWidget(app(session, const ReportsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Bs 4,795.00'), findsOneWidget);
    expect(find.text('Sin cifras de dinero: tu rol no las ve.'), findsNothing);
  });
}
