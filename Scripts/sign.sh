#!/bin/sh
# Signs ask's executable with the identity in ASK_SIGNING_IDENTITY, under the identifier `ask` (ADR-0133). A build signed with a stable
# identity reads its Keychain items with no prompt across rebuilds; an ad-hoc one would be asked about after every build.
#   Scripts/sign.sh [executable]   (default .build/release/ask)
# The first signing with a personal identity makes macOS ask for the login keychain's password, to use the identity's private key;
# "Always Allow" lets codesign use it from then on.
set -eu
binary=${1:-.build/release/ask}
if [ -z "${ASK_SIGNING_IDENTITY:-}" ]; then
    printf 'ASK_SIGNING_IDENTITY is not set: %s stays as it is (ad hoc), and credentials "auto" keeps keys in the file.\n' "$binary"
    exit 0
fi
codesign --force --sign "$ASK_SIGNING_IDENTITY" --identifier ask --timestamp=none "$binary"
codesign --verify "$binary"
printf 'signed %s as %s\n' "$binary" "$ASK_SIGNING_IDENTITY"
