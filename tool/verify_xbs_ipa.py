"""Verify the compiled XBS identity and requested content in an unsigned IPA."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile


def verify(package, label):
    version, build = label.split('+')
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate archive entries'
        assert archive.testzip() is None, 'Corrupt archive entry'
        roots = {n.split('/')[1] for n in names if n.startswith('Payload/')}
        assert roots - {''} == {'Runner.app'}, 'Unexpected application payload'
        info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.fwx997.origox.xbs'
        assert info['CFBundleShortVersionString'] == version
        assert info['CFBundleVersion'] == build
        binary = archive.read('Payload/Runner.app/Frameworks/App.framework/App')
        required = [
            label, '从 JSON / XBS 文件添加', '切换站点',
            '书籍设置', '文字亮度', '字体粗细', '章节进度', '偏好设置',
            '长按选中文字', '左侧边缘滑动返回', '滑动时隐藏操作栏',
            '阅读底部栏', '检查更新', '关联本地书',
        ]
        for text in required:
            assert any(text.encode(enc) in binary for enc in ('utf-8', 'utf-16-le')), text
        forbidden = ['cyber_begging_paper', 'alipay_donation_qr', 'wechat_donation_qr']
        for token in forbidden:
            assert not any(token in name for name in names), token
            assert token.encode() not in binary, token
        assert not any('kernel_blob.bin' in name for name in names), 'Debug snapshot'
        helpers = [n for n in names if n.endswith('/flutter_assets/assets/xbs/native_helpers.js')]
        assert len(helpers) == 1, 'Missing or duplicated XBS native helpers'
        helper_bytes = archive.read(helpers[0])
        expected_helpers = Path(__file__).resolve().parents[1] / 'assets/xbs/native_helpers.js'
        assert helper_bytes == expected_helpers.read_bytes(), 'XBS helpers differ from build source'
        for symbol in [b'XPathParserWithSource', b'md5Encode', b'base64Decode', b'setCache']:
            assert symbol in helper_bytes, 'Missing XBS helper: ' + symbol.decode()
        licenses = [n for n in names if n.endswith('/flutter_assets/assets/xbs/THIRD_PARTY_LICENSES.txt')]
        assert len(licenses) == 1, 'Missing XBS helper licenses'
        assert not any('/source-audit/' in name for name in names), 'Local audit data included'
    return {
        'version': version, 'build': build, 'compiled_build_label': label,
        'required_strings_present': required, 'donation_assets_removed': True,
        'single_payload': True, 'zip_integrity': 'passed',
        'xbs_helpers_match_source': True,
        'xbs_helpers_sha256': hashlib.sha256(helper_bytes).hexdigest(),
        'xbs_helper_licenses_present': True,
        'sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
    }


if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1]), sys.argv[2]), ensure_ascii=False, indent=2))
