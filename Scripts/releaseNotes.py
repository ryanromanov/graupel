#!/usr/bin/env python3
"""Prints one version's CHANGELOG.md section as an HTML fragment, for the update window.

    python3 Scripts/releaseNotes.py 0.4.0 < CHANGELOG.md

The section is the text between the version's heading and the next version's heading.
Only what CHANGELOG.md uses is handled: "### " headings, "- " items whose text may
continue on indented lines, `code`, and plain paragraphs.
"""

import html
import re
import sys


def section(lines, version):
    start = None
    for i, line in enumerate(lines):
        if re.match(rf'^{re.escape(version)} \(', line):
            start = i + 2  # skip the heading and its underline
        elif start is not None and re.match(r'^\d+\.\d+\.\d+ \(', line):
            return lines[start:i]
    if start is None:
        sys.exit(f'error: CHANGELOG.md has no section for {version}')
    return lines[start:]


def inline(text):
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', html.escape(text, quote=False))


def render(lines):
    out = []
    item = None
    in_list = False

    def flush():
        nonlocal item
        if item is not None:
            out.append(f'<li>{inline(item)}</li>')
            item = None

    for line in lines:
        if line.startswith('- '):
            flush()
            if not in_list:
                out.append('<ul>')
                in_list = True
            item = line[2:].strip()
        elif item is not None and line.startswith('  ') and line.strip():
            item += ' ' + line.strip()
        else:
            flush()
            if in_list:
                out.append('</ul>')
                in_list = False
            if line.startswith('### '):
                out.append(f'<h3>{inline(line[4:].strip())}</h3>')
            elif line.strip():
                out.append(f'<p>{inline(line.strip())}</p>')
    flush()
    if in_list:
        out.append('</ul>')
    return '\n'.join(out)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: releaseNotes.py <version> < CHANGELOG.md')
    print(render(section(sys.stdin.read().splitlines(), sys.argv[1])))
