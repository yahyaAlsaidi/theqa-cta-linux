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

- 64-bit Debian/Ubuntu-based Linux (tested on Zorin OS 18.1 / Ubuntu 24.04 base)
- a USB smart-card reader (tested: Alcor Link AK9563)
- Google Chrome, Chromium, Brave or Edge (Firefox: see [Limitations](#limitations))

To build the package you also need:

- .NET 8 SDK: `sudo apt install dotnet-sdk-8.0`
- Wine: `sudo apt install wine`
- `google-chrome` (used to pack the browser extension) and `openssl`

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
   packaging/build-deb.sh        # -> packaging/theqa-cta_<version>_amd64.deb
   ```

   The package version matches the CTA version you built from. The first build generates `packaging/browser-ext.pem`, the extension signing key. Keep it: it fixes the extension ID across updates. It is git-ignored and never packaged.

> The `.deb` contains Digitrustec's assemblies, so don't publish it without their permission.

## Install

```sh
sudo apt install ./packaging/theqa-cta_1.4.18_amd64.deb
```

Then:

1. Restart your browser if it was open. It installs the "Theqa CTA for Linux" extension by itself.
2. Log out and back in, or run `theqa-cta`. A tray icon appears, and from now on it starts at every login.
3. Plug in the reader, insert your ID card, open https://idp-pki.mtcit.gov.om, choose ID card login and enter your PIN on the page.

Uninstall with `sudo apt remove theqa-cta`. This also removes the browser policy and extension.

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
| `packaging/build-deb.sh` | builds the `.deb` |
| `packaging/browser-ext/` | browser extension |
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

Browser side, tested in a fresh headless Chrome 152 profile with the package installed:

- the extension is force-installed;
- the live login page reports `getCtaOs()` = `windows`, while other sites still see `Linux x86_64`;
- the login page reaches `localhost:5234` without a prompt.

## Limitations

- **Firefox.** Firefox only installs Mozilla-signed extensions through policy. Use the userscript (`/usr/share/doc/theqa-cta/theqa-linux.user.js`, needs Violentmonkey or Tampermonkey) until the extension is signed on addons.mozilla.org.
- **eToken.** eToken (`ETokenHub`) login doesn't work: the official code loads a hardcoded Windows PKCS#11 DLL path.
- **One desktop user at a time.** The port, 5234, is fixed.
- **Card photo.** It is returned as raw JPEG 2000, the same as on Windows.
- **New CTA versions.** A newer official CTA needs a rebuild.
- **Page changes.** The browser fix depends on the login page's current OS check. The proper fix is for the service to accept Linux.
