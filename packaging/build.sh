#!/bin/sh
# Builds Theqa CTA for Linux into packaging/dist/. By default only the package this machine needs (detected from its
# package manager); --all builds every format:
#   theqa-cta_<v>_amd64.deb              apt:    Debian, Ubuntu, Mint, Pop!_OS, Zorin
#   theqa-cta-<v>-1.x86_64.rpm           dnf/zypper: Fedora, RHEL/Alma/Rocky, openSUSE
#   theqa-cta-<v>-1-x86_64.pkg.tar.zst   pacman: Arch, Manjaro, EndeavourOS
#   theqa-cta-<v>-linux-x64.tar.gz       anything else (install.sh)
# Usage: packaging/build.sh [--install] [--all] [path/to/official-CTA-installer.exe]
#   --install   also install the package on this machine when the build is done
#   --all       build all formats (for a release)
# The official CTA files come from the installer you pass (unpacked by an unattended install into a throwaway Wine
# prefix), or, without an argument, from cta-linux/vendor/ or an existing Wine install (CtaDir in cta-linux/*.csproj).
# Build tools are set up on first run: .NET 8 SDK and nFPM go into packaging/.tools (no root); curl, python3, openssl
# and Wine come from the distro's package manager (asks first). The app is self-contained: targets need no .NET.
set -eu
install= all=
while [ $# -gt 0 ]; do
  case $1 in --install) install=1 ;; --all) all=1 ;; *) break ;; esac
  shift
done
here=$(cd "$(dirname "$0")" && pwd)
# Fail early, before setting up tools, if there are no CTA files to build from
if [ $# -gt 0 ]; then
  [ -f "$1" ] || { echo "Installer not found: $1" >&2; exit 1; }
elif [ ! -f "$here/../cta-linux/vendor/Digitrustec.CTA.Win.dll" ] &&
     [ ! -f "$HOME/.wine-theqa/drive_c/users/$USER/AppData/Local/Digitrustec.CTA.Win/Digitrustec.CTA.Win.dll" ]; then
  echo "No CTA files found. Pass the official Windows installer (see README, 'Where the CTA files come from'):" >&2
  echo "  packaging/build.sh --install ~/Downloads/CTA-V1.4.18.exe" >&2
  exit 1
fi
dist=$here/dist
tools=$here/.tools
stage=$(mktemp -d)
trap 'rm -rf "$stage" "$stage.yaml" "$stage-tar" "$stage-cta"' EXIT
app=$stage/opt/theqa-cta
mkdir -p "$tools"

if [ "$(id -u)" = 0 ]; then sudo=
elif [ ! -t 0 ] && command -v pkexec >/dev/null; then sudo=pkexec  # no terminal to type a password: desktop prompt
else sudo=sudo; fi
pm=$(for p in apt-get dnf zypper pacman; do command -v $p >/dev/null && echo $p && break; done)
case $pm in apt-get) formats=deb ;; dnf|zypper) formats=rpm ;; pacman) formats=archlinux ;; *) formats=tar ;; esac
[ -z "$all" ] || formats="deb rpm archlinux tar"
echo "Building: $formats"
need() { # need <command> <apt packages> <dnf packages> <zypper packages> <pacman packages>
  command -v "$1" >/dev/null && return 0
  case $pm in apt-get) pkgs=$2 ;; dnf) pkgs=$3 ;; zypper) pkgs=$4 ;; pacman) pkgs=$5 ;; *) echo "Install $1, then run again." >&2; exit 1 ;; esac
  printf '%s is missing. Install it now (%s install %s, needs sudo)? [y/N] ' "$1" "$pm" "$pkgs"
  read -r answer || true
  [ "$answer" = y ] || exit 1
  case $pm in
    apt-get) case $pkgs in *:i386*) $sudo dpkg --add-architecture i386 ;; esac
             $sudo apt-get update && $sudo apt-get install -y $pkgs ;;
    dnf) $sudo dnf install -y $pkgs ;;
    zypper) $sudo zypper install -y $pkgs ;;
    pacman) $sudo pacman -S --needed --noconfirm $pkgs ;;
  esac
}
need curl curl curl curl curl
need python3 python3 python3 python3 python
need openssl openssl openssl openssl openssl
# The official installer is a 32-bit program that only installs on 64-bit Windows: Debian/Ubuntu need 64- and 32-bit
# Wine (Fedora and Arch ship both in one package), openSUSE needs wine-32bit.
[ $# -eq 0 ] || need wine "wine wine64 wine32:i386" wine "wine wine-32bit" wine

# .NET 8 SDK: one on PATH, else Microsoft's dotnet-install.sh into .tools
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 DOTNET_CLI_TELEMETRY_OPTOUT=1  # SDK runs without libicu (minimal systems)
if ! dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
  [ -x "$tools/dotnet/dotnet" ] || curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0 --install-dir "$tools/dotnet"
  export DOTNET_ROOT="$tools/dotnet" PATH="$tools/dotnet:$PATH"
fi
# nFPM: one on PATH, else the pinned release into .tools (checksum-verified)
nfpm=$(command -v nfpm || echo "$tools/nfpm")
if [ "$formats" != tar ] && [ ! -x "$nfpm" ]; then
  nfpm_version=2.47.0
  tgz=nfpm_${nfpm_version}_Linux_x86_64.tar.gz
  url=https://github.com/goreleaser/nfpm/releases/download/v$nfpm_version
  curl -fsSL -o "$tools/$tgz" "$url/$tgz"
  curl -fsSL "$url/checksums.txt" | grep " $tgz\$" | (cd "$tools" && sha256sum -c --quiet -)
  tar -xzf "$tools/$tgz" -C "$tools" nfpm && rm "$tools/$tgz"
fi

cta_dir=
if [ $# -gt 0 ]; then
  cta_dir=$stage-cta/app
  mkdir -p "$cta_dir"
  # mscoree/mshtml off: no Wine Mono/Gecko install prompts (the installer needs neither)
  export WINEARCH=win64 WINEPREFIX="$stage-cta/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
  wine "$1" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS "/DIR=$(winepath -w "$cta_dir")" || true
  wineserver -k 2>/dev/null || true
  [ -f "$cta_dir/Digitrustec.CTA.Win.dll" ] || {
    echo "No CTA files after running $1. Is it the official CTA installer? Wine also needs 32-bit support:" >&2
    echo "  Debian/Ubuntu: sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install wine64 wine32:i386" >&2
    echo "  openSUSE: sudo zypper install wine-32bit" >&2
    exit 1
  }
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
python3 "$here/pack_crx.py" "$here/browser-ext" "$key" "$app/browser-ext.crx"
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
for packager in $formats; do
  [ "$packager" = tar ] || "$nfpm" package --config "$stage.yaml" --packager "$packager" --target "$dist/"
done

# Everything else: tarball + install.sh
case $formats in *tar*)
  mkdir -p "$stage-tar/theqa-cta-$version"
  cp -a "$stage" "$stage-tar/theqa-cta-$version/files"
  cp "$here/install.sh" "$stage-tar/theqa-cta-$version/"
  tar -C "$stage-tar" --owner=0 --group=0 -czf "$dist/theqa-cta-$version-linux-x64.tar.gz" "theqa-cta-$version" ;;
esac
ls -l "$dist"

# --install: the package for this distro (reinstalls when the same version is already there, e.g. after a rebuild)
if [ -n "$install" ]; then
  case $pm in
    apt-get) $sudo apt-get install -y --reinstall "$dist/theqa-cta_${version}_amd64.deb" ;;
    dnf) rpm -q theqa-cta >/dev/null 2>&1 && $sudo dnf reinstall -y "$dist/theqa-cta-$version-1.x86_64.rpm" \
           || $sudo dnf install -y "$dist/theqa-cta-$version-1.x86_64.rpm" ;;
    zypper) $sudo zypper install -y --force --allow-unsigned-rpm "$dist/theqa-cta-$version-1.x86_64.rpm" ;;
    pacman) $sudo pacman -U --noconfirm "$dist/theqa-cta-$version-1-x86_64.pkg.tar.zst" ;;
    *) $sudo "$stage-tar/theqa-cta-$version/install.sh" ;;
  esac
  echo "Installed. Restart your browser, then log out and back in (or run theqa-cta)."
fi
