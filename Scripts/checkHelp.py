#!/usr/bin/env python3
"""Checks Graupel's Help: links that lead nowhere, anchors the app opens that are missing, and writing that breaks
docs/HELP_STYLE.md.

    python3 Scripts/checkHelp.py [page.html ...]

With no pages, checks every page and the anchors. Link and anchor errors fail the check; style findings are listed
for review.
"""
import html
import os
import re
import sys

REPO = os.path.join(os.path.dirname(__file__), "..")
ROOT = os.path.join(REPO, "CotEditor", "Resources", "Graupel.help", "Contents", "Resources")
BOOK = os.path.join(ROOT, "en.lproj")

# pages allowed to name CotEditor (see docs/HELP_STYLE.md)
CREDIT_PAGES = {"about_sourcecode.html", "releasenotes.html"}

# names that keep their capitals in sentence-case headings
PROPER_NOUNS = {"Graupel", "CotEditor", "Boreas", "Graupel User Guide", "AppleScript", "Unicode", "Finder", "Terminal",
                "Mode", "Settings", "Markdown", "Python", "JavaScript", "Shift", "Japanese", "iCloud", "Apple"}

# anchors the app names that have no page on purpose
UNUSED_ANCHORS = {"about_donation"}  # the donation window can't be opened

BANNED = [
    "seamless", "robust", "powerful", "effortless", "intuitive", "leverage", "utilize", "delve", "streamline",
    "elevate", "enhance", "empower", "harness", "crucial", "vital", "comprehensive",
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


def anchors_in(source):
    return re.findall(r'<a name="([^"]+)"', source) + re.findall(r'\bid="([^"]+)"', source)


def app_anchors():
    """The Help anchors the app opens, from HelpLink(anchor:) and helpAnchor: in the source."""
    found = set()
    for folder in ("CotEditor/Sources", "Packages"):
        for directory, _, files in os.walk(os.path.join(REPO, folder)):
            for name in files:
                if name.endswith(".swift"):
                    source = open(os.path.join(directory, name), encoding="utf-8").read()
                    found.update(re.findall(r'(?:helpAnchor|anchor): "([^"]+)"', source))
    return found


def check_anchors(paths):
    """Each anchor the app opens is on exactly one page, and no anchor name is used twice."""
    errors = []
    owners = {}
    for path in paths:
        for name in re.findall(r'<a name="([^"]+)"', open(path, encoding="utf-8").read()):
            owners.setdefault(name, []).append(os.path.relpath(path, BOOK))
    for name, where in sorted(owners.items()):
        if len(where) > 1:
            errors.append(f"anchor {name} is on {len(where)} pages: {', '.join(where)}")
    for name in sorted(app_anchors() - UNUSED_ANCHORS):
        if name not in owners:
            errors.append(f"the app opens anchor {name}, but no page has it")
    return errors


def check(path):
    errors, findings = [], []
    source = open(path, encoding="utf-8").read()
    folder = os.path.dirname(path)

    for target, fragment in re.findall(r'(?:href|src)="([^"#:]+)(?:#([^"]*))?"', source):
        target_path = os.path.normpath(os.path.join(folder, target))
        if not os.path.exists(target_path):
            errors.append(f"broken link: {target}")
        elif fragment and fragment not in anchors_in(open(target_path, encoding="utf-8").read()):
            errors.append(f"broken link: {target}#{fragment}")

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
        heading = html.unescape(re.sub(r"<[^>]+>", "", heading)).strip()
        # later words that aren't short or proper names should be lowercase
        later = [w.strip("“”‘’\"'.,:;()") for w in heading.split()[1:]]
        later = [w for w in later if len(w) > 3 and w.isalpha() and w not in PROPER_NOUNS]
        if heading not in PROPER_NOUNS and len(later) >= 2 and all(w[:1].isupper() for w in later):
            findings.append(f"Title Case heading: {heading}")
    return errors, findings


def main():
    failed = False
    if not sys.argv[1:]:
        for line in check_anchors(pages([])):
            print("  ERROR", line)
            failed = True
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
