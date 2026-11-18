import 'package:flutter/material.dart';

/// Secciones del menú con su color: las mismas de la web
/// (dexi-web/app/Support/Navigation.php). Quien aprende que «violeta es Agenda»
/// o «naranja es Ventas» se ubica igual en la web y en la app.
enum NavGroup {
  inicio('Inicio', Icons.home_outlined, Color(0xFF0E9F9A)),
  pacientes('Pacientes', Icons.people_outline, Color(0xFF2563EB)),
  agenda('Agenda', Icons.calendar_month_outlined, Color(0xFF7C3AED)),
  clinica('Atención clínica', Icons.medical_services_outlined, Color(0xFF059669)),
  ventas('Ventas y caja', Icons.payments_outlined, Color(0xFFEA580C)),
  finanzas('Finanzas', Icons.account_balance_outlined, Color(0xFFCA8A04)),
  inventario('Inventario', Icons.inventory_2_outlined, Color(0xFF9333EA)),
  equipo('Equipo', Icons.badge_outlined, Color(0xFF4F46E5)),
  comunicaciones('Comunicaciones', Icons.campaign_outlined, Color(0xFFE11D48)),
  reportes('Reportes', Icons.insights_outlined, Color(0xFF0284C7)),
  cuenta('Cuenta', Icons.tune, Color(0xFF475569));

  const NavGroup(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// El color para texto: más oscuro en tema claro y más claro en oscuro, legible en ambos.
  Color ink(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Color.lerp(color, Colors.white, .35)! : Color.lerp(color, Colors.black, .18)!;

  /// Fondo suave del color de la sección.
  Color soft(BuildContext context, [double alpha = .12]) => color.withValues(alpha: alpha);
}
