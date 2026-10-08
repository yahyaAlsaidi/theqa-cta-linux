# Theqa CTA for Linux

Use your **Oman ID card** to log in to **Theqa** ([idp-pki.mtcit.gov.om](https://idp-pki.mtcit.gov.om)) on Linux.

On Windows and macOS, the Theqa login uses a small helper app from Digitrustec (the **CTA**, or Identity Reader) to read your card. This project brings that app to Linux: install one package, plug in your card reader, and log in as usual.

| I want to... | Go to |
|---|---|
| use it on my computer | [Install](#install): download one file, install it |
| build the package myself | [Build from source](#build-from-source): two commands |
| understand how it works | [Technical details](#technical-details) |

## Install

Ready-made packages are on the [Releases page](https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/latest). Nothing else to download: no Windows installer, no build tools.

You need:

- 64-bit (x86-64) Linux
- a USB smart-card reader (tested: Alcor Link AK9563)
- Google Chrome, Chromium, Brave or Edge (Firefox: see [Firefox users](#firefox-users))

### 1. Download and install the package for your distro

**Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin OS**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/theqa-cta_1.4.18_amd64.deb
sudo apt install ./theqa-cta_1.4.18_amd64.deb
```

**Fedora, RHEL, AlmaLinux, Rocky Linux**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/theqa-cta-1.4.18-1.x86_64.rpm
sudo dnf install ./theqa-cta-1.4.18-1.x86_64.rpm
```

**openSUSE**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/theqa-cta-1.4.18-1.x86_64.rpm
sudo zypper install --allow-unsigned-rpm ./theqa-cta-1.4.18-1.x86_64.rpm
```

**Arch Linux, Manjaro, EndeavourOS**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/theqa-cta-1.4.18-1-x86_64.pkg.tar.zst
sudo pacman -U ./theqa-cta-1.4.18-1-x86_64.pkg.tar.zst
```

**Any other distro**

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/theqa-cta-1.4.18-linux-x64.tar.gz
tar -xzf theqa-cta-1.4.18-linux-x64.tar.gz && sudo ./theqa-cta-1.4.18/install.sh
```

The packages also install your distro's smart-card service (pcsc-lite) and USB reader driver (CCID), and start the service. For the tarball, `install.sh` tells you what to install if they're missing.

To check a download (optional):

```sh
curl -LO https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v1.4.18-1/SHA256SUMS
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

The extension isn't installed automatically in Firefox yet. Instead, add a userscript manager (Violentmonkey or Tampermonkey) and load `/usr/share/doc/theqa-cta/theqa-linux.user.js`, which is installed with the package.

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
- Is the extension installed? Check `chrome://extensions` and `chrome://policy`
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
   | apt (Debian, Ubuntu, Mint, Pop!_OS, Zorin) | `theqa-cta_1.4.18_amd64.deb` |
   | dnf or zypper (Fedora, RHEL, AlmaLinux, Rocky, openSUSE) | `theqa-cta-1.4.18-1.x86_64.rpm` |
   | pacman (Arch, Manjaro, EndeavourOS) | `theqa-cta-1.4.18-1-x86_64.pkg.tar.zst` |
   | anything else | `theqa-cta-1.4.18-linux-x64.tar.gz` |

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

Firefox only force-installs extensions signed by Mozilla. Signing is free and the extension stays unlisted (private). It is a one-time setup per extension version:

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

With `packaging/firefox-ext.xpi` present, the packages also install `/etc/firefox/policies/policies.json`, which force-installs it. Commit the signed `.xpi`: Mozilla won't sign the same version twice. Without it, Firefox users can load the userscript (`/usr/share/doc/theqa-cta/theqa-linux.user.js`) in Violentmonkey or Tampermonkey.

## Technical details

### How it works

```
Browser (idp-pki.mtcit.gov.om)
  -> SignalR over WebSocket: http://localhost:5234/SmartCardHub
     Linux host (this repo: cta-linux/Program.cs, Avalonia tray)
       -> Digitrustec CTA assemblies, unchanged (hubs, Oman ID logic, card library)
          -> PC/SC (pcsc-sharp) -> pcscd -> USB card reader
```

The official CTA's own .NET assemblies are reused unchanged; only the Windows-specific shell (WPF window, tray, Win32 calls) is replaced by a small Linux host.

- **Portable assemblies.** The official CTA is .NET 8. Everything except its WPF shell (`Digitrustec.CTA.Win.dll`) already runs on Linux. Card access goes through PC/SC, which works with Linux's `pcscd` as-is.
- **Same host, minus Windows.** The Linux host registers the same services, SignalR hubs and port as the Windows app. Results therefore come back exactly as the Theqa server expects (they are signed and encrypted for the server by the original code).
- **Browser side.** The login page only accepts Windows and macOS, so a tiny browser extension makes that one site see Windows ([details](#browser-side)). The package installs it automatically in Chromium-based browsers.

### What runs where

| Official assembly | Role | On Linux |
|---|---|---|
| `Digitrustec.CTA.Win` | WPF shell: host setup, tray, updater, hotkey | **replaced** by `cta-linux/Program.cs` |
| `Digitrustec.CTA.SignalR.Hubs` | `SmartCardHub`, `ETokenHub`, controllers, result encryption | reused |
| `Digitrustec.CTA.SmartCard.Oman_ID`, `.SmartCard.Shared` | Oman ID logic: card data, certificates, PIN, signing | reused |
| `Digitrustec.CTA.Capabilities.*` | reader monitoring, signing helpers, interfaces | reused |
| `Digitrustec.CTA.EToken*` | SafeNet eToken over PKCS#11 | reused, not functional (see Limitations) |
| `Digitrustec.CTA.Shared` | logging, settings | reused |
| `OmanIDCard.CrossPlatform` | Oman ID card library (APDU level) | reused |

Third-party packages come from NuGet at the versions the official build uses: PCSC, Pkcs11Interop, Portable.BouncyCastle, Newtonsoft.Json, Serilog. The UI uses Avalonia.

### Windows to Linux mapping

| Area | Windows CTA | Linux |
|---|---|---|
| UI | WPF window + tray | Avalonia tray (StatusNotifierItem over D-Bus) |
| Open-logs hotkey | Ctrl+Alt+L, `explorer.exe` | tray "Open logs", `xdg-open` |
| Registry, SafeNet DLL preload | Windows-only | dropped |
| Self-updater | downloads the Windows build | dropped; update = rebuild with a newer CTA |
| Smart card | PC/SC (`winscard`) | PC/SC (`pcsc-lite`), same library |
| Logs | `%LOCALAPPDATA%\Digitrustec.CTA\Logs` | `~/.local/share/Digitrustec.CTA/logs` (the official code already does this) |
| Startup | Windows autostart | `/etc/xdg/autostart` + `digitrustec.cta://` URL handler |
| ASP.NET Core, SignalR, Serilog | Kestrel on `localhost:5234` | same |

How the host works:

- **Version.** The reported version is stamped at build time from the official `Digitrustec.CTA.Win.dll`, so the page sees the same version as on Windows.
- **Origin check.** Only `THEQA_ALLOWED_ORIGINS` may use the hubs. It is checked on every request, including WebSocket upgrades, which CORS doesn't cover.
- **Shutdown.** SIGTERM (logout, `systemctl stop`) stops the web host and the tray together.

### SmartCardHub API

Each call takes one argument, `{ "id": "<GUID>", "payload": ... }`. Results marked *sealed* are signed and encrypted for the Theqa server and are opaque to the browser.

| Method | Payload | Result |
|---|---|---|
| `GetCtaAppVersionAsync` | none | version string |
| `InitAsync`, `IsDeviceConnectedAsync`, `LogoutAsync` | none | bool |
| `GetCardInfoAsync` | none | sealed card data |
| `GetCertificatesAsync` | `1` authentication, `2` signing | sealed certificate list |
| `LogInAndVerifyPinAsync` | PIN | bool |
| `SignDataAsync`, `SignHashAsync`, `SignDocumentHashAsync` | `{ "CertificateType": n, "Data": "<base64>" }` | sealed signature |

Server-to-client events: `SmartCardDetected`, `SmartCardRemoved`, `ErrorOccurred`.

### Browser side

The page's `Extensions.getCtaOs()` returns `windows`, `mac` or `unsupported`, based on `navigator.userAgentData.platform`, `navigator.platform` and the user agent. It sends the result as an `X-CTA-OS` header with every request, and the server refuses `unsupported`.

[`packaging/browser-ext/`](packaging/browser-ext) is a Manifest V3 extension with one content script. It runs in the page's own JavaScript context before any page script, and only on `https://idp-pki.mtcit.gov.om/*`. It makes `navigator.platform` return `Win32` and `navigator.userAgentData.platform` return `Windows`. The user agent string is untouched, and other sites still see Linux.

The `.deb` installs it with no user action through browser policy:

| File | Purpose |
|---|---|
| `/opt/theqa-cta/browser-ext.crx`, `browser-ext.xml` | packed extension + local (`file://`) update manifest |
| `/etc/opt/chrome/policies/managed/theqa-cta.json`, same under `/etc/chromium`, `/etc/chromium-browser`, `/etc/brave`, `/etc/opt/edge` | `ExtensionInstallForcelist` installs the extension. `LocalNetworkAccessAllowedForUrls` lets the page reach `localhost:5234` without a permission prompt |

Because of the policy, the browser shows "Managed by your organization", and the extension can't be removed from inside the browser. Uninstalling the package removes both. To ship a change to the extension, raise `version` in its `manifest.json`.

### Repository

| Path | |
|---|---|
| `cta-linux/Program.cs` | Linux host + Avalonia tray |
| `cta-linux/Digitrustec.CTA.Linux.csproj` | references the official assemblies from `CtaDir`, version stamping |
| `cta-linux/probe.py` | hub test client |
| `cta-linux/appicon.png` | tray / menu icon |
| `cta-linux/vendor/` | Digitrustec's CTA files, unchanged: the DLLs the host uses + `ChainCertificates` |
| `packaging/build.sh` | builds the package for this distro (`--all`: every format), `--install` installs it |
| `packaging/postinstall.sh` | package post-install: starts `pcscd.socket` |
| `packaging/install.sh` | tarball installer / uninstaller |
| `packaging/browser-ext/` | browser extension (Chromium and Firefox) |
| `theqa-linux.user.js` | the same page fix as a userscript, for Firefox |

To read the official code for reference, decompile it yourself with [ILSpy](https://github.com/icsharpcode/ILSpy) (`ilspycmd -p -o decompiled/<name> <dll>`). Decompiled output is git-ignored.

## Testing

Tested against the official Windows CTA 1.4.18 (run under Wine), with the same card and reader:

| Check | Linux host | Windows CTA |
|---|---|---|
| `GetCtaAppVersionAsync` | 1.4.18 | 1.4.18 |
| `IsDeviceConnectedAsync` | true | true |
| `GetCardInfoAsync` | full card data | failed under Wine |
| `GetCertificatesAsync` | authentication certificate | same |
| Request from another website | rejected (403) | accepted |

Packages, tested in clean containers. In each one the distro's package manager installed the package and resolved the dependencies. The app started, `probe.py` got version 1.4.18 and sealed results, and with no usable display the app fell back to running without the tray:

| Distro | Package | Smart-card deps installed |
|---|---|---|
| Debian 13 (stable) | `.deb` | pcscd 2.3.3, libccid 1.6.2 |
| Ubuntu 24.04 | `.deb` | pcscd 2.0.3, libccid 1.5.5 |
| Fedora 44 | `.rpm` | pcsc-lite 2.4.1, pcsc-lite-ccid 1.7.1 |
| openSUSE Tumbleweed | `.rpm` | pcsc-lite 2.3.3 (the CCID driver is a recommended dependency; the container image skips those) |
| Arch Linux | `.pkg.tar.zst` | pcsclite 2.5.2, ccid 1.8.4 |
| AlmaLinux 9 | tarball | none: `install.sh` printed the hint. Install, run and uninstall all worked |

Browser side, tested in a fresh headless Chrome 152 profile with the package installed:

- the extension is force-installed;
- the live login page reports `getCtaOs()` = `windows`, while other sites still see `Linux x86_64`;
- the login page reaches `localhost:5234` without a prompt.

## Limitations

- **Firefox.** It needs the signed extension ([Firefox](#firefox)). Firefox 140 or newer is required.
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
