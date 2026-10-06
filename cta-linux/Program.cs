// Port of Digitrustec.CTA.Win.App: same services, hubs and port. Replaced: WPF window/tray -> Avalonia tray,
// Ctrl+Alt+L hotkey -> "Open logs" menu item, SafeNet registry probe/DLL preload and self-updater -> dropped.
using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using Digitrustec.CTA.EToken.Managers;
using Digitrustec.CTA.EToken.Shared;
using Digitrustec.CTA.Shared.Logging;
using Digitrustec.CTA.SignalR.Hubs;
using Digitrustec.CTA.SignalR.Hubs.CapabilitiesControllers;
using Digitrustec.CTA.SignalR.Hubs.Hubs;
using Digitrustec.CTA.SmartCard.Oman_ID;
using Digitrustec.CTA.SmartCard.Shared;
using Microsoft.AspNetCore.SignalR;

EarlyStartupBuffer.LogStartupBanner("CTA.Linux");
var origins = (Environment.GetEnvironmentVariable("THEQA_ALLOWED_ORIGINS") ?? "https://idp-pki.mtcit.gov.om").Split(',');

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(k => k.ListenLocalhost(5234));
var services = builder.Services;
EarlyStartupBuffer.Flush(LoggingBootstrap.ConfigureSerilog(services, "CTA.Linux"));
services.AddSingleton(new Version(Tray.Version));
services.AddTransient<IETokenManager, ETokenManager>();
services.AddTransient<Oman_CivilIDManager>();
services.AddTransient(p => new SmartCardManagerFactory(new List<ISmartCardManager> { p.GetRequiredService<Oman_CivilIDManager>() }));
services.AddTransient<ISmartCardManager>(p => p.GetRequiredService<SmartCardManagerFactory>());
services.AddSignalR(o => o.AddFilter<SignalRHubInterceptor>()).AddJsonProtocol(o =>
{
    o.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    o.PayloadSerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
    o.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
});
services.AddCors(o => o.AddPolicy("cta", p => p.WithOrigins(origins).AllowAnyMethod().AllowAnyHeader().AllowCredentials()));
services.AddSingleton<ETokenController>();
services.AddSingleton<SmartCardController>();
services.AddSingleton<SignalRHubInterceptor>();

var app = builder.Build();
// These hubs drive the ID card, so only listed sites get in;
// checked here because WebSocket connections skip CORS.
app.Use(async (ctx, next) =>
{
    if (origins.Contains(ctx.Request.Headers.Origin.ToString())) await next();
    else ctx.Response.StatusCode = 403;
});
app.UseCors("cta");
app.MapHub<ETokenHub>("/ETokenHub");
app.MapHub<SmartCardHub>("/SmartCardHub");
app.Start();

if (Environment.GetEnvironmentVariable("DISPLAY") is null && Environment.GetEnvironmentVariable("WAYLAND_DISPLAY") is null)
    app.WaitForShutdown(); // no graphical session (e.g. plain systemd): run without the tray
else
{
    // SIGTERM (logout, systemd stop) stops the web host; also end the tray loop so Main returns.
    app.Lifetime.ApplicationStopping.Register(() => Dispatcher.UIThread.Post(() =>
        ((IClassicDesktopStyleApplicationLifetime)Application.Current!.ApplicationLifetime!).Shutdown()));
    AppBuilder.Configure<Tray>().UsePlatformDetect().StartWithClassicDesktopLifetime(args, ShutdownMode.OnExplicitShutdown);
}
// Off this thread: Avalonia leaves its SynchronizationContext here, and stopping on it deadlocks.
Task.Run(() => app.StopAsync()).GetAwaiter().GetResult();

class Tray : Application
{
    // Assembly version is stamped from Digitrustec.CTA.Win.dll at build; the hub reports Major.Minor.Build.
    public static readonly string Version = Assembly.GetEntryAssembly()!.GetName().Version!.ToString(3);

    public override void OnFrameworkInitializationCompleted()
    {
        var logs = new NativeMenuItem("Open logs");
        logs.Click += (_, _) => Process.Start("xdg-open", Directory.CreateDirectory(LoggingPaths.LatestGeneralLogFolder()).FullName);
        var quit = new NativeMenuItem("Quit");
        quit.Click += (_, _) => ((IClassicDesktopStyleApplicationLifetime)ApplicationLifetime!).Shutdown();
        TrayIcon.SetIcons(this, new TrayIcons
        {
            new TrayIcon
            {
                Icon = new WindowIcon(Path.Combine(AppContext.BaseDirectory, "appicon.png")),
                ToolTipText = $"Digitrustec CTA {Version}",
                Menu = new NativeMenu { new NativeMenuItem($"Digitrustec CTA {Version}") { IsEnabled = false }, logs, quit },
            },
        });
        base.OnFrameworkInitializationCompleted();
    }
}
