// 文件说明：GBK 快速解码工具，为中文 TXT 导入提供高性能解码能力。
// 技术要点：工具方法、GBK 编解码。

import 'dart:convert';
import 'dart:typed_data';

import 'src/gbk_table.dart';

final ByteData _gbkCodepoints = ByteData.sublistView(
  base64Decode(gbkCodepointsBase64),
);

int _gbkRune(int lead, int trail) {
  if (lead < 0x81 || lead > 0xfe) return 0;
  final index = (lead - 0x81) * 190 + trail - 0x40 - (trail > 0x7f ? 1 : 0);
  return _gbkCodepoints.getUint16(index * 2, Endian.little);
}

final Map<int, int> _charToGbkCode = () {
  final result = <int, int>{};
  for (var index = 0; index < 23940; index++) {
    final rune = _gbkCodepoints.getUint16(index * 2, Endian.little);
    if (rune == 0) continue;
    final lead = 0x81 + index ~/ 190;
    final column = index % 190;
    final trail = 0x40 + column + (column >= 63 ? 1 : 0);
    result[rune] = (lead << 8) | trail;
  }
  return result;
}();

/// Encodes request text using the same mapping as the fast decoder.
/// Reject unmappable characters instead of truncating their Unicode values.
Uint8List encodeGbkFast(String text) {
  final bytes = BytesBuilder(copy: false);
  for (final rune in text.runes) {
    if (rune <= 0x7f) {
      bytes.addByte(rune);
      continue;
    }
    final code = _charToGbkCode[rune];
    if (code == null) {
      throw FormatException('Character cannot be encoded as GBK', text);
    }
    bytes.add([code >> 8, code & 0xff]);
  }
  return bytes.takeBytes();
}

bool isLikelyValidGbkByteStream(Uint8List bytes) {
  int i = 0;
  while (i < bytes.length) {
    final b1 = bytes[i];
    if (b1 <= 0x7f) {
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) {
      return false;
    }
    final b2 = bytes[i + 1];
    if (!(b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F)) {
      return false;
    }
    i += 2;
  }
  return true;
}

String decodeGbkFast(Uint8List bytes, {bool lenient = true}) {
  if (bytes.isEmpty) return '';
  final output = StringBuffer();

  int i = 0;
  while (i < bytes.length) {
    final b1 = bytes[i];
    if (b1 <= 0x7f) {
      output.writeCharCode(b1);
      i += 1;
      continue;
    }

    if (i + 1 < bytes.length) {
      final b2 = bytes[i + 1];
      if (b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        final rune = _gbkRune(b1, b2);
        if (rune != 0) {
          output.writeCharCode(rune);
        } else if (lenient) {
          output.writeCharCode(b1);
          output.writeCharCode(b2);
        } else {
          output.write('\uFFFD');
        }
        i += 2;
        continue;
      }
    }

    if (lenient) {
      output.writeCharCode(b1);
    } else {
      output.write('\uFFFD');
    }
    i += 1;
  }

  return output.toString();
}
