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

  print('BTX-USD: $field');
  print('field.info: ${field.info}');

  // Get the field value:
  var btcUsd = await field.get();

  print('field.get(): $btcUsd');

  print('BTX-USD: $field');
  print('field.info: ${field.info}');
}

/// Function that fetches the BTS-USD price.
Future<double> _fetchBtcUsd(AsyncField<double> field) async {
  return _getURL('https://api.coindesk.com/v1/bpi/currentprice.json')
      .resolveMapped((body) {
    var json = convert.json.decode(body) as Map<String, dynamic>;
    var rate = json['bpi']['USD']['rate_float'];
    return double.parse('$rate');
  });
}

/// Simple HTTP get URL function.
Future<String> _getURL(String url) async {
  var uri = Uri.parse(url);
  var httpClient = HttpClient();

  var response =
      await httpClient.getUrl(uri).then((request) => request.close());

  var data = await response.transform(convert.Utf8Decoder()).toList();
  var body = data.join();
  return body;
}

//-----------------------------
// OUTPUT:
//-----------------------------
// BTX-USD: NaN
// field.info: { "id": "btc_usd" , "storage": 1 }
// field.get(): 34498.9417
// BTX-USD: 34498.9417
// field.info: { "value": 34498.9417 , "id": "btc_usd" , "valueTime": 1624846823650 , "storage": 1 }
// onChange> 34498.9417
//
