#!/bin/sh
# Start the smart-card service. Debian/Ubuntu do this when pcscd is installed; Fedora, openSUSE and Arch don't.
systemctl enable --now pcscd.socket >/dev/null 2>&1 || true
