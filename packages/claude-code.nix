{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  autoPatchelfHook,
  alsa-lib,
  procps,
  ripgrep,
  bubblewrap,
  socat,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

let
  release = (import ./versions.nix).code;
  inherit (release) version sources;
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-code-releases/${version}/${source.platform}/claude";
    inherit (source) hash;
  };

  dontUnpack = true;
  dontBuild = true;
  # The binary is a Bun single-file executable; stripping drops the embedded
  # application and leaves only the Bun runtime.
  dontStrip = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    installBin $src

    # Nix owns the version, so the self-updater and install-method checks are
    # disabled. Plugins may still update themselves into ~/.claude.
    #
    # The "system" cert store only reads CA files (SSL_CERT_FILE/SSL_CERT_DIR).
    # On NixOS that bundle includes security.pki certificates, but on macOS it
    # is Nix's bundle and misses roots that live only in the Keychain (e.g. a
    # corporate TLS-inspection CA), so macOS keeps the upstream default.
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        --set-default CLAUDE_CODE_CERT_STORE system \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ alsa-lib ]} \
      ''}--prefix PATH : ${
        lib.makeBinPath (
          [
            # Process-tree cleanup shells out to pgrep (macOS) or ps (Linux).
            procps
            ripgrep
          ]
          # Required by the Bash tool sandbox on Linux.
          ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Anthropic's agentic coding tool for the terminal";
    homepage = "https://code.claude.com/docs";
    changelog = "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
