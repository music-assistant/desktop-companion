# NOTE: This package requires the upstream repo to add @tauri-apps/plugin-opener
# to package.json before it can build successfully.
# See: https://github.com/music-assistant/desktop-companion
#
# Once fixed, update the hashes below:
# - src.hash: compute from fetchFromGitHub
# - cargoHash: computed as sha256-bRcZFsSEuPNHBZq93EWlSIdtsJfivJTm3H/FhjTR6po= (from local yarn.lock)
# - yarnOfflineCache.hash: computed as sha256-10sriU2XiderfUpLMYC2JNbVXBGNsEEWh6OuqKxzUDo= (from local yarn.lock)
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchYarnDeps,
  cargo-tauri,
  glib-networking,
  nodejs,
  yarnConfigHook,
  yarn,
  openssl,
  pkg-config,
  webkitgtk_4_1,
  wrapGAppsHook3,
  alsa-lib,
  pulseaudio,
  darwin,
}:

let
  pname = "music-assistant-companion";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "music-assistant";
    repo = "desktop-companion";
    rev = "v${version}";
    hash = lib.fakeHash; # TODO: update when release is tagged
  };
in
rustPlatform.buildRustPackage {
  inherit pname version src;

  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";

  # Computed from Cargo.lock in src-tauri/
  cargoHash = lib.fakeHash; # TODO: sha256-bRcZFsSEuPNHBZq93EWlSIdtsJfivJTm3H/FhjTR6po=

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${src}/yarn.lock";
    # Computed from yarn.lock
    hash = lib.fakeHash; # TODO: sha256-10sriU2XiderfUpLMYC2JNbVXBGNsEEWh6OuqKxzUDo=
  };

  nativeBuildInputs = [
    cargo-tauri.hook
    nodejs
    yarn
    yarnConfigHook
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs =
    [
      openssl
      glib-networking
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      webkitgtk_4_1
      alsa-lib
      pulseaudio
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin (
      with darwin.apple_sdk.frameworks;
      [
        AppKit
        CoreServices
        Security
        WebKit
      ]
    );

  meta = {
    description = "Desktop companion app for Music Assistant";
    homepage = "https://github.com/music-assistant/desktop-companion";
    changelog = "https://github.com/music-assistant/desktop-companion/releases/tag/v${version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      eldios
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "music-assistant";
  };
}
