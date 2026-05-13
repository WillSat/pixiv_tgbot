import 'package:dio/dio.dart';
import 'config.dart';

final _dio = Dio();

Future<void> barkSuccess() async {
  await _dio.get(Config.barkSuccessUrl);
}

Future<void> barkFail() async {
  await _dio.get(Config.barkFailUrl);
}
