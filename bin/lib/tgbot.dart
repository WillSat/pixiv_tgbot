import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../utils.dart';

final botToken = File('in/botToken.key').readAsStringSync();

// !!! For test only !!!
// final chatID = File('in/chatID-test.key').readAsStringSync();
//
final chatID = File('in/chatID.key').readAsStringSync();

const ifDisableNotification = true;

final dio = Dio();

// Future<void> sendTextMessage(dynamic text)
Future<int?> sendTextMessage(text, {bool isShowLinkPreview = true}) async {
  try {
    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMessage',
      data: {
        'chat_id': chatID,
        'text': text,
        'parse_mode': 'HTML',
        'disable_notification': ifDisableNotification,
        'link_preview_options': {'is_disabled': !isShowLinkPreview},
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send text message [${response.statusCode}:${response.statusMessage}]: ${response.data}',
      );
      return null;
    }

    // Success
    // 返回消息id
    return response.data['result']['message_id'] as int;
  } catch (e) {
    wrn('Failed to send text message: $e');
    return null;
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
      if (caption != null && i == 0) "parse_mode": "HTML",
    });
  }

  final formMap = {
    'chat_id': chatID,
    'media': jsonEncode(media),
    'disable_notification': ifDisableNotification,
  };

  try {
    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMediaGroup',
      data: formMap,
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send photos. [${response.statusCode}:${response.data}:${response.statusMessage}]',
      );
      return 400;
    } else {
      return 1;
    }
  } catch (e) {
    if (e is DioException) {
      wrn(
        'Failed to send photos! [${e.response?.statusCode}:${e.response?.data}]',
      );

      final data = e.response?.data['description'] as String;

      if (data.contains('WEBPAGE_MEDIA_EMPTY')) {
        // TG bot bug
        return -1;
      } else if (data.contains('10485760')) {
        // Over 10MB
        return -2;
      } else {
        return e.response?.statusCode ?? 0;
      }
    } else {
      wrn('Unhandled exception: $e');
      return 400;
    }
  }
}

/// [urls] 上传图片（本地）
Future<int> sendPhotoViaDownload(List<String> urls, {String? caption}) async {
  List<Map<String, dynamic>> media = [];

  try {
    FormData formData = FormData.fromMap({
      'chat_id': chatID,
      'disable_notification': ifDisableNotification,
    });

    for (int i = 0; i < urls.length; i++) {
      String fileName = 'photo_$i.jpg';

      Response<List<int>> downloadResponse = await dio.get<List<int>>(
        urls[i],
        options: Options(responseType: ResponseType.bytes),
      );

      if (downloadResponse.statusCode != 200) {
        throw Exception(
          'Failed to download photo $i: ${downloadResponse.statusCode}',
        );
      }

      media.add({
        'type': 'photo',
        'media': 'attach://$fileName',
        if (caption != null && i == 0) "caption": caption,
        if (caption != null && i == 0) "parse_mode": "HTML",
      });

      formData.files.add(
        MapEntry(
          fileName,
          MultipartFile.fromBytes(downloadResponse.data!, filename: fileName),
        ),
      );
    }

    formData.fields.add(MapEntry('media', jsonEncode(media)));

    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMediaGroup',
      data: formData,
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send photos. [${response.statusCode}:${response.data}:${response.statusMessage}]',
      );
      return 400;
    } else {
      return 1;
    }
  } catch (e) {
    if (e is DioException) {
      wrn(
        'Failed to send photos! [${e.response?.statusCode}:${e.response?.data}]',
      );

      // Over 10MB
      if ((e.response?.data['description'] as String).contains('10485760')) {
        return -2;
      } else {
        return e.response?.statusCode ?? 0;
      }
    } else {
      wrn('Unhandled exception: $e');
      return 400;
    }
  }
}

/// 发送多个视频到指定 chat_id
/// [videoPaths] 本地视频文件路径列表
Future<int> sendMediaGroup(List<String> videoPaths, {String? caption}) async {
  final dio = Dio();
  final url = 'https://api.telegram.org/bot$botToken/sendMediaGroup';

  // 1. 构建 media 数组和 map 对象
  final List<Map<String, dynamic>> mediaList = [];
  final Map<String, dynamic> formDataMap = {
    'chat_id': chatID,
    'disable_notification': ifDisableNotification,
  };

  for (int i = 0; i < videoPaths.length; i++) {
    final String fieldName = 'video_$i.mp4';
    final String path = videoPaths[i];

    // 将文件放入 FormData
    formDataMap[fieldName] = await MultipartFile.fromFile(path);

    // 将媒体描述放入 media 列表
    mediaList.add({
      'type': 'video',
      'media': 'attach://$fieldName',
      if (i == 0 && caption != null) 'caption': caption,
      if (i == 0 && caption != null) 'parse_mode': 'HTML',
    });
  }

  // 2. 将 media 数组转为 JSON 字符串放入 FormData
  formDataMap['media'] = jsonEncode(mediaList);

  final formData = FormData.fromMap(formDataMap);

  try {
    final response = await dio.post(url, data: formData);
    if (response.data['ok'] == true) {
      log('Media group sent successfully.');
      return 1;
    } else {
      wrn(
        'Failed to send media group! ${response.statusCode}: ${response.data}',
      );
      return response.statusCode ?? 0;
    }
  } catch (e) {
    final statusCode = (e is DioException) ? e.response?.statusCode : 0;
    wrn('Error sending media group: ${e}');
    return statusCode ?? 0;
  }
}
