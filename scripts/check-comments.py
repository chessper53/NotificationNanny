#!/usr/bin/env python3
"""Check maintained comments against the convention in docs/ARCHITECTURE.md."""

import argparse
import ast
import io
from pathlib import Path
import re
import subprocess
import tokenize
import unicodedata


ROOT = Path(__file__).resolve().parent.parent
C_STYLE = {".swift", ".ts", ".js", ".css", ".strings"}
HASH_STYLE = {".sh", ".rb", ".yml", ".yaml"}
MARKUP = {".html", ".xml", ".plist", ".entitlements", ".md"}


def c_comments(source, language):
    """Yield comment spans, skipping strings and handling nested Swift blocks."""
    i = 0
    while i < len(source):
        if source.startswith("//", i) and language != ".css":
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            yield i, end, source[i + 2:end]
            i = end
        elif source.startswith("/*", i):
            start = i
            i += 2
            depth = 1
            while i < len(source) and depth:
                if source.startswith("/*", i) and language == ".swift":
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            yield start, i, source[start + 2:i - 2]
        else:
            raw = re.match(r'#+(?="|/)', source[i:]) if language == ".swift" and source[i] == "#" else None
            hashes = raw.group() if raw else ""
            quote_at = i + len(hashes)
            quote = source[quote_at:quote_at + 1]
            if quote in {'"', "'", "`"} or (hashes and quote == "/"):
                delimiter = '"""' if source.startswith('"""', quote_at) else quote
                closing = delimiter + hashes
                i = quote_at + len(delimiter)
                while i < len(source):
                    if source.startswith(closing, i):
                        i += len(closing)
                        break
                    if source[i] == "\\" and not hashes:
                        i += 2
                    else:
                        i += 1
            else:
                i += 1


def python_comments(source):
    lines = source.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.COMMENT:
            start = offsets[token.start[0] - 1] + token.start[1]
            end = offsets[token.end[0] - 1] + token.end[1]
            yield start, end, token.string[1:]
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) or not node.body:
            continue
        first = node.body[0]
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
            start_col = len(lines[first.lineno - 1].encode()[:first.col_offset].decode())
            end_col = len(lines[first.end_lineno - 1].encode()[:first.end_col_offset].decode())
            yield offsets[first.lineno - 1] + start_col, offsets[first.end_lineno - 1] + end_col, first.value.value


def hash_comments(source):
    offset = 0
    for line in source.splitlines(keepends=True):
        quote = None
        escaped = False
        for i, char in enumerate(line):
            if escaped:
                escaped = False
            elif char == "\\" and quote != "'":
                escaped = True
            elif quote:
                if char == quote:
                    quote = None
            elif char in {'"', "'"}:
                quote = char
            elif char == "#" and (i == 0 or line[i - 1].isspace()):
                end = len(line.rstrip("\r\n"))
                yield offset + i, offset + end, line[i + 1:end]
                break
        offset += len(line)


def comments(path, source):
    suffix = path.suffix
    if suffix in C_STYLE:
        yield from c_comments(source, suffix)
    elif suffix == ".py":
        yield from python_comments(source)
    elif suffix in HASH_STYLE or path.name in {"Makefile", ".gitignore", "robots.txt"}:
        yield from hash_comments(source)
    elif suffix in MARKUP:
        for match in re.finditer(r"<!--(.*?)-->", source, re.DOTALL):
            yield match.start(), match.end(), match.group(1)
        if suffix == ".html":
            for match in re.finditer(r"<(script|style)\b[^>]*>(.*?)</\1\s*>", source, re.DOTALL | re.IGNORECASE):
                language = ".js" if match.group(1).lower() == "script" else ".css"
                for start, end, body in c_comments(match.group(2), language):
                    yield match.start(2) + start, match.start(2) + end, body
        elif suffix == ".md":
            for match in re.finditer(r"^ *```(\w+)\n(.*?)^ *```", source, re.MULTILINE | re.DOTALL):
                language = {"swift": ".swift", "js": ".js", "javascript": ".js", "ts": ".ts", "css": ".css", "sh": ".sh", "bash": ".sh", "python": ".py", "yaml": ".yml"}.get(match.group(1))
                if language:
                    for start, end, body in comments(Path("example" + language), match.group(2)):
                        yield match.start(2) + start, match.start(2) + end, body


def forbidden(char):
    value = ord(char)
    return (
        char == "-" or unicodedata.category(char) == "Pd"
        or 0x1F000 <= value <= 0x1FAFF
        or 0x2600 <= value <= 0x27BF
        or 0x2194 <= value <= 0x2199
        or 0x21A9 <= value <= 0x21AA
        or 0x231A <= value <= 0x231B
        or 0x23E9 <= value <= 0x23F3
        or 0x23F8 <= value <= 0x23FA
        or 0x25AA <= value <= 0x25AB
        or 0x25FB <= value <= 0x25FE
        or value in {0x00A9, 0x00AE, 0x203C, 0x2049, 0x20E3, 0x2122, 0x2139, 0x2328, 0x23CF, 0x24C2, 0x25B6, 0x25C0, 0x2934, 0x2935, 0x2B05, 0x2B06, 0x2B07, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55, 0x3030, 0x303D, 0x3297, 0x3299, 0xFE0F}
    )


def violations(path, source):
    for start, end, body in comments(path, source):
        if path.name == "Package.swift" and start == 0 and re.fullmatch(r"// swift-tools-version: \d+\.\d+(?:\.\d+)?", source[start:end]):
            continue
        bad = sorted({char for char in body if forbidden(char)})
        if bad:
            yield source.count("\n", 0, start) + 1, bad


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    paths = args.paths or [Path(name) for name in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0") if name]
    failed = False
    for path in paths:
        full = path if path.is_absolute() else ROOT / path
        try:
            source = full.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line, bad in violations(path, source):
            codes = ", ".join(f"U+{ord(char):04X}" for char in bad)
            print(f"{path}:{line}: forbidden comment characters: {codes}")
            failed = True
    if not failed:
        print("Comment convention checks passed.")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
