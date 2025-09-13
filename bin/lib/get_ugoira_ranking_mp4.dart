import 'dart:io';
import 'package:dio/dio.dart';
import '../utils.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

const crf = 18;

final proxy = File('in/imgProxy.key').readAsStringSync();
final cookie = File('in/phpsessid.key').readAsStringSync();

final dio = Dio(
  BaseOptions(
    headers: {
      'Referer': 'https://www.pixiv.net',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
      'Cookie': cookie,
    },
  ),
);

/// 下载指定 Pixiv ugoira 并合成为 MP4 文件 (HEVC/H.265)
///
/// [pid] Pixiv 插画 ID
///
/// 返回：生成的 MP4 文件路径（绝对路径），失败时返回 null
Future<String?> downloadUgoiraAsMp4(String pid) async {
  try {
    // 1. 获取动图元数据
    final metaUrl = 'https://www.pixiv.net/ajax/illust/$pid/ugoira_meta';
    final metaResp = await dio.get(metaUrl);
    final meta = metaResp.data;

    if (meta['error'] == true) {
      wrn('Failed to get PIXIV metadata: ${meta['message']}');
      return null;
    }

    final body = meta['body'];
    final zipUrl = body['originalSrc'] as String;
    final frames = (body['frames'] as List)
        .map((f) => FrameInfo(file: f['file'], delay: f['delay']))
        .toList();

    log('Downloading: $zipUrl');

    // 2. 下载 zip
    final tmpDir = Directory('${Directory.current.path}/temp_$pid');
    tmpDir.createSync(recursive: true);
    final zipPath = p.join(tmpDir.path, '$pid.zip');
    await dio.download(proxy + zipUrl, zipPath);

    // 3. 解压 zip
    final extractDir = Directory(p.join(tmpDir.path, 'frames'));
    extractDir.createSync(recursive: true);

    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(inputStream);
    inputStream.close();

    for (final file in archive) {
      if (file.isFile) {
        final filePath = p.join(extractDir.path, file.name);
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      }
    }

    // 4. 生成 concat 列表文件（ffmpeg 合成用）
    final concatFile = File(p.join(tmpDir.path, 'concat.txt'));
    final sb = StringBuffer();
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final delaySec = frame.delay / 1000.0;
      sb.writeln(
        "file '${p.join(extractDir.path, frame.file).replaceAll("\\", "/")}'",
      );
      if (i < frames.length - 1) {
        sb.writeln('duration $delaySec');
      }
    }
    // 最后一帧重复一次（无 duration）
    final lastFrame = frames.last;
    sb.writeln(
      "file '${p.join(extractDir.path, lastFrame.file).replaceAll("\\", "/")}'",
    );
    concatFile.writeAsStringSync(sb.toString());

    // 5. 调用 ffmpeg 合成 mp4 (H.265)
    final outputPath = '${tmpDir.path}/$pid-$crf.mp4';
    final ffmpegArgs = [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', concatFile.path,
      '-vsync', 'vfr',
      '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2', // 保证偶数宽高
      '-c:v', 'libx265',
      '-preset', 'fast',
      '-crf', crf.toString(), // 码率控制：值越小画质越好（推荐 23-28）
      '-pix_fmt', 'yuv420p',
      outputPath,
    ];
    final result = await Process.run('ffmpeg', ffmpegArgs);

    if (result.exitCode == 0) {
      log('MP4 file successfully created: $outputPath');
      return outputPath;
    } else {
      wrn('Something wrong with ffmpeg:\n${result.stderr}');
      return null;
    }
  } catch (e) {
    wrn('Error in downloadUgoiraAsMp4: $e');
    return null;
  }
}

class FrameInfo {
  final String file;
  final int delay;
  FrameInfo({required this.file, required this.delay});
}
