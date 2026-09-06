# sqflite_devtools

A [Dart & Flutter DevTools extension](https://docs.flutter.dev/tools/devtools/custom-tool)
for browsing the sqflite databases of a running app — tables and views, their
schema, paged and filterable data, and an ad-hoc SQL editor — in a full-size
browser tab instead of a debug screen on the device.

![The sqflite_devtools tab in DevTools: table list on the left, paged data grid on the right](https://raw.githubusercontent.com/rasyeda/sqflite_devtools/main/doc/screenshot.png)

This repository holds two packages:

| Package | Published | What it is |
| --- | --- | --- |
| [`sqflite_devtools`](sqflite_devtools) | yes | The package your app depends on. Registers the service extensions and ships the compiled DevTools extension. |
| [`sqflite_devtools_extension`](sqflite_devtools_extension) | no | Source of the extension UI, a Flutter web app. Its build output is copied into the package above. |

See [`sqflite_devtools/README.md`](sqflite_devtools/README.md) for installation
and usage, and for how to rebuild the extension bundle after changing the UI.

## Licence

MIT — see [LICENSE](LICENSE).
