#!/usr/bin/env python3
"""`tw install-chrome` and `tw install-firefox` must name the real binary, however tw was started.

Run through PATH (the Homebrew symlink), argv[0] is just "tw"; resolving that against the
working directory wrote a manifest pointing at a file that does not exist, so Chrome could
not start the host. These cases run the built binary with a throwaway home directory, so the
developer's own browser configuration is never touched.

It also checks the Firefox add-on id in tw against the one the extension is built with, and that tw answers
when Firefox starts it as a native-messaging host.
"""
from pathlib import Path
import json
import os
import re
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path(os.environ.get("TW_BINARY") or root / "build/Build/Products/Debug/tw")
if not binary.exists():
    raise SystemExit(f"{binary} is missing; build it first with `make build` (or `xcodebuild -scheme tw build`)")
real = binary.resolve()
host = "io.github.sinhong2011.triwarden"
extension_id = "a" * 32


def manifest_in(home):
    return home / "Library/Application Support/Google/Chrome/NativeMessagingHosts" / f"{host}.json"


def run(args, cwd, home):
    """Run tw with a throwaway home, so manifests land there instead of the real one."""
    env = dict(os.environ, CFFIXED_USER_HOME=str(home), PATH=f"{home / 'bin'}:{os.environ['PATH']}")
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)


def check(label, args, cwd):
    with tempfile.TemporaryDirectory(prefix="triwarden-install-chrome-") as directory:
        home = Path(directory)
        (home / "bin").mkdir()
        (home / "Library/Application Support/Google/Chrome").mkdir(parents=True)
        (home / "elsewhere").mkdir()
        (home / "bin/tw").symlink_to(binary)

        result = run(args, cwd(home), home)
        assert result.returncode == 0, f"{label}: tw failed:\n{result.stdout}\n{result.stderr}"

        path = manifest_in(home)
        assert path.exists(), f"{label}: no manifest written:\n{result.stdout}"
        manifest = json.loads(path.read_text())
        written = Path(manifest["path"])

        # The regression: a relative argv[0] resolved against the working directory.
        assert written.is_absolute(), f"{label}: manifest path is not absolute: {written}"
        assert written == real, f"{label}: manifest names {written}, expected {real}"
        assert written.exists(), f"{label}: manifest names a file that does not exist: {written}"
        assert manifest["name"] == host and manifest["type"] == "stdio", f"{label}: bad manifest: {manifest}"
        assert manifest["allowed_origins"] == [f"chrome-extension://{extension_id}/"], f"{label}: bad origins: {manifest}"
        print(f"PASS: {label}")


check("via PATH symlink", ["tw", "install-chrome", extension_id], lambda home: home / "elsewhere")
check("via absolute path", [str(real), "install-chrome", extension_id], lambda home: home / "elsewhere")
check("via relative path", ["./tw", "install-chrome", extension_id], lambda home: home / "bin")

# A rejected id must not leave a manifest behind, so a bad invocation cannot break a good install.
with tempfile.TemporaryDirectory(prefix="triwarden-install-chrome-bad-") as directory:
    home = Path(directory)
    (home / "bin").mkdir()
    (home / "Library/Application Support/Google/Chrome").mkdir(parents=True)
    (home / "bin/tw").symlink_to(binary)
    result = run(["tw", "install-chrome", "not-an-id"], home, home)
    assert result.returncode == 64, f"bad extension id: expected exit 64, got {result.returncode}"
    assert not manifest_in(home).exists(), "bad extension id: a manifest was written anyway"
    print("PASS: rejects a bad extension id")


# ---- Firefox ----
gecko = re.search(r"gecko:\s*\{[^}]*?id:\s*'([^']+)'", (root / "BrowserExtension/WebExtension/wxt.config.ts").read_text(), re.S)
assert gecko, "no gecko id in BrowserExtension/WebExtension/wxt.config.ts"
firefox_id = gecko.group(1)
tw_source = (root / "CLI/main.swift").read_text()
assert f'let firefoxExtensionID = "{firefox_id}"' in tw_source, \
    f"CLI/main.swift names a different Firefox add-on id than wxt.config.ts ({firefox_id}); they must match"
print("PASS: tw and the extension agree on the Firefox add-on id")


def firefox_manifest_in(home):
    return home / "Library/Application Support/Mozilla/NativeMessagingHosts" / f"{host}.json"


with tempfile.TemporaryDirectory(prefix="triwarden-install-firefox-") as directory:
    home = Path(directory)
    (home / "bin").mkdir()
    (home / "Library/Application Support/Firefox").mkdir(parents=True)
    (home / "bin/tw").symlink_to(binary)

    result = run(["tw", "install-firefox"], home, home)
    assert result.returncode == 0, f"install-firefox failed:\n{result.stdout}\n{result.stderr}"
    path = firefox_manifest_in(home)
    assert path.exists(), f"install-firefox: no manifest written:\n{result.stdout}"
    manifest = json.loads(path.read_text())
    assert Path(manifest["path"]) == real, f"install-firefox: manifest names {manifest['path']}, expected {real}"
    assert manifest["name"] == host and manifest["type"] == "stdio", f"install-firefox: bad manifest: {manifest}"
    assert manifest["allowed_extensions"] == [firefox_id], f"install-firefox: bad allowed_extensions: {manifest}"
    assert "allowed_origins" not in manifest, f"install-firefox: Firefox ignores allowed_origins: {manifest}"
    print("PASS: install-firefox writes the Firefox host manifest")

    # Firefox starts the host as: <path to the host manifest> <add-on id>, and talks length-prefixed JSON.
    request = json.dumps({"command": "match", "url": "https://example.com/"}).encode()
    env = dict(os.environ, CFFIXED_USER_HOME=str(home), TW_SOCKET=str(home / "no-such.sock"))
    launched = subprocess.run([str(real), str(path), firefox_id], input=struct.pack("<I", len(request)) + request,
                              env=env, capture_output=True, timeout=30)
    assert launched.returncode == 0, f"firefox launch: tw exited {launched.returncode}: {launched.stderr!r}"
    (length,) = struct.unpack("<I", launched.stdout[:4])
    reply = json.loads(launched.stdout[4:4 + length])
    assert reply.get("ok") is False and reply.get("error"), f"firefox launch: expected an error reply, got {reply}"
    print("PASS: tw answers when Firefox starts it as a native-messaging host")

# No Firefox, no manifest: a failed install must not leave files behind.
with tempfile.TemporaryDirectory(prefix="triwarden-install-firefox-none-") as directory:
    home = Path(directory)
    (home / "bin").mkdir()
    (home / "bin/tw").symlink_to(binary)
    result = run(["tw", "install-firefox"], home, home)
    assert result.returncode == 1, f"no Firefox: expected exit 1, got {result.returncode}"
    assert not firefox_manifest_in(home).exists(), "no Firefox: a manifest was written anyway"
    print("PASS: install-firefox does nothing when Firefox is not installed")
