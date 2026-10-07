# Theqa CTA for Linux

Use your **Oman ID card** to log in to **Theqa** ([idp-pki.mtcit.gov.om](https://idp-pki.mtcit.gov.om)) on Linux.

The login page talks to a local helper app, Digitrustec's **CTA / Identity Reader**, which only exists for Windows and macOS. This project runs that same helper natively on Linux. It reuses the official CTA's own .NET assemblies unchanged and replaces only the Windows-specific shell (WPF window, tray, Win32 calls) with a small Linux host.

> **Unofficial.** Not affiliated with or endorsed by Digitrustec or MTCIT. This repository contains **no Digitrustec code or binaries**. You build the package from your own copy of the official Windows installer.

## How it works

```
Browser (idp-pki.mtcit.gov.om)
  -> SignalR over WebSocket: http://localhost:5234/SmartCardHub
     Linux host (this repo: cta-linux/Program.cs, Avalonia tray)
       -> Digitrustec CTA assemblies, unchanged (hubs, Oman ID logic, card library)
          -> PC/SC (pcsc-sharp) -> pcscd -> USB card reader
```

- **Portable assemblies.** The official CTA is .NET 8. Everything except its WPF shell (`Digitrustec.CTA.Win.dll`) already runs on Linux. Card access goes through PC/SC, which works with Linux's `pcscd` as-is.
- **Same host, minus Windows.** The Linux host registers the same services, SignalR hubs and port as the Windows app. Results therefore come back exactly as the Theqa server expects (they are signed and encrypted for the server by the original code).
- **Browser side.** The login page only accepts Windows and macOS, so a tiny browser extension makes that one site see Windows ([details](#browser-side)). The package installs it automatically in Chromium-based browsers.

## Requirements

- 64-bit (x86-64) Linux with glibc: Debian/Ubuntu, Fedora/RHEL, openSUSE, Arch and their derivatives get native packages; anything else uses the tarball
- a USB smart-card reader (tested: Alcor Link AK9563)
- Google Chrome, Chromium, Brave or Edge; Firefox once the extension is [signed](#firefox)

To build the packages you also need:

- .NET 8 SDK (e.g. `sudo apt install dotnet-sdk-8.0`)
- Wine
- [nFPM](https://nfpm.goreleaser.com): `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest`
- `google-chrome` (packs the browser extension) and `openssl`

## Build the package

1. **Get the official installer.** Download the Windows CTA from Theqa:
   https://idp-pki.mtcit.gov.om/IdentityReader/DownloadCTA?os=windows

2. **Install it under Wine.** This only copies its files; nothing has to run.

   ```sh
   WINEPREFIX=~/.wine-theqa wine CTA-V1.4.18.exe
   ```

   The files land in `~/.wine-theqa/drive_c/users/$USER/AppData/Local/Digitrustec.CTA.Win`. To use another location, set `CtaDir`, e.g. `dotnet build -p:CtaDir=/path/to/Digitrustec.CTA.Win`.

3. **Build.**

   ```sh
   packaging/build.sh
   ```

   Output in `packaging/dist/`:

   | File | For |
   |---|---|
   | `theqa-cta_1.4.18_amd64.deb` | Debian, Ubuntu, Mint, Pop!_OS, Zorin |
   | `theqa-cta-1.4.18-1.x86_64.rpm` | Fedora, RHEL, AlmaLinux, Rocky, openSUSE |
   | `theqa-cta-1.4.18-1-x86_64.pkg.tar.zst` | Arch, Manjaro, EndeavourOS |
   | `theqa-cta-1.4.18-linux-x64.tar.gz` | any other glibc distro |

   - **Version.** It matches the CTA version you built from.
   - **Contents.** Every package carries the same files. Only the dependency names differ per distro: pcsc-lite (smart-card service) and the CCID reader driver.
   - **Extension key.** The first build generates `packaging/browser-ext.pem`, the extension signing key. Keep it: it fixes the extension ID across updates. It is git-ignored and never packaged.

> The packages contain Digitrustec's assemblies, so don't publish them without their permission.

## Install

| Distro | Install | Remove |
|---|---|---|
| Debian, Ubuntu, Mint, Pop!_OS, Zorin | `sudo apt install ./theqa-cta_1.4.18_amd64.deb` | `sudo apt remove theqa-cta` |
| Fedora, RHEL, AlmaLinux, Rocky | `sudo dnf install ./theqa-cta-1.4.18-1.x86_64.rpm` | `sudo dnf remove theqa-cta` |
| openSUSE | `sudo zypper install --allow-unsigned-rpm ./theqa-cta-1.4.18-1.x86_64.rpm` | `sudo zypper remove theqa-cta` |
| Arch, Manjaro, EndeavourOS | `sudo pacman -U theqa-cta-1.4.18-1-x86_64.pkg.tar.zst` | `sudo pacman -R theqa-cta` |
| Other | `tar -xzf theqa-cta-1.4.18-linux-x64.tar.gz && sudo ./theqa-cta-1.4.18/install.sh` | `sudo /opt/theqa-cta/install.sh --uninstall` |

- **Smart-card service.** The native packages pull in the distro's smart-card service and reader driver, and start `pcscd.socket`.
- **Tarball.** `install.sh` tells you what to install if the smart-card service is missing.

Then:

1. Restart your browser if it was open. It installs the "Theqa CTA for Linux" extension by itself.
2. Log out and back in, or run `theqa-cta`. A tray icon appears, and from now on it starts at every login.
3. Plug in the reader, insert your ID card, open https://idp-pki.mtcit.gov.om, choose ID card login and enter your PIN on the page.

Uninstalling also removes the browser policy and extension.

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
   packaging/build.sh
   ```

With `packaging/firefox-ext.xpi` present, the packages also install `/etc/firefox/policies/policies.json`, which force-installs it. Commit the signed `.xpi`: Mozilla won't sign the same version twice. Without it, Firefox users can load the userscript (`/usr/share/doc/theqa-cta/theqa-linux.user.js`) in Violentmonkey or Tampermonkey.

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

## Technical details

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
| `packaging/build.sh` | builds all packages with nFPM, plus the tarball |
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
- **New CTA versions.** A newer official CTA needs a rebuild.
- **Page changes.** The browser fix depends on the login page's current OS check. The proper fix is for the service to accept Linux.
