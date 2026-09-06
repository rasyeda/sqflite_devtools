import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_devtools/protocol.dart';

/// Columns, indexes and the `CREATE` statement of one table.
class SchemaView extends StatelessWidget {
  const SchemaView({super.key, required this.info});

  final TableInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(denseSpacing),
      children: [
        Text('Columns', style: theme.textTheme.titleSmall),
        const SizedBox(height: denseSpacing),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: defaultRowHeight + denseSpacing,
            dataRowMinHeight: defaultRowHeight,
            dataRowMaxHeight: defaultRowHeight + denseSpacing,
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Nullable')),
              DataColumn(label: Text('Key')),
              DataColumn(label: Text('Default')),
            ],
            rows: [
              for (final column in info.columns)
                DataRow(
                  cells: [
                    DataCell(Text(column.name)),
                    DataCell(Text(column.type.isEmpty ? '—' : column.type)),
                    DataCell(Text(column.notNull ? 'NOT NULL' : 'NULL')),
                    DataCell(Text(column.primaryKey ? 'PK' : '')),
                    DataCell(Text(column.defaultValue ?? '—')),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: defaultSpacing),
        Text('Indexes', style: theme.textTheme.titleSmall),
        const SizedBox(height: denseSpacing),
        if (info.indexes.isEmpty)
          Text('None', style: theme.textTheme.bodySmall)
        else
          for (final index in info.indexes)
            Padding(
              padding: const EdgeInsets.only(bottom: densePadding),
              child: Text(
                '${index.unique ? 'UNIQUE ' : ''}${index.name} '
                '(${index.columns.join(', ')})',
                style: theme.textTheme.bodySmall,
              ),
            ),
        if (info.sql != null) ...[
          const SizedBox(height: defaultSpacing),
          Text('SQL', style: theme.textTheme.titleSmall),
          const SizedBox(height: denseSpacing),
          RoundedOutlinedBorder(
            child: Padding(
              padding: const EdgeInsets.all(denseSpacing),
              child: SelectableText(
                info.sql!,
                style: theme.fixedFontStyle,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
