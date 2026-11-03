#!/usr/bin/env python3
"""Checks Graupel's Help: links that lead nowhere, and writing that breaks docs/HELP_STYLE.md.

    python3 Scripts/checkHelp.py [page.html ...]

With no pages, checks every page. Link errors fail the check; style findings are listed for review.
"""
import html
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "CotEditor", "Resources", "Graupel.help", "Contents", "Resources")
BOOK = os.path.join(ROOT, "en.lproj")

# pages allowed to name CotEditor (see docs/HELP_STYLE.md)
CREDIT_PAGES = {"about_sourcecode.html", "releasenotes.html"}

BANNED = [
    "seamless", "robust", "powerful", "effortless", "intuitive", "leverage", "utilize", "delve", "streamline",
    "elevate", "enhance", "empower", "unlock", "harness", "crucial", "vital", "comprehensive",
    "simply", "just", "easily", "quickly", "of course", "note that", "worth noting", "keep in mind",
    "whether you", "in this section", "let's", "in summary", "additionally", "moreover", "furthermore",
    "that said", "not only", "preferences",
]


def pages(arguments):
    if arguments:
        return [os.path.abspath(a) for a in arguments]
    found = [os.path.join(BOOK, "Graupel.html"), os.path.join(BOOK, "toc.html")]
    for name in sorted(os.listdir(os.path.join(BOOK, "pgs"))):
        if name.endswith(".html"):
            found.append(os.path.join(BOOK, "pgs", name))
    return found


def text_of(source):
    """The visible text of a page, without tags, code, and keyboard keys."""
    source = re.sub(r"<(script|style|code|kbd|pre)\b.*?</\1>", " ", source, flags=re.S | re.I)
    source = re.sub(r"<[^>]+>", " ", source)
    return html.unescape(source)


def check(path):
    errors, findings = [], []
    source = open(path, encoding="utf-8").read()
    folder = os.path.dirname(path)

    for target in re.findall(r'(?:href|src)="([^"#:]+)(?:#[^"]*)?"', source):
        if not os.path.exists(os.path.normpath(os.path.join(folder, target))):
            errors.append(f"broken link: {target}")

    text = text_of(source)
    lowered = text.lower()
    for word in BANNED:
        for match in re.finditer(r"\b" + re.escape(word) + r"\b", lowered):
            context = text[max(match.start() - 30, 0):match.end() + 30].replace("\n", " ")
            findings.append(f"'{word}': …{context.strip()}…")
    if text.count("—") > 1:
        findings.append(f"{text.count('—')} em dashes (at most one per page)")
    if "!" in re.sub(r"<[^>]+>", "", text):
        findings.append("exclamation mark")
    if "CotEditor" in text and os.path.basename(path) not in CREDIT_PAGES:
        findings.append(f"names CotEditor {text.count('CotEditor')} times")
    for heading in re.findall(r"<h[1-3][^>]*>(.*?)</h[1-3]>", source, flags=re.S):
        words = re.sub(r"<[^>]+>", "", heading).split()
        if len(words) > 2 and all(w[:1].isupper() for w in words[1:] if w.isalpha() and len(w) > 3):
            findings.append(f"Title Case heading: {' '.join(words)}")
    return errors, findings


def main():
    failed = False
    for path in pages(sys.argv[1:]):
        errors, findings = check(path)
        if errors or findings:
            print(os.path.relpath(path, BOOK))
            for line in errors:
                print("  ERROR", line)
            for line in findings:
                print("  style", line)
        failed = failed or bool(errors)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
