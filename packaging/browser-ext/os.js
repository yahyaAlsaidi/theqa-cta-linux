// The login page sends its OS guess (Extensions.getCtaOs) as X-CTA-OS on every request, and the server
// rejects "unsupported" (= Linux). Theqa CTA for Linux behaves exactly like the Windows CTA, so report Windows.
// Runs before the page's scripts; only on idp-pki.mtcit.gov.om. The user agent string is left alone.
Object.defineProperty(Navigator.prototype, "platform", { get: () => "Win32" });
if (self.NavigatorUAData) Object.defineProperty(NavigatorUAData.prototype, "platform", { get: () => "Windows" });
