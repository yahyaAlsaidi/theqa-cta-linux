// ==UserScript==
// @name         Theqa CTA for Linux
// @namespace    theqa
// @match        https://idp-pki.mtcit.gov.om/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==
// Fallback for browsers the .deb's policy-installed extension doesn't cover (Firefox).
// Same code as packaging/browser-ext/os.js: the page rejects Linux, the Linux CTA acts like the Windows one.
Object.defineProperty(Navigator.prototype, "platform", { get: () => "Win32" });
if (self.NavigatorUAData) Object.defineProperty(NavigatorUAData.prototype, "platform", { get: () => "Windows" });
