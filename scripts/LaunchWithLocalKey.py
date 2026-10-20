#!/usr/bin/env python3
"""Launch an already-installed Debug app with a session key. Never builds or publishes."""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "au.com.billabyte.ScribbleScout"


def load_key(environment, env_file):
    key = environment.get("OPENAI_API_KEY", "").strip()
    if not key and env_file.exists():
        for line in env_file.read_text().splitlines():
            # Parse only this assignment; never execute a dotenv file as shell code.
            name, separator, value = line.partition("=")
            if separator and name.strip() in {"OPENAI_API_KEY", "export OPENAI_API_KEY"}:
                tokens = shlex.split(value, comments=True)
                if len(tokens) > 1:
                    raise ValueError("Invalid key assignment")
                key = tokens[0] if tokens else ""
    if key and any(character.isspace() for character in key):
        raise ValueError("Key contains whitespace")
    return key


def launch(device, simulator, environment, key):
    child_environment = dict(environment)
    # The provider key only belongs to the launched app, not devicectl itself.
    child_environment.pop("OPENAI_API_KEY", None)
    child_environment.pop("DEVICECTL_CHILD_OPENAI_API_KEY", None)
    child_environment.pop("SIMCTL_CHILD_OPENAI_API_KEY", None)
    if simulator:
        child_environment["SIMCTL_CHILD_OPENAI_API_KEY"] = key
        command = ["xcrun", "simctl", "launch", "--terminate-running-process", simulator, BUNDLE_ID]
    else:
        child_environment["DEVICECTL_CHILD_OPENAI_API_KEY"] = key
        command = ["xcrun", "devicectl", "device", "process", "launch", "--device", device,
                   "--terminate-existing", BUNDLE_ID, "--timeout", "30"]
    # Suppress tool output as a precaution: launch errors must never echo the environment.
    result = subprocess.run(command, env=child_environment, capture_output=True)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--device", help="Connected iPad identifier from xcrun devicectl list devices")
    target.add_argument("--simulator", help="Simulator identifier, or booted")
    args = parser.parse_args()
    try:
        key = load_key(os.environ, ROOT / ".env.local")
        status = launch(args.device, args.simulator, os.environ, key)
    except (OSError, ValueError):
        print("Could not read local credentials or launch the app. Check the local file and device connection.", file=sys.stderr)
        return 1
    if status:
        print("Launch failed. Check that the Debug app is installed and the device is unlocked.", file=sys.stderr)
        return status
    print("Launched with a session-only development key." if key else "Launched without a key; Ask Scout will request one.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
