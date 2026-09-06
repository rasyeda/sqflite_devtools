import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_devtools/protocol.dart';

import 'database_view.dart';
import 'sqlite_client.dart';

/// Root of the extension: picks a database, then hands off to [DatabaseView].
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  final SqliteClient _client = SqliteClient();

  late Future<List<DatabaseRef>> _databases;
  DatabaseRef? _selected;

  @override
  void initState() {
    super.initState();
    _databases = _load();
  }

  Future<List<DatabaseRef>> _load() async {
    final databases = await _client.listDatabases();
    _selected = databases.firstWhereOrNullBy((db) => db.id == _selected?.id) ??
        (databases.isEmpty ? null : databases.first);
    return databases;
  }

  void _refresh() {
    setState(() => _databases = _load());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectedState>(
      valueListenable: serviceManager.connectedState,
      builder: (context, state, _) {
        if (!state.connected) {
          return const _Message(
            icon: Icons.link_off,
            title: 'No app connected',
            detail: 'Connect DevTools to a running app to explore its '
                'databases.',
          );
        }
        return _buildDatabases(context);
      },
    );
  }

  Widget _buildDatabases(BuildContext context) {
    return FutureBuilder<List<DatabaseRef>>(
      future: _databases,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error!, onRetry: _refresh);
        }
        final databases = snapshot.data ?? const <DatabaseRef>[];
        if (databases.isEmpty) {
          return _EmptyState(onRetry: _refresh);
        }
        final selected = _selected ?? databases.first;
        return Column(
          children: [
            _Toolbar(
              databases: databases,
              selected: selected,
              onSelected: (db) => setState(() => _selected = db),
              onRefresh: _refresh,
            ),
            Expanded(
              child: DatabaseView(
                key: ValueKey(selected.id),
                client: _client,
                database: selected,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.databases,
    required this.selected,
    required this.onSelected,
    required this.onRefresh,
  });

  final List<DatabaseRef> databases;
  final DatabaseRef selected;
  final ValueChanged<DatabaseRef> onSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(denseSpacing),
      child: Row(
        children: [
          RoundedDropDownButton<DatabaseRef>(
            value: selected,
            items: [
              for (final database in databases)
                DropdownMenuItem(
                  value: database,
                  child: Text(database.label),
                ),
            ],
            onChanged: (database) {
              if (database != null) onSelected(database);
            },
          ),
          const SizedBox(width: denseSpacing),
          if (selected.path != null)
            Expanded(
              child: Text(
                selected.path!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            )
          else
            const Spacer(),
          if (!selected.allowWrite)
            Padding(
              padding: const EdgeInsets.only(right: denseSpacing),
              child: Tooltip(
                message: 'Registered read-only. Pass allowWrite: true to '
                    'SqfliteDevTools.register to run write statements.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: defaultIconSize),
                    const SizedBox(width: densePadding),
                    Text('Read-only', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          DevToolsButton(
            icon: Icons.refresh,
            label: 'Refresh',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.storage_outlined,
      title: 'No databases registered',
      detail: 'Call SqfliteDevTools.register(db, label: \'app.db\') after '
          'opening a database, then refresh.',
      onRetry: onRetry,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final missingRuntime = error is SqliteClientException &&
        (error as SqliteClientException).isMissingRuntime;
    return _Message(
      icon: missingRuntime ? Icons.link_off : Icons.error_outline,
      title: missingRuntime
          ? 'App is not exposing any database'
          : 'Failed to load databases',
      detail: '$error',
      onRetry: onRetry,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: defaultIconSize * 2, color: theme.hintColor),
            const SizedBox(height: defaultSpacing),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: denseSpacing),
            Text(
              detail,
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: defaultSpacing),
              DevToolsButton(
                icon: Icons.refresh,
                label: 'Retry',
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? firstWhereOrNullBy(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
