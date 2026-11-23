"""Exercise detection, tolerance, reporting, and missing captures using tiny fixtures."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

spec = importlib.util.spec_from_file_location('compare', Path(__file__).with_name('compare.py'))
compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare)


class ComparisonTests(unittest.TestCase):
    def test_detects_changes_and_inventory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            baseline, current, output = [root / name for name in ('base', 'current', 'report')]
            baseline.mkdir()
            current.mkdir()
            for folder in (baseline, current):
                Image.new('RGB', (10, 10), 'white').save(folder / 'same.png')
                Image.new('RGB', (10, 10), 'white').save(folder / 'changed.png')
            image = Image.open(current / 'changed.png')
            image.putpixel((2, 3), (0, 0, 0))
            image.save(current / 'changed.png')
            Image.new('RGB', (10, 10), (250, 250, 250)).save(current / 'same.png')
            Image.new('RGB', (1, 1)).save(baseline / 'removed.png')
            Image.new('RGB', (1, 1)).save(current / 'added.png')
            Image.new('RGB', (1, 1)).save(baseline / 'resized.png')
            Image.new('RGB', (2, 1)).save(current / 'resized.png')
            self.assertEqual(compare.compare(baseline, current, output), 4)
            rows = {row['name']: row for row in json.loads((output / 'results.json').read_text())}
            self.assertEqual(rows['same.png']['status'], 'unchanged')
            self.assertEqual(rows['changed.png']['changed_pixels'], 1)
            self.assertEqual(rows['changed.png']['changed_percent'], 1)
            self.assertEqual(rows['removed.png']['status'], 'missing')
            self.assertEqual(rows['added.png']['status'], 'added')
            self.assertEqual(rows['resized.png']['status'], 'resized')
            self.assertTrue((output / 'diff-changed.png').is_file())
            self.assertTrue((output / 'index.html').is_file())

    def test_cli_strict_mode_and_invalid_input(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            baseline, current = root / 'baseline', root / 'current'
            baseline.mkdir()
            current.mkdir()
            Image.new('RGB', (2, 2), 'white').save(baseline / 'a.png')
            Image.new('RGB', (2, 2), 'black').save(current / 'a.png')
            command = [sys.executable, str(Path(__file__).with_name('compare.py')),
                       str(baseline), str(current), str(root / 'report')]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(subprocess.run(command + ['--fail-on-change'], capture_output=True).returncode, 1)
            self.assertEqual(subprocess.run(command + ['--tolerance', '-1'], capture_output=True).returncode, 2)
            self.assertEqual(subprocess.run(command[:4] + [str(baseline)], capture_output=True).returncode, 2)

    def test_empty_capture_is_an_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaisesRegex(ValueError, 'No PNG'):
                compare.compare(root, root, root / 'output')


if __name__ == '__main__':
    unittest.main()
