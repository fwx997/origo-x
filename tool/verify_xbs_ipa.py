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
        required = [label, '从 JSON / XBS 文件添加', '切换站点']
        for text in required:
            assert any(text.encode(enc) in binary for enc in ('utf-8', 'utf-16-le')), text
        forbidden = ['cyber_begging_paper', 'alipay_donation_qr', 'wechat_donation_qr']
        for token in forbidden:
            assert not any(token in name for name in names), token
            assert token.encode() not in binary, token
        assert not any('kernel_blob.bin' in name for name in names), 'Debug snapshot'
    return {
        'version': version, 'build': build, 'compiled_build_label': label,
        'required_strings_present': required, 'donation_assets_removed': True,
        'single_payload': True, 'zip_integrity': 'passed',
        'sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
    }


if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1]), sys.argv[2]), ensure_ascii=False, indent=2))
