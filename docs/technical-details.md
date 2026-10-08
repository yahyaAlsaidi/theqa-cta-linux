# Technical details

How Theqa CTA for Linux works. For installing and building, see the [README](../README.md).

## How it works

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

## What runs where

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

## Windows to Linux mapping

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

## SmartCardHub API

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

## Browser side

The page's `Extensions.getCtaOs()` returns `windows`, `mac` or `unsupported`, based on `navigator.userAgentData.platform`, `navigator.platform` and the user agent. It sends the result as an `X-CTA-OS` header with every request, and the server refuses `unsupported`.

[`packaging/browser-ext/`](../packaging/browser-ext) is a Manifest V3 extension with one content script. It runs in the page's own JavaScript context before any page script, and only on `https://idp-pki.mtcit.gov.om/*`. It makes `navigator.platform` return `Win32` and `navigator.userAgentData.platform` return `Windows`. The user agent string is untouched, and other sites still see Linux.

The `.deb` installs it with no user action through browser policy:

| File | Purpose |
|---|---|
| `/opt/theqa-cta/browser-ext.crx`, `browser-ext.xml` | packed extension + local (`file://`) update manifest |
| `/etc/opt/chrome/policies/managed/theqa-cta.json`, same under `/etc/chromium`, `/etc/chromium-browser`, `/etc/brave`, `/etc/opt/edge` | `ExtensionInstallForcelist` installs the extension. `LocalNetworkAccessAllowedForUrls` lets the page reach `localhost:5234` without a permission prompt |
| `/etc/firefox/policies/policies.json` (and `/etc/firefox-esr/...`) | `LocalNetworkAccess` with `SkipDomains` lets the page reach `localhost:5234` without a prompt (Firefox 145+). Once a Mozilla-signed `/opt/theqa-cta/firefox-ext.xpi` is shipped, `ExtensionSettings` force-installs the extension |

Because of the policy, the browser shows "Managed by your organization", and the extension can't be removed from inside the browser. Uninstalling the package removes both. To ship a change to the extension, raise `version` in its `manifest.json`.

## Repository

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
