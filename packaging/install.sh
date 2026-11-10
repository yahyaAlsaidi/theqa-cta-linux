#!/bin/sh
# Theqa CTA for Linux: installer for distros without a .deb/.rpm/Arch package. Run as root:
#   sudo ./install.sh                              install or update
#   sudo /opt/theqa-cta/install.sh --uninstall     remove
# Plain POSIX sh + BusyBox-compatible tools, so it also runs on Alpine.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }

if [ "${1:-}" = --uninstall ]; then
    while IFS= read -r f; do rm -f "$f"; done < /opt/theqa-cta/files.txt
    rm -rf /opt/theqa-cta
    echo "Theqa CTA removed."
    exit
fi
if [ -e /etc/NIXOS ]; then
    echo "This is NixOS: use the flake instead (see \"NixOS\" in the README)." >&2
    exit 1
fi

cd "$(dirname "$0")"
mkdir -p /opt/theqa-cta
(cd files && find . ! -type d | sed 's|^\.||') > /opt/theqa-cta/files.txt
# File by file, so existing system directories (/etc, /usr, /opt) keep their owner and mode.
# rm first: an update replaces the files of a running CTA instead of writing into them.
while IFS= read -r f; do
    mkdir -p "${f%/*}" && rm -f "$f" && cp -P "files$f" "$f"
done < /opt/theqa-cta/files.txt
# Our directories belong to root. Installers before release 4 (tar) gave the ones they created to whoever
# extracted the tarball, which let that user change the CTA and the browser policies: take them back.
(cd files && find . -mindepth 1 -type d | sed 's|^\.||') | while IFS= read -r d; do
    [ "$(stat -c %u "$d")" = 0 ] || chown -h 0:0 "$d"
done
cp install.sh /opt/theqa-cta/install.sh
# Start the smart-card service: systemd, or OpenRC (Alpine)
systemctl enable --now pcscd.socket >/dev/null 2>&1 \
    || { rc-update add pcscd default && rc-service pcscd start; } >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true

echo "Theqa CTA installed. Log out and back in (or run theqa-cta), then restart your browser."
has() { find /lib /lib64 /usr/lib /usr/lib64 -maxdepth 2 -name "$1" 2>/dev/null | grep -q .; }
if [ -e /lib/ld-musl-x86_64.so.1 ]; then
    # musl (Alpine): the CTA is built for glibc and runs on Alpine's glibc compatibility layer, gcompat
    if ! { has ld-linux-x86-64.so.2 && has 'libstdc++.so.6' && has 'libpcsclite.so.1*'; }; then
        cat <<'MSG'
This system uses musl (e.g. Alpine), but the CTA is built for glibc, so it can't start yet.
Install Alpine's glibc compatibility layer (gcompat) and the smart-card service. As root:
  apk add gcompat libstdc++ pcsc-lite pcsc-lite-libs ccid
  rc-update add pcscd && rc-service pcscd start
MSG
    fi
elif ! has 'libpcsclite.so.1*'; then
    cat <<'MSG'
The smart-card service (pcsc-lite) is missing. Install it with the reader driver (CCID), then run:
  sudo systemctl enable --now pcscd.socket
Package names: pcsc-lite + pcsc-lite-ccid (Fedora/RHEL), pcsc-lite + pcsc-ccid (openSUSE),
  pcsclite + ccid (Arch), pcscd + libccid (Debian/Ubuntu), pcsc-lite + ccid (Void, Gentoo).
MSG
fi
