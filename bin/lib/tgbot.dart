import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../utils.dart';

final botToken = File('in/botToken.key').readAsStringSync();
final chatID = File('in/chatID.key').readAsStringSync();

// For test
// final chatID = File('in/chatID-test.key').readAsStringSync();

final goFileToken = File('in/GoFile.key').readAsStringSync();

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
    FormData formData = FormData.fromMap({'chat_id': chatID});

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
        if (caption != null && i == 0) "parse_mode": "MarkdownV2",
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

/// 发送文件到指定 chat_id
/// [zipPath] 本地文件路径
Future<void> uploadZip(String zipPath) async {
  final dio = Dio();
  final url = "https://api.telegram.org/bot$botToken/sendDocument";

  final formData = FormData.fromMap({
    "chat_id": chatID,
    "document": await MultipartFile.fromFile(zipPath),
  });

  try {
    final response = await dio.post(url, data: formData);
    if (response.statusCode == 200 && response.data["ok"] == true) {
      log("ZIP file uploaded.");
    } else {
      wrn("Failed to upload ZIP file");
    }
  } catch (e) {
    wrn("Unhandled error: $e");
  }
}

/// 上传文件到 GoFile (东京节点)
/// 返回直链 URL
Future<String?> uploadToGofile(String filePath) async {
  final dio = Dio();
  final file = File(filePath);

  if (!file.existsSync()) {
    wrn("File not found: $filePath");
    return null;
  }

  final url = "https://upload-ap-tyo.gofile.io/uploadfile";

  final formData = FormData.fromMap({
    "file": MultipartFile.fromStream(
      file.openRead,
      await file.length(),
      filename: file.uri.pathSegments.last,
    ),
  });

  try {
    final response = await dio.post(
      url,
      data: formData,
      options: Options(
        contentType: "multipart/form-data",
        headers: {'Authorization': 'Bearer $goFileToken'},
      ),
    );

    if (response.statusCode == 200 && response.data["status"] == "ok") {
      final directLink = response.data["data"]["downloadPage"] ?? "";
      log("ZIP Uploaded.");
      return directLink;
    } else {
      wrn("Upload failed: ${response.data}");
      return null;
    }
  } catch (e) {
    wrn("Error uploading: $e");
    return null;
  }
}
