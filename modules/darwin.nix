self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.anthropic-claude;
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.programs.anthropic-claude = {
    code = lib.mkEnableOption "the official Claude Code CLI";
    desktop = lib.mkEnableOption "the official Claude desktop app for macOS";
  };

  config = lib.mkIf (cfg.code || cfg.desktop) {
    environment.systemPackages =
      lib.optional cfg.code packages.claude-code ++ lib.optional cfg.desktop packages.claude-desktop;
  };
}
