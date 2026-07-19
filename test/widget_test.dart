// Basic widget test — verifies SpectraApp can build correctly
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';

import 'package:spectra/app.dart';
import 'package:spectra/data/database/app_database.dart';
import 'package:spectra/providers/providers.dart';

void main() {
  testWidgets('SpectraApp 可以正常构建', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const SpectraApp(),
      ),
    );
    // Pump to wait for async providers to complete
    await tester.pumpAndSettle();
    // Verify menu bar exists (File menu)
    expect(find.text('File'), findsOneWidget);
    await db.close();
  });
}
