// ignore_for_file: avoid_dynamic_calls

import 'dart:convert' as convert;
import 'dart:io';

import 'package:async_field/async_field.dart';

void main() async {
  // The fields storage:
  var storage = AsyncStorage();

  // Get field 'btc_usd',
  var field = storage.getField<double>('btc_usd')
    // default value (before fetch):
    ..defaultValue = double.nan
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

//-----------------------------
// OUTPUT:
//-----------------------------
// BTC-USD: NaN
// field.info: { "id": "btc_usd" , "storage": 1 }
// field.get(): 76879.455
// BTC-USD: 76879.455
// field.info: { "value": 76879.455 , "id": "btc_usd" , "valueTime": 1793767610222 , "storage": 1 }
// onChange> 76879.455
//
