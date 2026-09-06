# sqflite_devtools

A [DevTools extension](https://docs.flutter.dev/tools/devtools/custom-tool) that
lets you browse the sqflite databases of a running app: tables and views, their
schema, paged and filterable data, and an ad-hoc SQL editor — in a full-size
browser tab instead of a debug screen on the device.

Works with anything built on `sqflite_common`: `sqflite` on Android/iOS and
`sqflite_common_ffi` on desktop and in Dart CLI apps.

## Install

```yaml
dependencies:
  sqflite_devtools: ^0.1.0
```

## Use

Register each database once it is open:

```dart
final db = await openDatabase('majoo.db');
SqfliteDevTools.register(db, label: 'majoo.db');
```

Then run the app in debug or profile mode, open DevTools, and enable the
**sqflite_devtools** tab when DevTools offers it. The choice is remembered in
your project's `devtools_options.yaml`.

`register` is a no-op in release builds, so the call can stay in production
code. It is still reachable by anyone who can attach a debugger to a debug or
profile build, so guard it with `kDebugMode` for databases holding sensitive
data:

```dart
if (kDebugMode) {
  SqfliteDevTools.register(db, label: 'majoo.db');
}
```

Call `SqfliteDevTools.unregister(id)` before closing a database.

### Writes

Databases are read-only by default: `INSERT`, `UPDATE`, `DELETE` and DDL from
the SQL editor are rejected. Opt in per database:

```dart
SqfliteDevTools.register(db, label: 'majoo.db', allowWrite: true);
```

### Several databases

```dart
SqfliteDevTools.register(orders, label: 'orders.db');
SqfliteDevTools.register(catalog, label: 'catalog.db', id: 'catalog');
```

`id` defaults to `label` and must be unique; the extension shows one dropdown
entry per registration.

## Filtering

The **Data** tab has a filter field above the grid. It matches a substring
anywhere in the row, across every column by default, or in the one column
picked in the dropdown beside it. Columns are cast to text first, so numeric and
date columns match too.

Filtering happens in SQL (`LIKE` with `%` and `_` escaped as literals), not in
the extension, so it applies to the whole table rather than the page on screen;
the row counter shows how many rows matched.

## How it works

The extension is a Flutter web app running inside DevTools, so it cannot reach
the database file on the device. It calls service extensions
(`ext.sqflite_devtools.*`) that this package registers with `dart:developer` in
the app's main isolate; the app runs the SQL and returns JSON.

Consequences worth knowing:

- Results cross the wire as one JSON string, so a query is clipped at
  `kMaxRows` (500) rows; the extension reports when that happens. Table browsing
  pages with `LIMIT`/`OFFSET` and is not affected.
- BLOBs are base64-encoded on the wire and shown as `BLOB(n) …` in the grid.
- Only databases registered on the **main isolate** are visible.
- Filtering and paging run as extra `SELECT`s against the app's database, so a
  filter over a very large table costs the app a full scan.

## Developing this package

The extension UI lives in the sibling `sqflite_devtools_extension` package. After
changing it, rebuild the bundle that ships inside `extension/devtools/build`:

```bash
cd ../sqflite_devtools_extension
dart run devtools_extensions build_and_copy --source=. --dest=../sqflite_devtools/extension/devtools
```

Commit the rebuilt output — DevTools loads it straight from the published
package. To iterate on the UI without a full rebuild, run the extension app
directly:

```bash
flutter run -d chrome --dart-define=use_simulated_environment=true
```

Run the tests, including an end-to-end pass over a real VM service connection:

```bash
dart test
```
