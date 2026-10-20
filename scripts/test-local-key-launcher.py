"""Use synthetic values only; never starts a device or reads real credentials."""

import importlib.util
from pathlib import Path
import tempfile
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("local_launcher", Path(__file__).with_name("LaunchWithLocalKey.py"))
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

with tempfile.TemporaryDirectory(prefix="scribble-key-test-") as directory:
    env_file = Path(directory) / ".env.local"
    assert launcher.load_key({}, env_file) == ""
    env_file.write_text('# Comment\nOPENAI_API_KEY="synthetic-file-value" # local only\n')
    assert launcher.load_key({}, env_file) == "synthetic-file-value"
    assert launcher.load_key({"OPENAI_API_KEY": " synthetic-env-value "}, env_file) == "synthetic-env-value"
    assert launcher.load_key({"OPENAI_API_KEY": " "}, env_file) == "synthetic-file-value"
    env_file.write_text("OPENAI_API_KEY='$(this-is-not-executed)'\n")
    assert launcher.load_key({}, env_file) == "$(this-is-not-executed)"
    env_file.write_text("OPENAI_API_KEY='invalid value'\n")
    try:
        launcher.load_key({}, env_file)
        raise AssertionError("Whitespace key accepted")
    except ValueError:
        pass

for simulator in (None, "booted"):
    with patch.object(launcher.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
        key = "synthetic-value-never-in-arguments"
        original = {"OPENAI_API_KEY": key, "PATH": "/usr/bin"}
        assert launcher.launch("synthetic-device", simulator, original, key) == 0
        arguments, kwargs = run.call_args
        assert key not in repr(arguments)
        assert "OPENAI_API_KEY" not in kwargs["env"]
        prefix = "SIMCTL_CHILD_" if simulator else "DEVICECTL_CHILD_"
        assert kwargs["env"][prefix + "OPENAI_API_KEY"] == key
        assert kwargs["capture_output"] is True
        assert original["OPENAI_API_KEY"] == key
print("Local launcher passed: precedence, missing key, no shell evaluation, and secret-free arguments.")
