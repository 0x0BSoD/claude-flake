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
  # Anthropic does not publish a Linux build of the desktop app.
  options.programs.anthropic-claude = {
    code = lib.mkEnableOption "the official Claude Code CLI";
  };

  config = lib.mkIf cfg.code {
    environment.systemPackages = [ packages.claude-code ];
  };
}
