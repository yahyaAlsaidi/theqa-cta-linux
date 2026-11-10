{
  description = "Theqa CTA for Linux: Oman ID card login for idp-pki.mtcit.gov.om";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      # The release tarball (same files as the .deb/.rpm), patched to run from the Nix store.
      # On a new release: bump version/release and update hash (from SHA256SUMS, as SRI: nix hash convert).
      theqa-cta = pkgs.callPackage ({ stdenv, lib, fetchurl, autoPatchelfHook, makeWrapper, zlib, fontconfig
                                    , openssl, krb5, pcsclite, libx11, libice, libsm, libxi, libxcursor
                                    , libxrandr, libxext }:
        stdenv.mkDerivation rec {
          pname = "theqa-cta";
          version = "1.4.18";
          release = "3";
          src = fetchurl {
            url = "https://github.com/yahyaAlsaidi/theqa-cta-linux/releases/download/v${version}-${release}/theqa-cta-linux-x64.tar.gz";
            hash = "sha256-g1/xKGsWQPW4AYvgdYMLzdypQs5IPqu1SWj54V3HNM4=";
          };
          nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
          buildInputs = [ stdenv.cc.cc.lib zlib fontconfig openssl krb5 ];
          dontStrip = true; # .NET single-file host breaks when stripped
          installPhase = ''
            app=$out/lib/theqa-cta
            mkdir -p $out/bin $out/lib $out/share $out/etc
            cp -r files/opt/theqa-cta $app
            rm $app/libcoreclrtraceptprovider.so # optional LTTng tracing, needs liblttng-ust
            cp -r files/usr/share/applications files/usr/share/doc $out/share/
            # Policies and desktop entry, pointed at the store instead of /opt and /usr/bin
            cp -r files/etc/. $out/etc/
            rm -r $out/etc/xdg $out/etc/firefox* # Firefox: set by the NixOS module
            for f in $app/browser-ext.xml $out/share/applications/theqa-cta.desktop \
                     $(find $out/etc -name '*.json'); do
              substituteInPlace $f --replace-quiet /opt/theqa-cta $app --replace-quiet Exec=theqa-cta Exec=$out/bin/theqa-cta
            done
            # Loaded at runtime with dlopen: card service client, X11 for the tray icon, OpenSSL for the certificates
            makeWrapper $app/Digitrustec.CTA.Linux $out/bin/theqa-cta \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pcsclite openssl fontconfig libx11 libice libsm libxi libxcursor libxrandr libxext ]}
          '';
          meta = {
            description = "Digitrustec CTA (Identity Reader) for Linux, for the Theqa login";
            platforms = [ "x86_64-linux" ];
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            mainProgram = "theqa-cta";
          };
        }) { };
    in {
      packages.x86_64-linux.default = theqa-cta;

      # Usage: imports = [ theqa-cta.nixosModules.default ]; services.theqa-cta.enable = true;
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.theqa-cta;
          etc = "${cfg.package}/etc";
          # Same as the policies.json in the other packages (packaging/build.sh)
          ff = {
            ExtensionSettings."theqa-cta-linux@yahya.saidi" = {
              installation_mode = "force_installed";
              install_url = "file://${cfg.package}/lib/theqa-cta/firefox-ext.xpi";
            };
            LocalNetworkAccess.SkipDomains = [ "idp-pki.mtcit.gov.om" ];
          };
        in {
          options.services.theqa-cta = {
            enable = lib.mkEnableOption "Theqa CTA (Oman ID card login on idp-pki.mtcit.gov.om)";
            package = lib.mkOption { type = lib.types.package; default = theqa-cta; };
          };
          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
            services.pcscd.enable = true; # smart-card service, with the CCID reader driver by default
            environment.etc = lib.genAttrs
              (map (d: "${d}/policies/managed/theqa-cta.json") [ "opt/chrome" "chromium" "chromium-browser" "brave" "opt/edge" ])
              (p: { source = "${etc}/${p}"; })
            // {
              "xdg/autostart/theqa-cta.desktop".source = "${cfg.package}/share/applications/theqa-cta.desktop";
              # programs.firefox owns this file when enabled; the policies are merged into it below instead
              "firefox/policies/policies.json" = lib.mkIf (!config.programs.firefox.enable) { source = (pkgs.formats.json { }).generate "policies.json" { policies = ff; }; };
            };
            programs.firefox.policies = ff;
          };
        };

      # nix flake check: boots a NixOS VM with the module and checks the CTA answers the login page
      checks.x86_64-linux.vm = pkgs.testers.nixosTest {
        name = "theqa-cta";
        nodes.machine = {
          imports = [ self.nixosModules.default ];
          services.theqa-cta.enable = true;
          programs.firefox.enable = true;
          environment.systemPackages = [ pkgs.curl ];
        };
        testScript = ''
          machine.wait_for_unit("pcscd.socket")
          machine.succeed("test -f /etc/opt/chrome/policies/managed/theqa-cta.json")
          machine.succeed("grep -q LocalNetworkAccess /etc/firefox/policies/policies.json")
          machine.succeed("grep -q /nix/store /etc/xdg/autostart/theqa-cta.desktop")
          machine.succeed("ls $(grep -o '/nix/store/[^:]*pcsclite[^:]*/lib' $(readlink -f $(command -v theqa-cta)))/libpcsclite.so.1")
          machine.succeed("theqa-cta >/tmp/cta.log 2>&1 &")
          machine.wait_until_succeeds("curl -sf -H 'Origin: https://idp-pki.mtcit.gov.om' -X POST "
                                      "'http://127.0.0.1:5234/SmartCardHub/negotiate?negotiateVersion=1' | grep -q connectionId", timeout=60)
        '';
      };
    };
}
