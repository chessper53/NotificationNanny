"""Check comment detection across languages without scanning literal contents."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("comments", Path(__file__).with_name("check-comments.py"))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class CommentConventionTests(unittest.TestCase):
    def bad(self, name, source):
        return list(CHECK.violations(Path(name), source))

    def test_plain_comments_pass(self):
        for name, source in [
            ("a.swift", "// Keep the host visible.\n/// Returns nil when unavailable."),
            ("a.py", '# Keep the host visible.\n"""Capture native widgets."""'),
            ("a.sh", "#!/usr/bin/env bash\n# Restore on exit."),
            ("a.strings", '/* Sidebar tabs */\n"key" = "value";'),
            ("a.html", "<!-- Keep this explanation. -->"),
        ]:
            with self.subTest(name=name):
                self.assertFalse(self.bad(name, source))

    def test_forbidden_characters_in_all_comment_forms(self):
        for char in ["-", "\u2013", "\u2014", "\u2011", "\U0001f600", "\u2705", "\u2764\ufe0f", "1\u20e3", "\U0001f1e8\U0001f1ed"]:
            for name, source in [
                ("a.swift", f"let value = 1 // {char}"),
                ("a.ts", f"/* {char} */"),
                ("a.css", f"/* {char} */"),
                ("a.py", f"# {char}"),
                ("a.py", f'"""{char}"""'),
                ("a.sh", f"echo ok # {char}"),
                ("a.rb", f"# {char}"),
                ("a.yml", f"name: CI # {char}"),
                ("Makefile", f"# {char}"),
                (".gitignore", f"# {char}"),
                ("a.html", f"<!-- {char} -->"),
                ("a.plist", f"<!-- {char} -->"),
                ("a.strings", f"/* {char} */"),
            ]:
                with self.subTest(char=char, name=name):
                    self.assertTrue(self.bad(name, source))

    def test_literals_and_operators_are_not_comments(self):
        for name, source in [
            ("a.swift", 'let url = "https://example.org/a-b"\nlet n = 3 - 1\nlet s = #"// raw-string"#\nlet m = """\n// literal-text\n"""'),
            ("a.ts", 'const s = "/* literal-text */"; const t = `// literal-text`; const u = "https://example.org";'),
            ("a.css", 'a { background: url("https://example.org/a-b"); }'),
            ("a.py", 's = "# literal-text"\nn = 6 // 2\ns2 = "https://example.org"'),
            ("a.sh", 'echo "# literal-text"\necho ${#items[@]}\necho "${item#prefix}"'),
            ("a.yml", 'name: "# literal-text"'),
            ("a.strings", '"key" = "/* literal-text */";'),
        ]:
            with self.subTest(name=name):
                self.assertFalse(self.bad(name, source))

    def test_only_required_manifest_directive_is_exempt(self):
        self.assertFalse(self.bad("Package.swift", "// swift-tools-version: 5.9\nimport PackageDescription"))
        self.assertTrue(self.bad("other.swift", "// swift-tools-version: 5.9"))
        self.assertTrue(self.bad("Package.swift", "\n// swift-tools-version: 5.9"))
        self.assertTrue(self.bad("Package.swift", "// swift-tools-version: 5.9 extra-text"))
        self.assertTrue(self.bad("Package.swift", "// swift-tools-version: 5.9\n// ordinary-comment"))

    def test_nested_swift_comments_and_line_numbers(self):
        source = 'let x = 1\n/* Outer /* nested */ bad-comment */\n// another-comment'
        self.assertEqual([line for line, _ in self.bad("a.swift", source)], [2, 3])

    def test_python_docstrings_include_classes_and_functions(self):
        source = 'class Example:\n    """bad-comment"""\n    def method(self):\n        """bad-comment"""\n        return "# literal-text"\n'
        self.assertEqual([line for line, _ in self.bad("a.py", source)], [2, 4])

    def test_markup_and_markdown_code_examples(self):
        self.assertTrue(self.bad("a.html", '<script>const s = "https://example.org"; /* bad-comment */</script>'))
        self.assertTrue(self.bad("a.html", '<style>/* bad-comment */</style>'))
        self.assertTrue(self.bad("a.md", 'Ordinary prose-with-dashes.\n```swift\n// bad-comment\n```'))
        self.assertFalse(self.bad("a.md", 'Ordinary prose-with-dashes.\n```sh\necho "--flag"\n```'))


if __name__ == "__main__":
    unittest.main()
