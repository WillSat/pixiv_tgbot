// via bark APP
// https://bark.day.app/

import 'dart:io';
import 'package:dio/dio.dart';

final dio = Dio();

Future<void> barkSuccess() async {
  final url = File('in/bark-success.key').readAsStringSync();
  await dio.get(url, options: Options(method: 'GET'));
}

Future<void> barkFail() async {
  final url = File('in/bark-fail.key').readAsStringSync();
  await dio.get(url, options: Options(method: 'GET'));
}
