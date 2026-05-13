import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils.dart';
import 'config.dart';

final _dio = Dio();

/// Publish an article with images to telegra.ph.
///
/// [title] is the article title (used as the page title on Telegraph).
/// [imageUrls] are the proxied image URLs to embed.
///
/// Returns the published article URL, or null on failure.
Future<String?> publishToTelegraph(String title, List<String> imageUrls) async {
  final nodes = <Map<String, dynamic>>[
    {
      'tag': 'p',
      'children': ['${imageUrls.length} ${imageUrls.length == 1 ? 'image' : 'images'}'],
    },
    ...imageUrls.map((url) => {
          'tag': 'img',
          'attrs': {'src': url},
        }),
  ];

  try {
    final response = await _dio.post(
      'https://api.telegra.ph/createPage',
      data: {
        'access_token': Config.telegraphToken,
        'title': title,
        'content': jsonEncode(nodes),
        'return_content': false,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    if (response.statusCode == 200 && response.data['ok'] == true) {
      return response.data['result']['url'] as String?;
    } else {
      WRN('Failed to publish to Telegraph: ${response.data}');
      return null;
    }
  } on DioException catch (e) {
    WRN('Failed to publish to Telegraph: ${e.response?.statusCode}');
    return null;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return null;
  }
}
