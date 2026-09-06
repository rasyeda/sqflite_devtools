import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_devtools/protocol.dart';
import 'package:sqflite_devtools/src/handlers.dart';
import 'package:sqflite_devtools/src/registered_database.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  RegisteredDatabase entry({bool allowWrite = false}) => RegisteredDatabase(
        id: 'test',
        label: 'test',
        database: db,
        allowWrite: allowWrite,
      );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE "user order" (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute('CREATE UNIQUE INDEX name_idx ON "user order" (name)');
    await db.execute('CREATE VIEW recent AS SELECT * FROM "user order"');
    await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['ana']);
    await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['budi']);
  });

  tearDown(() async => db.close());

  test('lists tables and views but not sqlite internals', () async {
    final result = await handleListTables(entry());
    final tables = (result['tables']! as List<Object?>)
        .map((e) => TableRef.fromJson(e! as Map<String, Object?>))
        .toList();

    expect(tables.map((t) => t.name), ['user order', 'recent']);
    expect(tables.last.isView, isTrue);
    expect(tables.first.sql, contains('CREATE TABLE'));
  });

  test('describes columns, indexes and row count', () async {
    final info =
        TableInfo.fromJson(await handleTableInfo(entry(), 'user order'));

    expect(info.rowCount, 2);
    expect(info.columns.map((c) => c.name), ['id', 'name']);
    expect(info.columns.first.primaryKey, isTrue);
    expect(info.columns.last.notNull, isTrue);
    expect(info.indexes.single.name, 'name_idx');
    expect(info.indexes.single.unique, isTrue);
    expect(info.indexes.single.columns, ['name']);
  });

  test('rejects an unknown table', () {
    expect(
      () => handleTableInfo(entry(), 'nope'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('returns rows for a read-only statement', () async {
    final result = QueryResult.fromJson(
      await handleQuery(entry(), sql: 'SELECT id, name FROM "user order"'),
    );

    expect(result.columns, ['id', 'name']);
    expect(result.rows, [
      [1, 'ana'],
      [2, 'budi'],
    ]);
    expect(result.hasMore, isFalse);
  });

  test('clips oversized results and reports hasMore', () async {
    final result = QueryResult.fromJson(
      await handleQuery(entry(), sql: 'SELECT * FROM "user order"', limit: 1),
    );

    expect(result.rows, hasLength(1));
    expect(result.hasMore, isTrue);
  });

  test('round-trips a BLOB through the wire format', () async {
    await db.execute('CREATE TABLE blobs (data BLOB)');
    await db.rawInsert('INSERT INTO blobs (data) VALUES (?)', [
      Uint8List.fromList([1, 2, 3]),
    ]);

    final result = QueryResult.fromJson(
      await handleQuery(entry(), sql: 'SELECT data FROM blobs'),
    );

    expect(result.rows.single.single, [1, 2, 3]);
  });

  test('refuses to write unless the database opted in', () {
    expect(
      () => handleQuery(entry(), sql: "DELETE FROM 'user order'"),
      throwsA(isA<StateError>()),
    );
  });

  test('sees past comments when classifying a statement', () {
    expect(
      () => handleQuery(entry(), sql: '-- tidy up\n/* now */ DELETE FROM x'),
      throwsA(isA<StateError>()),
    );
  });

  test('reports affected rows when writing is allowed', () async {
    final result = QueryResult.fromJson(
      await handleQuery(
        entry(allowWrite: true),
        sql: 'UPDATE "user order" SET name = name || \'!\'',
      ),
    );

    expect(result.rowsAffected, 2);
    expect(result.rows, isEmpty);
  });

  group('filterClause', () {
    /// Runs the generated clause the way the extension's paging query does.
    Future<List<Object?>> matches(String text, {List<String>? columns}) async {
      final where = filterClause(
        columns: columns ?? ['id', 'name'],
        text: text,
      );
      final sql = 'SELECT name FROM "user order"'
          '${where == null ? '' : ' WHERE $where'} ORDER BY id';
      final result = QueryResult.fromJson(await handleQuery(entry(), sql: sql));
      return [for (final row in result.rows) row.single];
    }

    test('returns null when there is nothing to filter on', () {
      expect(filterClause(columns: ['a'], text: '   '), isNull);
      expect(filterClause(columns: [], text: 'ana'), isNull);
    });

    test('matches a substring in any column', () async {
      expect(await matches('an'), ['ana']);
      expect(await matches(''), ['ana', 'budi']);
    });

    test('matches numbers by casting columns to text', () async {
      expect(await matches('2', columns: ['id']), ['budi']);
    });

    test('restricts to the chosen column', () async {
      await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['3']);
      expect(await matches('3', columns: ['name']), ['3']);
      expect(await matches('3', columns: ['id']), ['3']);
    });

    test('treats LIKE wildcards as literals', () async {
      await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['a%b']);
      await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['a_b']);
      await db.rawInsert('INSERT INTO "user order" (name) VALUES (?)', ['axb']);

      expect(await matches('a%b'), ['a%b']);
      expect(await matches('a_b'), ['a_b']);
    });

    test('survives quotes and backslashes in the search text', () async {
      await db.rawInsert(
        'INSERT INTO "user order" (name) VALUES (?)',
        [r"o'neil\path"],
      );

      expect(await matches("o'neil"), [r"o'neil\path"]);
      expect(await matches(r'neil\path'), [r"o'neil\path"]);
      expect(await matches("'; DROP TABLE x --"), isEmpty);
    });

    test('quotes column identifiers', () async {
      await db.execute('CREATE TABLE weird ("odd ""name" TEXT)');
      await db.rawInsert('INSERT INTO weird VALUES (?)', ['hit']);

      final where = filterClause(columns: ['odd "name'], text: 'hit');
      final result = QueryResult.fromJson(
        await handleQuery(entry(), sql: 'SELECT * FROM weird WHERE $where'),
      );
      expect(result.rows, hasLength(1));
    });
  });
}
