# async_field

[![pub package](https://img.shields.io/pub/v/async_field.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/async_field)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Codecov](https://img.shields.io/codecov/c/github/eneural-net/async_field)](https://app.codecov.io/gh/eneural-net/async_field)
[![Dart CI](https://github.com/eneural-net/async_field/actions/workflows/dart.yml/badge.svg)](https://github.com/eneural-net/async_field/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/eneural-net/async_field?logo=git&logoColor=white)](https://github.com/eneural-net/async_field/releases)
[![New Commits](https://img.shields.io/github/commits-since/eneural-net/async_field/latest?logo=git&logoColor=white)](https://github.com/eneural-net/async_field/network)
[![Last Commits](https://img.shields.io/github/last-commit/eneural-net/async_field?logo=git&logoColor=white)](https://github.com/eneural-net/async_field/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/eneural-net/async_field?logo=github&logoColor=white)](https://github.com/eneural-net/async_field/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/eneural-net/async_field?logo=github&logoColor=white)](https://github.com/eneural-net/async_field)
[![License](https://img.shields.io/github/license/eneural-net/async_field?logo=open-source-initiative&logoColor=green)](https://github.com/eneural-net/async_field/blob/master/LICENSE)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Feneural-net%2Fasync_field.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Feneural-net%2Fasync_field?ref=badge_shield)

Async fields that can be stored or fetched from any source (databases, web services, local storage or other thread/isolate), with observable values, caches and stale versions.

## Usage


A simple usage example:

```dart
import 'dart:convert' as convert;
import 'dart:io';

import 'package:async_field/async_field.dart';

void main() async {
  // The fields storage:
  var storage = AsyncStorage();

  // Get field 'btc_usd',
  var field = storage.getField<double>('btc_usd')
    ..defaultValue = double.nan // default value (before fetch).
    ..withFetcher(_fetchBtcUsd) // the field fetcher.
    ..onChange.listen((field) => print('onChange> $field')); // change listener.

  print('BTC-USD: $field');
  print('field.info: ${field.info}');

  // Get the field value:
  var btcUsd = await field.get();

  print('field.get(): $btcUsd');

  print('BTC-USD: $field');
  print('field.info: ${field.info}');
}

/// Function that fetches the BTC-USD spot price (Coinbase public API).
Future<double> _fetchBtcUsd(AsyncField<double> field) async {
  return _getURL('https://api.coinbase.com/v2/prices/BTC-USD/spot')
      .resolveMapped((body) {
        var json = convert.json.decode(body) as Map<String, dynamic>;
        var amount = json['data']['amount'];
        return double.parse('$amount');
      });
}

/// Simple HTTP get URL function.
Future<String> _getURL(String url) async {
  var uri = Uri.parse(url);
  var httpClient = HttpClient();

  try {
    var response = await httpClient
        .getUrl(uri)
        .then((request) => request.close());

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    return await response.transform(convert.utf8.decoder).join();
  } finally {
    httpClient.close();
  }
}
```

OUTPUT:

```text
BTC-USD: NaN
field.info: { "id": "btc_usd" , "storage": 1 }
field.get(): 76879.455
BTC-USD: 76879.455
field.info: { "value": 76879.455 , "id": "btc_usd" , "valueTime": 1793767610222 , "storage": 1 }
onChange> 76879.455
```

## Source

The official source code is [hosted @ GitHub][github_async_field]:

- https://github.com/eneural-net/async_field

[github_async_field]: https://github.com/eneural-net/async_field

# Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

# Contribution

Any help from the open-source community is always welcome and needed:

- Found an issue?
    - Please fill a bug report with details.
- Wish a feature?
    - Open a feature request with use cases.
- Are you using and liking the project?
    - Promote the project: create an article, do a post or make a donation.
- Are you a developer?
    - Fix a bug and send a pull request.
    - Implement a new feature.
    - Improve the Unit Tests.
- Have you already helped in any way?
    - **Many thanks from me, the contributors and everybody that uses this project!**

*If you donate 1 hour of your time, you can contribute a lot,
because others will do the same, just be part and start with your 1 hour.*

[tracker]: https://github.com/eneural-net/async_field/issues

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Feneural-net%2Fasync_field.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Feneural-net%2Fasync_field?ref=badge_large)