// Helper app used by vm_service_test.dart: opens an in-memory database,
// registers it, and stays alive until stdin closes.
import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_devtools/sqflite_devtools.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE product (id INTEGER PRIMARY KEY, name TEXT)');
  await db.insert('product', {'name': 'Kopi susu'});

  SqfliteDevTools.register(db, label: 'example.db');

  stdout.writeln('ready');
  await stdin.drain<void>();
}
