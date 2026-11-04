## 1.1.3

- Example and README:
  - Replaced the retired CoinDesk endpoint (`api.coindesk.com/v1/bpi/currentprice.json`) with the
    Coinbase public spot price API (`api.coinbase.com/v2/prices/BTC-USD/spot`).
  - `_getURL` now checks the HTTP status and closes the `HttpClient`, so the example exits cleanly.
  - Fixed `BTX-USD`/`BTS-USD` typos and refreshed the sample output.

## 1.1.2

- `AsyncField`:
  - Fixed dartdoc references in `isClosed` and `timeoutChecker`.
- Added `test/async_field_api_test.dart`: coverage for `AsyncFieldID`, values/defaults, saver/deleter/dispose,
  slate values, `timeoutChecker`, `periodicRefresh`, `fieldsTimeout` and `clear`/`reopen`.
- `.github/workflows/dart.yml`:
  - `actions/checkout@v7`, `codecov/codecov-action@v7`.

- sdk: ^3.13.0

- collection: ^1.19.1
- async_extension: ^1.2.23
- lints: ^6.1.0
- test: ^1.33.0
- dependency_validator: ^5.1.0
- coverage: ^1.16.0

## 1.1.1

- `AsyncField`:
  - Added `timeoutChecker`.

## 1.1.0

- `AsyncField`:
  - `refresh`: ensure that `_fetching` is removed on error.

- sdk: '>=3.0.0 <4.0.0'

- collection: ^1.18.0
- async_extension: ^1.2.12
- lints: ^3.0.0
- test: ^1.25.5
- dependency_validator: ^3.2.3
- coverage: ^1.8.0

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
