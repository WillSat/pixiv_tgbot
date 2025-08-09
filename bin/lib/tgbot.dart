import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../utils.dart';

final botToken = File('in/botToken.key').readAsStringSync();
final chatID = File('in/chatID.key').readAsStringSync();

final dio = Dio();

int finishedMsgCount = 0;

// Future<void> sendTextMessage(dynamic text)
Future<void> sendTextMessage(text) async {
  try {
    final response = await dio.post(
      'https://api.telegram.org/bot$botToken/sendMessage',
      data: {'chat_id': chatID, 'text': text},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    if (response.statusCode != 200) {
      wrn(
        'Failed to send message [${response.statusCode}:${response.statusMessage}]: ${response.data}',
      );
    }
  } catch (e) {
    wrn('Failed to send message: $e， ');
  }
}

// Future<void> sendPhotoUrls(List<String> urls, {String? caption})
Future<int> sendPhotoUrls(List<String> urls, {String? caption}) async {
  const int maxBatchSize = 10;

  for (
    int start = finishedMsgCount * maxBatchSize;
    start < urls.length;
    start += maxBatchSize
  ) {
    final end = (start + maxBatchSize) > urls.length
        ? urls.length
        : (start + maxBatchSize);

    final batch = urls.sublist(start, end);

    List<Map<String, dynamic>> media = [];

    for (int i = 0; i < batch.length; i++) {
      media.add({
        'type': 'photo',
        'media': batch[i],
        if (caption != null && i == 0) "caption": caption,
      });
    }

    final formMap = {'chat_id': chatID, 'media': jsonEncode(media)};

    final url = 'https://api.telegram.org/bot$botToken/sendMediaGroup';

    try {
      final response = await dio.post(url, data: formMap);

      if (response.statusCode != 200) {
        wrn(
          'Failed to send photos batch [${response.statusCode}:${response.statusMessage}]: ${response.data}',
        );
        return 0;
      } else {
        log('Batch sent successfully: photos ${start + 1} to $end');
        finishedMsgCount++;
      }
    } catch (e) {
      wrn(
        'Failed to send photos batch: ${(e as DioException).response?.statusCode}',
      );
      return e.response?.statusCode ?? 0;
    }
  }
  finishedMsgCount = 0;
  return 1;
}

// Future<void> sendLocalPhotos(List<String> photoPaths, {String? caption})
// Future<void> sendLocalPhotos(List<String> photoPaths, {String? caption}) async {
//   for (int start = 0; start < photoPaths.length; start += maxBatchSize) {
//     final end = (start + maxBatchSize) > photoPaths.length
//         ? photoPaths.length
//         : (start + maxBatchSize);

//     final batch = photoPaths.sublist(start, end);

//     List<Map<String, dynamic>> media = [];

//     for (int i = 0; i < batch.length; i++) {
//       media.add({
//         'type': 'photo',
//         'media': 'attach://file$i',
//         if (caption != null) "caption": caption,
//       });
//     }

//     Map<String, dynamic> formMap = {
//       'chat_id': chatID,
//       'media': jsonEncode(media),
//     };

//     for (int i = 0; i < batch.length; i++) {
//       formMap['file$i'] = await MultipartFile.fromFile(
//         batch[i],
//         filename: 'file$i.jpg',
//       );
//     }

//     FormData formData = FormData.fromMap(formMap);

//     final url = 'https://api.telegram.org/bot$botToken/sendMediaGroup';

//     try {
//       final response = await dio.post(url, data: formData);

//       if (response.statusCode != 200 || response.data['ok'] != true) {
//         wrn(
//           'Failed to send photos batch [${response.statusCode}:${response.statusMessage}]: ${response.data}',
//         );
//       } else {
//         log('Batch sent successfully: photos ${start + 1} to $end');
//       }
//     } catch (e) {
//       wrn('Failed to send photos batch: $e');
//     }
//   }
// }
