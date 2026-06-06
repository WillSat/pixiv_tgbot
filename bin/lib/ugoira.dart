import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../utils.dart';
import 'config.dart';
import 'pixiv_api.dart';

final _downloadDio = Dio();

const _crf = 18; // visually lossless for H.264

/// Download a Pixiv ugoira ZIP, extract frames, and convert to MP4 (H.264).
///
/// Returns the path to the MP4 file, or null on failure.
Future<String?> downloadUgoiraAsMp4(int illustId) async {
  // 1. Get metadata
  final meta = await getUgoiraMeta(illustId);
  if (meta == null) return null;

  final (zipUrl: zipUrl, frames: frames) = meta;
  LOG('Downloading ugoira $illustId: $zipUrl');

  // 2. Set up temp directory
  final tmpDir = Directory('${Directory.current.path}/temp_$illustId')
    ..createSync(recursive: true);

  try {
    final zipPath = p.join(tmpDir.path, '$illustId.zip');
    await _downloadDio.download(Config.proxy + zipUrl, zipPath);

    // 3. Extract zip
    final extractDir = Directory(p.join(tmpDir.path, 'frames'))
      ..createSync(recursive: true);

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

    // ZIP no longer needed — frames are extracted
    try {
      File(zipPath).deleteSync();
    } catch (_) {}

    // 4. Generate concat file for ffmpeg
    final concatFile = File(p.join(tmpDir.path, 'concat.txt'));
    final sb = StringBuffer();
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      sb.writeln(
        "file '${p.join(extractDir.path, frame.file).replaceAll('\\', '/')}'",
      );
      if (i < frames.length - 1) {
        sb.writeln('duration ${frame.delay / 1000.0}');
      }
    }
    // Repeat the last frame so it has a visible duration
    final lastFrame = frames.last;
    sb.writeln(
      "file '${p.join(extractDir.path, lastFrame.file).replaceAll('\\', '/')}'",
    );
    concatFile.writeAsStringSync(sb.toString());

    // 5. Encode with ffmpeg: concat frames → H.264 MP4
    //    x264 veryfast is ~200x faster than x265 fast on single-core CPUs
    final outputPath = '${tmpDir.path}/$illustId-$_crf.mp4';

    Future<int> runFfmpeg(String preset, String crf) async {
      final process = await Process.start('ffmpeg', [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', concatFile.path,
        '-vsync', 'vfr',
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v', 'libx264',
        '-preset', preset,
        '-crf', crf,
        '-pix_fmt', 'yuv420p',
        outputPath,
      ]);

      process.stdout.drain();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      final stderrStr = await stderrFuture;

      if (code != 0) {
        WRN('ffmpeg exit=$code preset=$preset crf=$crf for $illustId:\n$stderrStr');
      }
      return code;
    }

    final exitCode = await runFfmpeg('veryfast', _crf.toString());
    if (exitCode == 0) {
      LOG('MP4 file created: $outputPath');
    } else {
      // Retry with ultrafast for problematic files
      LOG('Retrying with ultrafast for $illustId');
      final retryCode = await runFfmpeg('ultrafast', '28');
      if (retryCode != 0) return null;
      LOG('MP4 file created (ultrafast fallback): $outputPath');
    }

    // Clean up intermediate files — only the MP4 remains
    try {
      if (concatFile.existsSync()) concatFile.deleteSync();
    } catch (_) {}
    try {
      if (extractDir.existsSync()) extractDir.deleteSync(recursive: true);
    } catch (_) {}

    return outputPath;
  } catch (e) {
    WRN('Error in downloadUgoiraAsMp4: $e');
    return null;
  }
}
