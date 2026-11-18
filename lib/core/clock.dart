/// Hora de la clínica activa.
///
/// La agenda y los registros van en la hora local de la clínica (su país;
/// Bolivia por defecto), no en la del teléfono: alguien de viaje o con el
/// teléfono en otra zona debe ver la cita de las 9:00 a las 9:00.
///
/// Las fechas se manejan como «hora de pared»: un DateTime sin zona con la hora
/// que marca el reloj de la clínica.
class CompanyClock {
  /// Desfase de la clínica respecto de UTC. Bolivia (UTC−4) hasta que llegue el perfil.
  static Duration offset = const Duration(hours: -4);
}

/// La hora actual en la clínica.
DateTime companyNow() {
  final t = DateTime.now().toUtc().add(CompanyClock.offset);
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond);
}

/// Lee una fecha de la API como hora de pared de la clínica.
///
/// El servidor ya manda la hora local de la clínica con su desfase
/// (`2026-11-16T09:00:00-04:00`): se toma la hora tal cual, sin convertirla a la
/// zona del teléfono.
DateTime? parseCompanyTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  if (iso.length >= 19 && iso[10] == 'T') return DateTime.tryParse(iso.substring(0, 19));
  return DateTime.tryParse(iso);
}
