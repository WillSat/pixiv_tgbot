import 'dart:convert';

import 'package:dio/dio.dart';

Future<void> createAccount() async {
  final dio = Dio();
  final res = await dio.post(
    'https://api.telegra.ph/createAccount',
    data: {
      'short_name': 'xx', // 你的昵称
      'author_name': 'xx', // 作者名
    },
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );

  print(jsonEncode(res.data));
}
