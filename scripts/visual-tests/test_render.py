"""Check renderer exit status and cleanup with a stand in test launcher."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class RendererTests(unittest.TestCase):
    def run_renderer(self, test_status, cleanup_fails):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scripts = root / 'scripts'
            (scripts / 'visual-tests').mkdir(parents=True)
            render = scripts / 'visual-tests/render.sh'
            shutil.copyfile(Path(__file__).with_name('render.sh'), render)
            launcher = scripts / 'test.sh'
            launcher.write_text('#!/bin/bash\nif [ "$MOCK_TEST_STATUS" != 0 ]; then exit "$MOCK_TEST_STATUS"; fi\n'
                                'for i in {1..54}; do touch "$NN_SNAPSHOT_DIR/$i.png"; done\n')
            launcher.chmod(0o755)
            temporary = root / 'tmp'
            temporary.mkdir()
            binaries = root / 'bin'
            binaries.mkdir()
            if cleanup_fails:
                find = binaries / 'find'
                find.write_text('#!/bin/bash\nexit 1\n')
                find.chmod(0o755)
            environment = dict(os.environ, TMPDIR=str(temporary), MOCK_TEST_STATUS=str(test_status),
                               PATH=str(binaries) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['/bin/bash', str(render), str(root / 'output')],
                                    env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, test_status, result.stdout + result.stderr)
            self.assertEqual('warning:' in result.stderr, cleanup_fails)
            self.assertEqual(bool(list(temporary.iterdir())), cleanup_fails)

    def test_successful_capture_and_cleanup(self):
        self.run_renderer(0, False)

    def test_cleanup_failure_does_not_fail_successful_capture(self):
        self.run_renderer(0, True)

    def test_failed_capture_is_preserved(self):
        self.run_renderer(7, False)

    def test_cleanup_failure_preserves_capture_failure(self):
        self.run_renderer(7, True)


if __name__ == '__main__':
    unittest.main()
