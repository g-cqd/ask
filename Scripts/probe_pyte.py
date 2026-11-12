"""Where the PTY probes find pyte (t246): `ASK_PYTE` when set, else a cache that outlives /tmp, which `Scripts/probe-deps.sh` fills
from `Scripts/probe-requirements.txt`. Import this, call `ensure()`, then import pyte.
"""
import os
import platform
import sys


def directory():
    """The directory pyte is installed in for the probes."""
    if os.environ.get("ASK_PYTE"):
        return os.environ["ASK_PYTE"]
    if platform.system() == "Darwin":
        base = os.path.expanduser("~/Library/Caches")
    else:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "ask", "probe-python")


def ensure():
    """Puts the probes' pyte on the path, or stops with what to run when it is not installed."""
    path = directory()
    if not os.path.isdir(os.path.join(path, "pyte")):
        sys.exit(f"pyte is not installed for the probes in {path}: run Scripts/probe-deps.sh (or set ASK_PYTE)")
    if path not in sys.path:
        sys.path.insert(0, path)


if __name__ == "__main__" and sys.argv[1:] == ["--print-directory"]:
    print(directory())
