# EZVenera

EZVenera is a simplified, maintainable fork direction of Venera.

Current product goal:

- Windows and Android only
- plugin-first architecture
- keep source `login`, `search`, `category`, `details`, `reading`, `download`
- simplify non-core features aggressively

## Current Status

Implemented so far:

- new EZVenera app shell
- Windows sidebar and Android bottom navigation
- simplified plugin runtime compatible with original `venera-configs`
- source management page with install, reload, delete
- searchable source selection and search result flow

Main runtime code:

- `lib/src/plugin_runtime`

Main documents:

- `docs/EZVenera_execution_plan.md`
- `docs/EZVenera_plugin_runtime_design.md`
- `docs/EZVenera_plugin_doc.md`

## Source Config Repository

EZVenera source configs should come from:

- [EZVenera-config](https://github.com/WEP-56/EZvenera-config)

Do not use the original Venera default source repository for EZVenera.

## Development

Run locally:

```bash
flutter pub get
flutter run
```

Validate:

```bash
flutter analyze
flutter test
```

## Repository

App repository:

- [WEP-56/EZVenera](https://github.com/WEP-56/EZVenera)

## 感谢社区
https://linux.do/
