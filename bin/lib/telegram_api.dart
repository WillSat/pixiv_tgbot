import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils.dart';
import 'config.dart';

final _dio = Dio();
const _disableNotification = true;

String get _baseUrl => 'https://api.telegram.org/bot${Config.botToken}';

/// Send a text message. Returns the message ID, or null on failure.
Future<int?> sendTextMessage(String text, {bool showLinkPreview = true}) async {
  try {
    final response = await _dio.post(
      '$_baseUrl/sendMessage',
      data: {
        'chat_id': Config.chatId,
        'text': text,
        'parse_mode': 'HTML',
        'disable_notification': _disableNotification,
        'link_preview_options': {'is_disabled': !showLinkPreview},
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (response.statusCode != 200) {
      WRN('Failed to send text message [${response.statusCode}]: ${response.data}');
      return null;
    }
    return response.data['result']['message_id'] as int;
  } catch (e) {
    WRN('Failed to send text message: $e');
    return null;
  }
}

/// Send photos via URL (Telegram downloads them from the URLs).
///
/// Return codes: 1 = success, 400 = general failure,
/// -1 = WEBPAGE_MEDIA_EMPTY (retry via download), -2 = over 10MB (retry with regular quality).
Future<int> sendPhotoGroupViaUrls(List<String> urls, {String? caption}) async {
  final media = <Map<String, dynamic>>[];
  for (var i = 0; i < urls.length; i++) {
    final entry = <String, dynamic>{
      'type': 'photo',
      'media': urls[i],
    };
    if (caption != null && i == 0) {
      entry['caption'] = caption;
      entry['parse_mode'] = 'HTML';
    }
    media.add(entry);
  }

  try {
    final response = await _dio.post(
      '$_baseUrl/sendMediaGroup',
      data: {
        'chat_id': Config.chatId,
        'media': jsonEncode(media),
        'disable_notification': _disableNotification,
      },
    );

    if (response.statusCode != 200) {
      WRN('Failed to send photos. [${response.statusCode}: ${response.data}]');
      return 400;
    }
    return 1;
  } on DioException catch (e) {
    WRN('Failed to send photos! [${e.response?.statusCode}: ${e.response?.data}]');
    final desc = e.response?.data['description'] as String? ?? '';
    if (desc.contains('WEBPAGE_MEDIA_EMPTY')) return -1;
    if (desc.contains('10485760')) return -2;
    return e.response?.statusCode ?? 0;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return 400;
  }
}

/// Download photos then upload them to Telegram.
///
/// Return codes: 1 = success, 400 = general failure, -2 = over 10MB.
Future<int> sendPhotoGroupViaDownload(List<String> urls, {String? caption}) async {
  final media = <Map<String, dynamic>>[];
  final formData = FormData.fromMap({
    'chat_id': Config.chatId,
    'disable_notification': _disableNotification,
  });

  try {
    for (var i = 0; i < urls.length; i++) {
      final fileName = 'photo_$i.jpg';

      final downloadResp = await _dio.get<List<int>>(
        urls[i],
        options: Options(responseType: ResponseType.bytes),
      );

      if (downloadResp.statusCode != 200) {
        throw Exception('Failed to download photo $i: ${downloadResp.statusCode}');
      }

      final entry = <String, dynamic>{
        'type': 'photo',
        'media': 'attach://$fileName',
      };
      if (caption != null && i == 0) {
        entry['caption'] = caption;
        entry['parse_mode'] = 'HTML';
      }
      media.add(entry);

      formData.files.add(MapEntry(
        fileName,
        MultipartFile.fromBytes(downloadResp.data!, filename: fileName),
      ));
    }

    formData.fields.add(MapEntry('media', jsonEncode(media)));

    final response = await _dio.post('$_baseUrl/sendMediaGroup', data: formData);

    if (response.statusCode != 200) {
      WRN('Failed to send photos. [${response.statusCode}: ${response.data}]');
      return 400;
    }
    return 1;
  } on DioException catch (e) {
    WRN('Failed to send photos! [${e.response?.statusCode}: ${e.response?.data}]');
    if ((e.response?.data['description'] as String?)?.contains('10485760') == true) {
      return -2;
    }
    return e.response?.statusCode ?? 0;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return 400;
  }
}

/// Send local video files as a media group.
///
/// Return codes: 1 = success, or HTTP status code on failure.
Future<int> sendVideoGroup(List<String> paths, {String? caption}) async {
  final mediaList = <Map<String, dynamic>>[];
  final formDataMap = <String, dynamic>{
    'chat_id': Config.chatId,
    'disable_notification': _disableNotification,
  };

  for (var i = 0; i < paths.length; i++) {
    final fieldName = 'video_$i.mp4';
    formDataMap[fieldName] = await MultipartFile.fromFile(paths[i]);

    final entry = <String, dynamic>{
      'type': 'video',
      'media': 'attach://$fieldName',
    };
    if (i == 0 && caption != null) {
      entry['caption'] = caption;
      entry['parse_mode'] = 'HTML';
    }
    mediaList.add(entry);
  }

  formDataMap['media'] = jsonEncode(mediaList);
  final formData = FormData.fromMap(formDataMap);

  try {
    final response = await _dio.post('$_baseUrl/sendMediaGroup', data: formData);
    if (response.data['ok'] == true) {
      return 1;
    } else {
      WRN('Failed to send media group! ${response.statusCode}: ${response.data}');
      return response.statusCode ?? 0;
    }
  } on DioException catch (e) {
    WRN('Error sending media group: $e');
    return e.response?.statusCode ?? 0;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return 0;
  }
}
