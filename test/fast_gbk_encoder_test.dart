import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/utils/fast_gbk_decoder.dart';

void main() {
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
