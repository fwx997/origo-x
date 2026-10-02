import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:xxread/utils/fast_gbk_decoder.dart';

void main() {
  test('decodes GBK boundary pairs and malformed trailing bytes', () {
    expect(decodeGbkFast(Uint8List.fromList([0xd6, 0xd0, 0xce, 0xc4])), '中文');
    expect(
      decodeGbkFast(
        Uint8List.fromList([0x81, 0x40, 0xfe, 0xfe]),
        lenient: false,
      ),
      '丂\uFFFD',
    );
    expect(decodeGbkFast(Uint8List.fromList([0xbd]), lenient: false), '\uFFFD');
  });
  test('encodes ASCII and Chinese request text as standard GBK bytes', () {
    expect(encodeGbkFast('q=中文 A'), [
      0x71,
      0x3d,
      0xd6,
      0xd0,
      0xce,
      0xc4,
      0x20,
      0x41,
    ]);
    expect(encodeGbkFast(''), isEmpty);
  });

  test('rejects unsupported characters instead of emitting corrupt bytes', () {
    expect(() => encodeGbkFast('书📖'), throwsFormatException);
  });
}
