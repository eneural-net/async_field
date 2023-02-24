## 1.0.8

- `AsyncStorage`:
  - Added `reopen`.
- `AsyncField`:
  - Added `valueOrSlate` and `valueOrSlateNoTimeoutCheck`.
  - Added `isSlate` and `isSetOrSlate`.
  - Added `onChangeFilter`.
  - Added `dsxValueAllowSlate` and `dsxValueAllowAutoFetch`.
- `analysis_options.yaml`:
  - Added linter rules:
    - `avoid_dynamic_calls`.
    - `avoid_type_to_string`.
    - `no_runtimeType_toString`.
    - `discarded_futures`.
    - `no_adjacent_strings_in_list`.
- sdk: '>=2.18.0 <3.0.0'
- async_extension: ^1.1.0
- test: ^1.23.1
- coverage: ^1.6.3

## 1.0.7

- `AsyncField`:
  - Added `isFetching`.
  - `get`: now respect the current fetching `Future`.
- lints: ^2.0.1
- test: ^1.22.2
- coverage: ^1.6.2

## 1.0.6

- `AsyncStorage`:
  - Added `close` and `isClosed`:
    will stop `fetch`, `save` and `delete` operations.

## 1.0.5

- Added `deletedValue`.
- `delete` won't call `dispose` anymore.
- Improve Null Safety.
- sdk: '>=2.14.0 <3.0.0'
- collection: ^1.16.0
- async_extension: ^1.0.12
- lints: ^2.0.0
- test: ^1.21.4
- dependency_validator: ^3.2.2
- coverage: ^1.3.2

## 1.0.4

- Added `periodicRefresh`.
- Fixed events to allow multiple listeners (`StreamController.broadcast`).
- Added DSX dynamic interface (package `dom_builder`).
- improve tests.

## 1.0.3

- Change `AsyncField.set` to return the defined value.
- improve tests
- async_extension: ^1.0.4

## 1.0.2

- Adjust `pubspec.yaml` `description`.
- Adjust `README.md`.
- Fix dispose.

## 1.0.1

- Add `AsyncField.timeout`.
- Added `get( onSlateValue )`.
- Improve tests.

## 1.0.0

- Initial version.
