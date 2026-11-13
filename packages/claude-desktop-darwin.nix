{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  release = (import ./versions.nix).desktop;
  inherit (release) version build hash;
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/darwin/universal/${version}/Claude-${build}.zip";
    inherit hash;
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";
  # Any post-install rewriting, including shebang patching, invalidates the
  # app's nested code signatures and causes Gatekeeper to reject the bundle.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -a Claude.app "$out/Applications/"
    ln -s "$out/Applications/Claude.app/Contents/MacOS/Claude" "$out/bin/claude-desktop"
    runHook postInstall
  '';

  meta = {
    description = "Anthropic's official Claude desktop app for macOS";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
