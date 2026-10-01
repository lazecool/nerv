#!/usr/bin/env bash

# Configure the workspace with macOS system shell tools only.
# Existing workspace files are preserved; missing files receive defaults.
# Coding-agent CLIs are installed with their official standalone installers.
set -Eeuo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORKSPACE_ONLY=0
SKIP_INSTALL=0
CHECK_ONLY=0
CODEX_INSTALLED_NOW=0

usage() {
  printf '%s\n' 'Usage: ./setup.sh [--workspace-only] [--skip-install] [--check]' \
    '  --workspace-only  Create missing workspace files; no installations or home changes.' \
    '  --skip-install    Skip CLI and mcp-memory-service installation.' \
    '  --check           Check workspace files and shell syntax without changing anything.'
}

die() { printf 'setup: error: %s\n' "$*" >&2; exit 1; }
info() { printf 'setup: %s\n' "$*"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_memory_service() {
  local memory_dir="$ROOT_DIR/external/mcp-memory-service"
  command_exists git || die "git is required to install mcp-memory-service"
  command_exists python3 || die "python3 is required to install mcp-memory-service"

  if [[ ! -e "$memory_dir" ]]; then
    info "cloning mcp-memory-service into external/mcp-memory-service"
    git clone https://github.com/doobidoo/mcp-memory-service.git "$memory_dir"
  elif [[ ! -d "$memory_dir/.git" ]]; then
    die "$memory_dir exists but is not a Git repository; move it or inspect it before setup"
  else
    info "preserved existing external/mcp-memory-service checkout"
  fi

  if [[ ! -x "$memory_dir/.venv/bin/memory" ]]; then
    info "creating isolated Python environment and installing mcp-memory-service (editable)"
    python3 -m venv "$memory_dir/.venv"
    "$memory_dir/.venv/bin/python" -m pip install --upgrade pip
  fi
  if ! "$memory_dir/.venv/bin/python" -c 'import importlib.util, sys; sys.exit(0 if all(importlib.util.find_spec(name) for name in ("torch", "sentence_transformers", "onnxruntime")) else 1)' >/dev/null 2>&1; then
    info "installing mcp-memory-service with SQLite-vec and ML search dependencies"
    "$memory_dir/.venv/bin/python" -m pip install --editable "$memory_dir[sqlite-ml]"
  else
    info "mcp-memory-service SQLite-vec and ML search dependencies are already installed"
  fi
  info "mcp-memory-service is configured for local SQLite-vec; start with:"
  info "MCP_MEMORY_STORAGE_BACKEND=sqlite_vec '$memory_dir/.venv/bin/memory' launch"
}

for option in "$@"; do
  case "$option" in
    --workspace-only) WORKSPACE_ONLY=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $option" ;;
  esac
done

# Consume the heredoc even when preserving a file, avoiding broken-pipe errors.
write_default() {
  local relative="$1" destination="$ROOT_DIR/$1"
  if [[ -e "$destination" || -L "$destination" ]]; then
    cat >/dev/null
    info "preserved $relative"
  else
    mkdir -p "$(dirname -- "$destination")"
    cat > "$destination"
    info "created $relative"
  fi
}

configure_workspace() {
  mkdir -p "$ROOT_DIR/projects" "$ROOT_DIR/external" "$ROOT_DIR/memory"
  write_default 'projects/.gitkeep' </dev/null
  write_default 'external/.gitkeep' </dev/null
  write_default '.agentignore' <<'NERV_DEFAULT_EOF'
# Agent exploration exclusions; these are not Git ignore rules.
AGENTS.local.md
**/.env
**/.env.*
**/secrets/**
**/*.pem
**/*.key
**/.aws/**
**/.venv/**
**/node_modules/**
**/__pycache__/**
.git/**
external/**
NERV_DEFAULT_EOF
  write_default '.claude/agents/magi.md' <<'NERV_DEFAULT_EOF'
---
name: magi
description: 사용자가 마기, MAGI 또는 magi를 명시적으로 호출하거나 기존 MAGI 작업을 이어갈 때만 사용한다.
model: fable
---
AGENTS.md의 공통 규칙을 따른다.
사용자가 마기, MAGI 또는 magi를 명시적으로 호출하거나 기존 MAGI 작업을 이어갈 때만 수행한다.
원래 요청, 관련 파일, 결정, 실패한 시도, 기대하는 산출물을 확인한다.
탐색 전에 .agentignore를 확인한다. 사용자 대상 결과는 기본 한국어로 작성한다.
근거와 가정을 구분하고 변경에 적합한 검증을 수행한다.
모든 최종 답변은 ✨ MAGI: prefix로 시작한다.
NERV_DEFAULT_EOF
  write_default '.claude/settings.json' <<'NERV_DEFAULT_EOF'
{
  "env": {
    "MAX_MCP_OUTPUT_TOKENS": "2000",
    "BASH_MAX_OUTPUT_LENGTH": "8000"
  },
  "permissions": {
    "deny": [
      "Read(**/.env)", "Edit(**/.env)", "Write(**/.env)",
      "Read(**/.env.*)", "Edit(**/.env.*)", "Write(**/.env.*)",
      "Read(**/secrets/**)", "Edit(**/secrets/**)", "Write(**/secrets/**)",
      "Read(**/*.pem)", "Edit(**/*.pem)", "Write(**/*.pem)",
      "Read(**/*.key)", "Edit(**/*.key)", "Write(**/*.key)",
      "Read(**/.aws/**)", "Edit(**/.aws/**)", "Write(**/.aws/**)"
    ]
  }
}
NERV_DEFAULT_EOF
  write_default '.codex/agents/fast.toml' <<'NERV_DEFAULT_EOF'
model = "gpt-6-luna"
model_reasoning_effort = "low"
developer_instructions = """
AGENTS.md의 공통 규칙을 따른다. 일반 위임을 빠르게 수행한다.
탐색 전에 .agentignore를 확인한다. 사용자 대상 결과는 기본 한국어로 작성한다.
일반 최종 답변은 💬 MARVIN: prefix로 시작한다.
"""
NERV_DEFAULT_EOF
  write_default '.codex/agents/magi.toml' <<'NERV_DEFAULT_EOF'
model = "gpt-6-astra"
model_reasoning_effort = "xhigh"
developer_instructions = """
AGENTS.md의 공통 규칙을 따른다.
사용자가 마기, MAGI 또는 magi를 명시적으로 호출하거나 기존 MAGI 작업을 이어갈 때만 수행한다.
원래 요청, 관련 파일, 결정, 실패한 시도, 기대하는 산출물을 확인한다.
탐색 전에 .agentignore를 확인한다. 사용자 대상 결과는 기본 한국어로 작성한다.
근거와 가정을 구분하고 변경에 적합한 검증을 수행한다.
모든 최종 답변은 ✨ MAGI: prefix로 시작한다.
"""
NERV_DEFAULT_EOF
  write_default '.codex/config.toml' <<'NERV_DEFAULT_EOF'
model = "gpt-6-luna"
model_reasoning_effort = "low"
tool_output_token_limit = 2000
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[agents.fast]
description = "일반 위임을 빠르게 처리하고 한국어로 결과를 반환한다."
config_file = "agents/fast.toml"

[agents.magi]
description = "사용자가 마기, MAGI 또는 magi를 명시적으로 호출하거나 기존 MAGI 작업을 이어갈 때만 사용한다."
config_file = "agents/magi.toml"
NERV_DEFAULT_EOF
  write_default '.mcp.json' <<'NERV_DEFAULT_EOF'
{
  "mcpServers": {}
}
NERV_DEFAULT_EOF
  write_default 'CLAUDE.md' <<'NERV_DEFAULT_EOF'
# 공통 workspace 지침

@AGENTS.md
@AGENTS.local.md
@.agentignore

`.agentignore`의 패턴에 해당하는 경로는 기본 탐색에서 제외한다.
Claude의 파일 도구 접근 차단은 `.claude/settings.json`에도 설정한다.
NERV_DEFAULT_EOF
  write_default 'memory/GLOBAL.md' <<'NERV_DEFAULT_EOF'
# 전역 메모리

사용자 공통 선호와 workspace 운영 결정만 기록한다.
프로젝트별 정보는 `projects/<project-name>/MEMORY.md`에 기록하고,
해당 파일이 없으면 `memory/<project-name>-MEMORY.md`를 사용한다.

- 사용자 대상 응답의 기본 언어는 한국어다.
- 일반 agent는 MARVIN, 명시 호출한 심층 추론 agent는 MAGI다.
- 프로젝트 코드는 `projects/`, 외부 독립 저장소는 `external/`에서 관리한다.
NERV_DEFAULT_EOF
}

# Check workspace structure, JSON/TOML syntax, and drift from embedded defaults.
check_workspace() {
  local relative failures=0 defaults_dir default_file
  for relative in AGENTS.md .agentignore CLAUDE.md bin/nerv lib/nerv.rb lib/nerv/cli.rb \
    lib/nerv/memory_service.rb .codex/config.toml \
    .codex/agents/fast.toml .codex/agents/magi.toml .claude/settings.json \
    .claude/agents/magi.md .mcp.json memory/GLOBAL.md; do
    if [[ -s "$ROOT_DIR/$relative" ]]; then
      info "OK: $relative"
    else
      info "FAIL: missing or empty $relative"
      failures=1
    fi
  done
  for relative in projects external memory lib/nerv lib/nerv/adapters test; do
    if [[ -d "$ROOT_DIR/$relative" ]]; then
      info "OK: $relative/"
    else
      info "FAIL: missing directory $relative/"
      failures=1
    fi
  done
  if command_exists ruby; then
    for relative in bin/nerv lib/nerv.rb lib/nerv/cli.rb lib/nerv/memory_service.rb; do
      if ruby -c "$ROOT_DIR/$relative" >/dev/null; then
        info "OK: $relative syntax"
      else
        info "FAIL: $relative syntax"
        failures=1
      fi
    done
  else
    info 'WARN: Ruby unavailable; NERV CLI syntax not checked'
  fi
  defaults_dir="$(mktemp -d "${TMPDIR:-/tmp}/nerv-setup-check.XXXXXX")" || return 1
  trap 'rm -rf "$defaults_dir"' RETURN

  extract_default() {
    local relative="$1" marker="NERV_DEFAULT_EOF" destination="$defaults_dir/$1"
    mkdir -p "$(dirname -- "$destination")"
    awk -v relative="$relative" -v marker="$marker" '
      $0 == "  write_default '\''" relative "'\'' <<'\''" marker "'\''" { copying=1; next }
      copying && $0 == marker { found=1; exit }
      copying { print }
      END { if (!found) exit 1 }
    ' "$ROOT_DIR/setup.sh" > "$destination"
  }

  for relative in .codex/config.toml .codex/agents/fast.toml \
    .codex/agents/magi.toml .claude/settings.json .claude/agents/magi.md .mcp.json; do
    default_file="$defaults_dir/$relative"
    if ! extract_default "$relative"; then
      info "FAIL: could not extract embedded default for $relative"
      failures=1
    elif ! cmp -s "$default_file" "$ROOT_DIR/$relative"; then
      info "DIFF: $relative differs from setup.sh default (preserved; not modified)"
      diff -u "$default_file" "$ROOT_DIR/$relative" || true
    else
      info "OK: $relative matches setup.sh default"
    fi
  done
  if [[ -f "$ROOT_DIR/AGENTS.local.md" ]]; then
    info 'OK: AGENTS.local.md (local override present; excluded from default comparison)'
  else
    info 'OK: AGENTS.local.md (optional local override not present)'
  fi

  for relative in .claude/settings.json .mcp.json; do
    if command_exists python3; then
      if python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$ROOT_DIR/$relative" >/dev/null 2>&1; then
        info "OK: $relative JSON syntax"
      else
        info "FAIL: $relative JSON syntax"
        failures=1
      fi
    elif command_exists node; then
      if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$ROOT_DIR/$relative" >/dev/null 2>&1; then
        info "OK: $relative JSON syntax"
      else
        info "FAIL: $relative JSON syntax"
        failures=1
      fi
    else
      info "WARN: no JSON parser available; $relative syntax not checked"
    fi
  done

  for relative in .codex/config.toml .codex/agents/fast.toml .codex/agents/magi.toml; do
    if command_exists python3 && python3 -c 'import tomllib' >/dev/null 2>&1; then
      if python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT_DIR/$relative" >/dev/null 2>&1; then
        info "OK: $relative TOML syntax"
      else
        info "FAIL: $relative TOML syntax"
        failures=1
      fi
    else
      info "WARN: no TOML parser available; $relative syntax not checked"
    fi
  done

  local codex_magi_description claude_magi_description
  codex_magi_description="$(sed -n '/^\[agents\.magi\]/,/^\[/s/^description = "\(.*\)"$/\1/p' "$ROOT_DIR/.codex/config.toml" | tail -n 1)"
  claude_magi_description="$(sed -n 's/^description: //p' "$ROOT_DIR/.claude/agents/magi.md")"
  if [[ -z "$codex_magi_description" || "$codex_magi_description" != "$claude_magi_description" ]]; then
    info 'FAIL: Codex and Claude MAGI descriptions differ'
    failures=1
  else
    info 'OK: Codex and Claude MAGI descriptions match'
  fi
  if /bin/bash -n "$ROOT_DIR/setup.sh"; then
    info 'OK: setup.sh syntax'
  else
    failures=1
  fi
  if [[ -f "$ROOT_DIR/bootstrap.sh" ]] && ! /bin/bash -n "$ROOT_DIR/bootstrap.sh"; then
    failures=1
  fi
  rm -rf "$defaults_dir"
  trap - RETURN
  return "$failures"
}

[[ "$(uname -s)" == "Darwin" ]] || die "this setup script supports macOS only"
if ((CHECK_ONLY)); then
  check_workspace
  exit 0
fi
configure_workspace
if ((WORKSPACE_ONLY)); then
  check_workspace
  info 'workspace configuration complete'
  exit 0
fi

if ((SKIP_INSTALL == 0)); then
  install_memory_service

  if ! command_exists codex; then
    command_exists curl || die "curl is required to install Codex CLI"
    info "installing Codex CLI with OpenAI's official standalone installer"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
    CODEX_INSTALLED_NOW=1
  else
    info "Codex CLI is already installed"
  fi
  command_exists codex || die "Codex installer completed but 'codex' is not on PATH"
  if ! command_exists claude; then
    command_exists curl || die "curl is required to install Claude Code"
    info "installing Claude Code with Anthropic's official installer"
    curl -fsSL https://claude.ai/install.sh | bash
  else
    info "Claude Code is already installed"
  fi
  command_exists claude || die "Claude Code installer completed but 'claude' is not on PATH"
fi

if ((CODEX_INSTALLED_NOW)); then
  info "Codex Computer Use requires macOS permissions in addition to Codex app rules."
  info "Open System Settings > Privacy & Security > Accessibility and enable 'Codex Computer Use'."
  info "Also enable 'Codex Computer Use' under Screen Recording (or Screen & System Audio Recording)."
  info "macOS requires you to grant these permissions manually; this script cannot enable them."
  info "If the entry is missing, install/enable the Computer Use plugin in the desktop app and start a Computer Use task, then return here."

  if [[ -t 0 && -t 1 ]]; then
    permission_reply='n'
    read -r -p "Open Accessibility settings now? [Y/n] " permission_reply || permission_reply='n'
    case "$permission_reply" in
      ''|y|Y|yes|YES)
        if open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'; then
          read -r -p "Enable the permission, then press Enter to continue setup. " permission_reply || true
        else
          info "Could not open System Settings; open the Accessibility section manually."
        fi
        ;;
      *) info "Skipped opening settings; grant the permissions manually before using Computer Use." ;;
    esac
  else
    info "Non-interactive setup: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' to configure Accessibility."
  fi

  info "After changing permissions, fully quit and reopen the Codex desktop app."
fi

CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_DIR}/config.toml"
TARGET_TABLE='[computer_use.macos.bundle_ids]'
TARGET_KEY='"com.googlecode.iterm2"'

mkdir -p "$CODEX_DIR"

# Refuse an inline bundle_ids table: appending a TOML subtable beside it would
# make the config invalid, and safely merging arbitrary inline TOML needs a parser.
if [[ -f "$CODEX_CONFIG" ]] && awk '
  /^[[:space:]]*\[computer_use\.macos\][[:space:]]*(#.*)?$/ { in_macos=1; next }
  /^[[:space:]]*\[/ { in_macos=0 }
  in_macos && /^[[:space:]]*bundle_ids[[:space:]]*=/ { found=1 }
  END { exit !found }
' "$CODEX_CONFIG"; then
  die "${CODEX_CONFIG} defines bundle_ids inline under [computer_use.macos]; merge the iTerm2 rule into that table manually"
fi

config_tmp="$(mktemp "${CODEX_DIR}/.config.toml.XXXXXX")"
cleanup() {
  [[ -z "${config_tmp:-}" ]] || rm -f "$config_tmp"
}
trap cleanup EXIT

if [[ -f "$CODEX_CONFIG" ]]; then
  awk -v target_table="$TARGET_TABLE" -v target_key="$TARGET_KEY" '
    function trim_left(s) { sub(/^[[:space:]]+/, "", s); return s }
    BEGIN { in_target=0; table_seen=0; key_seen=0 }
    {
      clean=trim_left($0)
      if (clean ~ /^\[/) {
        if (in_target && !key_seen) {
          print target_key " = \"allow\""
          key_seen=1
        }
        in_target=(clean ~ /^\[computer_use\.macos\.bundle_ids\][[:space:]]*(#.*)?$/)
        if (in_target) table_seen=1
        print
        next
      }
      if (in_target && clean ~ /^"com\.googlecode\.iterm2"[[:space:]]*=/) {
        print target_key " = \"allow\""
        key_seen=1
        next
      }
      print
    }
    END {
      if (in_target && !key_seen) {
        print target_key " = \"allow\""
        key_seen=1
      }
      if (!table_seen) {
        if (NR > 0) print ""
        print target_table
        print target_key " = \"allow\""
      }
    }
  ' "$CODEX_CONFIG" > "$config_tmp"

  chmod "$(stat -f '%Lp' "$CODEX_CONFIG")" "$config_tmp"
else
  {
    printf '%s\n' "$TARGET_TABLE"
    printf '%s = "allow"\n' "$TARGET_KEY"
  } > "$config_tmp"
  chmod 600 "$config_tmp"
fi

if ! cmp -s "$config_tmp" "$CODEX_CONFIG" 2>/dev/null; then
  mv "$config_tmp" "$CODEX_CONFIG"
  config_tmp=''
  info "allowed Codex Computer Use access to iTerm2 in ${CODEX_CONFIG}"
else
  info "Codex Computer Use access to iTerm2 is already configured"
fi

check_workspace
info "setup complete; run 'codex' or 'claude' to sign in and start using either tool"
