#!/bin/sh
# Builds theqa-cta_<version>_amd64.deb: the Linux CTA host + Digitrustec's DLLs, self-contained (target needs no .NET).
# Build machine needs the .NET 8 SDK and the Windows CTA installed under Wine (CtaDir in cta-linux/*.csproj).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
app=$stage/opt/theqa-cta

dotnet publish "$here/../cta-linux" -c Release -r linux-x64 --self-contained -p:DebugType=none -o "$app"
version=$(grep -o '"Digitrustec.CTA.Linux/[0-9.]*"' "$app/Digitrustec.CTA.Linux.deps.json" | head -1 | sed 's/.*\/\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')

mkdir -p "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/applications" "$stage/etc/xdg/autostart" "$stage/usr/share/doc/theqa-cta"
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

cat > "$stage/DEBIAN/control" <<EOF
Package: theqa-cta
Version: $version
Architecture: amd64
Maintainer: yahya.saidi <al.saidi.yahya1@gmail.com>
Depends: pcscd, libccid
Section: utils
Priority: optional
Description: Digitrustec CTA (Identity Reader) for Linux
 Lets the Theqa login page (idp-pki.mtcit.gov.om) use an Oman ID card on Linux.
 Runs Digitrustec's original CTA $version assemblies with a native Linux host.
EOF

chmod -R u+rwX,go+rX,go-w "$stage"
dpkg-deb --root-owner-group --build "$stage" "$here/theqa-cta_${version}_amd64.deb"
