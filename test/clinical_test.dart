import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dexi_movil/screens/consultation_screens.dart';
import 'package:dexi_movil/screens/odontogram.dart';

import 'app_test.dart' show json;
import 'screens_test.dart' show app, sessionWith;

final clinicalOptions = {
  'diagnoses': [
    {'key': 'caries_dentina', 'label': 'Caries de la dentina', 'icd': 'K02.1'},
    {'key': 'pulpitis_reversible', 'label': 'Pulpitis reversible', 'icd': 'K04.0'},
  ],
  'surfaces': [
    {'key': 'O', 'label': 'Oclusal / incisal'},
    {'key': 'M', 'label': 'Mesial'},
    {'key': 'D', 'label': 'Distal'},
    {'key': 'V', 'label': 'Vestibular'},
    {'key': 'L', 'label': 'Lingual / palatino'},
  ],
  'conditions': [
    {'key': 'caries', 'label': 'Caries', 'type': 'hallazgo', 'scope': 'cara', 'symbol': 'fill'},
    {'key': 'obturacion', 'label': 'Obturación / resina', 'type': 'tratamiento', 'scope': 'cara', 'symbol': 'fill'},
    {'key': 'ausente', 'label': 'Ausente', 'type': 'tratamiento', 'scope': 'pieza', 'symbol': 'missing'},
  ],
  'rows': {
    'permanente': [
      [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28],
      [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38],
    ],
    'temporal': [
      [55, 54, 53, 52, 51, 61, 62, 63, 64, 65],
      [85, 84, 83, 82, 81, 71, 72, 73, 74, 75],
    ],
  },
  'marks': {'OPE-01': 'obturacion'},
  'professionals': [
    {'id': 1, 'name': 'Ana Ruiz'},
  ],
};

Map<String, dynamic> consultationJson({bool open = true, List<Map<String, dynamic>> diagnoses = const []}) => {
  'id': 9,
  'code': 'C-000009',
  'status': open ? 'abierta' : 'cerrada',
  'open': open,
  'started_at': '2026-11-17T10:00:00',
  'reason': 'Dolor en molar',
  'patient': {
    'id': 7,
    'full_name': 'María Rojas',
    'whatsapp_link': 'https://wa.me/591700',
    'alerts': [
      {'label': 'Alergia: penicilina', 'critical': true},
    ],
  },
  'professional': {'id': 1, 'name': 'Ana Ruiz'},
  'diagnoses': diagnoses,
  'procedures': [],
  'plan_items': [],
  'previous': [],
  'odontogram': {
    'state': {
      '16': {
        'whole': [],
        'surfaces': {'O': 'caries'},
        'count': 1,
      },
    },
    'summary': {'findings': 1, 'teeth_with_findings': 1, 'missing': 0, 'treatments': 0},
    'dentition': 'permanente',
  },
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(ClinicalCatalog.clear);

  test('cada cara del dibujo es la cara clínica correcta según la arcada y el lado', () {
    // Superior derecha (16): arriba vestibular, abajo palatino, la mesial mira a la línea media (derecha del dibujo).
    expect(faceMap(16), {'top': 'V', 'bottom': 'L', 'left': 'D', 'right': 'M', 'center': 'O'});
    // Inferior izquierda (36): arriba lingual, abajo vestibular, mesial a la izquierda.
    expect(faceMap(36), {'top': 'L', 'bottom': 'V', 'left': 'M', 'right': 'D', 'center': 'O'});
    expect(ToothPainter.surfaceAt(16, const Offset(75, 75), 150), 'O');
    expect(ToothPainter.surfaceAt(16, const Offset(75, 5), 150), 'V');
    expect(ToothPainter.surfaceAt(16, const Offset(145, 75), 150), 'M');
  });

  testWidgets('la consulta muestra las alertas y agrega un diagnóstico del catálogo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? posted;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/clinical/options')) return json(clinicalOptions);
      if (request.method == 'POST' && path.endsWith('/diagnoses')) {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return json(
          consultationJson(
            diagnoses: [
              {'id': 1, 'code': 'caries_dentina', 'label': 'Caries de la dentina', 'icd': 'K02.1', 'tooth': 16},
            ],
          ),
          201,
        );
      }
      return json(consultationJson());
    });
    final session = sessionWith(
      client,
      permissions: ['consultations.view', 'consultations.edit', 'odontogram.view', 'odontogram.edit'],
      features: ['historia_clinica'],
    );

    await tester.pumpWidget(app(session, const ConsultationScreen(id: 9)));
    await tester.pumpAndSettle();

    expect(find.text('Antes de atender'), findsOneWidget);
    expect(find.text('Cerrar consulta'), findsOneWidget);

    await tester.tap(find.text('Diagnósticos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar diagnóstico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caries de la dentina'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Pieza (opcional, FDI: 16, 36, 55…)'), '16');
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(posted, {'code': 'caries_dentina', 'tooth': 16});
    expect(find.textContaining('K02.1'), findsOneWidget);
  });

  testWidgets('en el odontograma se toca un diente, una cara y se registra', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    Map<String, dynamic>? recorded;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/clinical/options')) return json(clinicalOptions);
      if (path.contains('/teeth/')) return json({'tooth': 26, 'name': 'Primer molar superior izquierdo', 'current': [], 'history': []});
      if (request.method == 'POST') {
        recorded = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'state': {}, 'summary': {}, 'message': 'Pieza 26: Caries.'}, 201);
      }
      return json(consultationJson()['odontogram']);
    });
    final session = sessionWith(client, permissions: ['odontogram.view', 'odontogram.edit'], features: ['historia_clinica']);

    await tester.pumpWidget(
      app(
        session,
        Scaffold(
          body: SingleChildScrollView(child: OdontogramPanel(api: session.api, patientId: 7, editable: true, consultationId: 9)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 hallazgo'), findsOneWidget);

    await tester.tap(find.text('26'));
    await tester.pumpAndSettle();
    expect(find.text('Primer molar superior izquierdo'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Caries'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('O · Oclusal'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Registrar caries'), 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Registrar caries'));
    await tester.pumpAndSettle();

    expect(recorded, {
      'tooth': 26,
      'condition': 'caries',
      'surfaces': ['O'],
      'consultation_id': 9,
    });
  });
}
