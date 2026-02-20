import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import '../utils.dart';

final accessToken = File('in/telegraphToken.key').readAsStringSync();

Future<String?> parseAndPublishTelegraph(
  String title,
  List<String> urls,
) async {
  // Build nodes
  final List<Map<String, dynamic>> nodes = [
    {
      'tag': 'p',
      'children': ['${urls.length} ${urls.length == 1 ? 'image' : 'images'}'],
    },
    ...urls.map(createImg),
  ];

  return await publishToTelegraph(title, nodes);
}

Map<String, dynamic> createImg(String url) {
  return {
    'tag': 'img',
    'attrs': {'src': url},
  };
}

/// 发布文章到 telegra.ph
Future<String?> publishToTelegraph(
  String title,
  List<Map<String, dynamic>> nodes,
) async {
  final dio = Dio();
  try {
    final response = await dio.post(
      'https://api.telegra.ph/createPage',
      data: {
        'access_token': accessToken.trim(),
        'title': title,
        'content': jsonEncode(nodes),
        'return_content': false,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    if (response.statusCode == 200 && response.data['ok'] == true) {
      return response.data['result']['url'];
    } else {
      wrn('Failed to publish: ${response.data}');
      return null;
    }
  } catch (e) {
    if (e is DioException) {
      wrn('Failed to publish: ${e.response?.statusCode}');
    } else {
      wrn('Unhandled exception: $e');
    }
    return null;
  }
}
