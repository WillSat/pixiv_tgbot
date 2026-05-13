import 'dart:convert';
import 'package:dio/dio.dart';

Future<void> main() async {
  final dio = Dio();
  final res = await dio.post(
    'https://api.telegra.ph/createAccount',
    data: {
      'short_name': 'xx',
      'author_name': 'xx',
    },
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );

  print(jsonEncode(res.data));
}
