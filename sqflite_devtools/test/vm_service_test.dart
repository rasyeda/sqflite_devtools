@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_devtools/protocol.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Boots a real Dart isolate, registers a database in it and drives the
/// service extensions the way the DevTools extension does.
void main() {
  late Process app;
  late VmService service;
  late String isolateId;

  setUpAll(() async {
    app = await Process.start(Platform.executable, [
      'run',
      '--enable-vm-service=0',
      '--disable-service-auth-codes',
      'test/fixtures/registered_app.dart',
    ]);

    final uri = Completer<Uri>();
    final ready = Completer<void>();
    app.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      final match = RegExp(r'http://[^\s]+').firstMatch(line);
      if (line.contains('Dart VM service') && match != null && !uri.isCompleted) {
        uri.complete(Uri.parse(match.group(0)!));
      }
      if (line.trim() == 'ready' && !ready.isCompleted) ready.complete();
    });
    app.stderr.transform(utf8.decoder).listen(stderr.write);

    final httpUri = await uri.future.timeout(const Duration(seconds: 30));
    await ready.future.timeout(const Duration(seconds: 30));

    service = await vmServiceConnectUri(
      httpUri.replace(scheme: 'ws', path: '${httpUri.path}ws').toString(),
    );
    final vm = await service.getVM();
    isolateId = vm.isolates!.first.id!;
  });

  tearDownAll(() async {
    await service.dispose();
    app.kill();
  });

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final response = await service.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args,
    );
    return response.json ?? const {};
  }

  test('lists the registered database', () async {
    final databases = (await call(kListDatabases))['databases']! as List<Object?>;
    final ref = DatabaseRef.fromJson(databases.single! as Map<String, Object?>);

    expect(ref.id, 'example.db');
    expect(ref.allowWrite, isFalse);
  });

  test('lists tables and reads rows', () async {
    final tables =
        (await call(kListTables, {Params.database: 'example.db'}))['tables']!
            as List<Object?>;
    expect(
      [
        for (final table in tables)
          TableRef.fromJson(table! as Map<String, Object?>).name,
      ],
      ['product'],
    );

    final result = QueryResult.fromJson(
      await call(kQuery, {
        Params.database: 'example.db',
        Params.sql: 'SELECT name FROM product',
      }),
    );
    expect(result.rows.single.single, 'Kopi susu');
  });

  test('surfaces handler errors as RPC errors', () async {
    await expectLater(
      call(kQuery, {
        Params.database: 'example.db',
        Params.sql: 'DELETE FROM product',
      }),
      throwsA(
        isA<RPCError>().having(
          (e) => jsonDecode(e.details!)['error'] as String,
          'error detail',
          contains('registered read-only'),
        ),
      ),
    );
  });
}
