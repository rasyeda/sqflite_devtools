import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:sqflite_common/sqlite_api.dart';

import '../protocol.dart';
import 'handlers.dart';
import 'registered_database.dart';

/// True in a release (product) build, where the VM service is unavailable.
const bool _isProduct = bool.fromEnvironment('dart.vm.product');

/// Exposes sqflite databases to the `sqflite_devtools` DevTools extension.
///
/// Register each database once it is open, ideally right after `openDatabase`:
///
/// ```dart
/// final db = await openDatabase('majoo.db');
/// SqfliteDevTools.register(db, label: 'majoo.db');
/// ```
///
/// Every method is a no-op in release builds, so the calls can stay in
/// production code — but the database is still reachable by anyone who can
/// attach a debugger to a debug or profile build, so prefer guarding
/// registration with `kDebugMode` for databases holding sensitive data.
abstract final class SqfliteDevTools {
  static final Map<String, RegisteredDatabase> _databases = {};
  static bool _serviceExtensionsInstalled = false;

  /// Whether service extensions can be installed at all — false in release.
  static bool get isAvailable => !_isProduct;

  /// Ids of the currently registered databases, in registration order.
  static List<String> get registeredIds => _databases.keys.toList();

  /// Makes [database] visible in the DevTools extension.
  ///
  /// [label] is what the extension shows; [id] defaults to it and must be
  /// unique. Set [allowWrite] to also permit `INSERT`/`UPDATE`/`DELETE` and
  /// DDL from the extension's query editor.
  static void register(
    DatabaseExecutor database, {
    required String label,
    String? id,
    bool allowWrite = false,
  }) {
    if (_isProduct) return;
    final key = id ?? label;
    _databases[key] = RegisteredDatabase(
      id: key,
      label: label,
      database: database,
      allowWrite: allowWrite,
    );
    _installServiceExtensions();
  }

  /// Removes a database registered under [id]; call this before closing it.
  static void unregister(String id) {
    _databases.remove(id);
  }

  /// Removes every registered database.
  static void unregisterAll() {
    _databases.clear();
  }

  static void _installServiceExtensions() {
    if (_serviceExtensionsInstalled) return;
    _serviceExtensionsInstalled = true;

    _registerHandler(kListDatabases, (params) async {
      return {
        'databases': [
          for (final entry in _databases.values) entry.toRef().toJson(),
        ],
      };
    });

    _registerHandler(kListTables, (params) async {
      return handleListTables(_lookup(params));
    });

    _registerHandler(kTableInfo, (params) async {
      final table = params[Params.table];
      if (table == null) {
        throw ArgumentError.notNull(Params.table);
      }
      return handleTableInfo(_lookup(params), table);
    });

    _registerHandler(kQuery, (params) async {
      final sql = params[Params.sql];
      if (sql == null) {
        throw ArgumentError.notNull(Params.sql);
      }
      return handleQuery(
        _lookup(params),
        sql: sql,
        limit: int.tryParse(params[Params.limit] ?? ''),
      );
    });
  }

  static RegisteredDatabase _lookup(Map<String, String> params) {
    final id = params[Params.database];
    if (id == null) {
      throw ArgumentError.notNull(Params.database);
    }
    final entry = _databases[id];
    if (entry == null) {
      throw ArgumentError.value(
        id,
        Params.database,
        'Not registered. Known databases: ${_databases.keys.join(', ')}',
      );
    }
    return entry;
  }

  static void _registerHandler(
    String method,
    Future<Map<String, Object?>> Function(Map<String, String> params) handler,
  ) {
    developer.registerExtension(method, (_, params) async {
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode(await handler(params)),
        );
      } catch (error, stackTrace) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          jsonEncode({'error': '$error', 'stackTrace': '$stackTrace'}),
        );
      }
    });
  }
}
