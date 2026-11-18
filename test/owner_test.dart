import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/owner_screens.dart';
import 'package:dexi_movil/screens/profile_screen.dart';

import 'app_test.dart' show json;
import 'operations_test.dart' show expenseOptionsJson;
import 'screens_test.dart' show app, sessionWith;

Map<String, dynamic> summaryJson({String preset = 'this_month'}) => {
  'period': {
    'preset': preset,
    'label': '1 – 18 nov. 2026',
    'previous': '1 – 18 oct. 2026',
    'presets': [
      {'key': 'this_month', 'label': 'Este mes'},
      {'key': 'last_month', 'label': 'Mes pasado'},
    ],
  },
  'totals': {'income': 4795, 'cost': 970.45, 'expenses': 337, 'profit': 3487.55},
  'deltas': {
    'income': {'pct': -52, 'direction': 'down', 'tone': 'bad'},
    'profit': {'pct': -40, 'direction': 'down', 'tone': 'bad'},
  },
  'chart': {
    'labels': ['1 nov', '2 nov', '3 nov'],
    'income': [1200, 0, 3595],
    'expenses': [0, 337, 0],
  },
  'by_method': [
    {'label': 'Efectivo', 'value': 3000},
    {'label': 'QR', 'value': 1795},
  ],
  'receivable': 980,
  'receivable_overdue': 300,
  'payable': 450,
  'insights': [
    {'icon': 'bi-graph-down-arrow', 'text': 'Cobraste **Bs 4,795.00**, **52 % menos** que los mismos días del mes anterior.'},
    {'icon': 'bi-trophy', 'text': 'El tratamiento que más facturó fue **Endodoncia** (**Bs 2,100.00**).'},
  ],
  'attention': [
    {'key': 'receivables', 'tone': 'critical', 'text': '2 deudas de pacientes vencidas'},
    {'key': 'commissions', 'tone': 'warning', 'text': 'Comisiones por pagar: Bs 130.00'},
  ],
  'professionals': [
    {'id': 1, 'name': 'Ana Ruiz', 'consultations': 18, 'patients': 15, 'done': 3200, 'commissions': 960, 'attendance': 92},
  ],
};

final commissionsJson = {
  'personal_id': 1,
  'name': 'Ana Ruiz',
  'from': '2026-11-01',
  'to': '2026-11-18',
  'pending_total': 130,
  'data': [
    {
      'id': 1,
      'earned_at': '2026-11-10T10:00:00',
      'description': 'Resina compuesta 1 cara · pieza 16',
      'patient': 'María Rojas',
      'rate': '50 %',
      'base': 200,
      'amount': 100,
      'settlement': null,
    },
    {
      'id': 2,
      'earned_at': '2026-11-10T10:00:00',
      'description': 'Consulta y diagnóstico',
      'patient': 'María Rojas',
      'rate': '30 %',
      'base': 100,
      'amount': 30,
      'settlement': null,
    },
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('cómo va la clínica: utilidad, lo importante en negrita y otro período', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final presets = <String?>[];
    final client = MockClient((request) async {
      presets.add(request.url.queryParameters['preset']);
      return json(summaryJson(preset: request.url.queryParameters['preset'] ?? 'this_month'));
    });
    final session = sessionWith(client, permissions: ['reports.finance', 'receivables.view'], features: ['estadisticas', 'ventas']);

    await tester.pumpWidget(app(session, const SummaryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Bs 3,487.55'), findsWidgets);
    expect(find.text('2 deudas de pacientes vencidas'), findsOneWidget);

    await tester.tap(find.text('Mes pasado'));
    await tester.pumpAndSettle();
    expect(presets, ['this_month', 'last_month']);

    // Las negritas se dibujan sin los asteriscos.
    expect(find.textContaining('**'), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('52 % menos', findRichText: true),
      200,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
    expect(find.textContaining('52 % menos', findRichText: true), findsOneWidget);
  });

  testWidgets('comisiones: pagar lo que se debe desde la caja abierta', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? settled;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/finance/options')) return json(expenseOptionsJson);
      if (request.method == 'POST') {
        settled = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 1, 'code': 'L-000001', 'total': 130}, 201);
      }
      return json(commissionsJson);
    });
    final session = sessionWith(client, permissions: ['commissions.view', 'commissions.create'], features: ['comisiones']);

    await tester.pumpWidget(
      app(
        session,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const ProfessionalCommissionsScreen(personalId: 1, since: '2026-11-10')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Se le debe (de cualquier fecha)'), findsOneWidget);

    await tester.tap(find.text('Pagar Bs 130.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pagar Bs 130.00').last);
    await tester.pumpAndSettle();

    expect(settled?['period_start'], '2026-11-10');
    expect(settled?['source'], 'cash');
    expect(settled?['cash_session_id'], 8);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('cambiar la contraseña: el error queda bajo su campo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'message': 'La contraseña actual no es correcta.',
          'errors': {
            'current_password': ['La contraseña actual no es correcta.'],
          },
        }),
        422,
        headers: {'content-type': 'application/json'},
      );
    });
    final session = sessionWith(client);

    await tester.pumpWidget(app(session, const ChangePasswordScreen()));
    await tester.enterText(find.widgetWithText(TextField, 'Contraseña actual'), 'mala');
    await tester.enterText(find.widgetWithText(TextField, 'Contraseña nueva'), 'NuevaClave2026');
    await tester.enterText(find.widgetWithText(TextField, 'Repite la contraseña nueva'), 'NuevaClave2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Cambiar contraseña'));
    await tester.pumpAndSettle();

    expect(sent, {'current_password': 'mala', 'password': 'NuevaClave2026', 'password_confirmation': 'NuevaClave2026'});
    expect(find.text('La contraseña actual no es correcta.'), findsOneWidget);
  });
}
