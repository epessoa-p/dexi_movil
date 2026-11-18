import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/sales_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

final salesOptions = {
  'currency': 'Bs',
  'payment_methods': [
    {'id': 1, 'name': 'Efectivo', 'is_cash': true, 'requires_reference': false},
    {'id': 2, 'name': 'QR', 'is_cash': false, 'requires_reference': true},
  ],
  'cash': {
    'enabled': true,
    'sessions': [
      {'id': 5, 'name': 'Caja 1', 'opened_at': '2026-11-17T08:00:00'},
    ],
  },
  'professionals': [
    {'id': 1, 'name': 'Ana Ruiz'},
  ],
  'default_professional': 1,
};

final _patient = {'id': 7, 'full_name': 'María Rojas', 'whatsapp_link': 'https://wa.me/59170011223', 'alerts': []};

Map<String, dynamic> saleJson({double paid = 100, double balance = 180}) => {
  'id': 1,
  'code': 'V-000001',
  'created_at': '2026-11-17T10:30:00',
  'status': 'completada',
  'cancelled': false,
  'patient': {'id': 7, 'full_name': 'María Rojas'},
  'subtotal': 280,
  'discount': 0,
  'total': 280,
  'paid': paid,
  'balance': balance,
  'overdue': false,
  'user': 'admin',
  'items': [
    {'id': 1, 'description': 'Consulta', 'origin': 'C-000001', 'quantity': 1, 'unit_price': 100, 'discount': 0, 'total': 100},
    {'id': 2, 'description': 'Resina · pieza 16 O', 'origin': 'C-000001', 'quantity': 1, 'unit_price': 180, 'discount': 0, 'total': 180},
  ],
  'payments': [
    {'id': 1, 'kind': 'venta', 'method': 'Efectivo', 'amount': paid, 'paid_at': '2026-11-17T10:30:00', 'user': 'admin'},
  ],
  'receipt': {'message': 'Recibo V-000001\nTotal: Bs 280', 'whatsapp_url': 'https://wa.me/59170011223?text=Recibo'},
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('cobrar lo realizado: viene marcado, se paga una parte y queda saldo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? posted;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/sales/options')) return json(salesOptions);
      if (path.endsWith('/patients/7/pending')) {
        return json({
          'patient': _patient,
          'debt': 0,
          'pending_total': 280,
          'data': [
            {'source': 'consultation', 'id': 11, 'name': 'Consulta', 'quantity': 1, 'subtotal': 100, 'origin': 'C-000001', 'done': true},
            {
              'source': 'consultation',
              'id': 12,
              'name': 'Resina',
              'tooth': 16,
              'surfaces': 'O',
              'quantity': 1,
              'subtotal': 180,
              'origin': 'C-000001',
              'done': true,
            },
            {'source': 'plan', 'id': 30, 'name': 'Corona', 'quantity': 1, 'subtotal': 900, 'origin': 'P-000001', 'done': false},
          ],
        });
      }
      if (request.method == 'POST' && path.endsWith('/sales')) {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return json(saleJson(), 201);
      }
      if (path.endsWith('/sales/1')) return json(saleJson());
      return json({});
    });
    final session = sessionWith(client, permissions: ['sales.view', 'sales.create', 'receivables.create'], features: ['ventas']);

    await tester.pumpWidget(app(session, const ChargeScreen(patientId: 7)));
    await tester.pumpAndSettle();

    // Lo realizado viene marcado; lo del plan aún no hecho, no.
    expect(find.text('Cobrar Bs 280.00'), findsOneWidget);
    expect(find.textContaining('por adelantado'), findsOneWidget);

    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Monto que paga'), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'Monto que paga'), '100');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Queda debiendo'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Queda debiendo'), findsOneWidget);

    await tester.tap(find.text('Cobrar Bs 100.00'));
    await tester.pumpAndSettle();

    expect(posted?['patient_id'], 7);
    expect(posted?['items'], [
      {'source': 'consultation', 'id': 11},
      {'source': 'consultation', 'id': 12},
    ]);
    expect(posted?['payments'], [
      {'payment_method_id': 1, 'amount': 100.0},
    ]);
    expect(posted?['cash_session_id'], 5);
    // Recién cobrada: ofrece mandar el recibo.
    expect(find.text('Venta V-000001 registrada'), findsOneWidget);
    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
  });

  testWidgets('cuentas por cobrar: abono con QR exige el comprobante y devuelve el recibo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? paid;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/sales/options')) return json(salesOptions);
      if (path.endsWith('/receivables/7/pay')) {
        paid = jsonDecode(request.body) as Map<String, dynamic>;
        return json({
          'amount': 80,
          'applied': [
            {'sale': 'V-000001', 'amount': 80},
          ],
          'debt': 100,
          'receipt': {'message': 'Recibo de Clínica Demo\nAbono: Bs 80\nSaldo pendiente: Bs 100', 'whatsapp_url': 'https://wa.me/1?text=x'},
        }, 201);
      }
      if (path.endsWith('/receivables')) {
        return json({
          'total': 180,
          'overdue': 1,
          'data': [
            {
              'patient': _patient,
              'balance': 180,
              'count': 1,
              'oldest': '2026-11-01',
              'overdue': true,
              'reminder': {'message': 'Hola María', 'whatsapp_url': 'https://wa.me/1?text=Hola'},
            },
          ],
        });
      }
      return json({});
    });
    final session = sessionWith(client, permissions: ['receivables.view', 'receivables.create'], features: ['ventas']);

    await tester.pumpWidget(app(session, const ReceivablesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1 vencido'), findsOneWidget);
    expect(find.text('María Rojas'), findsOneWidget);

    await tester.tap(find.text('Abonar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'QR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto del abono'), '80');
    await tester.enterText(find.widgetWithText(TextField, 'N.º de comprobante de QR'), 'QR-123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar abono de Bs 80.00'));
    await tester.pumpAndSettle();

    expect(paid, {'payment_method_id': 2, 'amount': 80.0, 'reference': 'QR-123', 'cash_session_id': 5});
    expect(find.textContaining('Saldo pendiente: Bs 100'), findsOneWidget);
  });
}
