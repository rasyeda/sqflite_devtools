# sqflite_devtools_extension

The DevTools extension UI for the `sqflite_devtools` package. This package is
never published; its compiled web output is copied into
`../sqflite_devtools/extension/devtools/build`.

Rebuild the bundle after changing anything here:

```bash
dart run devtools_extensions build_and_copy --source=. --dest=../sqflite_devtools/extension/devtools
```

Iterate on the UI in a browser, against a simulated DevTools environment:

```bash
flutter run -d chrome --dart-define=use_simulated_environment=true
```
