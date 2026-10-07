#!/bin/sh
# Theqa CTA for Linux: installer for distros without a .deb/.rpm/Arch package. Run as root:
#   sudo ./install.sh                              install or update
#   sudo /opt/theqa-cta/install.sh --uninstall     remove
set -eu
[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }

if [ "${1:-}" = --uninstall ]; then
    xargs -rd '\n' rm -f < /opt/theqa-cta/files.txt
    rm -rf /opt/theqa-cta
    echo "Theqa CTA removed."
    exit
fi

cd "$(dirname "$0")"
# --no-overwrite-dir: leave the owner/mode of existing system directories (/etc, /usr, /opt) alone
tar -C files -cf - . | tar -C / -xf - --no-overwrite-dir
(cd files && find . ! -type d | sed 's|^\.||') > /opt/theqa-cta/files.txt
cp install.sh /opt/theqa-cta/install.sh
systemctl enable --now pcscd.socket >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true

echo "Theqa CTA installed. Log out and back in (or run theqa-cta), then restart your browser."
if ! ldconfig -p | grep -q 'libpcsclite\.so\.1'; then
    cat <<'MSG'
The smart-card service (pcsc-lite) is missing. Install it with the reader driver (CCID), then run:
  sudo systemctl enable --now pcscd.socket
Package names: pcsc-lite + pcsc-lite-ccid (Fedora/RHEL), pcsc-lite + pcsc-ccid (openSUSE),
  pcsclite + ccid (Arch), pcscd + libccid (Debian/Ubuntu), pcsc-lite + ccid (Void, Gentoo, Alpine).
MSG
fi
