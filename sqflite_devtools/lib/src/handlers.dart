import 'package:sqflite_common/sqlite_api.dart';

import '../protocol.dart';
import 'registered_database.dart';

/// Statement kinds that cannot modify the database.
const Set<String> _readOnlyKeywords = {
  'select',
  'with',
  'pragma',
  'explain',
  'values',
};

/// Lists the tables and views of [entry], hiding SQLite's internal ones.
Future<Map<String, Object?>> handleListTables(RegisteredDatabase entry) async {
  final rows = await entry.database.rawQuery(
    'SELECT name, type, sql FROM sqlite_master '
    "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' "
    'ORDER BY type, name',
  );
  return {
    'tables': [
      for (final row in rows)
        TableRef(
          name: row['name']! as String,
          type: row['type']! as String,
          sql: row['sql'] as String?,
        ).toJson(),
    ],
  };
}

/// Describes one table: columns, indexes and row count.
Future<Map<String, Object?>> handleTableInfo(
  RegisteredDatabase entry,
  String table,
) async {
  final db = entry.database;
  final quoted = quoteIdentifier(table);

  final columnRows = await db.rawQuery('PRAGMA table_info($quoted)');
  if (columnRows.isEmpty) {
    throw ArgumentError.value(table, 'table', 'No such table or view');
  }
  final columns = [
    for (final row in columnRows)
      ColumnInfo(
        name: row['name']! as String,
        type: (row['type'] as String?) ?? '',
        notNull: (row['notnull'] as int? ?? 0) != 0,
        primaryKey: (row['pk'] as int? ?? 0) != 0,
        defaultValue: row['dflt_value']?.toString(),
      ),
  ];

  final indexes = <IndexInfo>[];
  for (final row in await db.rawQuery('PRAGMA index_list($quoted)')) {
    final name = row['name']! as String;
    final members = await db.rawQuery(
      'PRAGMA index_info(${quoteIdentifier(name)})',
    );
    indexes.add(
      IndexInfo(
        name: name,
        unique: (row['unique'] as int? ?? 0) != 0,
        columns: [
          for (final member in members)
            (member['name'] as String?) ?? '?',
        ],
      ),
    );
  }

  final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM $quoted');
  final sqlRows = await db.rawQuery(
    'SELECT sql FROM sqlite_master WHERE name = ?',
    [table],
  );

  return TableInfo(
    name: table,
    columns: columns,
    indexes: indexes,
    rowCount: (countRows.first['c'] as int?) ?? 0,
    sql: sqlRows.isEmpty ? null : sqlRows.first['sql'] as String?,
  ).toJson();
}

/// Runs [sql] against [entry].
///
/// Read-only statements come back as rows, clipped to [kMaxRows]; anything
/// else needs `allowWrite: true` at registration time and reports the number
/// of affected rows instead.
Future<Map<String, Object?>> handleQuery(
  RegisteredDatabase entry, {
  required String sql,
  int? limit,
}) async {
  final statement = sql.trim();
  if (statement.isEmpty) {
    throw ArgumentError.value(sql, 'sql', 'Statement is empty');
  }
  final isReadOnly = _readOnlyKeywords.contains(_leadingKeyword(statement));
  if (!isReadOnly && !entry.allowWrite) {
    throw StateError(
      'Database "${entry.id}" is registered read-only. Pass '
      'allowWrite: true to SqfliteDevTools.register to run this statement.',
    );
  }

  final stopwatch = Stopwatch()..start();
  if (!isReadOnly) {
    final rowsAffected = await _execute(entry.database, statement);
    stopwatch.stop();
    return QueryResult(
      columns: const [],
      rows: const [],
      elapsedMicros: stopwatch.elapsedMicroseconds,
      rowsAffected: rowsAffected,
    ).toJson();
  }

  final result = await entry.database.rawQuery(statement);
  stopwatch.stop();

  final cap = (limit == null || limit > kMaxRows) ? kMaxRows : limit;
  final hasMore = result.length > cap;
  final page = hasMore ? result.sublist(0, cap) : result;
  final columns = page.isEmpty ? <String>[] : page.first.keys.toList();

  return QueryResult(
    columns: columns,
    rows: [
      for (final row in page) [for (final column in columns) row[column]],
    ],
    elapsedMicros: stopwatch.elapsedMicroseconds,
    hasMore: hasMore,
  ).toJson();
}

Future<int> _execute(DatabaseExecutor db, String statement) async {
  switch (_leadingKeyword(statement)) {
    case 'insert':
    case 'update':
    case 'delete':
    case 'replace':
      return db.rawUpdate(statement);
    default:
      await db.execute(statement);
      return 0;
  }
}

/// First keyword of [statement], skipping `--` and `/* */` comments.
String _leadingKeyword(String statement) {
  var index = 0;
  while (index < statement.length) {
    final rest = statement.substring(index);
    if (rest.startsWith('--')) {
      final newline = rest.indexOf('\n');
      if (newline == -1) return '';
      index += newline + 1;
    } else if (rest.startsWith('/*')) {
      final close = rest.indexOf('*/');
      if (close == -1) return '';
      index += close + 2;
    } else if (rest.trimLeft().length != rest.length) {
      index += rest.length - rest.trimLeft().length;
    } else {
      break;
    }
  }
  final match = RegExp(r'^[a-zA-Z]+').firstMatch(statement.substring(index));
  return match?.group(0)!.toLowerCase() ?? '';
}
