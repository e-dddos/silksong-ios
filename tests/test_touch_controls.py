from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from scripts.common import REPO


class TouchControlTests(unittest.TestCase):
    def test_touch_key_mapping_and_short_taps(self):
        compiler = shutil.which('clang++') or shutil.which('g++')
        if not compiler:
            self.skipTest('Native touch tests require a C++ compiler')
        with tempfile.TemporaryDirectory() as tmp:
            program = Path(tmp) / 'touch-tests.exe'
            result = subprocess.run([compiler, '-std=c++17', str(REPO / 'tests/TouchStateTests.cpp'),
                                     '-o', str(program)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(program)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_native_source_is_compiled_by_xcode(self):
        config = (REPO / 'scripts/configure_xcode.rb').read_text(encoding='utf-8')
        listed = set(re.search(r'%w\[(Native[^\]]+\.mm)\]\.each', config)[1].split())
        self.assertEqual(listed, {p.name for p in (REPO / 'src/runtime').glob('*.mm')})

    def test_overlay_artwork_is_shipped(self):
        source = (REPO / 'src/runtime/NativeTouchControls.mm').read_text(encoding='utf-8')
        names = set(re.findall(r'@"([A-Za-z]+)"', source.split('@interface NativeTouchControls')[1]))
        icons = {p.stem for p in (REPO / 'src/touch').glob('*.png')}
        used = {n for n in names if n in icons}
        self.assertEqual(used, icons)
        self.assertTrue({'Ring', 'Knob', 'PortOptionsGlyph'} <= icons)
