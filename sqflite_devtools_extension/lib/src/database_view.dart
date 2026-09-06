import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_devtools/protocol.dart';

import 'query_view.dart';
import 'schema_view.dart';
import 'sqlite_client.dart';
import 'table_data_view.dart';

/// Table list on the left, details of the selected table on the right.
class DatabaseView extends StatefulWidget {
  const DatabaseView({
    super.key,
    required this.client,
    required this.database,
  });

  final SqliteClient client;
  final DatabaseRef database;

  @override
  State<DatabaseView> createState() => _DatabaseViewState();
}

class _DatabaseViewState extends State<DatabaseView> {
  final TextEditingController _filterController = TextEditingController();

  late Future<List<TableRef>> _tables;
  TableRef? _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _tables = widget.client.listTables(widget.database.id);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TableRef>>(
      future: _tables,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final tables = snapshot.data ?? const <TableRef>[];
        final visible = tables
            .where((t) => t.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList();
        final fallback = visible.isNotEmpty
            ? visible.first
            : (tables.isEmpty ? null : tables.first);
        final selected = _selected != null && tables.contains(_selected)
            ? _selected
            : fallback;

        return SplitPane(
          axis: Axis.horizontal,
          initialFractions: const [0.25, 0.75],
          minSizes: const [180, 320],
          children: [
            _TableList(
              tables: visible,
              selected: selected,
              controller: _filterController,
              onFilterChanged: (value) => setState(() => _filter = value),
              onSelected: (table) => setState(() => _selected = table),
            ),
            _DetailPane(
              client: widget.client,
              database: widget.database,
              table: selected,
            ),
          ],
        );
      },
    );
  }
}

class _TableList extends StatelessWidget {
  const _TableList({
    required this.tables,
    required this.selected,
    required this.controller,
    required this.onFilterChanged,
    required this.onSelected,
  });

  final List<TableRef> tables;
  final TableRef? selected;

  /// Owned by the parent state: rebuilding this widget must not reset the
  /// text the user has typed.
  final TextEditingController controller;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<TableRef> onSelected;

  @override
  Widget build(BuildContext context) {
    return RoundedOutlinedBorder(
      child: Column(
        children: [
          AreaPaneHeader(
            title: Text('Tables (${tables.length})'),
            includeTopBorder: false,
          ),
          Padding(
            padding: const EdgeInsets.all(denseSpacing),
            child: DevToolsClearableTextField(
              controller: controller,
              labelText: 'Filter',
              onChanged: onFilterChanged,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tables.length,
              itemBuilder: (context, index) {
                final table = tables[index];
                return ListTile(
                  dense: true,
                  selected: table.name == selected?.name,
                  leading: Icon(
                    table.isView
                        ? Icons.visibility_outlined
                        : Icons.table_rows_outlined,
                    size: defaultIconSize,
                  ),
                  title: Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelected(table),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPane extends StatefulWidget {
  const _DetailPane({
    required this.client,
    required this.database,
    required this.table,
  });

  final SqliteClient client;
  final DatabaseRef database;
  final TableRef? table;

  @override
  State<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<_DetailPane> {
  Future<TableInfo>? _info;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void didUpdateWidget(_DetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table?.name != widget.table?.name) {
      _loadInfo();
    }
  }

  void _loadInfo() {
    final table = widget.table;
    _info = table == null
        ? null
        : widget.client.tableInfo(widget.database.id, table.name);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Data'),
              Tab(text: 'Schema'),
              Tab(text: 'SQL'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _withInfo(
                  (info) => TableDataView(
                    client: widget.client,
                    database: widget.database,
                    info: info,
                  ),
                ),
                _withInfo((info) => SchemaView(info: info)),
                QueryView(
                  client: widget.client,
                  database: widget.database,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _withInfo(Widget Function(TableInfo info) builder) {
    final info = _info;
    if (info == null) {
      return const Center(child: Text('Select a table.'));
    }
    return FutureBuilder<TableInfo>(
      future: info,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        return builder(snapshot.data!);
      },
    );
  }
}
