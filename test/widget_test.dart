import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liburan_seru/main.dart';

void main() {
  testWidgets('Liburan Seru tampil', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LiburanSeruApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Liburan Seru'), findsWidgets);
    expect(find.text('Pesanan'), findsWidgets);
    expect(find.text('Jastip'), findsOneWidget);
    expect(find.text('Kurs'), findsOneWidget);
  });
}
