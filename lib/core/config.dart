import 'package:flutter/foundation.dart';

/// Configuración de compilación.
///
/// - En depuración (`flutter run`) la app usa el servidor local [localApiUrl].
/// - Al compilar (`flutter build apk`, `appbundle`, `ipa`…) usa producción, [productionApiUrl].
///
/// Para usar otra dirección sin tocar este archivo (p. ej. la IP de tu PC en la red):
///   flutter run --dart-define=API_URL=http://192.168.0.13:8000/api/v1
class AppConfig {
  /// Servidor de desarrollo: `php artisan serve --host=0.0.0.0` en la PC.
  /// 10.0.2.2 es la PC vista desde el emulador de Android.
  static const localApiUrl = 'http://192.168.0.13:8090/api/v1';

  /// Servidor de producción.
  static const productionApiUrl = 'https://dexi.sczsoft.net/api/v1';

  static const _override = String.fromEnvironment('API_URL');

  static const apiUrl = _override != '' ? _override : (kDebugMode ? localApiUrl : productionApiUrl);

  static const appName = 'Dexi';
}
