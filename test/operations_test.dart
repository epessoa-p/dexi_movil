import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/finance_screens.dart';
import 'package:dexi_movil/screens/inventory_screens.dart';
import 'package:dexi_movil/screens/lab_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

final labOrderJson = {
  'id': 4,
  'code': 'OT-000004',
  'status': 'enviado',
  'status_label': 'Enviado',
  'status_color': 'info',
  'work': 'Corona',
  'summary': 'Corona · Zirconio · pieza 16 · A2',
  'patient': {'id': 7, 'full_name': 'María Rojas'},
  'lab': 'LAB CERÁMICO',
  'professional': 'Ana Ruiz',
  'sent_at': '2026-11-10',
  'due_at': '2026-11-15',
  'late': true,
  'returns_count': 0,
  'teeth': '16',
  'material': 'Zirconio',
  'shade': 'A2',
  'next': [
    {'status': 'recibido', 'label': 'Llegó del laboratorio'},
    {'status': 'en_proceso', 'label': 'En proceso'},
    {'status': 'cancelado', 'label': 'Cancelar'},
  ],
  'log': [
    {'from': null, 'to': 'Enviado', 'at': '2026-11-10T10:00:00', 'user': 'admin'},
  ],
};

final labOptionsJson = {
  'labs': [
    {'id': 2, 'name': 'DENTAL SUR'},
    {'id': 3, 'name': 'LAB CERÁMICO'},
  ],
  'used_labs': [3],
  'professionals': [
    {'id': 1, 'name': 'Ana Ruiz'},
  ],
  'default_professional': 1,
  'work_types': [
    {'key': 'corona', 'label': 'Corona'},
    {'key': 'carilla', 'label': 'Carilla'},
  ],
  'materials': ['Zirconio', 'Metal-porcelana'],
  'shades': ['A1', 'A2', 'A3'],
  'plan_items': [],
};

final productJson = {
  'id': 11,
  'name': 'Guantes de nitrilo',
  'label': 'Guantes de nitrilo — caja x100',
  'category': 'Bioseguridad y descartables',
  'unit': 'Caja',
  'stock': 3,
  'min_stock': 5,
  'low': true,
  'expiring': false,
  'track_batches': false,
  'by_branch': [
    {'branch_id': 1, 'branch': 'Central', 'quantity': 3},
  ],
  'batches': [],
  'movements': [
    {'id': 1, 'type': 'in', 'type_label': 'Entrada', 'reason': 'Compra', 'quantity': 10, 'at': '2026-11-01T09:00:00', 'user': 'admin'},
  ],
};

final movementOptionsJson = {
  'branches': [
    {'id': 1, 'name': 'Central'},
  ],
  'default_branch': 1,
  'in_reasons': [
    {'key': 'purchase', 'label': 'Compra'},
  ],
  'out_reasons': [
    {'key': 'internal_use', 'label': 'Uso interno'},
  ],
};

final expenseOptionsJson = {
  'group': 'general',
  'categories': [
    {'id': 21, 'name': 'LIMPIEZA'},
    {'id': 22, 'name': 'PAPELERÍA'},
  ],
  'default_category_id': null,
  'suppliers': [],
  'personal': [],
  'sources': [
    {'key': 'account', 'label': 'Cuenta'},
    {'key': 'cash', 'label': 'Caja'},
  ],
  'accounts': [
    {'id': 1, 'name': 'Banco Unión', 'balance': 5000},
  ],
  'open_sessions': [
    {'id': 8, 'name': 'Caja 1', 'expected_cash': 400},
  ],
  'preferred_session_id': 8,
  'preferred_account_id': 1,
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('laboratorio: el trabajo atrasado y «Llegó del laboratorio»', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? moved;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        moved = jsonDecode(request.body) as Map<String, dynamic>;
        return json({...labOrderJson, 'status': 'recibido', 'status_label': 'Recibido', 'next': []});
      }
      return json(labOrderJson);
    });
    final session = sessionWith(client, permissions: ['lab_orders.view', 'lab_orders.edit'], features: ['laboratorio']);

    await tester.pumpWidget(app(session, const LabOrderScreen(id: 4)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Atrasado: era para el'), findsOneWidget);

    await tester.tap(find.text('Llegó del laboratorio'));
    await tester.pumpAndSettle();
    expect(moved, {'status': 'recibido'});
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('laboratorio: la orden nueva propone el laboratorio de siempre y se envía', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? posted;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return json(labOrderJson, 201);
      }
      return json(labOptionsJson);
    });
    final session = sessionWith(client, permissions: ['lab_orders.view', 'lab_orders.create'], features: ['laboratorio']);

    await tester.pumpWidget(app(session, const LabOrderFormScreen(patientId: 7, patientName: 'María Rojas')));
    await tester.pumpAndSettle();
    expect(find.text('LAB CERÁMICO'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Pieza(s)'), '16');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Zirconio'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'A2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar al laboratorio'));
    await tester.pumpAndSettle();

    expect(posted?['supplier_id'], 3);
    expect(posted?['work_type'], 'corona');
    expect(posted?['teeth'], '16');
    expect(posted?['material'], 'Zirconio');
    expect(posted?['shade'], 'A2');
    expect(posted?['personal_id'], 1);
    expect(posted?['due_at'], isA<String>());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('inventario: contar deja la existencia en lo contado', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? moved;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/stock-movements/options')) return json(movementOptionsJson);
      if (request.method == 'POST') {
        moved = jsonDecode(request.body) as Map<String, dynamic>;
        return json({...productJson, 'stock': 7, 'low': false}, 201);
      }
      return json(productJson);
    });
    final session = sessionWith(client, permissions: ['products.view', 'inventory.create'], features: ['inventario']);

    await tester.pumpWidget(app(session, const ProductScreen(id: 11)));
    await tester.pumpAndSettle();
    expect(find.text('Mínimo 5'), findsOneWidget);

    await tester.tap(find.text('Contar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '¿Cuántos hay?'), '7');
    await tester.tap(find.text('Registrar conteo físico'));
    await tester.pumpAndSettle();

    expect(moved, {'kind': 'ajuste', 'product_id': 11, 'quantity': 7.0, 'branch_id': 1});
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('inventario: un código que no existe se avisa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'message': 'No hay ningún producto.'}), 404, headers: {'content-type': 'application/json'}),
    );
    final session = sessionWith(client, permissions: ['products.view'], features: ['inventario']);

    await tester.pumpWidget(
      app(
        session,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => openScanned(context, '000123'), child: const Text('escanear')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('escanear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay ningún producto con el código 000123'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('gasto: sale de la caja abierta por defecto', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? posted;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 30, 'code': 'G-000030', 'amount': 45}, 201);
      }
      return json(expenseOptionsJson);
    });
    final session = sessionWith(client, permissions: ['expenses.view', 'expenses.create'], features: ['caja']);

    await tester.pumpWidget(app(session, const ExpenseFormScreen(group: 'general')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'LIMPIEZA'));
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '45');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar gasto'));
    await tester.pumpAndSettle();

    expect(posted?['group'], 'general');
    expect(posted?['expense_category_id'], '21');
    expect(posted?['amount'], '45.0');
    expect(posted?['source'], 'cash');
    expect(posted?['cash_session_id'], '8');
    await tester.pump(const Duration(seconds: 6));
  });
}
