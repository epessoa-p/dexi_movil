import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/communication_screens.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

Map<String, dynamic> _row(String key, String kind, String name, String detail, {Map<String, dynamic>? sent, int? appointment, int? followup}) => {
  'key': key,
  'kind': kind,
  'patient': {'id': 7, 'full_name': name, 'phone': '70011223'},
  'detail': detail,
  'message': 'Hola $name, te escribimos de Clínica Demo.',
  'whatsapp_url': 'https://wa.me/59170011223?text=Hola',
  'appointment_id': appointment,
  'followup_id': followup,
  'sent': sent,
};

final queueJson = {
  'remind_for': '2026-11-18',
  'pending': 3,
  'kinds': [
    {'key': 'recordatorio', 'label': 'Recordatorio de cita', 'color': '#0E9F9A', 'total': 2, 'pending': 1},
    {'key': 'cumpleanos', 'label': 'Cumpleaños', 'color': '#db2777', 'total': 1, 'pending': 1},
    {'key': 'seguimiento', 'label': 'Seguimiento y controles', 'color': '#4f46e5', 'total': 1, 'pending': 1},
  ],
  'data': {
    'recordatorio': [
      _row('recordatorio-3', 'recordatorio', 'María Rojas', '09:30 · Limpieza · Ana Ruiz', appointment: 3),
      _row(
        'recordatorio-4',
        'recordatorio',
        'Jorge Paz',
        '10:00 · Control · Ana Ruiz',
        appointment: 4,
        sent: {'at': '2026-11-17T08:15:00', 'user': 'admin'},
      ),
    ],
    'cumpleanos': [_row('cumpleanos-9', 'cumpleanos', 'Lucía Soliz', 'Cumple 9 años')],
    'seguimiento': [_row('seguimiento-5', 'seguimiento', 'Pedro Gutiérrez', 'Control de 6 meses · desde el 10/11/2026', followup: 5)],
  },
};

final followupsJson = {
  'status': 'pendiente',
  'counts': {'pendiente': 1},
  'reasons': ['Control de 6 meses', 'Limpieza / profilaxis', 'Retiro de puntos'],
  'quick': [
    {'label': '1 semana', 'in': '+1 week'},
    {'label': '1 mes', 'in': '+1 month'},
    {'label': '6 meses', 'in': '+6 months'},
  ],
  'data': [
    {
      'id': 5,
      'patient': {'id': 7, 'full_name': 'María Rojas'},
      'due_date': '2026-11-10',
      'reason': 'Control de 6 meses',
      'status': 'pendiente',
      'status_label': 'Pendiente',
      'overdue': true,
    },
  ],
};

void main() {
  final launched = <String>[];
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launched.add('${(call.arguments as Map)['url']}');
        return true;
      },
    );
  });

  testWidgets('para enviar hoy: abre WhatsApp, registra el envío y marca un control como hecho', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final posts = <String, Map<String, dynamic>>{};
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posts[request.url.path] = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 1}, 201);
      }
      return json(queueJson);
    });
    final session = sessionWith(client, permissions: ['communications.view', 'communications.create'], features: ['recordatorios']);

    await tester.pumpWidget(app(session, const MessagesScreen()));
    await tester.pumpAndSettle();

    // Abre en el primer tipo con algo pendiente; lo ya enviado se ve como enviado.
    expect(find.text('María Rojas'), findsOneWidget);
    expect(find.text('Enviado 08:15'), findsOneWidget);
    expect(find.text('Enviar de nuevo'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pumpAndSettle();
    expect(launched, ['https://wa.me/59170011223?text=Hola']);
    expect(posts['/api/v1/communications/send'], {
      'kind': 'recordatorio',
      'patient_id': 7,
      'message': 'Hola María Rojas, te escribimos de Clínica Demo.',
      'appointment_id': 3,
    });
    expect(find.text('Enviado ahora'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('Controles ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Controles ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hecho'));
    await tester.pumpAndSettle();
    expect(posts['/api/v1/followups/5/status'], {'status': 'hecho'});
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('programar un control: motivo sugerido y en 6 meses por defecto', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? scheduled;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/patients/7/followups')) {
        scheduled = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 6}, 201);
      }
      return json(followupsJson);
    });
    final session = sessionWith(client, permissions: ['communications.view', 'communications.create'], features: ['recordatorios']);

    await tester.pumpWidget(
      app(
        session,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => scheduleFollowup(context, patientId: 7, consultationId: 9), child: const Text('abrir')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Retiro de puntos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programar'));
    await tester.pumpAndSettle();

    expect(scheduled, {'reason': 'Retiro de puntos', 'in': '+6 months', 'consultation_id': 9});
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('controles: los vencidos se marcan en rojo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final session = sessionWith(
      MockClient((request) async => json(followupsJson)),
      permissions: ['communications.view', 'communications.create'],
      features: ['recordatorios'],
    );

    await tester.pumpWidget(app(session, const FollowupsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Pendientes · 1'), findsOneWidget);
    expect(find.textContaining('vencido desde el 10 nov'), findsOneWidget);
  });
}
