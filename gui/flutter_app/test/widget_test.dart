import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:douk_gui/pages/splash_page.dart';

void main() {
  testWidgets('app renders splash screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashPage(autoStart: false)),
    );
    expect(find.text('DouK 下载器'), findsOneWidget);
  });
}
