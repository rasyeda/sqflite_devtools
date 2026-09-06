import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_devtools/protocol.dart';

import 'result_grid.dart';
import 'sqlite_client.dart';

/// How long to wait after the last keystroke before querying again.
const Duration _filterDebounce = Duration(milliseconds: 300);

/// A paged, filterable view of the rows of one table.
class TableDataView extends StatefulWidget {
  const TableDataView({
    super.key,
    required this.client,
    required this.database,
    required this.info,
  });

  final SqliteClient client;
  final DatabaseRef database;
  final TableInfo info;

  @override
  State<TableDataView> createState() => _TableDataViewState();
}

/// One resolved page, together with the row count it was paged against.
class _Page {
  const _Page(this.result, this.total);

  final QueryResult result;
  final int total;
}

class _TableDataViewState extends State<TableDataView> {
  final TextEditingController _filterController = TextEditingController();

  Timer? _debounce;
  int _offset = 0;
  String? _orderBy;
  bool _descending = false;

  /// Column the filter applies to; null means every column.
  String? _filterColumn;
  String _filterText = '';

  late Future<_Page> _page;

  /// Last resolved page, so the toolbar keeps its numbers while reloading.
  _Page? _lastPage;

  @override
  void initState() {
    super.initState();
    _page = _fetch();
  }

  @override
  void didUpdateWidget(TableDataView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.name != widget.info.name) {
      _offset = 0;
      _orderBy = null;
      _filterColumn = null;
      _filterText = '';
      _filterController.clear();
      _lastPage = null;
      _reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  String? get _where => filterClause(
        columns: _filterColumn != null
            ? [_filterColumn!]
            : [for (final column in widget.info.columns) column.name],
        text: _filterText,
      );

  Future<_Page> _fetch() async {
    final where = _where;
    // An unfiltered count is already in the schema; a filtered one is not.
    final total = where == null
        ? widget.info.rowCount
        : await widget.client.count(
            widget.database.id,
            widget.info.name,
            where: where,
          );
    final result = await widget.client.page(
      widget.database.id,
      widget.info.name,
      offset: _offset,
      orderBy: _orderBy,
      descending: _descending,
      where: where,
    );
    return _lastPage = _Page(result, total);
  }

  void _reload() => setState(() => _page = _fetch());

  void _goTo(int offset, int total) {
    _offset = offset.clamp(0, _lastPageOffset(total));
    _reload();
  }

  void _onFilterChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_filterDebounce, () {
      if (!mounted) return;
      _filterText = text;
      _offset = 0;
      _reload();
    });
  }

  int _lastPageOffset(int total) {
    if (total == 0) return 0;
    return ((total - 1) ~/ kDefaultPageSize) * kDefaultPageSize;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Page>(
      future: _page,
      builder: (context, snapshot) {
        final page = snapshot.data ?? _lastPage;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        return Column(
          children: [
            _FilterBar(
              controller: _filterController,
              columns: widget.info.columns,
              column: _filterColumn,
              onTextChanged: _onFilterChanged,
              onColumnChanged: (column) {
                setState(() => _filterColumn = column);
                _offset = 0;
                _reload();
              },
            ),
            _Toolbar(
              total: page?.total ?? 0,
              offset: _offset,
              filtered: _filterText.trim().isNotEmpty,
              unfilteredTotal: widget.info.rowCount,
              columns: widget.info.columns,
              orderBy: _orderBy,
              descending: _descending,
              lastPageOffset: _lastPageOffset(page?.total ?? 0),
              onGoTo: (offset) => _goTo(offset, page?.total ?? 0),
              onReload: _reload,
              onSortChanged: (column, descending) {
                _orderBy = column;
                _descending = descending;
                _goTo(0, page?.total ?? 0);
              },
            ),
            Expanded(
              child: switch (snapshot) {
                AsyncSnapshot(hasError: true, :final error?) =>
                  Center(child: Text('$error')),
                _ when page == null && loading =>
                  const Center(child: CircularProgressIndicator()),
                _ when page == null => const SizedBox.shrink(),
                _ => Stack(
                    children: [
                      ResultGrid(result: page.result),
                      if (loading)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.columns,
    required this.column,
    required this.onTextChanged,
    required this.onColumnChanged,
  });

  final TextEditingController controller;
  final List<ColumnInfo> columns;
  final String? column;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String?> onColumnChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        denseSpacing,
        denseSpacing,
        denseSpacing,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: DevToolsClearableTextField(
              controller: controller,
              hintText: column == null
                  ? 'Filter rows across all columns'
                  : 'Filter rows by $column',
              prefixIcon: Icon(Icons.search, size: defaultIconSize),
              onChanged: onTextChanged,
            ),
          ),
          const SizedBox(width: denseSpacing),
          RoundedDropDownButton<String?>(
            value: column,
            items: [
              const DropdownMenuItem(value: null, child: Text('All columns')),
              for (final candidate in columns)
                DropdownMenuItem(
                  value: candidate.name,
                  child: Text(candidate.name),
                ),
            ],
            onChanged: onColumnChanged,
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.total,
    required this.offset,
    required this.filtered,
    required this.unfilteredTotal,
    required this.columns,
    required this.orderBy,
    required this.descending,
    required this.lastPageOffset,
    required this.onGoTo,
    required this.onReload,
    required this.onSortChanged,
  });

  final int total;
  final int offset;
  final bool filtered;
  final int unfilteredTotal;
  final List<ColumnInfo> columns;
  final String? orderBy;
  final bool descending;
  final int lastPageOffset;
  final ValueChanged<int> onGoTo;
  final VoidCallback onReload;
  final void Function(String? column, bool descending) onSortChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = total == 0 ? 0 : (offset + kDefaultPageSize).clamp(0, total);
    final label = total == 0
        ? (filtered ? 'No matching rows' : 'No rows')
        : 'Rows ${offset + 1}–$last of $total'
            '${filtered ? ' (filtered from $unfilteredTotal)' : ''}';

    return Padding(
      padding: const EdgeInsets.all(denseSpacing),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(width: defaultSpacing),
          _SortControl(
            columns: columns,
            orderBy: orderBy,
            descending: descending,
            onChanged: onSortChanged,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'First page',
            iconSize: defaultIconSize,
            onPressed: offset == 0 ? null : () => onGoTo(0),
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Previous page',
            iconSize: defaultIconSize,
            onPressed:
                offset == 0 ? null : () => onGoTo(offset - kDefaultPageSize),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next page',
            iconSize: defaultIconSize,
            onPressed: offset >= lastPageOffset
                ? null
                : () => onGoTo(offset + kDefaultPageSize),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Last page',
            iconSize: defaultIconSize,
            onPressed:
                offset >= lastPageOffset ? null : () => onGoTo(lastPageOffset),
            icon: const Icon(Icons.last_page),
          ),
          IconButton(
            tooltip: 'Reload',
            iconSize: defaultIconSize,
            onPressed: onReload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.columns,
    required this.orderBy,
    required this.descending,
    required this.onChanged,
  });

  final List<ColumnInfo> columns;
  final String? orderBy;
  final bool descending;
  final void Function(String? column, bool descending) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundedDropDownButton<String?>(
          value: orderBy,
          items: [
            const DropdownMenuItem(value: null, child: Text('Unsorted')),
            for (final column in columns)
              DropdownMenuItem(value: column.name, child: Text(column.name)),
          ],
          onChanged: (column) => onChanged(column, descending),
        ),
        IconButton(
          tooltip: descending ? 'Descending' : 'Ascending',
          iconSize: defaultIconSize,
          onPressed:
              orderBy == null ? null : () => onChanged(orderBy, !descending),
          icon: Icon(descending ? Icons.arrow_downward : Icons.arrow_upward),
        ),
      ],
    );
  }
}
