import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dexi_movil/ui/common.dart';

void main() {
  testWidgets('sin logo propio, la clínica muestra el diente de Dexi', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CompanyLogo(url: null))));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/images/logo_mark.png');
  });

  testWidgets('con logo propio, se usa el de la clínica', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CompanyLogo(url: 'https://dexi.test/storage/logo.png')),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://dexi.test/storage/logo.png');
  });
}
