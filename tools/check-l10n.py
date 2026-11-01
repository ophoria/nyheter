#!/usr/bin/env python3
"""Checks every Resources/l10n/<code>.lproj/Localizable.strings and Help.strings against the English source:
same keys, same placeholders (%@ / %d, positional %1$@ allowed), valid .strings syntax.
Also reports L("…") keys used in the code that are missing from English.
Usage: tools/check-l10n.py   (exit code 1 on problems)"""
import glob, os, re, subprocess, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
l10n = os.path.join(root, "Resources", "l10n")
entry = re.compile(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$', re.M)

def load(path):
    return dict(entry.findall(open(path, encoding="utf-8").read()))

def placeholders(s):
    return sorted(re.sub(r"%\d\$", "%", m) for m in re.findall(r"%(?:\d\$)?[@d]", s))

tables = ["Localizable", "Help"]
english_tables = {t: load(os.path.join(l10n, "en.lproj", f"{t}.strings")) for t in tables}
english = english_tables["Localizable"]
problems = 0

used = set()
for path in glob.glob(os.path.join(root, "App", "*.swift")) + glob.glob(os.path.join(root, "Shared", "*.swift")) + glob.glob(os.path.join(root, "Saver", "*.swift")):
    used |= set(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', open(path, encoding="utf-8").read()))
for key in sorted(used - english.keys()):
    print(f"en: key used in code but missing: {key}"); problems += 1

for folder in sorted(glob.glob(os.path.join(l10n, "*.lproj"))):
    code = os.path.basename(folder)[:-6]
    for name in tables:
        path = os.path.join(folder, f"{name}.strings")
        source = english_tables[name]
        if not os.path.exists(path):
            print(f"{code}: missing file {name}.strings"); problems += 1; continue
        if subprocess.run(["plutil", "-lint", "-s", path]).returncode != 0:
            problems += 1; continue
        table = load(path)
        for key in source:
            if key not in table:
                print(f"{code}/{name}: missing: {key}"); problems += 1
            elif placeholders(source[key]) != placeholders(table[key]):
                print(f"{code}/{name}: placeholders differ: {key}"); problems += 1
            elif name == "Help" and source[key].count("**") != table[key].count("**"):
                print(f"{code}/{name}: bold markers (**) differ: {key}"); problems += 1
        for key in table.keys() - source.keys():
            print(f"{code}/{name}: unknown key: {key}"); problems += 1

print(f"{len(glob.glob(os.path.join(l10n, '*.lproj')))} languages, {len(english)} strings + {len(english_tables['Help'])} help texts, {problems} problems")
sys.exit(1 if problems else 0)
