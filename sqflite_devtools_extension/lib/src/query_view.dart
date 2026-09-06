import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_devtools/protocol.dart';

import 'result_grid.dart';
import 'sqlite_client.dart';

/// A SQL editor with the result of the last run below it.
class QueryView extends StatefulWidget {
  const QueryView({
    super.key,
    required this.client,
    required this.database,
  });

  final SqliteClient client;
  final DatabaseRef database;

  @override
  State<QueryView> createState() => _QueryViewState();
}

class _QueryViewState extends State<QueryView> {
  final TextEditingController _controller = TextEditingController();
  Future<QueryResult>? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run() {
    final sql = _controller.text.trim();
    if (sql.isEmpty) return;
    setState(() {
      _result = widget.client.query(widget.database.id, sql);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SplitPane(
      axis: Axis.vertical,
      initialFractions: const [0.35, 0.65],
      minSizes: const [120, 120],
      children: [
        Padding(
          padding: const EdgeInsets.all(denseSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    // Cmd/Ctrl+Enter runs, so the editor keeps plain Enter for
                    // newlines.
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _run,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _run,
                  },
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.fixedFontStyle,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'SELECT * FROM …',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: denseSpacing),
              Row(
                children: [
                  DevToolsButton(
                    icon: Icons.play_arrow,
                    label: 'Run',
                    onPressed: _run,
                  ),
                  const SizedBox(width: denseSpacing),
                  Text(
                    widget.database.allowWrite
                        ? 'Cmd/Ctrl+Enter to run.'
                        : 'Cmd/Ctrl+Enter to run. Read-only: writes are rejected.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        _ResultPane(result: _result),
      ],
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({required this.result});

  final Future<QueryResult>? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (result == null) {
      return Center(
        child: Text(
          'Run a statement to see its result.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }
    return FutureBuilder<QueryResult>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(defaultSpacing),
            child: SelectableText(
              '${snapshot.error}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          );
        }
        final value = snapshot.data!;
        final elapsed = (value.elapsedMicros / 1000).toStringAsFixed(1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(denseSpacing),
              child: Text(
                value.rowsAffected != null
                    ? '${value.rowsAffected} row(s) affected in $elapsed ms'
                    : '${value.rows.length} row(s) in $elapsed ms'
                        '${value.hasMore ? ' — clipped at $kMaxRows rows' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: value.rowsAffected != null
                  ? const SizedBox.shrink()
                  : ResultGrid(result: value),
            ),
          ],
        );
      },
    );
  }
}
