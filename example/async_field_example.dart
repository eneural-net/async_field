import 'package:async_field/async_field.dart';

void main() {
  var storage = AsyncStorage();

  var field = storage.getField('a');

  print(field);
}
