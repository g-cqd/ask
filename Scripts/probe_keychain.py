"""A throwaway keychain for probes (roadmap 0110): a signed ask keeps credentials in the Keychain, never the person's own in a
probe. Set ASK_KEYCHAIN_PATH to `throwaway_keychain()` in every environment that starts ask."""
import os, subprocess, tempfile

_KEYCHAIN = []


def throwaway_keychain():
    """One keychain file for every run this probe process starts, unlocked, deleted at exit; kept off the search list."""
    if not _KEYCHAIN:
        import atexit
        path = os.path.join(tempfile.mkdtemp(prefix="ask-probe-kc-"), "probe.keychain-db")
        searched = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout.split()
        for arguments in (["create-keychain", "-p", "probe", path], ["set-keychain-settings", path],
                          ["unlock-keychain", "-p", "probe", path]):
            subprocess.run(["security", *arguments], check=True, capture_output=True)
        # create-keychain may add the file to the user's search list; put the list back as it was.
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *[s.strip('"') for s in searched]], capture_output=True)
        atexit.register(lambda: subprocess.run(["security", "delete-keychain", path], capture_output=True))
        _KEYCHAIN.append(path)
    return _KEYCHAIN[0]
