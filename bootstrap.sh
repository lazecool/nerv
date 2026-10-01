#!/usr/bin/env bash

# Bootstrap the macOS development workspace.
# Every installation/configuration step is guarded so this script is safe to rerun.

set -Eeuo pipefail

# Keep long Homebrew downloads/builds visibly alive. Homebrew's curl progress
# bars are intentionally suppressed, so verbose mode emits periodic dots.
export HOMEBREW_VERBOSE=1
export HOMEBREW_VERBOSE_USING_DOTS=1

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SKIP_INSTALL=0
OMZ_DIR="${ZSH:-${HOME}/.oh-my-zsh}"
ITERM_PROFILE_DIR="${HOME}/Library/Application Support/iTerm2/DynamicProfiles"
ITERM_PROFILE_NAME="nerv-d2coding.json"
ITERM_PROFILE_GUID="8B2F40C3-0A0B-4D38-9D67-3D60E5A0E3A1"

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

Install and configure the macOS workspace:
  Homebrew, Python, Node.js, tmux, iTerm2, D2 Coding, Oh My Zsh,
  and af-magic. Run ./setup.sh afterward to install and configure Codex
  and Claude Code for this workspace.

Options:
  --skip-install  Skip package installation and only apply shell/iTerm2 config.
  -h, --help      Show this help.
EOF
}

die() {
  printf 'bootstrap: error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'bootstrap: %s\n' "$*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

brew_is_installed() {
  brew list --formula "$1" >/dev/null 2>&1 || brew list --cask "$1" >/dev/null 2>&1
}

install_brew_formula() {
  local package="$1"
  if brew_is_installed "${package}"; then
    info "${package} is already installed"
  else
    info "installing ${package}"
    brew install -y "${package}"
  fi
}

install_brew_cask() {
  local package="$1"
  if brew_is_installed "${package}"; then
    info "${package} is already installed"
  else
    info "installing ${package}"
    brew install --cask -y "${package}"
  fi
}

ensure_homebrew() {
  if command_exists brew; then
    return 0
  fi

  command_exists curl || die "curl is required to install Homebrew"
  info "installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  command_exists brew || die "Homebrew was installed but brew is not on PATH"
}

ensure_brew_shellenv() {
  local brew_path shellenv_line zprofile
  brew_path="$(command -v brew)"
  shellenv_line="eval \"\$(${brew_path} shellenv)\""

  for zprofile in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    touch "${zprofile}"
    if ! grep -Fqx "${shellenv_line}" "${zprofile}"; then
      printf '\n# Homebrew\n%s\n' "${shellenv_line}" >> "${zprofile}"
      info "added Homebrew to ${zprofile}"
    fi
  done
}

ensure_oh_my_zsh() {
  if [[ ! -d "${OMZ_DIR}" ]]; then
    command_exists curl || die "curl is required to install Oh My Zsh"
    info "installing Oh My Zsh"
    RUNZSH=no KEEP_ZSHRC=yes ZSH="${OMZ_DIR}" \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  else
    info "Oh My Zsh is already installed"
  fi

  [[ -f "${OMZ_DIR}/themes/af-magic.zsh-theme" ]] || die "Oh My Zsh does not contain the af-magic theme"
}

set_zsh_theme() {
  local zshrc="${HOME}/.zshrc"
  touch "${zshrc}"

  if grep -Eq '^[[:space:]]*ZSH_THEME=' "${zshrc}"; then
    sed -i '' 's/^[[:space:]]*ZSH_THEME=.*/ZSH_THEME="af-magic"/' "${zshrc}"
  else
    printf '\n# Oh My Zsh theme\nZSH_THEME="af-magic"\n' >> "${zshrc}"
  fi
  info "configured Oh My Zsh theme: af-magic"
}

configure_iterm2_font() {
  local profile_file
  mkdir -p "${ITERM_PROFILE_DIR}"
  profile_file="${ITERM_PROFILE_DIR}/${ITERM_PROFILE_NAME}"

  if [[ ! -f "${profile_file}" ]] || ! grep -Fq '"Normal Font": "D2Coding 14"' "${profile_file}"; then
    cat > "${profile_file}" <<EOF
{
  "Profiles": [
    {
      "Guid": "${ITERM_PROFILE_GUID}",
      "Name": "nerv D2Coding",
      "Normal Font": "D2Coding 14",
      "Non-ASCII Font": "D2Coding 14",
      "Use Non-ASCII Font": true
    }
  ]
}
EOF
    info "configured iTerm2 font: D2Coding 14"
  else
    info "iTerm2 D2Coding profile is already configured"
  fi

  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "${ITERM_PROFILE_GUID}"
}

while (($# > 0)); do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || die "this bootstrap script supports macOS only"

if ((SKIP_INSTALL == 0)); then
  ensure_homebrew
  ensure_brew_shellenv
  install_brew_formula python
  install_brew_formula node
  install_brew_formula tmux
  install_brew_cask iterm2
  install_brew_cask font-d2coding
fi

ensure_oh_my_zsh
set_zsh_theme
configure_iterm2_font

info "workspace bootstrap complete"
