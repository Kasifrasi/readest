{
  description = "Readest Tauri v2 development environment for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      rust-overlay,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        inherit (pkgs) lib;

        # Keep the Rust tools on one release and make rust-analyzer use the same
        # standard-library sources as cargo/rustc.
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "clippy"
            "llvm-tools-preview"
            "rust-analyzer"
            "rust-src"
            "rustfmt"
          ];
        };

        # Native libraries used by Tauri/wry and Readest's Linux-specific Rust
        # dependencies. The Darwin branch keeps flake evaluation portable.
        tauriLibs =
          with pkgs;
          [
            fontconfig
            freetype
            openssl
            zlib
          ]
          ++ lib.optionals stdenv.isLinux [
            at-spi2-atk
            atkmm
            cairo
            dbus
            gdk-pixbuf
            glib
            glib-networking
            gtk3
            gtk4
            harfbuzz
            libGL
            librsvg
            libsoup_3
            libxkbcommon
            pango
            wayland
            webkitgtk_4_1
          ]
          ++ lib.optionals stdenv.isDarwin [
            libiconv
          ];

        runtimeLibraryPath = lib.makeLibraryPath tauriLibs;
        pkgConfigPath = lib.concatStringsSep ":" [
          (lib.makeSearchPath "lib/pkgconfig" (map lib.getDev tauriLibs))
          (lib.makeSearchPath "share/pkgconfig" (map lib.getDev tauriLibs))
        ];
        xdgDataPath = lib.makeSearchPath "share/gsettings-schemas" [
          pkgs.gsettings-desktop-schemas
          pkgs.gtk3
        ];

        fontConfig = pkgs.writeText "readest-fonts.conf" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <include ignore_missing="yes">${pkgs.fontconfig.out}/etc/fonts/conf.d</include>
            <dir prefix="xdg">fonts</dir>
            <dir>~/.fonts</dir>
            <dir>~/.nix-profile/share/fonts</dir>
            <dir>/run/current-system/sw/share/X11/fonts</dir>
            <dir>/run/current-system/sw/share/fonts</dir>
            <dir>/usr/local/share/fonts</dir>
            <dir>/usr/share/fonts</dir>
            <dir>${pkgs.dejavu_fonts}/share/fonts/truetype</dir>
            <cachedir prefix="xdg">fontconfig</cachedir>
            <cachedir>/var/cache/fontconfig</cachedir>
          </fontconfig>
        '';

        # Real commands in PATH, so they also work in Nushell and other shells.
        script-setup = pkgs.writeShellScriptBin "setup-readest" ''
          set -euo pipefail
          root="$(git rev-parse --show-toplevel)"
          cd "$root"

          git submodule update --init --recursive
          CI=true pnpm install --frozen-lockfile
          pnpm --filter @readest/readest-app setup-vendors
        '';

        script-dev = pkgs.writeShellScriptBin "dev" ''
          set -euo pipefail
          root="$(git rev-parse --show-toplevel)"
          cd "$root"

          if [ ! -f packages/tauri/Cargo.toml ] || [ ! -f apps/readest-app/node_modules/next/package.json ]; then
            echo 'Readest ist noch nicht vollständig eingerichtet; setup-readest wird ausgeführt.'
            setup-readest
          fi

          export READEST_DISABLE_UPDATER="''${READEST_DISABLE_UPDATER:-1}"
          exec pnpm tauri dev "$@"
        '';

        script-dev-web = pkgs.writeShellScriptBin "dev-web" ''
          set -euo pipefail
          root="$(git rev-parse --show-toplevel)"
          cd "$root"
          if [ ! -f apps/readest-app/node_modules/next/package.json ]; then
            setup-readest
          fi
          exec pnpm dev-web "$@"
        '';

        script-tauri-info = pkgs.writeShellScriptBin "tauri-info" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          exec pnpm tauri info "$@"
        '';

        script-test = pkgs.writeShellScriptBin "test-readest" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          exec pnpm test -- --watch=false "$@"
        '';

        script-lint = pkgs.writeShellScriptBin "lint-readest" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          exec pnpm lint "$@"
        '';

        script-fmt = pkgs.writeShellScriptBin "fmt-readest" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          pnpm fmt:check
          exec pnpm format:check
        '';

        script-clippy = pkgs.writeShellScriptBin "clippy-readest" ''
          set -euo pipefail
          cd "$(git rev-parse --show-toplevel)"
          exec pnpm clippy:check "$@"
        '';

        devTools = with pkgs; [
          cargo-nextest
          clang
          git
          lld
          llvmPackages.libclang
          nodejs_24
          pkg-config
          pnpm
          xdg-utils
          script-setup
          script-dev
          script-dev-web
          script-tauri-info
          script-test
          script-lint
          script-fmt
          script-clippy
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = devTools;
          nativeBuildInputs = [ rustToolchain ];
          buildInputs = tauriLibs;

          CC = "clang";
          CXX = "clang++";
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          PKG_CONFIG_PATH = pkgConfigPath;
          LIBRARY_PATH = runtimeLibraryPath;
          LD_LIBRARY_PATH = "${runtimeLibraryPath}${lib.optionalString pkgs.stdenv.isLinux ":/run/opengl-driver/lib"}";
          FONTCONFIG_FILE = fontConfig;

          # WebKitGTK needs the GIO TLS module for HTTPS on NixOS. Disabling
          # compositing also avoids the common blank/crashing Tauri window on
          # drivers where WebKit's accelerated renderer is unavailable.
          GIO_EXTRA_MODULES = lib.optionalString pkgs.stdenv.isLinux "${pkgs.glib-networking}/lib/gio/modules";
          GDK_BACKEND = lib.optionalString pkgs.stdenv.isLinux "x11";
          WEBKIT_DISABLE_COMPOSITING_MODE = lib.optionalString pkgs.stdenv.isLinux "1";

          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "clang";
          CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "clang";
          RUSTFLAGS = lib.optionalString pkgs.stdenv.isLinux "-C link-arg=-fuse-ld=lld -C link-arg=-Wl,-rpath,${runtimeLibraryPath}";

          shellHook = ''
            export XDG_DATA_DIRS="${xdgDataPath}:''${XDG_DATA_DIRS:-}"
            echo '=================================================='
            echo '📚 Readest | Tauri v2 development shell'
            echo '=================================================='
            echo "Node:  $(node --version)"
            echo "pnpm:  $(pnpm --version)"
            echo "Rust:  $(rustc --version)"
            echo
            echo 'Verfügbare Befehle:'
            echo '  setup-readest  - Submodule, pnpm-Pakete und Vendor-Dateien einrichten'
            echo '  dev            - Readest als Tauri-Desktop-App starten'
            echo '  dev-web        - Nur das Next.js-Frontend starten'
            echo '  tauri-info     - Erkannte Tauri-Systemabhängigkeiten anzeigen'
            echo '  test-readest   - Unit-Tests einmalig ausführen'
            echo '  lint-readest   - TypeScript und Biome prüfen'
            echo '  fmt-readest    - Rust- und Frontend-Formatierung prüfen'
            echo '  clippy-readest - Rust-Code prüfen'
          '';
        };
      }
    );
}
