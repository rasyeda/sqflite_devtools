import 'dart:convert';

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_devtools/protocol.dart';

/// Renders a [QueryResult] as a scrollable grid.
class ResultGrid extends StatelessWidget {
  const ResultGrid({super.key, required this.result});

  final QueryResult result;

  @override
  Widget build(BuildContext context) {
    if (result.columns.isEmpty) {
      return const Center(child: Text('No columns to show.'));
    }
    if (result.rows.isEmpty) {
      return const Center(child: Text('No rows.'));
    }

    final theme = Theme.of(context);
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: defaultRowHeight + denseSpacing,
            dataRowMinHeight: defaultRowHeight,
            dataRowMaxHeight: defaultRowHeight + denseSpacing,
            columnSpacing: defaultSpacing * 2,
            columns: [
              for (final column in result.columns)
                DataColumn(
                  label: Text(column, style: theme.textTheme.titleSmall),
                ),
            ],
            rows: [
              for (final row in result.rows)
                DataRow(
                  cells: [
                    for (final cell in row) DataCell(_Cell(value: cell)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = formatValue(value);
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Copied')),
            );
          }
        },
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: value == null
              ? theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic, color: theme.hintColor)
              : null,
        ),
      ),
    );
  }
}

/// Renders one SQLite cell for display.
String formatValue(Object? value) {
  if (value == null) return 'NULL';
  if (value is Uint8List || value is List<int>) {
    final bytes = value as List<int>;
    final preview = base64Encode(bytes.take(24).toList());
    return 'BLOB(${bytes.length}) $preview${bytes.length > 24 ? '…' : ''}';
  }
  return '$value';
}
