#!/usr/bin/env bash
set -euo pipefail

# Detect OS
detect_os() {
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    echo "macos"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  elif [[ -f /etc/arch-release ]]; then
    echo "arch"
  elif [[ -f /etc/redhat-release ]]; then
    echo "redhat"
  else
    echo "unknown"
  fi
}

OS="$(detect_os)"

REQUIRED_TOOLS="git curl jq"
RECOMMENDED_TOOLS="nmap subfinder whatweb"

missing_required=""
missing_recommended=""
available_tools=""

for tool in $REQUIRED_TOOLS; do
  if ! command -v "$tool" &>/dev/null; then
    missing_required="${missing_required:+$missing_required }$tool"
  fi
done

for tool in $RECOMMENDED_TOOLS; do
  if ! command -v "$tool" &>/dev/null; then
    missing_recommended="${missing_recommended:+$missing_recommended }$tool"
  else
    available_tools="${available_tools:+$available_tools }$tool"
  fi
done

# Helper: convert space-separated string to JSON array
to_json_array() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "[]"
    return
  fi
  local result="["
  local first=true
  for item in $input; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      result="${result},"
    fi
    result="${result}\"${item}\""
  done
  result="${result}]"
  echo "$result"
}

# Get install command for a tool on a given OS
get_install_cmd() {
  local tool="$1"
  local os="$2"
  case "${os}:${tool}" in
    macos:nmap)      echo "brew install nmap" ;;
    macos:subfinder) echo "brew install subfinder" ;;
    macos:whatweb)   echo "brew install whatweb" ;;
    debian:nmap)     echo "sudo apt-get install -y nmap" ;;
    debian:subfinder) echo "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" ;;
    debian:whatweb)  echo "sudo apt-get install -y whatweb" ;;
    arch:nmap)       echo "sudo pacman -S nmap" ;;
    arch:subfinder)  echo "yay -S subfinder" ;;
    arch:whatweb)    echo "yay -S whatweb" ;;
    *) echo "" ;;
  esac
}

# Build install_commands object for missing recommended tools
build_install_commands() {
  if [[ -z "$missing_recommended" ]]; then
    echo "{}"
    return
  fi

  local macos_cmds=""
  local debian_cmds=""
  local arch_cmds=""

  for tool in $missing_recommended; do
    local mcmd dcmd acmd
    mcmd="$(get_install_cmd "$tool" "macos")"
    dcmd="$(get_install_cmd "$tool" "debian")"
    acmd="$(get_install_cmd "$tool" "arch")"
    if [[ -n "$mcmd" ]]; then
      macos_cmds="${macos_cmds:+$macos_cmds && }$mcmd"
    fi
    if [[ -n "$dcmd" ]]; then
      debian_cmds="${debian_cmds:+$debian_cmds && }$dcmd"
    fi
    if [[ -n "$acmd" ]]; then
      arch_cmds="${arch_cmds:+$arch_cmds && }$acmd"
    fi
  done

  jq -n \
    --arg macos "$macos_cmds" \
    --arg debian "$debian_cmds" \
    --arg arch "$arch_cmds" \
    '{macos: $macos, debian: $debian, arch: $arch}'
}

missing_req_json="$(to_json_array "$missing_required")"
missing_rec_json="$(to_json_array "$missing_recommended")"
available_json="$(to_json_array "$available_tools")"
install_cmds_json="$(build_install_commands)"

jq -n \
  --arg os "$OS" \
  --argjson missing_required "$missing_req_json" \
  --argjson missing_recommended "$missing_rec_json" \
  --argjson available_tools "$available_json" \
  --argjson install_commands "$install_cmds_json" \
  '{
    os: $os,
    missing_required: $missing_required,
    missing_recommended: $missing_recommended,
    available_tools: $available_tools,
    install_commands: $install_commands
  }'

# Fail if any required tools are missing
if [[ -n "$missing_required" ]]; then
  exit 1
fi
