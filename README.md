# claude-flake

Personal Nix flake packaging Anthropic's official artifacts:

- `claude-code`: the official native Claude Code release for Linux and macOS
- `claude-desktop`: the official Claude desktop app for macOS

Claude Code supports `x86_64-linux`, `aarch64-linux`, and Apple Silicon macOS
(`aarch64-darwin`). Anthropic does not publish a Linux desktop app, so
`claude-desktop` is only built for `aarch64-darwin`.

## NixOS module

```nix
{
  inputs.claude.url = "github:0x0bsod/claude-flake";

  outputs = { nixpkgs, claude, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        claude.nixosModules.default
        { programs.anthropic-claude.code = true; }
      ];
    };
  };
}
```

## nix-darwin module

```nix
{
  inputs.claude.url = "github:0x0bsod/claude-flake";

  outputs = { nix-darwin, claude, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      modules = [
        claude.darwinModules.default
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          programs.anthropic-claude.code = true;
          programs.anthropic-claude.desktop = true;
        }
      ];
    };
  };
}
```

Both options default to `false`.

## Home Manager

Home Manager's `programs.claude-code` module can use the package directly.
With a non-null package it can also declare MCP servers, which it wires in
through a generated plugin:

```nix
{ inputs, pkgs, ... }:
let
  claude = inputs.claude.packages.${pkgs.stdenv.hostPlatform.system};
in {
  programs.claude-code = {
    enable = true;
    package = claude.claude-code;
    settings.theme = "auto";
  };

  home.packages = [ claude.claude-desktop ];
}
```

## Standalone use

```console
nix run .#claude-code
nix build .#claude-desktop
```

The artifacts use immutable, versioned Anthropic release URLs and pinned
hashes so Nix builds remain reproducible. Claude Code's built-in auto-updater
is disabled in the wrapper, because Nix owns the version. The desktop app's
own updater cannot write to the Nix store, so it fails without side effects;
update through this flake instead.

## Updating package versions

Check whether Anthropic has published a newer release:

```console
nix run .#update -- --check
```

The check exits with status `1` when an update is available, which makes it
suitable for CI. Apply all available updates with:

```console
nix run .#update
```

To operate on only one package, pass `--code` or `--desktop`. Claude Code
follows the `latest` channel by default; pass `--channel stable` to pin the
slower stable channel instead. The updater reads the Claude Code release
manifest (which carries per-platform SHA-256 checksums) and the macOS app's
`RELEASES.json` update feed. That feed has no checksum, so the desktop archive
is prefetched and hashed locally. `packages/versions.nix` is rewritten
atomically. Review and build the result before committing it.
