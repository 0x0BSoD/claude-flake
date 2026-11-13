#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update [--check] [--code | --desktop] [--channel latest|stable]

Checks Anthropic's official release metadata. Without --check, updates
packages/versions.nix atomically. By default both packages are checked.

  --check            Report updates and exit 1 when versions.nix is outdated
  --code             Check/update only the Claude Code CLI
  --desktop          Check/update only the Claude desktop app
  --channel CHANNEL  Claude Code release channel (default: latest)
EOF
}

check_only=false
update_code=false
update_desktop=false
channel=latest

while (($#)); do
  case "$1" in
    --check) check_only=true ;;
    --code) update_code=true ;;
    --desktop) update_desktop=true ;;
    --channel)
      [[ $# -ge 2 ]] || { echo "--channel needs a value" >&2; exit 2; }
      channel=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$channel" in
  latest|stable) ;;
  *) echo "Unknown channel: $channel (expected latest or stable)" >&2; exit 2 ;;
esac

if ! $update_code && ! $update_desktop; then
  update_code=true
  update_desktop=true
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
versions_file="$repo_root/packages/versions.nix"
[[ -f "$versions_file" ]] || { echo "Cannot find $versions_file" >&2; exit 2; }

nix_value() {
  nix --extra-experimental-features nix-command eval --raw --file "$versions_file" "$1"
}

hex_to_sri() {
  nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$1"
}

fetch() {
  curl --fail --silent --show-error --location "$1"
}

code_base=https://downloads.claude.ai/claude-code-releases
desktop_base=https://downloads.claude.ai/releases/darwin/universal

code_version=$(nix_value code.version)
code_linux_x64_hash=$(nix_value code.sources.x86_64-linux.hash)
code_linux_arm64_hash=$(nix_value code.sources.aarch64-linux.hash)
code_darwin_arm64_hash=$(nix_value code.sources.aarch64-darwin.hash)
desktop_version=$(nix_value desktop.version)
desktop_build=$(nix_value desktop.build)
desktop_hash=$(nix_value desktop.hash)

old_code_version=$code_version
old_desktop_version=$desktop_version

if $update_code; then
  new_code_version=$(fetch "$code_base/$channel" | tr -d '[:space:]')
  [[ "$new_code_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || {
    echo "Unexpected Claude Code version on channel $channel: $new_code_version" >&2; exit 1;
  }
  code_version=$new_code_version

  if ! $check_only && [[ "$code_version" != "$old_code_version" ]]; then
    manifest=$(fetch "$code_base/$code_version/manifest.json")
    code_digest() {
      jq -er --arg p "$1" '.platforms[$p].checksum' <<<"$manifest"
    }
    code_linux_x64_hash=$(hex_to_sri "$(code_digest linux-x64)")
    code_linux_arm64_hash=$(hex_to_sri "$(code_digest linux-arm64)")
    code_darwin_arm64_hash=$(hex_to_sri "$(code_digest darwin-arm64)")
  fi
fi

if $update_desktop; then
  # RELEASES.json is the Squirrel.Mac feed the app itself updates from.
  read -r new_desktop_version desktop_url <<<"$(
    fetch "$desktop_base/RELEASES.json" |
      jq -er '.currentRelease as $v
        | .releases[] | select(.version == $v)
        | "\($v) \(.updateTo.url)"'
  )"
  [[ -n "$new_desktop_version" && -n "$desktop_url" ]] || {
    echo "Could not read the macOS desktop release metadata" >&2; exit 1;
  }
  [[ "$desktop_url" =~ /${new_desktop_version//./\\.}/Claude-([0-9a-f]+)\.zip$ ]] || {
    echo "Unexpected desktop download URL: $desktop_url" >&2; exit 1;
  }
  new_desktop_build=${BASH_REMATCH[1]}

  # The feed carries no checksum, so the archive is hashed locally.
  if ! $check_only && [[ "$new_desktop_version" != "$desktop_version" ]]; then
    desktop_hash=$(
      nix --extra-experimental-features nix-command store prefetch-file --json "$desktop_url" |
        jq -er .hash
    )
  fi
  desktop_version=$new_desktop_version
  desktop_build=$new_desktop_build
fi

changed=false
if $update_code; then
  if [[ "$code_version" != "$old_code_version" ]]; then
    echo "Claude Code ($channel): $old_code_version -> $code_version"
    changed=true
  else
    echo "Claude Code ($channel): $old_code_version (current)"
  fi
fi
if $update_desktop; then
  if [[ "$desktop_version" != "$old_desktop_version" ]]; then
    echo "Claude desktop (macOS): $old_desktop_version -> $desktop_version"
    changed=true
  else
    echo "Claude desktop (macOS): $old_desktop_version (current)"
  fi
fi

if $check_only; then
  $changed && exit 1
  exit 0
fi

tmp=$(mktemp "$repo_root/packages/.versions.nix.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<EOF
{
  code = {
    version = "$code_version";
    sources = {
      x86_64-linux = {
        platform = "linux-x64";
        hash = "$code_linux_x64_hash";
      };
      aarch64-linux = {
        platform = "linux-arm64";
        hash = "$code_linux_arm64_hash";
      };
      aarch64-darwin = {
        platform = "darwin-arm64";
        hash = "$code_darwin_arm64_hash";
      };
    };
  };

  desktop = {
    version = "$desktop_version";
    build = "$desktop_build";
    hash = "$desktop_hash";
  };
}
EOF
mv "$tmp" "$versions_file"
trap - EXIT

if $changed; then
  echo "Updated packages/versions.nix"
else
  echo "No update needed"
fi
