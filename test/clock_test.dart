import 'package:flutter_test/flutter_test.dart';
import 'package:dexi_movil/core/models.dart';

void main() {
  tearDown(() => CompanyClock.offset = const Duration(hours: -4));

  test('las horas de la API se muestran en la hora de la clínica, no en la del teléfono', () {
    final cita = {'starts_at': '2026-11-16T09:00:00-04:00', 'birth': '2020-05-01'};

    expect(cita.date('starts_at'), DateTime(2026, 11, 16, 9));
    expect(cita.date('birth'), DateTime(2020, 5, 1));
  });

  test('«ahora» es la hora de la clínica según su desfase', () {
    CompanyClock.offset = const Duration(hours: -4);
    final bolivia = companyNow();
    CompanyClock.offset = const Duration(hours: -6);
    final mexico = companyNow();

    expect(bolivia.difference(mexico).inMinutes, closeTo(120, 1));
    final utc = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    expect(mexico.hour, utc.hour);
  });

  test('el perfil trae el desfase y Bolivia es el valor por defecto', () {
    final info = CompanyInfo.fromJson({'id': 1, 'name': 'Vet', 'timezone': 'America/Mexico_City', 'utc_offset': -360});
    expect(info.utcOffset, -360);
    expect(CompanyClock.offset, const Duration(hours: -4));
  });
}
