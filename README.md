# Dexi — app móvil (`dexi_movil`)

App Flutter de Dexi para Android e iOS (`net.sczsoft.dexi`). Usa la API `/api/v1`
de `dexi-web`: la app nunca decide permisos, el servidor revalida todo.
Avance y pendientes: [CHECKLIST-MOVIL.md](CHECKLIST-MOVIL.md).

## Correr en desarrollo

1. En `dexi-web`, levantar Laravel visible en la red:
   `php artisan serve --host=0.0.0.0 --port=8000`
2. En `dexi_movil`:
   - Emulador de Android (la PC es `10.0.2.2`): `flutter run`
   - Teléfono en la misma red: `flutter run --dart-define=API_URL=http://<IP-de-tu-PC>:8000/api/v1`
3. Ingresar con un usuario de la clínica (por ejemplo `admin@clinicademo.test` de los datos demo).

Al compilar (`flutter build apk`, `appbundle`, `ipa`) usa producción:
`https://dexi.sczsoft.net/api/v1` (ver `lib/core/config.dart`).

## Estructura

- `lib/core`: configuración, cliente HTTP (token Sanctum y `X-Company-Id`), sesión, modelos y hora de la clínica.
- `lib/ui`: tema (turquesa de Dexi), colores de sección (los mismos del menú web) y piezas comunes.
- `lib/screens`: login, armazón (barra inferior y menú), Inicio, Agenda (día, cita, agendar, sala de espera), Pacientes (búsqueda, ficha en pestañas, alta), Consultas (`consultation_screens.dart`), cobros y cuentas por cobrar (`sales_screens.dart`), «Para enviar hoy» y controles (`communication_screens.dart`), laboratorio (`lab_screens.dart`), inventario con escáner (`inventory_screens.dart`), gastos y cuentas (`finance_screens.dart`), resumen para el dueño y comisiones (`owner_screens.dart`), reportes por sección (`report_screens.dart`), odontograma interactivo (`odontogram.dart`), documentos y fotos (`patient_documents.dart`) y Perfil.

## Pruebas

- `flutter analyze` y `flutter test`.
- Capturas para revisar el diseño (no corren en la suite normal):
  `flutter test test/shots_test.dart --dart-define=SHOTS_DIR=<carpeta> --dart-define=FONTS_DIR=<flutter>/bin/cache/artifacts/material_fonts`

## Logo e íconos

Se generan desde `../recursos/logo.webp` con `php ../recursos/scripts/generar-iconos.php ..` (desde esta carpeta).
