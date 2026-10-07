#!/bin/sh
# Builds Theqa CTA for Linux into packaging/dist/:
#   theqa-cta_<v>_amd64.deb              Debian, Ubuntu, Mint, Pop!_OS, Zorin
#   theqa-cta-<v>-1.x86_64.rpm           Fedora, RHEL/Alma/Rocky, openSUSE
#   theqa-cta-<v>-1-x86_64.pkg.tar.zst   Arch, Manjaro, EndeavourOS
#   theqa-cta-<v>-linux-x64.tar.gz       any other glibc distro (install.sh)
# Usage: packaging/build.sh [path/to/official-CTA-installer.exe]
# Needs: .NET 8 SDK, nfpm, Wine, google-chrome + openssl (to pack the browser extension).
# The official CTA files come from the installer you pass (unpacked by an unattended install into a throwaway Wine
# prefix), or, without an argument, from an existing Wine install (CtaDir in cta-linux/*.csproj).
# The app is self-contained: target machines need no .NET.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dist=$here/dist
stage=$(mktemp -d)
trap 'rm -rf "$stage" "$stage.yaml" "$stage-tar" "$stage-cta"' EXIT
app=$stage/opt/theqa-cta
nfpm=$(command -v nfpm || echo "$HOME/go/bin/nfpm")

cta_dir=
if [ $# -gt 0 ]; then
  cta_dir=$stage-cta/app
  mkdir -p "$cta_dir"
  # mscoree/mshtml off: no Wine Mono/Gecko install prompts (the installer needs neither)
  export WINEPREFIX="$stage-cta/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
  wine "$1" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS "/DIR=$(winepath -w "$cta_dir")"
  wineserver -k 2>/dev/null || true
  [ -f "$cta_dir/Digitrustec.CTA.Win.dll" ] || { echo "No CTA files after running $1. Is it the official CTA installer?" >&2; exit 1; }
fi

dotnet publish "$here/../cta-linux" -c Release -r linux-x64 --self-contained -p:DebugType=none ${cta_dir:+"-p:CtaDir=$cta_dir"} -o "$app"
version=$(grep -o '"Digitrustec.CTA.Linux/[0-9.]*"' "$app/Digitrustec.CTA.Linux.deps.json" | head -1 | sed 's/.*\/\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')

mkdir -p "$stage/usr/bin" "$stage/usr/share/applications" "$stage/etc/xdg/autostart" "$stage/usr/share/doc/theqa-cta"
ln -s /opt/theqa-cta/Digitrustec.CTA.Linux "$stage/usr/bin/theqa-cta"
# Menu entry + digitrustec.cta:// handler (the login page uses it to start the CTA); also started at login.
cat > "$stage/usr/share/applications/theqa-cta.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Theqa CTA
Comment=Oman ID card reader for the Theqa login (idp-pki.mtcit.gov.om)
Exec=theqa-cta
Icon=/opt/theqa-cta/appicon.png
MimeType=x-scheme-handler/digitrustec.cta;
Terminal=false
Categories=Utility;
EOF
ln -s /usr/share/applications/theqa-cta.desktop "$stage/etc/xdg/autostart/theqa-cta.desktop"
cp "$here/../theqa-linux.user.js" "$here/../README.md" "$stage/usr/share/doc/theqa-cta/"

# Browser extension (browser-ext/) that makes the login page accept Linux, force-installed by managed policy in
# Chromium-based browsers. The same policy pre-allows the page to reach the CTA on localhost (no permission prompt).
# browser-ext.pem fixes the extension ID: keep it to ship updates, never package it.
key=$here/browser-ext.pem
[ -f "$key" ] || openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$key"
google-chrome --pack-extension="$here/browser-ext" --pack-extension-key="$key" --user-data-dir="$stage/chrome" --no-message-box >/dev/null
rm -rf "$stage/chrome"
mv "$here/browser-ext.crx" "$app/browser-ext.crx"
ext_id=$(openssl pkey -in "$key" -pubout -outform DER | sha256sum | head -c32 | tr 0-9a-f a-p)
ext_version=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$here/browser-ext/manifest.json")
cat > "$app/browser-ext.xml" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$ext_id'><updatecheck codebase='file:///opt/theqa-cta/browser-ext.crx' version='$ext_version' /></app>
</gupdate>
EOF
for dir in etc/opt/chrome etc/chromium etc/chromium-browser etc/brave etc/opt/edge; do
  mkdir -p "$stage/$dir/policies/managed"
  cat > "$stage/$dir/policies/managed/theqa-cta.json" <<EOF
{
  "ExtensionInstallForcelist": ["$ext_id;file:///opt/theqa-cta/browser-ext.xml"],
  "LocalNetworkAccessAllowedForUrls": ["https://idp-pki.mtcit.gov.om"]
}
EOF
done

# Firefox only force-installs Mozilla-signed extensions: included once packaging/firefox-ext.xpi exists (see README).
if [ -f "$here/firefox-ext.xpi" ]; then
  gecko_id=$(sed -n 's/.*"id": "\(.*\)".*/\1/p' "$here/browser-ext/manifest.json")
  cp "$here/firefox-ext.xpi" "$app/firefox-ext.xpi"
  mkdir -p "$stage/etc/firefox/policies"
  cat > "$stage/etc/firefox/policies/policies.json" <<EOF
{
  "policies": {
    "ExtensionSettings": {
      "$gecko_id": { "installation_mode": "force_installed", "install_url": "file:///opt/theqa-cta/firefox-ext.xpi" }
    }
  }
}
EOF
fi

chmod -R u+rwX,go+rX,go-w "$stage"
rm -rf "$dist" && mkdir -p "$dist"

# Native packages: same files, per-distro names for pcsc-lite (smart-card service) and CCID (USB reader driver).
{
  cat <<EOF
name: theqa-cta
arch: amd64
version: $version
maintainer: yahya.saidi <al.saidi.yahya1@gmail.com>
description: |-
  Digitrustec CTA (Identity Reader) for Linux.
  Lets the Theqa login page (idp-pki.mtcit.gov.om) use an Oman ID card on Linux.
scripts:
  postinstall: $here/postinstall.sh
deb:
  compression: xz
rpm:
  compression: xz
overrides:
  deb:
    depends: [pcscd, libccid]
  rpm:
    depends: [pcsc-lite]
    recommends: [pcsc-lite-ccid, pcsc-ccid]  # Fedora, openSUSE
  archlinux:
    depends: [pcsclite, ccid]
contents:
EOF
  (cd "$stage" && find . -mindepth 1 ! -type d | sed 's|^\./||') | while read -r f; do
    if [ -L "$stage/$f" ]; then
      printf "  - src: '%s'\n    dst: '/%s'\n    type: symlink\n" "$(readlink "$stage/$f")" "$f"
    else
      printf "  - src: '%s'\n    dst: '/%s'\n" "$stage/$f" "$f"
    fi
  done
} > "$stage.yaml"
for packager in deb rpm archlinux; do
  "$nfpm" package --config "$stage.yaml" --packager "$packager" --target "$dist/"
done

# Everything else: tarball + install.sh
mkdir -p "$stage-tar/theqa-cta-$version"
cp -a "$stage" "$stage-tar/theqa-cta-$version/files"
cp "$here/install.sh" "$stage-tar/theqa-cta-$version/"
tar -C "$stage-tar" --owner=0 --group=0 -czf "$dist/theqa-cta-$version-linux-x64.tar.gz" "theqa-cta-$version"
ls -l "$dist"
