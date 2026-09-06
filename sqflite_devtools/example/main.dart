// Run with:
//   dart run --observe example/main.dart
// then open the printed DevTools URL and enable the sqflite_devtools tab.
import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_devtools/sqflite_devtools.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute(
    'CREATE TABLE product (id INTEGER PRIMARY KEY, name TEXT, price REAL)',
  );
  await db.insert('product', {'name': 'Kopi susu', 'price': 18000.0});
  await db.insert('product', {'name': 'Teh tarik', 'price': 15000.0});

  SqfliteDevTools.register(db, label: 'example.db', allowWrite: true);

  print('Registered: ${SqfliteDevTools.registeredIds}');
  print('Leaving the isolate alive so DevTools can attach…');
  // A pending timer keeps the event loop — and so the VM service — running.
  Timer.periodic(const Duration(minutes: 1), (_) {});
}
