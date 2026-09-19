#!/usr/bin/env bash
# bootcrew addons: install Homebrew (Homebrew on Linux / "linuxbrew") plus a
# curated set of daily-driver CLI tools into every image.
#
# Layout rationale:
#   bootc-rootfs.sh replaces /home with a symlink to /var/home, so the brew
#   prefix /home/linuxbrew/.linuxbrew physically lives at /var/home/linuxbrew.
#   bootc seeds image content in /var onto the *mutable* var partition on the
#   first deployment and leaves it untouched on later upgrades/rollbacks, which
#   is exactly what a self-updating package manager wants.
#
# The brew user/group is declared via sysusers.d and the home dir via
# tmpfiles.d so both stay reproducible across updates and bootc container lint
# stays quiet.
set -euo pipefail

BREW_USER="linuxbrew"
BREW_GROUP="linuxbrew"
BREW_USER_HOME="/var/home/linuxbrew"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_PACKAGES=(
  eza
  bat
  ripgrep
  fd
  fzf
  zoxide
  btop
  tmux
  fastfetch
  starship
  gh
  git-lfs
  jq
)

# bootc-rootfs.sh deletes /var, and some distros keep their TLS trust store
# there (openSUSE: /var/lib/ca-certificates/ca-bundle.pem). Make sure a real
# CA bundle exists before any https fetch, rebuilding it from the distro
# toolchain if the common paths were wiped or left dangling.
ensure_ca_bundle() {
  for bundle in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ca-certificates/extracted/ca-certificates.crt \
    /var/lib/ca-certificates/ca-bundle.pem; do
    if [[ -s "${bundle}" ]]; then
      return 0
    fi
  done
  if command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates 2>/dev/null && return 0
  fi
  if command -v update-ca-trust >/dev/null 2>&1; then
    update-ca-trust 2>/dev/null && return 0
  fi
  echo "::error::No TLS CA bundle available; Homebrew installation needs https." >&2
  echo "::error::The CA store may have lived in /var and been cleared by bootc-rootfs.sh." >&2
  exit 1
}

# Bookkeeping so the user/dirs are reproducible after deploy (and so
# `bootc container lint` doesn't flag them).
mkdir -p /usr/lib/sysusers.d /usr/lib/tmpfiles.d

printf 'u %s - "Homebrew on Linux" %s /bin/bash\n' \
  "${BREW_USER}" "${BREW_USER_HOME}" \
  > /usr/lib/sysusers.d/linuxbrew.conf

printf 'd %s 0755 %s %s -\n' \
  "${BREW_USER_HOME}" "${BREW_USER}" "${BREW_GROUP}" \
  > /usr/lib/tmpfiles.d/linuxbrew.conf

# Realize the user now (idempotent) so the brew tree below can be owned by its
# eventual runtime owner instead of root.
systemd-sysusers

# /home is a symlink to /var/home after bootc-rootfs.sh; materialize the real
# directory and hand it to the brew user so the installer needs no sudo.
install -d -m 0755 \
  -o "${BREW_USER}" -g "${BREW_GROUP}" "${BREW_USER_HOME}"

run_as_brew() {
  local cmd="$1"
  # Prepend the brew prefix to PATH: these shells are non-login/non-interactive
  # so /etc/profile.d is never sourced and bare `brew` would not resolve.
  local brew_env
  brew_env="export PATH=${BREW_PREFIX}/bin:${BREW_PREFIX}/sbin:\$PATH"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "${BREW_USER}" -- /bin/bash -c "${brew_env}; ${cmd}"
  else
    su -s /bin/bash "${BREW_USER}" -c "${brew_env}; ${cmd}"
  fi
}

if [[ ! -x "${BREW_PREFIX}/bin/brew" ]]; then
  ensure_ca_bundle
  curl -fsSL "${BREW_INSTALLER}" -o /tmp/homebrew-install.sh
  run_as_brew "NONINTERACTIVE=1 CI=1 /bin/bash /tmp/homebrew-install.sh"
  rm -f /tmp/homebrew-install.sh
fi

# Make brew available to every login shell. Guarded so root/anonymous logins
# (e.g. the bcvk boot tests) don't get "Don't run Homebrew as root" noise.
cat > /etc/profile.d/homebrew.sh <<'EOF'
# bootcrew: Homebrew (installed under /home/linuxbrew/.linuxbrew)
command -v brew >/dev/null 2>&1 || {
  [ -x /home/linuxbrew/.linuxbrew/bin/brew ] &&
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)"
}
EOF

# Curated daily-driver toolbox, installed through brew itself so it is kept
# fresh and consistent across every distro this repo builds.
if [[ "${#BREW_PACKAGES[@]}" -gt 0 ]]; then
  run_as_brew "
    set -euo pipefail
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1
    NONINTERACTIVE=1 brew install ${BREW_PACKAGES[*]}
  "
fi

# Shrink the image: drop cached bottles/downloads and pruned old versions.
run_as_brew "
  set -euo pipefail
  export HOMEBREW_NO_AUTO_UPDATE=1
  NONINTERACTIVE=1 brew cleanup --prune=all -s || true
  NONINTERACTIVE=1 brew autoremove || true
"
rm -rf "${BREW_USER_HOME}/.cache/Homebrew" 2>/dev/null || true

run_as_brew "export HOMEBREW_NO_AUTO_UPDATE=1 && NONINTERACTIVE=1 ${BREW_PREFIX}/bin/brew --version"