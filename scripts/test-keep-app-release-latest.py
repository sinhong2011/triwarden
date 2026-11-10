#!/usr/bin/env python3
"""The extension release must not remain GitHub's Latest release.

release-please cannot pass make_latest, so scripts/keep-app-release-latest.sh
turns Latest off for extension-v* and points it at the app release (vX.Y.Z).
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "keep-app-release-latest.sh"

FAKE_GH = r"""#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path

args = sys.argv[1:]
with Path(os.environ["FAKE_GH_LOG"]).open("a") as fh:
    fh.write(json.dumps(args) + "\n")

def flag(name):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args) and not args[i + 1].startswith("-"):
            return args[i + 1]
    prefix = name + "="
    for arg in args:
        if arg.startswith(prefix):
            return arg.split("=", 1)[1]
    return None

if args and args[0] == "api":
    data = json.loads(Path(os.environ["FAKE_GH_RELEASES"]).read_text())
    proc = subprocess.run(
        ["jq", "-r", flag("--jq")],
        input=json.dumps(data).encode(),
        capture_output=True,
    )
    sys.stdout.buffer.write(proc.stdout)
    sys.stderr.buffer.write(proc.stderr)
    raise SystemExit(proc.returncode)

state_path = Path(os.environ["FAKE_GH_STATE"])
state = json.loads(state_path.read_text()) if state_path.exists() else {}

if args[:2] == ["release", "edit"]:
    tag = args[2]
    latest = flag("--latest")
    state.setdefault("edits", []).append({"tag": tag, "latest": latest})
    if latest == "true":
        state["latest"] = tag
    elif latest == "false" and state.get("latest") == tag:
        state["latest"] = None
    state_path.write_text(json.dumps(state))
    raise SystemExit(0)

if args[:2] == ["release", "view"]:
    forced = os.environ.get("FAKE_GH_FORCE_LATEST")
    tag = forced if forced else state.get("latest")
    proc = subprocess.run(
        ["jq", "-r", flag("--jq")],
        input=json.dumps({"tagName": tag}).encode(),
        capture_output=True,
    )
    sys.stdout.buffer.write(proc.stdout)
    raise SystemExit(proc.returncode)

sys.stderr.write("unexpected gh invocation: %s\n" % args)
raise SystemExit(2)
"""

RELEASES = [
    {
        "tag_name": "extension-v0.4.3",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-11-09T11:24:46Z",
    },
    {
        "tag_name": "v0.9.1",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-11-09T11:07:40Z",
    },
    {
        "tag_name": "v0.10.0",
        "draft": True,
        "prerelease": False,
        "published_at": "2026-11-10T00:00:00Z",
    },
    {
        "tag_name": "v0.9.1-beta",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-11-10T01:00:00Z",
    },
    {
        "tag_name": "v0.9.0",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-11-07T16:26:02Z",
    },
]


def run(tag, app_tag=None, *, releases=None, force_latest=None, initial_latest=None):
    with tempfile.TemporaryDirectory(prefix="triwarden-latest-") as directory:
        root = Path(directory)
        gh = root / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        (root / "releases.json").write_text(json.dumps(releases if releases is not None else RELEASES))
        env = dict(
            os.environ,
            PATH=f"{root}{os.pathsep}{os.environ.get('PATH', '')}",
            GITHUB_REPOSITORY="sinhong2011/triwarden",
            FAKE_GH_LOG=str(root / "log"),
            FAKE_GH_STATE=str(root / "state.json"),
            FAKE_GH_RELEASES=str(root / "releases.json"),
        )
        if initial_latest is not None:
            (root / "state.json").write_text(json.dumps({"latest": initial_latest}))
        if force_latest is not None:
            env["FAKE_GH_FORCE_LATEST"] = force_latest
        cmd = ["bash", str(SCRIPT), tag]
        if app_tag is not None:
            cmd.append(app_tag)
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        log_path = root / "log"
        calls = [json.loads(line) for line in log_path.read_text().splitlines()] if log_path.exists() else []
        return result, calls


def edits(calls):
    found = []
    for args in calls:
        if args[:2] != ["release", "edit"]:
            continue
        latest = None
        for arg in args:
            if arg.startswith("--latest="):
                latest = arg.split("=", 1)[1]
        found.append((args[2], latest))
    return found


def test_refuses_non_extension_tag():
    result, calls = run("v0.9.1")
    assert result.returncode != 0, result.stdout + result.stderr
    assert calls == [], calls
    print("PASS: non-extension tag is refused before any release edit")


def test_explicit_app_tag_from_this_run():
    result, calls = run("extension-v0.5.0", "v0.10.0", initial_latest="extension-v0.5.0")
    assert result.returncode == 0, result.stdout + result.stderr
    assert edits(calls) == [("extension-v0.5.0", "false"), ("v0.10.0", "true")], edits(calls)
    assert not any(args and args[0] == "api" for args in calls), calls
    print("PASS: this run's app release stays Latest")


def test_selects_newest_published_app_release():
    result, calls = run("extension-v0.5.0", initial_latest="extension-v0.5.0")
    assert result.returncode == 0, result.stdout + result.stderr
    assert edits(calls) == [("extension-v0.5.0", "false"), ("v0.9.1", "true")], edits(calls)
    print("PASS: newest published vX.Y.Z stays Latest")


def test_ignores_a_non_app_second_argument():
    result, calls = run("extension-v0.5.0", "extension-v0.5.0", initial_latest="extension-v0.5.0")
    assert result.returncode == 0, result.stdout + result.stderr
    assert edits(calls)[-1] == ("v0.9.1", "true"), edits(calls)
    print("PASS: a non-app tag is not marked Latest")


def test_fails_when_no_app_release_exists():
    result, calls = run("extension-v0.5.0", releases=[])
    assert result.returncode != 0, result.stdout + result.stderr
    assert edits(calls) == [], edits(calls)
    print("PASS: missing app release edits nothing")


def test_fails_when_latest_does_not_stick():
    result, calls = run("extension-v0.5.0", "v0.10.0", force_latest="extension-v0.5.0")
    assert result.returncode != 0, result.stdout + result.stderr
    assert ("v0.10.0", "true") in edits(calls)
    print("PASS: a Latest pointer that stays on the extension fails the script")


if __name__ == "__main__":
    test_refuses_non_extension_tag()
    test_explicit_app_tag_from_this_run()
    test_selects_newest_published_app_release()
    test_ignores_a_non_app_second_argument()
    test_fails_when_no_app_release_exists()
    test_fails_when_latest_does_not_stick()
