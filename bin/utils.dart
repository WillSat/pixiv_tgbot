import 'dart:io';

import 'package:dio/dio.dart';

final downDio = Dio();
final cookie = File('in/phpsessid.key').readAsStringSync();

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

void writeOut(String fileName, String content) async {
  if (!Directory('out').existsSync()) await Directory('out').create();

  await File('out/$fileName').writeAsString(content);
  log('Worte to out/$fileName');
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

bool isNumeric(String str) {
  if (str.isEmpty) return false;
  return RegExp(r'^\d+$').hasMatch(str);
}
