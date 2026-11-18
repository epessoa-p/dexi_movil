// Capturas de pantalla para revisar el diseño (no es parte de la suite normal).
// Uso: flutter test test/shots_test.dart --dart-define=SHOTS_DIR=<carpeta> --dart-define=FONTS_DIR=<flutter>/bin/cache/artifacts/material_fonts
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/core/session.dart';
import 'package:dexi_movil/screens/agenda_screens.dart';
import 'package:dexi_movil/screens/auth_screens.dart';
import 'package:dexi_movil/screens/communication_screens.dart';
import 'package:dexi_movil/screens/finance_screens.dart';
import 'package:dexi_movil/screens/inventory_screens.dart';
import 'package:dexi_movil/screens/lab_screens.dart';
import 'package:dexi_movil/screens/owner_screens.dart';
import 'package:dexi_movil/screens/report_screens.dart';
import 'package:dexi_movil/screens/consultation_screens.dart';
import 'package:dexi_movil/screens/odontogram.dart';
import 'package:dexi_movil/screens/patient_screens.dart';
import 'package:dexi_movil/screens/sales_screens.dart';
import 'package:dexi_movil/screens/shell.dart';
import 'package:dexi_movil/ui/common.dart';

import 'app_test.dart' show json;
import 'clinical_test.dart' show clinicalOptions;
import 'sales_test.dart' show salesOptions, saleJson;
import 'communications_test.dart' show queueJson, followupsJson;
import 'owner_test.dart' show summaryJson, commissionsJson;
import 'reports_test.dart' show reportsMeta, clinicReport;
import 'operations_test.dart' show expenseOptionsJson, labOptionsJson, labOrderJson, productJson;
import 'screens_test.dart' show sessionWith;
import 'package:provider/provider.dart';

const _dir = String.fromEnvironment('SHOTS_DIR');
const _fonts = String.fromEnvironment('FONTS_DIR');

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$_fonts/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$_fonts/materialicons-regular.otf').readAsBytesSync())));
  await icons.load();
}

final _maria = {
  'id': 7,
  'code': 'HC-000007',
  'full_name': 'María Fernanda Rojas',
  'age_label': '36 años',
  'phone': '70011223',
  'whatsapp_link': 'https://wa.me/59170011223',
  'alerts': [
    {'label': 'Alergia: penicilina', 'critical': true},
    {'label': 'Hipertensión', 'critical': false},
  ],
  'active': true,
};

Map<String, dynamic> _appt(
  int id,
  String time,
  String status,
  String label,
  String color,
  String name,
  String title, {
  String pro = 'Ana Ruiz',
  String proColor = '#0e9f9a',
}) => {
  'id': id,
  'starts_at': '2026-11-17T$time:00',
  'ends_at': '2026-11-17T$time:00',
  'duration_minutes': 30,
  'status': status,
  'status_label': label,
  'status_color': color,
  'next_statuses': ['confirmada', 'en_espera', 'cancelada', 'no_asistio'],
  'title': title,
  'patient': {..._maria, 'full_name': name, 'alerts': name.startsWith('María') ? _maria['alerts'] : []},
  'professional': {'id': 1, 'name': pro, 'color': proColor},
};

Map<String, dynamic> _tooth({List<String> whole = const [], Map<String, String> surfaces = const {}}) => {
  'whole': whole,
  'surfaces': surfaces,
  'count': whole.length + surfaces.length,
};

final _consultation = <String, dynamic>{
  'id': 9,
  'code': 'C-000009',
  'status': 'abierta',
  'status_label': 'Abierta',
  'open': true,
  'started_at': '2026-11-17T09:00:00',
  'reason': 'Dolor al masticar en molar superior',
  'history': 'Dolor de 5 días, aumenta con el frío.',
  'exam': 'Caries profunda en 16 oclusal, sin movilidad.',
  'indications': 'Evitar alimentos muy fríos. Ibuprofeno 400 mg cada 8 h por 3 días.',
  'patient': _maria,
  'professional': {'id': 1, 'name': 'Ana Ruiz'},
  'diagnoses': [
    {'id': 1, 'code': 'caries_dentina', 'label': 'Caries de la dentina', 'icd': 'K02.1', 'tooth': 16},
    {'id': 2, 'code': 'pulpitis_reversible', 'label': 'Pulpitis reversible', 'icd': 'K04.0', 'tooth': 16},
  ],
  'procedures': [
    {'id': 1, 'name': 'Resina compuesta 1 cara', 'tooth': 16, 'surfaces': 'O', 'quantity': 1, 'price': 250, 'billed': false},
  ],
  'plan_items': [
    {'id': 4, 'name': 'Profilaxis', 'plan': 'Plan P-000003'},
  ],
  'previous': [],
  'to_bill': 250,
  'odontogram': {
    'state': {
      '16': _tooth(surfaces: {'O': 'caries', 'M': 'caries'}),
      '26': _tooth(surfaces: {'O': 'obturacion'}),
      '36': _tooth(whole: ['ausente']),
      '46': _tooth(surfaces: {'O': 'obturacion', 'V': 'caries'}),
      '11': _tooth(surfaces: {'M': 'caries'}),
    },
    'summary': {'findings': 4, 'teeth_with_findings': 3, 'missing': 1, 'treatments': 2},
    'dentition': 'permanente',
  },
};

final _pending = {
  'patient': _maria,
  'debt': 150,
  'pending_total': 430,
  'data': [
    {'source': 'consultation', 'id': 11, 'name': 'Consulta y diagnóstico', 'quantity': 1, 'subtotal': 100, 'origin': 'C-000009', 'done': true},
    {
      'source': 'consultation',
      'id': 12,
      'name': 'Resina compuesta 1 cara',
      'tooth': 16,
      'surfaces': 'O',
      'quantity': 1,
      'subtotal': 250,
      'origin': 'C-000009',
      'done': true,
    },
    {'source': 'plan', 'id': 30, 'name': 'Profilaxis', 'quantity': 1, 'subtotal': 80, 'origin': 'P-000003', 'done': true},
    {'source': 'plan', 'id': 31, 'name': 'Corona metal-porcelana', 'tooth': 46, 'quantity': 1, 'subtotal': 1200, 'origin': 'P-000003', 'done': false},
  ],
};

Map<String, dynamic> _debtor(int id, String name, double balance, String oldest, bool overdue, int count) => {
  'patient': {..._maria, 'id': id, 'full_name': name},
  'balance': balance,
  'count': count,
  'oldest': oldest,
  'overdue': overdue,
  'reminder': {'message': 'Hola', 'whatsapp_url': 'https://wa.me/1?text=Hola'},
};

final _receivables = {
  'total': 2830,
  'overdue': 2,
  'data': [
    _debtor(7, 'María Fernanda Rojas', 1350, '2026-10-02', true, 2),
    _debtor(8, 'Jorge Mendoza Ríos', 980, '2026-10-20', true, 1),
    _debtor(9, 'Lucía Arteaga Soliz', 500, '2026-11-12', false, 1),
  ],
};

Map<String, dynamic> _saleRow(int id, String name, String time, double total, double balance, {bool cancelled = false}) => {
  'id': id,
  'code': 'V-00000$id',
  'created_at': '2026-11-17T$time:00',
  'cancelled': cancelled,
  'patient': {'id': id, 'full_name': name},
  'total': total,
  'paid': total - balance,
  'balance': balance,
  'overdue': false,
};

final _sales = {
  'filter': 'hoy',
  'filters': {'hoy': 'Hoy', 'mes': 'Este mes', 'saldo': 'Con saldo', 'anuladas': 'Anuladas', 'todas': 'Todas'},
  'collected_today': 1430,
  'by_method': [
    {'name': 'Efectivo', 'amount': 830},
    {'name': 'QR', 'amount': 600},
  ],
  'data': [
    _saleRow(4, 'María Fernanda Rojas', '10:30', 350, 0),
    _saleRow(3, 'Jorge Mendoza Ríos', '09:45', 1200, 600),
    _saleRow(2, 'Lucía Arteaga Soliz', '09:10', 80, 0),
    _saleRow(1, 'Pedro Gutiérrez', '08:40', 150, 0, cancelled: true),
  ],
};

final _agenda = [
  _appt(
    1,
    '09:00',
    'en_atencion',
    'En atención',
    'info',
    'Lucía Arteaga Soliz',
    'Endodoncia unirradicular',
    pro: 'Carlos Méndez',
    proColor: '#7c3aed',
  ),
  _appt(2, '09:30', 'en_espera', 'En sala de espera', 'warning', 'Jorge Mendoza Ríos', 'Consulta y diagnóstico'),
  _appt(3, '10:30', 'confirmada', 'Confirmada', 'primary', 'María Fernanda Rojas', 'Resina simple (1 cara)'),
  _appt(
    4,
    '11:00',
    'agendada',
    'Agendada',
    'secondary',
    'Roberto Chávez Montaño',
    'Radiografía panorámica',
    pro: 'Carlos Méndez',
    proColor: '#7c3aed',
  ),
];

final _client = MockClient((request) async {
  final path = request.url.path;
  if (path.endsWith('/dashboard')) {
    return json({
      'greeting': 'Buenos días',
      'today': {'total': 6, 'waiting': 1, 'done': 2, 'next': _agenda.take(3).toList()},
      'alerts': [
        {'key': 'waiting', 'title': 'En sala de espera', 'count': 1, 'tone': 'warning', 'hint': 'Pacientes que ya llegaron'},
        {'key': 'messages', 'title': 'WhatsApp por enviar', 'count': 5, 'tone': 'success', 'hint': 'Recordatorios, cumpleaños y controles'},
        {'key': 'lab_late', 'title': 'Trabajos de laboratorio atrasados', 'count': 1, 'tone': 'danger'},
      ],
      'finance': {
        'today': 300,
        'sales_today': 2,
        'month': 4250.5,
        'receivable': 150,
        'receivable_overdue': 0,
        'month_delta': {'pct': 12, 'direction': 'up', 'tone': 'good'},
      },
    });
  }
  if (path.endsWith('/clinical/options')) return json(clinicalOptions);
  if (path.endsWith('/reports/summary')) return json(summaryJson());
  if (path.contains('/reports/')) return json(clinicReport(money: true));
  if (path.endsWith('/reports')) return json(reportsMeta(money: true));
  if (path.endsWith('/commissions/1')) return json(commissionsJson);
  if (path.endsWith('/finance/options')) return json(expenseOptionsJson);
  if (path.endsWith('/lab-orders/options')) return json(labOptionsJson);
  if (path.endsWith('/lab-orders/4')) return json(labOrderJson);
  if (path.endsWith('/products/11')) return json(productJson);
  if (path.endsWith('/communications/queue')) return json(queueJson);
  if (path.endsWith('/followups')) return json(followupsJson);
  if (path.endsWith('/sales/options')) return json(salesOptions);
  if (path.endsWith('/sales/1')) return json(saleJson());
  if (path.endsWith('/patients/7/pending')) return json(_pending);
  if (path.endsWith('/receivables')) return json(_receivables);
  if (path.endsWith('/sales')) return json(_sales);
  if (path.endsWith('/consultations/9')) return json(_consultation);
  if (path.endsWith('/patients/7/odontogram')) return json(_consultation['odontogram']);
  if (path.endsWith('/appointments/3')) {
    return json({
      ..._agenda[2],
      'history': [
        {'description': 'Cita creada', 'at': '2026-11-15T10:00:00', 'user': 'admin_demo'},
      ],
      'reminder': {'message': 'Hola', 'whatsapp_url': 'https://wa.me/1?text=Hola', 'log': true, 'sent_at': null},
    });
  }
  if (path.endsWith('/appointments')) {
    return json({
      'data': _agenda,
      'professionals': [
        {'id': 1, 'name': 'Ana Ruiz', 'color': '#0e9f9a'},
        {'id': 2, 'name': 'Carlos Méndez', 'color': '#7c3aed'},
      ],
    });
  }
  if (path.endsWith('/patients/7')) {
    return json({
      ..._maria,
      'document': 'CI 4567891',
      'birth_date': '1990-03-12',
      'email': 'maria@correo.com',
      'address': 'Av. Banzer 4to anillo',
      'allergies': 'Penicilina',
      'medications': 'Losartán 50 mg',
      'medical_updated_at': '2026-11-10T09:00:00',
    });
  }
  if (path.endsWith('/patients')) {
    return json({
      'data': [
        _maria,
        {..._maria, 'id': 8, 'code': 'HC-000008', 'full_name': 'Jorge Mendoza Ríos', 'age_label': '52 años', 'alerts': []},
        {..._maria, 'id': 9, 'code': 'HC-000009', 'full_name': 'Lucía Arteaga Soliz', 'age_label': '9 años', 'alerts': []},
      ],
      'meta': {'total': 3},
    });
  }
  return json({});
});

Future<void> _shot(WidgetTester tester, Widget home, String name, {Session? session}) async {
  final key = GlobalKey();
  final s =
      session ??
      sessionWith(_client, permissions: _all, features: ['agenda', 'historia_clinica', 'ventas', 'recordatorios', 'estadisticas', 'comisiones']);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light).copyWith(textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto')),
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

const _all = [
  'appointments.view',
  'appointments.create',
  'appointments.edit',
  'patients.view',
  'patients.create',
  'patients.edit',
  'procedures.view',
  'consultations.view',
  'consultations.create',
  'consultations.edit',
  'odontogram.view',
  'odontogram.edit',
  'sales.view',
  'sales.create',
  'sales.delete',
  'receivables.view',
  'receivables.create',
  'communications.view',
  'communications.create',
  'lab_orders.view',
  'lab_orders.create',
  'lab_orders.edit',
  'products.view',
  'inventory.create',
  'expenses.view',
  'expenses.create',
  'reports.finance',
  'reports.view',
  'commissions.view',
  'commissions.create',
];

void main() {
  if (_dir.isEmpty) return;
  setUpAll(() async {
    await initializeDateFormatting('es');
    await _loadFonts();
  });

  testWidgets('capturas', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _shot(tester, const AppShell(), 'app-inicio');
    await _shot(tester, const AgendaScreen(), 'app-agenda');
    await _shot(tester, const AppointmentScreen(id: 3), 'app-cita');
    await _shot(tester, const PatientScreen(id: 7), 'app-paciente');
    await _shot(tester, const PatientSearchScreen(), 'app-pacientes');
    await _shot(tester, const ConsultationScreen(id: 9), 'app-consulta');
    final s = sessionWith(
      _client,
      permissions: _all,
      features: ['agenda', 'historia_clinica', 'ventas', 'recordatorios', 'estadisticas', 'comisiones'],
    );
    await _shot(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('Odontograma')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: OdontogramPanel(api: s.api, patientId: 7, editable: true),
        ),
      ),
      'app-odontograma',
      session: s,
    );
    await _shot(tester, const ChargeScreen(patientId: 7), 'app-cobrar');
    await _shot(tester, const SaleScreen(id: 1), 'app-venta');
    await _shot(tester, const SalesScreen(), 'app-ventas');
    await _shot(tester, const ReceivablesScreen(), 'app-por-cobrar');
    await _shot(tester, const MessagesScreen(), 'app-enviar-hoy');
    await _shot(tester, const FollowupsScreen(), 'app-controles');
    await _shot(tester, const ExpenseFormScreen(group: 'general'), 'app-gasto');
    await _shot(tester, const LabOrderScreen(id: 4), 'app-laboratorio');
    await _shot(tester, const LabOrderFormScreen(patientId: 7, patientName: 'María Fernanda Rojas'), 'app-orden-lab');
    await _shot(tester, const ProductScreen(id: 11), 'app-producto');
    await _shot(tester, const SummaryScreen(), 'app-resumen');
    await _shot(tester, const ProfessionalCommissionsScreen(personalId: 1, since: '2026-11-10'), 'app-comisiones');
    await _shot(tester, const ReportsScreen(), 'app-reportes');
    await _shot(tester, const LoginScreen(), 'app-login');
  });
}
