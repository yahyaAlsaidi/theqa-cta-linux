# Theqa CTA for Linux

Use your **Oman ID card** to log in to **Theqa** ([idp-pki.mtcit.gov.om](https://idp-pki.mtcit.gov.om)) on Linux.

On Windows and macOS, the Theqa login uses a small helper app from Digitrustec (the **CTA**, or Identity Reader) to read your card. This project brings that app to Linux: install one package, plug in your card reader, and log in as usual in **Chrome, Chromium, Brave, Edge or Firefox**.

| I want to... | Go to |
|---|---|
| use it on my computer | [Install](#install): download one file, install it |
| build the package myself | [Build from source](#build-from-source): two commands |
| understand how it works | [Technical details](docs/technical-details.md) |

## Install

Ready-made packages are on the [Releases page](https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest). Nothing else to download: no Windows installer, no build tools.

You need:

- 64-bit (x86-64) Linux
- a USB smart-card reader (tested: Alcor Link AK9563)
- Google Chrome, Chromium, Brave, Edge, or Firefox 140 or newer

### 1. Download and install the package for your distro

**Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin OS**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/theqa-cta_amd64.deb
sudo apt install ./theqa-cta_amd64.deb
```

**Fedora, RHEL, AlmaLinux, Rocky Linux**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/theqa-cta.x86_64.rpm
sudo dnf install ./theqa-cta.x86_64.rpm
```

**openSUSE**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/theqa-cta.x86_64.rpm
sudo zypper install --allow-unsigned-rpm ./theqa-cta.x86_64.rpm
```

**Arch Linux, Manjaro, EndeavourOS**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/theqa-cta-x86_64.pkg.tar.zst
sudo pacman -U ./theqa-cta-x86_64.pkg.tar.zst
```

**Any other distro**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/theqa-cta-linux-x64.tar.gz
tar -xzf theqa-cta-linux-x64.tar.gz && sudo ./theqa-cta-*/install.sh
```

The packages also install your distro's smart-card service (pcsc-lite) and USB reader driver (CCID), and start the service. For the tarball, `install.sh` tells you what to install if they're missing.

To check a download (optional):

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest/download/SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

### 2. Start using it

1. Restart your browser if it was open. It installs the "Theqa CTA for Linux" extension by itself.
2. Log out and back in, or run `theqa-cta`. A tray icon appears, and from now on it starts at every login.
3. Plug in the reader, insert your ID card, open https://idp-pki.mtcit.gov.om, choose ID card login and enter your PIN on the page.

### Remove

| Distro | Command |
|---|---|
| Debian, Ubuntu and derivatives | `sudo apt remove theqa-cta` |
| Fedora, RHEL and derivatives | `sudo dnf remove theqa-cta` |
| openSUSE | `sudo zypper remove theqa-cta` |
| Arch and derivatives | `sudo pacman -R theqa-cta` |
| Tarball install | `sudo /opt/theqa-cta/install.sh --uninstall` |

Removing also removes the browser policy and extension.

### Firefox users

Firefox 140 and newer is supported, the same way as Chrome:

- **Extension.** The package installs the Mozilla-signed "Theqa CTA for Linux" extension automatically.
- **Local connection.** It lets the login page talk to the CTA on your computer without asking (Firefox 145+ would otherwise show a permission prompt).

Restart Firefox after installing. To check, open `about:addons` (the extension is listed) and `about:policies` (`ExtensionSettings` and `LocalNetworkAccess` are active).

Ubuntu's default Firefox is a Snap, which hasn't been tested. If the extension doesn't show up there, load the userscript `/usr/share/doc/theqa-cta/theqa-linux.user.js` in Violentmonkey or Tampermonkey instead.

## Usage

| | |
|---|---|
| Start manually | `theqa-cta`, or "Theqa CTA" in the app menu |
| Tray menu | version, **Open logs**, **Quit** |
| Headless | without `DISPLAY` / `WAYLAND_DISPLAY` it runs without the tray (e.g. under systemd) |
| Logs | `~/.local/share/Digitrustec.CTA/logs/{General,Errors}/<date>/` |
| Allowed sites | `THEQA_ALLOWED_ORIGINS`, comma-separated (default `https://idp-pki.mtcit.gov.om`) |

### Troubleshooting

- Is it running? `ss -ltn | grep 5234`
- Does Linux see the reader? `pcsc_scan` (package `pcsc-tools`)
- Is the extension installed? Chrome-based browsers: `chrome://extensions` and `chrome://policy`. Firefox: `about:addons` and `about:policies`
- `IsDeviceConnected` is false for the first few seconds. The card monitor starts on the page's first request and polls every 5 s, the same as on Windows.
- Hub smoke test without the browser (needs `python3 -m venv .venv && .venv/bin/pip install aiohttp`):

  ```sh
  .venv/bin/python cta-linux/probe.py          # version, card presence, card info, certificate
  .venv/bin/python cta-linux/probe.py --pin    # + PIN login and a test signature (asks for the PIN; a wrong PIN uses up an attempt)
  ```

## Build from source

Only needed if you want to build the package yourself. To just use it, see [Install](#install).

Digitrustec's CTA files are already in the repository (`cta-linux/vendor/`), so nothing else is needed.

```sh
git clone https://github.com/yahyaAlsaidi/theqa-cta-linux.git && cd theqa-cta-linux
packaging/build.sh --install
```

That one command:

1. **Detects your distro** from its package manager, and builds only the package it needs:

   | Your package manager | Built (in `packaging/dist/`) |
   |---|---|
   | apt (Debian, Ubuntu, Mint, Pop!_OS, Zorin) | `theqa-cta_amd64.deb` |
   | dnf or zypper (Fedora, RHEL, AlmaLinux, Rocky, openSUSE) | `theqa-cta.x86_64.rpm` |
   | pacman (Arch, Manjaro, EndeavourOS) | `theqa-cta-x86_64.pkg.tar.zst` |
   | anything else | `theqa-cta-linux-x64.tar.gz` |

2. **Sets up the build tools it's missing** (see [Build tools](#build-tools)).
3. **Installs the package** (`--install`), and reinstalls it on later rebuilds. Without `--install` it only builds.

To build every format, e.g. for a release, run `packaging/build.sh --all`.

### Build tools

Nothing has to be set up in advance. Tools already on your system are used as they are; missing ones are set up like this:

| Tool | How `packaging/build.sh` gets it |
|---|---|
| .NET 8 SDK | Microsoft's `dotnet-install.sh`, into `packaging/.tools` (no root) |
| [nFPM](https://nfpm.goreleaser.com) | pinned release, checksum-verified, into `packaging/.tools` |
| curl, python3, openssl | your package manager (apt, dnf, zypper or pacman), after asking |

Notes:

- **Contents.** Every package carries the same files. Only the dependency names differ per distro: pcsc-lite (smart-card service) and the CCID reader driver.
- **Extension key.** The first build generates `packaging/browser-ext.pem`, the extension signing key. Keep it: it fixes the extension ID across updates. It is git-ignored and never packaged.

> The packages contain Digitrustec's assemblies. Publish them only with Digitrustec's permission.

### Firefox

The packages include the extension signed by Mozilla (`packaging/firefox-ext.xpi`); Firefox only force-installs signed extensions. After changing the extension, raise `version` in `packaging/browser-ext/manifest.json` and sign it again (free, unlisted):

1. Create API credentials at https://addons.mozilla.org/developers/addon/api/key/ and put them in your shell environment. Never commit them.

   ```sh
   export WEB_EXT_API_KEY=...  WEB_EXT_API_SECRET=...
   ```

2. Sign and rebuild:

   ```sh
   npx web-ext sign --source-dir packaging/browser-ext --channel unlisted \
       --artifacts-dir packaging/browser-ext/web-ext-artifacts
   cp packaging/browser-ext/web-ext-artifacts/*.xpi packaging/firefox-ext.xpi
   packaging/build.sh --all
   ```

The packages always install a Firefox policy (`/etc/firefox/policies/policies.json`, and `/etc/firefox-esr/...` for Debian's ESR). It lets the login page reach `localhost:5234` without a prompt (`LocalNetworkAccess` / `SkipDomains`). With `packaging/firefox-ext.xpi` present, the same policy also force-installs the extension. Commit the signed `.xpi`: Mozilla won't sign the same version twice. Without it, Firefox users can load the userscript (`/usr/share/doc/theqa-cta/theqa-linux.user.js`) in Violentmonkey or Tampermonkey.

## Limitations

- **Firefox.** Version 140 or newer.
- **Snap and Flatpak browsers.** They don't read the policies in `/etc`, and may not be able to read `/opt`. Untested: use the userscript there. Google Chrome, Brave and Edge are normal packages, not snaps.
- **Tray on plain GNOME.** Fedora, Debian and Arch's GNOME show no tray icons without the "AppIndicator and KStatusNotifierItem Support" extension. The app still works; the icon just isn't visible. KDE, Cinnamon, XFCE and Ubuntu-based desktops show it.
- **Architecture.** x86-64 with glibc only. ARM64 or musl (Alpine) would need `-r linux-arm64` / `linux-musl-x64` builds.
- **eToken.** eToken (`ETokenHub`) login doesn't work: the official code loads a hardcoded Windows PKCS#11 DLL path.
- **One desktop user at a time.** The port, 5234, is fixed.
- **Card photo.** It is returned as raw JPEG 2000, the same as on Windows.
- **New CTA versions.** A newer official CTA needs a rebuild ([Advanced](#advanced-building-with-another-cta-version)).
- **Page changes.** The browser fix depends on the login page's current OS check. The proper fix is for the service to accept Linux.

## Advanced: building with another CTA version

Normal builds use the CTA files in `cta-linux/vendor/` and need none of this. To build against a different CTA version, pass its official Windows installer:

```sh
packaging/build.sh --install ~/Downloads/CTA-V<version>.exe
```

- **Unattended unpack.** The script runs the installer unattended in a throwaway 64-bit Wine prefix, only to unpack it. It sets up Wine if needed.
- **Desktop needed.** Unpacking needs a desktop session, because the installer opens a window even when unattended. Without one (servers, CI), use `xvfb-run -a packaging/build.sh ...`.
- **Tested** with stock Wine on Debian 13, Ubuntu 24.04, Fedora 44 and Arch, and with WineHQ on Zorin OS. It hung on openSUSE Tumbleweed.
- **Getting the installer.** Open https://idp-pki.mtcit.gov.om, choose ID card login and click **Download CTA**. On Linux the page says "not supported"; open the browser console there (F12, Console) and run `location.href = Extensions.getDownloadCtaUrl("windows")`.
- **Wine.** The script installs it with your package manager after asking: `wine wine64 wine32:i386` on Debian/Ubuntu (enables i386 first), `wine wine-32bit` on openSUSE, `wine` on Fedora/Arch.
- **Bundling the new version.** To make a new CTA version the default, replace the files in `cta-linux/vendor/` with the same files from the new version.

The package version is the version of the CTA files used.
