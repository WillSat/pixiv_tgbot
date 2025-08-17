import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../utils.dart';

final botToken = File('in/botToken.key').readAsStringSync();
final chatID = File('in/chatID.key').readAsStringSync();
// For test
// final chatID = File('in/chatID-test.key').readAsStringSync();

final dio = Dio();

// Future<void> sendTextMessage(dynamic text)
Future<void> sendTextMessage(text) async {
  try {
    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMessage',
      data: {'chat_id': chatID, 'text': text, "parse_mode": "MarkdownV2"},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send text message [${response.statusCode}:${response.statusMessage}]: ${response.data}',
      );
    }
  } catch (e) {
    wrn('Failed to send text message: $e');
  }
}

/// [urls] 图片链接（网络）
Future<int> sendPhotoViaUrls(List<String> urls, {String? caption}) async {
  List<Map<String, dynamic>> media = [];

  for (int i = 0; i < urls.length; i++) {
    media.add({
      'type': 'photo',
      'media': urls[i],
      if (caption != null && i == 0) "caption": caption,
      if (caption != null && i == 0) "parse_mode": "MarkdownV2",
    });
  }

  final formMap = {'chat_id': chatID, 'media': jsonEncode(media)};

  try {
    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMediaGroup',
      data: formMap,
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send photos. [${response.statusCode}:${response.statusMessage}]\n${response.data}',
      );
      return 0;
    } else {
      return 1;
    }
  } catch (e) {
    if (e is DioException) {
      wrn(
        'Failed to send photos! [${e.response?.statusCode}:${e.response?.data}]\n$e',
      );
      return e.response?.statusCode ?? 0;
    } else {
      wrn('Unhandled exception: $e');
      return 0;
    }
  }
}

/// 发送视频到指定 chat_id
/// [videoPath] 本地视频文件路径
Future<int> sendVideo(String videoPath, {String? caption}) async {
  final dio = Dio();

  final url = 'https://api.telegram.org/bot$botToken/sendVideo';

  final formData = FormData.fromMap({
    'chat_id': chatID,
    'video': await MultipartFile.fromFile(videoPath),
    if (caption != null) 'caption': caption,
    if (caption != null) "parse_mode": "MarkdownV2",
  });

  try {
    final response = await dio.post(url, data: formData);
    if (response.data['ok'] == true) {
      log('Video message sent successfully.');
      return 1;
    } else {
      wrn(
        'Failed to send video message! ${response.statusCode}: ${response.data}',
      );
      return response.statusCode ?? 0;
    }
  } catch (e) {
    e as DioException;
    wrn(
      'Failed to send video message! ${e.response?.statusCode}: ${e.response?.data}',
    );
    return e.response?.statusCode ?? 0;
  }
}
