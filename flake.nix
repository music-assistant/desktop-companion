{
  description = "Music Assistant Desktop Companion - Tauri v2 app with Vue 3 frontend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      pre-commit-hooks,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Rust toolchain (minimum 1.77.2 as per Cargo.toml)
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "clippy"
            "rustfmt"
          ];
        };

        # Pre-commit hooks configuration
        # NOTE: This project has an existing .pre-commit-config.yaml + husky setup.
        # The Nix-managed hooks are complementary and can be run via:
        #   nix flake check (CI)
        #   pre-commit run --all-files (manually, after removing .pre-commit-config.yaml)
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = pkgs.lib.cleanSource ./.;
          hooks = {
            # Rust hooks
            rustfmt = {
              enable = true;
              entry = "${rustToolchain}/bin/cargo fmt --manifest-path src-tauri/Cargo.toml --";
            };
            clippy = {
              enable = true;
              entry = "${rustToolchain}/bin/cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings";
              pass_filenames = false;
            };

            # Frontend hooks (using yarn scripts)
            eslint = {
              enable = true;
              entry = "${pkgs.yarn}/bin/yarn lint";
              files = "\\.(vue|ts|tsx|js|jsx)$";
              pass_filenames = false;
            };

            # General hooks (built-in) - matching existing .pre-commit-config.yaml
            prettier.enable = true;
            check-merge-conflicts.enable = true;
            end-of-file-fixer.enable = true;
            trim-trailing-whitespace.enable = true;
            check-added-large-files.enable = true;
            check-json.enable = true;
            # codespell for spell checking (matches existing config)
            typos.enable = true; # faster alternative to codespell
          };
        };

        # Common build inputs for Tauri
        buildInputs =
          with pkgs;
          [
            # Tauri dependencies
            webkitgtk_4_1
            gtk3
            cairo
            gdk-pixbuf
            glib
            glib-networking
            dbus
            openssl
            librsvg

            # Audio/media dependencies
            alsa-lib
            pulseaudio
          ]
          ++ lib.optionals stdenv.hostPlatform.isDarwin [
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.CoreServices
            darwin.apple_sdk.frameworks.CoreFoundation
            darwin.apple_sdk.frameworks.Foundation
            darwin.apple_sdk.frameworks.AppKit
            darwin.apple_sdk.frameworks.WebKit
            darwin.apple_sdk.frameworks.Cocoa
          ];

        nativeBuildInputs = with pkgs; [
          # Rust
          rustToolchain
          cargo-tauri
          cargo-watch
          cargo-audit
          cargo-deny

          # Node.js / Frontend
          nodejs_22
          yarn

          # Build tools
          pkg-config
          makeWrapper

          # For cargo-tauri to work
          wrapGAppsHook3

          # Linting and formatting
          nodePackages.prettier
          nodePackages.eslint

          # Testing
          # (vitest is installed via yarn, but we need chromium for e2e if needed)

          # Pre-commit and git hooks
          pre-commit
          git

          # Development utilities
          jq
          watchexec
          typos # spell checker (faster than codespell)
        ];

        # Local package build (uses local source)
        localPackage = pkgs.rustPlatform.buildRustPackage {
          pname = "music-assistant-companion";
          version = "0.1.0-local";

          src = pkgs.lib.cleanSource ./.;

          cargoRoot = "src-tauri";
          buildAndTestSubdir = "src-tauri";

          # These hashes need to be computed - use lib.fakeHash initially
          # then replace with actual hash after first build attempt
          cargoHash = "sha256-4+uRwaeVMq2E6cRDmkq1GET3XW1ucd+LJs/AWNEsX2U=";

          yarnOfflineCache = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            hash = "sha256-XxP3c6aloiEzqRLdH5EgFjyvr9bYEeseF6HY7QCf8Xk=";
          };

          nativeBuildInputs = with pkgs; [
            cargo-tauri.hook
            nodejs_22
            yarn
            yarnConfigHook
            pkg-config
            wrapGAppsHook3
          ];

          buildInputs =
            with pkgs;
            [
              openssl
              glib-networking
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              webkitgtk_4_1
              alsa-lib
              pulseaudio
              libayatana-appindicator
            ]
            ++ lib.optionals stdenv.hostPlatform.isDarwin [
              darwin.apple_sdk.frameworks.AppKit
              darwin.apple_sdk.frameworks.CoreServices
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.WebKit
            ];

          # Ensure dlopen'd libraries are found at runtime
          postFixup = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            patchelf --add-rpath ${pkgs.libayatana-appindicator}/lib $out/bin/.music-assistant-companion-wrapped
          '';

          meta = with pkgs.lib; {
            description = "Desktop companion app for Music Assistant";
            homepage = "https://github.com/music-assistant/desktop-companion";
            license = licenses.asl20;
            platforms = platforms.linux ++ platforms.darwin;
            mainProgram = "music-assistant";
          };
        };

      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          shellHook = ''
            # Set up environment for Tauri
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath buildInputs}:$LD_LIBRARY_PATH"

            # WebKit/GTK environment
            export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"

            # OpenSSL for tungstenite native-tls
            export OPENSSL_DIR="${pkgs.openssl.dev}"
            export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
            export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include"
            export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"

            # Tauri dev server port
            export TAURI_DEV_HOST="localhost"

            # Set up pre-commit hooks
            ${pre-commit-check.shellHook}

            echo ""
            echo "🎵 Music Assistant Desktop Companion - Dev Environment"
            echo ""
            echo "Development Commands:"
            echo "  yarn install        - Install Node dependencies"
            echo "  yarn dev            - Start Vite dev server (frontend only)"
            echo "  yarn tauri dev      - Start full Tauri dev environment"
            echo "  yarn tauri build    - Build production binary"
            echo ""
            echo "Testing Commands:"
            echo "  yarn test           - Run frontend tests in watch mode"
            echo "  yarn test:run       - Run frontend tests once"
            echo "  yarn test:coverage  - Run tests with coverage"
            echo "  cargo test --manifest-path src-tauri/Cargo.toml  - Run Rust tests"
            echo ""
            echo "Linting & Formatting:"
            echo "  yarn lint           - Lint and fix frontend code"
            echo "  cargo fmt --manifest-path src-tauri/Cargo.toml   - Format Rust code"
            echo "  cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings  - Lint Rust code"
            echo ""
            echo "Pre-commit Hooks:"
            echo "  pre-commit run --all-files  - Run all pre-commit hooks"
            echo "  pre-commit install          - Install git hooks"
            echo ""
            echo "Security Auditing:"
            echo "  cargo audit --file src-tauri/Cargo.lock  - Audit Rust dependencies"
            echo "  cargo deny check --manifest-path src-tauri/Cargo.toml  - Check dependencies"
            echo ""
          '';

          RUST_BACKTRACE = 1;
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
        };

        # Local package using rustPlatform.buildRustPackage + cargo-tauri.hook
        packages.default = localPackage;

        # Expose pre-commit checks
        checks = {
          pre-commit-check = pre-commit-check;
        };
      }
    );
}
