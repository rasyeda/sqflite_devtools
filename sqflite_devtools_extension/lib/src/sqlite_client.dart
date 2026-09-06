import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:sqflite_devtools/protocol.dart';
import 'package:vm_service/vm_service.dart';

/// A failure that is worth showing to the user verbatim.
class SqliteClientException implements Exception {
  SqliteClientException(this.message, {this.isMissingRuntime = false});

  final String message;

  /// True when the app never called `SqfliteDevTools.register`.
  final bool isMissingRuntime;

  @override
  String toString() => message;
}

/// Talks to the app's `sqflite_devtools` runtime over the VM service.
class SqliteClient {
  Future<List<DatabaseRef>> listDatabases() async {
    final json = await _call(kListDatabases, const {});
    return [
      for (final entry in json['databases']! as List<Object?>)
        DatabaseRef.fromJson(entry! as Map<String, Object?>),
    ];
  }

  Future<List<TableRef>> listTables(String databaseId) async {
    final json = await _call(kListTables, {Params.database: databaseId});
    return [
      for (final entry in json['tables']! as List<Object?>)
        TableRef.fromJson(entry! as Map<String, Object?>),
    ];
  }

  Future<TableInfo> tableInfo(String databaseId, String table) async {
    return TableInfo.fromJson(
      await _call(kTableInfo, {
        Params.database: databaseId,
        Params.table: table,
      }),
    );
  }

  Future<QueryResult> query(
    String databaseId,
    String sql, {
    int? limit,
  }) async {
    return QueryResult.fromJson(
      await _call(kQuery, {
        Params.database: databaseId,
        Params.sql: sql,
        if (limit != null) Params.limit: '$limit',
      }),
    );
  }

  /// Reads one page of a table, optionally narrowed by a [where] clause built
  /// with [filterClause].
  Future<QueryResult> page(
    String databaseId,
    String table, {
    required int offset,
    int limit = kDefaultPageSize,
    String? orderBy,
    bool descending = false,
    String? where,
  }) {
    final order = orderBy == null
        ? ''
        : ' ORDER BY ${quoteIdentifier(orderBy)}${descending ? ' DESC' : ' ASC'}';
    return query(
      databaseId,
      'SELECT * FROM ${quoteIdentifier(table)}${_where(where)}$order '
      'LIMIT $limit OFFSET $offset',
      limit: limit,
    );
  }

  /// Counts the rows of a table, optionally narrowed by [where].
  Future<int> count(
    String databaseId,
    String table, {
    String? where,
  }) async {
    final result = await query(
      databaseId,
      'SELECT COUNT(*) AS c FROM ${quoteIdentifier(table)}${_where(where)}',
    );
    return result.rows.single.single as int? ?? 0;
  }

  String _where(String? where) =>
      where == null || where.isEmpty ? '' : ' WHERE $where';

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, String> args,
  ) async {
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        method,
        args: args,
      );
      return response.json ?? const {};
    } on RPCError catch (error) {
      throw _translate(error);
    }
  }

  SqliteClientException _translate(RPCError error) {
    // -32601 is the JSON-RPC "method not found" code, which here means the app
    // never registered a database with the runtime.
    if (error.code == RPCErrorKind.kMethodNotFound.code) {
      return SqliteClientException(
        'This app has not registered any database with sqflite_devtools.',
        isMissingRuntime: true,
      );
    }
    final details = error.details;
    if (details != null) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map && decoded['error'] is String) {
          return SqliteClientException(decoded['error'] as String);
        }
      } on FormatException {
        // Fall through to the raw message below.
      }
    }
    return SqliteClientException(error.message);
  }
}
