import 'package:sqflite_common/sqlite_api.dart';

import '../protocol.dart';

/// A database the app handed to `SqfliteDevTools.register`.
class RegisteredDatabase {
  RegisteredDatabase({
    required this.id,
    required this.label,
    required this.database,
    required this.allowWrite,
  });

  final String id;
  final String label;
  final DatabaseExecutor database;

  /// When false, statements that are not read-only are rejected.
  final bool allowWrite;

  String? get path {
    final db = database;
    return db is Database ? db.path : null;
  }

  DatabaseRef toRef() => DatabaseRef(
        id: id,
        label: label,
        path: path,
        allowWrite: allowWrite,
      );
}
