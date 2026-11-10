#!/usr/bin/env python3
"""The app release PR must set package.json to the new app version.

Feature PRs leave the store version alone. release-please extra-files sets
BrowserExtension/WebExtension/package.json to MARKETING_VERSION. The script
must reject a conflicted .release-please-manifest.json so that cannot land.
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
PROJECT = Path("project.yml")


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=check,
        text=True,
        capture_output=True,
    )


def write_tree(repo: Path, *, app: str, pkg: str, manifest: str | None = None) -> None:
    (repo / PKG).parent.mkdir(parents=True, exist_ok=True)
    (repo / PKG).write_text(json.dumps({"name": "triwarden-extension", "version": pkg}) + "\n")
    (repo / PROJECT).write_text(f'settings:\n  base:\n    MARKETING_VERSION: "{app}" # x-release-please-version\n')
    (repo / MANIFEST).write_text(
        manifest if manifest is not None else json.dumps({".": app}) + "\n"
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
    write_tree(repo, app="0.10.0", pkg="0.5.0")
    base = commit(repo, "released")
    write_tree(repo, app="0.10.1", pkg="0.10.1")
    commit(repo, "chore: release 0.10.1")
    result = run_script(repo, base)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "0.5.0 → 0.10.1" in result.stdout, result.stdout
    print("PASS: package.json matching the new app version is above the base store version")


def test_package_must_match_app_version() -> None:
    repo = make_repo()
    write_tree(repo, app="0.10.0", pkg="0.5.0")
    base = commit(repo, "released")
    write_tree(repo, app="0.10.1", pkg="0.5.1")
    commit(repo, "chore: release 0.10.1")
    result = run_script(repo, base)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "MARKETING_VERSION is 0.10.1" in result.stderr, result.stderr
    print("PASS: package.json not matching MARKETING_VERSION fails")


def test_same_store_version_fails() -> None:
    repo = make_repo()
    write_tree(repo, app="0.10.0", pkg="0.10.0")
    base = commit(repo, "released")
    write_tree(repo, app="0.10.0", pkg="0.10.0")
    (repo / PKG.parent / "wxt.config.ts").write_text("// zip input\n")
    commit(repo, "chore: release 0.10.0")
    result = run_script(repo, base)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "not greater than the PR base 0.10.0" in result.stderr, result.stderr
    print("PASS: package.json still at the base store version fails")


def test_conflicted_manifest_fails() -> None:
    repo = make_repo()
    write_tree(repo, app="0.10.0", pkg="0.5.0")
    base = commit(repo, "released")
    write_tree(repo, app="0.10.1", pkg="0.10.1")
    (repo / MANIFEST).write_text(
        '<<<<<<< HEAD\n{".":"0.10.0"}\n=======\n{".":"0.10.1"}\n>>>>>>> pr\n'
    )
    commit(repo, "chore: release 0.10.1")
    result = run_script(repo, base)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "not valid JSON" in result.stderr, result.stderr
    print("PASS: conflict markers in the manifest fail")


if __name__ == "__main__":
    os.environ.setdefault("GIT_AUTHOR_DATE", "2026-11-10T00:00:00Z")
    os.environ.setdefault("GIT_COMMITTER_DATE", "2026-11-10T00:00:00Z")
    test_release_please_commit_passes()
    test_package_must_match_app_version()
    test_same_store_version_fails()
    test_conflicted_manifest_fails()
