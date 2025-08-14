import 'dart:io';

import 'package:dio/dio.dart';

final downDio = Dio();
final cookie = File('in/phpsessid.key').readAsStringSync();

// void log(String msg)
void log(String msg) {
  final dt = DateTime.now();
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');

  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');

  print('[$month/$day $hour:$minute:$second] $msg');
}

void wrn(String msg) {
  log('[WRN] $msg');
}

// void writeOut(String fileName, String content)
void writeOut(String fileName, String content) async {
  if (!Directory('out').existsSync()) await Directory('out').create();

  await File('out/$fileName').writeAsString(content);
  log('Worte to out/$fileName');
}

// Future<void> downloadImages(List<String> uriList, String fileNmae)
Future<List<String>> downloadImages(List<String> uriList, String id) async {
  final dt = DateTime.now();
  final monthDay =
      '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';

  await Directory('out/img/$monthDay').create(recursive: true);

  // 使用map产生一系列下载任务的Future
  final futures = uriList.asMap().entries.map((entry) async {
    final i = entry.key;
    final uri = entry.value;

    try {
      final response = await downDio.get<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
            'Accept':
                'image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5',
            'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
            'Referer': 'https://www.pixiv.net/',
            'Cookie': cookie,
          },
        ),
      );

      final name = '$id-$i.' + getExt(response.data!);
      final filePath = 'out/img/$monthDay/$name';
      await File(filePath).writeAsBytes(response.data!);

      return filePath;
    } catch (e) {
      wrn('Failed to download $uri:$i: $e');
      return null;
    }
  }).toList();

  final results = await Future.wait(futures);
  return results.whereType<String>().toList();
}

String getExt(List<int> bytes) {
  String ext = 'bin';
  if (bytes.length <= 4) return ext;

  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    ext = 'jpg';
  } else if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    ext = 'png';
  } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    ext = 'gif';
  }

  return ext;
}

String escapeMarkdownV2(String text) {
  final specialChars = r'_*[]()~`>#+-=|{}.!';
  return text.replaceAllMapped(
    RegExp('([${RegExp.escape(specialChars)}])'),
    (Match m) => '\\${m[0]}',
  );
}
