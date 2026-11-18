import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:dexi_movil/core/api_client.dart';
import 'package:dexi_movil/core/models.dart';
import 'package:dexi_movil/core/session.dart';
import 'package:dexi_movil/screens/agenda_screens.dart';
import 'package:dexi_movil/screens/patient_screens.dart';
import 'package:dexi_movil/screens/shell.dart';

import 'app_test.dart' show MemoryStore, json;

Session sessionWith(MockClient client, {List<String> permissions = const [], List<String> features = const []}) {
  final session = Session(
    ApiClient(baseUrl: 'https://dexi.test/api/v1', httpClient: client),
    store: MemoryStore(),
  );
  session.profile = Profile.fromJson({
    'user': {'id': 4, 'name': 'Dra. Ana Ruiz', 'email': 'ana@demo.test'},
    'company': {'id': 1, 'name': 'Clínica Demo', 'currency_symbol': 'Bs'},
    'companies': [
      {'id': 1, 'name': 'Clínica Demo'},
    ],
    'permissions': permissions,
    'plan': {'name': 'Clínica', 'features': features},
  });
  session.status = SessionStatus.ready;
  return session;
}

Widget app(Session session, Widget home) => ChangeNotifierProvider.value(
  value: session,
  child: MaterialApp(home: home),
);

final _maria = {
  'id': 7,
  'code': 'HC-000007',
  'full_name': 'María Rojas',
  'age_label': '36 años',
  'phone': '70011223',
  'whatsapp_link': 'https://wa.me/59170011223',
  'alerts': [
    {'label': 'Alergia: penicilina', 'critical': true},
  ],
  'active': true,
};

Map<String, dynamic> _appointment({String status = 'agendada', List<String> next = const ['confirmada', 'en_espera', 'cancelada', 'no_asistio']}) => {
  'id': 3,
  'starts_at': '2026-11-17T09:30:00',
  'ends_at': '2026-11-17T10:00:00',
  'duration_minutes': 30,
  'status': status,
  'status_label': status == 'agendada' ? 'Agendada' : 'Confirmada',
  'status_color': 'secondary',
  'next_statuses': next,
  'title': 'Limpieza',
  'patient': _maria,
  'professional': {'id': 1, 'name': 'Ana Ruiz', 'color': '#0e9f9a'},
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('el menú muestra solo las secciones del plan y del rol', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final empty = MockClient((request) async => json({'data': [], 'alerts': [], 'today': null, 'greeting': 'Hola'}));
    final session = sessionWith(empty, permissions: ['patients.view']);

    await tester.pumpWidget(app(session, const AppShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menú').first);
    await tester.pumpAndSettle();

    final drawer = find.byType(NavigationDrawer);
    expect(find.descendant(of: drawer, matching: find.text('Pacientes')), findsWidgets);
    // Sin el módulo de agenda en el plan: ni Agenda ni Sala de espera.
    expect(find.descendant(of: drawer, matching: find.text('Agenda')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Sala de espera')), findsNothing);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('el inicio muestra la agenda de hoy, lo pendiente y lo cobrado', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final client = MockClient(
      (request) async => json({
        'greeting': 'Buenos días',
        'today': {
          'total': 6,
          'waiting': 1,
          'done': 2,
          'next': [_appointment()],
        },
        'alerts': [
          {'key': 'messages', 'title': 'WhatsApp por enviar', 'count': 4, 'tone': 'success'},
        ],
        'finance': {
          'today': 350,
          'sales_today': 2,
          'month': 4200.5,
          'receivable': 150,
          'receivable_overdue': 0,
          'month_delta': {'pct': 12, 'direction': 'up', 'tone': 'good'},
        },
      }),
    );
    final session = sessionWith(
      client,
      permissions: ['appointments.view', 'appointments.create', 'patients.view', 'patients.create'],
      features: ['agenda'],
    );

    await tester.pumpWidget(app(session, const AppShell()));
    await tester.pumpAndSettle();

    expect(find.text('Buenos días, Ana'), findsOneWidget);
    expect(find.text('Citas hoy'), findsOneWidget);
    expect(find.text('WhatsApp por enviar'), findsOneWidget);
    expect(find.text('Bs 350.00'), findsOneWidget);
    expect(find.text('Te deben Bs 150.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('María Rojas'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('María Rojas'), findsOneWidget);
    expect(find.text('Agendar'), findsWidgets);
  });

  testWidgets('la cita muestra las alertas médicas y cambia de estado', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    String? patched;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        patched = (jsonDecode(request.body) as Map)['status'] as String;
        return json(_appointment(status: 'confirmada'));
      }
      return json({
        ..._appointment(),
        'history': [],
        'reminder': {'message': 'Hola María', 'whatsapp_url': 'https://wa.me/59170011223?text=Hola', 'log': true, 'sent_at': null},
      });
    });
    final session = sessionWith(client, permissions: ['appointments.view', 'appointments.edit', 'patients.view'], features: ['agenda']);

    await tester.pumpWidget(app(session, const AppointmentScreen(id: 3)));
    await tester.pumpAndSettle();

    expect(find.text('Antes de atender'), findsOneWidget);
    expect(find.text('Alergia: penicilina'), findsOneWidget);
    expect(find.text('Recordar por WhatsApp'), findsOneWidget);

    await tester.tap(find.text('Confirmó'));
    await tester.pumpAndSettle();
    expect(patched, 'confirmada');
  });

  testWidgets('desde la cita se atiende: abre la consulta ligada a la cita', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? started;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/consultations')) {
        started = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'id': 9}, 201);
      }
      if (path.endsWith('/consultations/9')) {
        return json({
          'id': 9,
          'code': 'C-000009',
          'status': 'abierta',
          'open': true,
          'started_at': '2026-11-17T09:30:00',
          'patient': _maria,
          'professional': {'id': 1, 'name': 'Ana Ruiz'},
          'diagnoses': [],
          'procedures': [],
          'plan_items': [],
          'previous': [],
        });
      }
      if (path.endsWith('/clinical/options')) {
        return json({'diagnoses': [], 'surfaces': [], 'conditions': [], 'rows': {}, 'marks': {}, 'professionals': []});
      }
      return json({..._appointment(status: 'en_espera'), 'history': [], 'consultation_id': null});
    });
    final session = sessionWith(
      client,
      permissions: ['appointments.view', 'consultations.view', 'consultations.create', 'consultations.edit'],
      features: ['agenda', 'historia_clinica'],
    );

    await tester.pumpWidget(app(session, const AppointmentScreen(id: 3)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Atender: abrir consulta'));
    await tester.tap(find.text('Atender: abrir consulta'));
    await tester.pumpAndSettle();

    expect(started, {'appointment_id': 3});
    expect(find.text('Cerrar consulta'), findsOneWidget);
  });

  testWidgets('el alta de paciente exige nombres y apellidos', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    var posted = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return json({..._maria, 'code': 'HC-000008'}, 201);
      }
      return json({
        'document_types': [
          {'key': 'ci', 'label': 'CI'},
        ],
        'genders': [
          {'key': 'F', 'label': 'Femenino'},
        ],
        'referral_sources': [],
        'conditions': [
          {'key': 'diabetes', 'label': 'Diabetes', 'critical': true},
        ],
        'blood_types': ['O+'],
      });
    });
    final session = sessionWith(client, permissions: ['patients.view', 'patients.create']);

    await tester.pumpWidget(app(session, const PatientFormScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Registrar paciente'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Registrar paciente'));
    await tester.pumpAndSettle();
    expect(posted, isFalse);
    expect(find.text('Obligatorio.'), findsNWidgets(2));
  });
}
