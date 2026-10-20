"""Exercise the hook in a disposable Git repository using synthetic secrets."""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


source = Path(__file__).resolve().parent.parent
# Isolate this repository even when invoked from a Git hook or alternate index.
environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}

with tempfile.TemporaryDirectory(prefix="scribble-secrets-") as directory:
    root = Path(directory)

    def git(*args):
        return subprocess.run(["git", *args], cwd=root, env=environment,
                              capture_output=True, check=True)

    def check(expected):
        result = subprocess.run(["git", "hook", "run", "pre-commit"], cwd=root,
                                env=environment, capture_output=True)
        assert result.returncode == expected, result.stderr.decode()
        assert fake_key.encode() not in result.stdout + result.stderr, "Credential printed"

    def stage(path, content):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        git("add", "-f", "--", path)

    git("init", "-q")
    (root / ".githooks").mkdir()
    shutil.copy2(source / ".githooks/pre-commit", root / ".githooks/pre-commit")
    shutil.copy2(source / ".gitignore", root / ".gitignore")
    git("config", "core.hooksPath", ".githooks")
    fake_key = "sk-" + "synthetic_test_value_" * 3
    stage(".githooks/pre-commit", (source / ".githooks/pre-commit").read_text())
    stage(".githooks/test-secret-guard.py", Path(__file__).read_text())
    stage(".env.example", "# Empty template\nOPENAI_API_KEY=\n")
    check(0)

    (root / ".env.local").write_text("OPENAI_API_KEY=" + fake_key)
    assert git("check-ignore", ".env.local").stdout.strip() == b".env.local"

    for path, content in (
        (".env.local", "OPENAI_API_KEY=" + fake_key),
        ("Config/Secrets.xcconfig", "OPENAI_API_KEY=anything"),
        ("AuthKey.p8", "signing material"),
        ("secrets/credentials.json", "{}"),
        ("leak with spaces.swift", 'let apiKey = "' + fake_key + '"'),
        ("private.txt", "-----BEGIN " + "PRIVATE KEY-----"),
    ):
        stage(path, content)
        # Clean working-tree content must not hide a secret in the Git index.
        (root / path).write_text("clean working copy\n")
        check(1)
        git("rm", "-f", "--cached", "--", path)
        check(0)

    stage(".env.example", "OPENAI_API_KEY=accidental-value\n")
    check(1)
    stage(".env.example", (source / ".env.example").read_text())
    check(0)

print("Secret guard passed: ignored files, force-adds, staged content, templates, and redaction.")
