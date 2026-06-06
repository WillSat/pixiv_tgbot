import 'package:dio/dio.dart';
import '../utils.dart';
import 'config.dart';

final _dio = Dio();

Future<void> barkSuccess() async {
  try {
    await _dio.get(Config.barkSuccessUrl);
  } catch (e) {
    WRN('Bark success notification failed: $e');
  }
}

Future<void> barkFail() async {
  try {
    await _dio.get(Config.barkFailUrl);
  } catch (e) {
    WRN('Bark fail notification failed: $e');
  }
}
