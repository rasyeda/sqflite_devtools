/// Wire protocol shared by the app-side runtime and the DevTools extension.
///
/// This library deliberately imports nothing from `sqflite` or `dart:developer`
/// so that the DevTools extension (a Flutter **web** app) can depend on it too,
/// keeping method names and JSON keys in a single place.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Prefix required by the VM service for user-defined service extensions.
const String kServiceExtensionPrefix = 'ext.sqflite_devtools.';

/// Lists the databases registered with `SqfliteDevTools.register`.
const String kListDatabases = '${kServiceExtensionPrefix}listDatabases';

/// Lists the tables and views of one database.
const String kListTables = '${kServiceExtensionPrefix}listTables';

/// Returns columns, indexes and the row count of one table.
const String kTableInfo = '${kServiceExtensionPrefix}tableInfo';

/// Runs an arbitrary SQL statement.
const String kQuery = '${kServiceExtensionPrefix}query';

/// Every service extension parameter is a `String`; these are the keys.
abstract final class Params {
  static const String database = 'database';
  static const String table = 'table';
  static const String sql = 'sql';
  static const String limit = 'limit';
  static const String offset = 'offset';
}

/// Maximum number of rows a single [kQuery] response will carry.
///
/// Results cross the VM service as one JSON string, so an unbounded
/// `SELECT * FROM huge_table` would stall DevTools. The runtime truncates and
/// reports [QueryResult.hasMore] instead.
const int kMaxRows = 500;

/// Default page size used by the extension when browsing a table.
const int kDefaultPageSize = 100;

/// A database registered by the app.
class DatabaseRef {
  const DatabaseRef({
    required this.id,
    required this.label,
    this.path,
    this.allowWrite = false,
  });

  factory DatabaseRef.fromJson(Map<String, Object?> json) => DatabaseRef(
        id: json['id']! as String,
        label: json['label']! as String,
        path: json['path'] as String?,
        allowWrite: json['allowWrite'] as bool? ?? false,
      );

  final String id;
  final String label;

  /// Absolute path on the device, when the database exposes one.
  final String? path;

  /// Whether the app opted in to statements that modify data.
  final bool allowWrite;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'path': path,
        'allowWrite': allowWrite,
      };
}

/// A table or view inside a database.
class TableRef {
  const TableRef({required this.name, required this.type, this.sql});

  factory TableRef.fromJson(Map<String, Object?> json) => TableRef(
        name: json['name']! as String,
        type: json['type']! as String,
        sql: json['sql'] as String?,
      );

  final String name;

  /// Either `table` or `view`.
  final String type;

  /// The `CREATE …` statement recorded in `sqlite_master`.
  final String? sql;

  bool get isView => type == 'view';

  Map<String, Object?> toJson() => {'name': name, 'type': type, 'sql': sql};
}

/// One column of a table, as reported by `PRAGMA table_info`.
class ColumnInfo {
  const ColumnInfo({
    required this.name,
    required this.type,
    required this.notNull,
    required this.primaryKey,
    this.defaultValue,
  });

  factory ColumnInfo.fromJson(Map<String, Object?> json) => ColumnInfo(
        name: json['name']! as String,
        type: json['type'] as String? ?? '',
        notNull: json['notNull'] as bool? ?? false,
        primaryKey: json['primaryKey'] as bool? ?? false,
        defaultValue: json['defaultValue'] as String?,
      );

  final String name;
  final String type;
  final bool notNull;
  final bool primaryKey;
  final String? defaultValue;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type,
        'notNull': notNull,
        'primaryKey': primaryKey,
        'defaultValue': defaultValue,
      };
}

/// One index of a table, as reported by `PRAGMA index_list` / `index_info`.
class IndexInfo {
  const IndexInfo({
    required this.name,
    required this.unique,
    required this.columns,
  });

  factory IndexInfo.fromJson(Map<String, Object?> json) => IndexInfo(
        name: json['name']! as String,
        unique: json['unique'] as bool? ?? false,
        columns: (json['columns'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(),
      );

  final String name;
  final bool unique;
  final List<String> columns;

  Map<String, Object?> toJson() => {
        'name': name,
        'unique': unique,
        'columns': columns,
      };
}

/// Schema of a single table.
class TableInfo {
  const TableInfo({
    required this.name,
    required this.columns,
    required this.indexes,
    required this.rowCount,
    this.sql,
  });

  factory TableInfo.fromJson(Map<String, Object?> json) => TableInfo(
        name: json['name']! as String,
        columns: (json['columns']! as List<Object?>)
            .map((e) => ColumnInfo.fromJson(e! as Map<String, Object?>))
            .toList(),
        indexes: (json['indexes']! as List<Object?>)
            .map((e) => IndexInfo.fromJson(e! as Map<String, Object?>))
            .toList(),
        rowCount: json['rowCount']! as int,
        sql: json['sql'] as String?,
      );

  final String name;
  final List<ColumnInfo> columns;
  final List<IndexInfo> indexes;
  final int rowCount;
  final String? sql;

  Map<String, Object?> toJson() => {
        'name': name,
        'columns': [for (final c in columns) c.toJson()],
        'indexes': [for (final i in indexes) i.toJson()],
        'rowCount': rowCount,
        'sql': sql,
      };
}

/// The outcome of a [kQuery] call.
class QueryResult {
  const QueryResult({
    required this.columns,
    required this.rows,
    required this.elapsedMicros,
    this.hasMore = false,
    this.rowsAffected,
  });

  factory QueryResult.fromJson(Map<String, Object?> json) => QueryResult(
        columns: (json['columns']! as List<Object?>).cast<String>().toList(),
        rows: [
          for (final row in json['rows']! as List<Object?>)
            (row! as List<Object?>).map(decodeValue).toList(),
        ],
        elapsedMicros: json['elapsedMicros']! as int,
        hasMore: json['hasMore'] as bool? ?? false,
        rowsAffected: json['rowsAffected'] as int?,
      );

  final List<String> columns;

  /// Row-major cells, already decoded with [decodeValue].
  final List<List<Object?>> rows;
  final int elapsedMicros;

  /// True when the result was clipped at [kMaxRows].
  final bool hasMore;

  /// Set instead of [rows] for statements that write.
  final int? rowsAffected;

  Map<String, Object?> toJson() => {
        'columns': columns,
        'rows': [
          for (final row in rows) [for (final cell in row) encodeValue(cell)],
        ],
        'elapsedMicros': elapsedMicros,
        'hasMore': hasMore,
        'rowsAffected': rowsAffected,
      };
}

/// Key used to tag a BLOB cell, which JSON cannot represent directly.
const String kBlobKey = r'$blob';

/// Encodes one SQLite cell into something `jsonEncode` accepts.
Object? encodeValue(Object? value) {
  if (value is Uint8List) {
    return {kBlobKey: base64Encode(value)};
  }
  if (value is List<int>) {
    return {kBlobKey: base64Encode(value)};
  }
  return value;
}

/// Reverses [encodeValue].
Object? decodeValue(Object? value) {
  if (value is Map && value.containsKey(kBlobKey)) {
    return base64Decode(value[kBlobKey]! as String);
  }
  return value;
}

/// Quotes an identifier so table and column names with spaces, quotes or
/// reserved words are safe to interpolate into SQL.
String quoteIdentifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Builds a `WHERE` fragment matching [text] anywhere in [columns].
///
/// Every column is cast to text, so numeric and date columns match too.
/// Returns null when there is nothing to filter on.
String? filterClause({
  required List<String> columns,
  required String text,
}) {
  final value = text.trim();
  if (value.isEmpty || columns.isEmpty) return null;

  // Escape the LIKE wildcards first, then the SQL string delimiter.
  final pattern = value
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll("'", "''");
  return [
    for (final column in columns)
      "CAST(${quoteIdentifier(column)} AS TEXT) LIKE '%$pattern%' ESCAPE '\\'",
  ].join(' OR ');
}
