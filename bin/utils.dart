import 'dart:io';

// ── Logger ──

void LOG(String msg) => _emit('LOG', msg);
void WRN(String msg) => _emit('WRN', msg);
void ERR(String msg) => _emit('ERR', msg, toStderr: true);

void _emit(String level, String msg, {bool toStderr = false}) {
  final now = DateTime.now();
  final ts = '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  final line = '[$ts] [$level] $msg';
  if (toStderr) {
    stderr.writeln(line);
  } else {
    print(line);
  }
}

// ── HTML ──

/// Escape special characters for Telegram HTML parse mode.
String escapeHTML(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

// ── Helpers ──

bool isNumeric(String str) {
  if (str.isEmpty) return false;
  return RegExp(r'^\d+$').hasMatch(str);
}

/// Detect image extension from magic bytes.
String getExt(List<int> bytes) {
  if (bytes.length < 4) return 'bin';
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
  return 'bin';
}
