#!/usr/bin/env python3
"""The extension release PR must compare package.json to the *base* manifest.

release-please bumps BrowserExtension/WebExtension in
.release-please-manifest.json in the same commit as package.json. Reading the
working-tree manifest would compare 0.5.0 to 0.5.0 and fail a correct release.
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ci" / "check-extension-version.sh"
PKG = Path("BrowserExtension/WebExtension/package.json")
MANIFEST = Path(".release-please-manifest.json")


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=check,
        text=True,
        capture_output=True,
    )


def write_tree(repo: Path, *, app: str, extension: str, pkg: str) -> None:
    (repo / PKG).parent.mkdir(parents=True, exist_ok=True)
    (repo / PKG).write_text(json.dumps({"name": "triwarden-extension", "version": pkg}) + "\n")
    (repo / MANIFEST).write_text(
        json.dumps({".": app, "BrowserExtension/WebExtension": extension}) + "\n"
    )


def commit(repo: Path, message: str) -> str:
    git(repo, "add", "-A")
    git(repo, "commit", "-m", message)
    return git(repo, "rev-parse", "HEAD").stdout.strip()


def run_script(repo: Path, base: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), base],
        cwd=repo,
        text=True,
        capture_output=True,
    )


def make_repo() -> Path:
    repo = Path(tempfile.mkdtemp(prefix="ext-ver-"))
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.email", "ci@example.com")
    git(repo, "config", "user.name", "ci")
    return repo


def test_release_please_commit_passes() -> None:
    repo = make_repo()
    write_tree(repo, app="0.9.1", extension="0.4.3", pkg="0.4.3")
    base = commit(repo, "released")
    write_tree(repo, app="0.9.1", extension="0.5.0", pkg="0.5.0")
    commit(repo, "chore(extension): release 0.5.0")
    result = run_script(repo, base)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "released 0.4.3 → 0.5.0" in result.stdout, result.stdout
    print("PASS: release-please commit (manifest and package.json both 0.5.0) is above 0.4.3")


def test_same_version_fails() -> None:
    repo = make_repo()
    write_tree(repo, app="0.9.1", extension="0.4.3", pkg="0.4.3")
    base = commit(repo, "released")
    write_tree(repo, app="0.9.1", extension="0.4.3", pkg="0.4.3")
    (repo / PKG.parent / "wxt.config.ts").write_text("// zip input\n")
    commit(repo, "chore(extension): release 0.4.3")
    result = run_script(repo, base)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "0.4.3 is not greater than last released 0.4.3" in result.stderr, result.stderr
    print("PASS: package.json still at the last released version fails")


def test_lower_version_fails() -> None:
    repo = make_repo()
    write_tree(repo, app="0.9.1", extension="0.4.3", pkg="0.4.3")
    base = commit(repo, "released")
    write_tree(repo, app="0.9.1", extension="0.4.2", pkg="0.4.2")
    commit(repo, "chore(extension): release 0.4.2")
    result = run_script(repo, base)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "0.4.2 is not greater than last released 0.4.3" in result.stderr, result.stderr
    print("PASS: a lower package.json fails")


def test_uses_base_manifest_not_head() -> None:
    repo = make_repo()
    write_tree(repo, app="0.10.0", extension="0.4.3", pkg="0.4.3")
    base = commit(repo, "app 0.10.0 already released")
    write_tree(repo, app="0.10.0", extension="0.5.0", pkg="0.5.0")
    commit(repo, "chore(extension): release 0.5.0")
    result = run_script(repo, base)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "released 0.4.3 → 0.5.0" in result.stdout, result.stdout
    print("PASS: last released version comes from the PR base manifest")


if __name__ == "__main__":
    os.environ.setdefault("GIT_AUTHOR_DATE", "2026-11-10T00:00:00Z")
    os.environ.setdefault("GIT_COMMITTER_DATE", "2026-11-10T00:00:00Z")
    test_release_please_commit_passes()
    test_same_version_fails()
    test_lower_version_fails()
    test_uses_base_manifest_not_head()
