#!/usr/bin/env python3
"""Release notes: written once from the pull requests merged since the last release, kept in the annotated tag.

    scripts/release-notes.py markdown v0.10.0 origin/main > notes.md   # the notes scripts/tag-release.sh puts in the tag
    scripts/release-notes.py html notes.md > Triwarden-0.11.0.html    # what Sparkle's update window shows
    scripts/release-notes.py --self-test

Squash merges put each pull request's title on main as one first-parent commit, so the notes are those titles,
grouped by their Conventional Commits type. docs/chore/test/ci/refactor/build/revert stay out, as do subjects that
aren't conventional. `type!:` or a `BREAKING CHANGE:` footer lists the change under Breaking changes.
"""
from __future__ import annotations

import html
import re
import subprocess
import sys

# Shown types, in order. Anything else is left out of the notes.
SECTIONS = [
    ("feat", "Features"),
    ("fix", "Fixes"),
    ("perf", "Performance"),
    ("security", "Security"),
    ("ui", "UI"),
]
SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]+)\))?(?P<bang>!)?:\s*(?P<text>.+)$")
EMPTY = "Maintenance release: no user-facing changes."


def entries(messages: list[str]) -> str:
    """Markdown notes for full commit messages (subject + body), newest first as git log prints them."""
    groups: dict[str, list[str]] = {title: [] for _, title in SECTIONS}
    breaking: list[str] = []
    titles = dict(SECTIONS)
    for message in messages:
        subject, _, body = message.strip().partition("\n")
        m = SUBJECT.match(subject.strip())
        if not m:
            continue
        scope = f"**{m['scope']}:** " if m["scope"] else ""
        line = f"* {scope}{m['text'].strip()}"
        if m["bang"] or re.search(r"^BREAKING[ -]CHANGE:", body, re.M):
            breaking.append(line)
        elif m["type"] in titles:
            groups[titles[m["type"]]].append(line)
    parts = []
    if breaking:
        parts.append("### Breaking changes\n\n" + "\n".join(breaking))
    for title, lines in groups.items():
        if lines:
            parts.append(f"### {title}\n\n" + "\n".join(lines))
    return "\n\n".join(parts) if parts else EMPTY


def markdown(since: str, until: str) -> str:
    out = subprocess.check_output(
        ["git", "log", "--first-parent", "--format=%B%x00", f"{since}..{until}"], text=True
    )
    return entries([m for m in out.split("\0") if m.strip()])


# --- HTML for Sparkle ------------------------------------------------------------------------------------------------

STYLE = """<meta charset="utf-8">
<style>
  :root { color-scheme: light dark; }
  body, div { font: 13px -apple-system, system-ui, sans-serif; line-height: 1.45; }
  h3 { font-size: 13px; font-weight: 600; margin: 14px 0 4px; }
  h3:first-child { margin-top: 0; }
  ul { margin: 0; padding-left: 18px; }
  li { margin: 3px 0; }
  .breaking { color: #c2410c; }
  code { font: 12px ui-monospace, SFMono-Regular, monospace; }
  a { color: inherit; }
</style>"""


def inline(text: str) -> str:
    """Escapes, then keeps `code` and **bold**, drops commit links like ([abc1234](…)) and plain issue links."""
    text = re.sub(r"\s*\(\[[0-9a-f]{7,40}\]\([^)]*\)\)", "", text)  # (commit hash link)
    text = re.sub(r"\[(#\d+)\]\([^)]*\)", r"\1", text)              # [#21](…) -> #21
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)            # other links -> their text
    out = html.escape(text.strip(), quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    return out


def render(notes: str) -> str:
    parts, in_list = [], False
    for raw in notes.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        heading = re.match(r"^#{1,4}\s+(.*)$", line)
        if heading:
            if in_list:
                parts.append("</ul>")
                in_list = False
            title = heading[1].strip()
            attr = ' class="breaking"' if "BREAKING" in title.upper() else ""
            parts.append(f"<h3{attr}>{html.escape(title)}</h3>")
        elif re.match(r"^\s*[*-]\s+", line):
            if not in_list:
                parts.append("<ul>")
                in_list = True
            item = re.sub(r"^\s*[*-]\s+", "", line)
            item = item[:1].upper() + item[1:]  # commit subjects start lower-case; entries read as sentences
            parts.append(f"<li>{inline(item)}</li>")
        else:
            if in_list:
                parts.append("</ul>")
                in_list = False
            parts.append(f"<p>{inline(line)}</p>")
    if in_list:
        parts.append("</ul>")
    return "\n".join(parts)


def page(notes: str) -> str:
    """No DOCTYPE or <body>, so generate_appcast embeds it in the appcast item."""
    return STYLE + "\n<div>\n" + (render(notes) or f"<p>{html.escape(EMPTY)}</p>") + "\n</div>"


# --- self-test -------------------------------------------------------------------------------------------------------

def self_test() -> None:
    notes = entries([
        "fix(extension): place overlay icons outside the field (#223)",
        "docs: explain releases (#230)",
        "feat(browser): add Zen to the native-messaging browser list (#195)",
        "Merge branch 'main' into something",
        "feat!: drop macOS 15 (#240)",
        "fix: tidy the vault list (#241)\n\nBREAKING CHANGE: the old export format is gone",
        "chore(extension): release 0.5.0 (#200)",
        "security: lock the vault after sleep (#242)",
    ])
    expected = """### Breaking changes

* drop macOS 15 (#240)
* tidy the vault list (#241)

### Features

* **browser:** add Zen to the native-messaging browser list (#195)

### Fixes

* **extension:** place overlay icons outside the field (#223)

### Security

* lock the vault after sleep (#242)"""
    assert notes == expected, f"notes:\n{notes}"
    print("PASS: notes group shown types, list breaking changes first, and drop the rest")

    assert entries(["docs: x (#1)", "chore: y (#2)"]) == EMPTY
    print("PASS: a release with nothing user-facing says so")

    out = page(notes)
    assert '<h3 class="breaking">Breaking changes</h3>' in out, out
    assert "<li><b>browser:</b> add Zen" in out, out
    assert "<li>Drop macOS 15 (#240)</li>" in out, out
    assert "<li>Lock the vault after sleep (#242)</li>" in out, out
    print("PASS: HTML capitalises entries and keeps scopes bold")

    assert "<script>" not in page("* fix <script>alert(1)</script>")
    print("PASS: HTML escapes subjects")

    out = page("## Highlights\n\n- **Sign up anywhere.** The generator is in every browser.\n\n## Fixes\n\n- x")
    assert "<h3>Highlights</h3>" in out and "<h3>Fixes</h3>" in out and "##" not in out, out
    assert "<li><b>Sign up anywhere.</b> The generator is in every browser.</li>" in out, out
    print("PASS: hand-written ## headings and - bullets render too")

    assert EMPTY in page("")
    print("PASS: empty notes still render a line")


def main() -> None:
    args = sys.argv[1:]
    if args == ["--self-test"]:
        self_test()
    elif len(args) == 3 and args[0] == "markdown":
        print(markdown(args[1], args[2]))
    elif len(args) == 2 and args[0] == "html":
        with open(args[1], encoding="utf-8") as fh:
            print(page(fh.read()))
    else:
        sys.exit("usage: release-notes.py markdown <since> <until> | html <notes.md> | --self-test")


if __name__ == "__main__":
    main()
