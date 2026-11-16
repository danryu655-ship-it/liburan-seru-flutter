import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liburan_seru/main.dart';

void main() {
  testWidgets('Liburan Seru tampil', (WidgetTester tester) async {
    await tester.pumpWidget(const LiburanSeruApp());
    await tester.pumpAndSettle();
    expect(find.text('Liburan Seru'), findsWidgets);
    expect(find.text('Tambah Titipan'), findsOneWidget);
  });
}
