#!/usr/bin/env bash
# GHA helper: write SSH key + config so publish-*.sh can rsync to VPS beta.
# Env (from secrets):
#   SSH_KEY              required (PEM / OpenSSH private key)
#   XIAOHE_VPS_SSH       optional, default ubuntu@159.75.28.184 (public IP; not Tailscale)
#   XIAOHE_VPS_SSH_PORT  optional, default 22022
#
# Exports XIAOHE_VPS_SSH as user@IP (bare IP), not a Host alias — self-hosted
# runners often fail to resolve aliases like xiaohe-vps when ssh ignores config.
set -euo pipefail

[[ -n "${SSH_KEY:-}" ]] || { echo "SSH_KEY empty" >&2; exit 1; }

HOST_SPEC="${XIAOHE_VPS_SSH:-}"
_DEFAULT_VPS_IP="${XIAOHE_VPS_PUBLIC_IP:-}"
if [[ -z "$_DEFAULT_VPS_IP" ]]; then
  _XH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _DEFAULT_VPS_IP="$("${PYTHON:-python3}" "$_XH_DIR/../release/read_setting.py" infra.vps.public_ip 2>/dev/null || true)"
fi
_DEFAULT_VPS_IP="${_DEFAULT_VPS_IP:-159.75.28.184}"
HOST_SPEC="${HOST_SPEC:-ubuntu@${_DEFAULT_VPS_IP}}"
PORT="${XIAOHE_VPS_SSH_PORT:-22022}"

if [[ "$HOST_SPEC" == *@* ]]; then
  USER_PART="${HOST_SPEC%%@*}"
  HOST_PART="${HOST_SPEC#*@}"
else
  USER_PART="ubuntu"
  HOST_PART="$HOST_SPEC"
fi
# strip accidental :port from host
if [[ "$HOST_PART" == *:* ]]; then
  PORT="${HOST_PART##*:}"
  HOST_PART="${HOST_PART%:*}"
fi

# CI must dial a bare IP (Tailscale / Host aliases break on some runners).
case "$HOST_PART" in
  *.ts.net|ts-*|xiaohe-vps)
    echo "warn: XIAOHE_VPS_SSH host='$HOST_PART' is not a bare IP; using ${_DEFAULT_VPS_IP}" >&2
    HOST_PART="${_DEFAULT_VPS_IP}"
    ;;
esac
if [[ ! "$HOST_PART" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && [[ ! "$HOST_PART" =~ ^[0-9a-fA-F:]+$ ]]; then
  echo "warn: XIAOHE_VPS_SSH host='$HOST_PART' is not an IP; prefer user@PUBLIC_IP in secrets" >&2
fi

TARGET_SPEC="${USER_PART}@${HOST_PART}"

# On Windows self-hosted, prefer Git ssh (reads $HOME/.ssh).
is_windows=0
case "${OS:-}/$(uname -s 2>/dev/null || true)" in
  Windows_NT/*|*/MINGW*|*/MSYS*|*/CYGWIN*) is_windows=1 ;;
esac

if [[ "$is_windows" -eq 1 ]]; then
  for git_ssh_dir in \
    "/c/Program Files/Git/usr/bin" \
    "/mingw64/bin" \
    "/usr/bin"
  do
    if [[ -x "${git_ssh_dir}/ssh.exe" || -x "${git_ssh_dir}/ssh" ]]; then
      export PATH="${git_ssh_dir}:${PATH}"
      if [[ -n "${GITHUB_PATH:-}" ]]; then
        # Windows GITHUB_PATH wants native path separators.
        if [[ "$git_ssh_dir" =~ ^/([a-zA-Z])/(.*)$ ]]; then
          drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
          echo "${drive}:\\${BASH_REMATCH[2]//\//\\}" >> "$GITHUB_PATH"
        else
          echo "${git_ssh_dir}" >> "$GITHUB_PATH"
        fi
      fi
      break
    fi
  done
fi

to_win_path() {
  local p="$1"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    local drive
    drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
    printf '%s:/%s' "$drive" "${BASH_REMATCH[2]}"
  else
    printf '%s' "$p"
  fi
}

write_ssh_home() {
  local ssh_home="${1//\\//}"
  local id_style="${2:-unix}" # unix | windows
  [[ -n "$ssh_home" ]] || return 0
  mkdir -p "${ssh_home}/.ssh"
  chmod 700 "${ssh_home}/.ssh" 2>/dev/null || true
  local key_file="${ssh_home}/.ssh/xiaohe_vps"
  printf '%s\n' "$SSH_KEY" > "$key_file"
  chmod 600 "$key_file" 2>/dev/null || true

  local id_path="$key_file"
  if [[ "$id_style" == windows ]]; then
    if [[ "$key_file" =~ ^[A-Za-z]:/ ]]; then
      id_path="$key_file"
    else
      id_path="$(to_win_path "$key_file")"
    fi
  fi

  # Only Host=<IP> — never rely on xiaohe-vps aliases in CI.
  cat > "${ssh_home}/.ssh/config" <<EOF
Host ${HOST_PART}
  HostName ${HOST_PART}
  Port ${PORT}
  User ${USER_PART}
  IdentityFile ${id_path}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
  chmod 600 "${ssh_home}/.ssh/config" 2>/dev/null || true
  ssh-keyscan -p "$PORT" -H "$HOST_PART" >> "${ssh_home}/.ssh/known_hosts" 2>/dev/null || true
}

# Runner-scoped ssh home — NEVER the operator's real ~/.ssh. Self-hosted
# runners run CI jobs as the operator; writing $HOME/.ssh here would clobber
# their Host aliases on every publish. $RUNNER_TEMP is per-job and reclaimed.
if [[ -n "${RUNNER_TEMP:-}" ]]; then
  SSH_HOME_BASE="${RUNNER_TEMP}"
else
  SSH_HOME_BASE="${XIAOHE_SSH_HOME:-$HOME}"
fi
SSH_HOME="${SSH_HOME_BASE}/.ssh"
write_ssh_home "$SSH_HOME_BASE" unix

if [[ "$is_windows" -eq 1 && -n "${USERPROFILE:-}" ]]; then
  write_ssh_home "${USERPROFILE}" windows
fi

# Always export user@IP — never a Host alias. Also export the runner-scoped
# SSH home/key/port so later steps (publish-vps.sh, scp staging) connect with
# `ssh -F "$XIAOHE_SSH_HOME/config"` without ever touching ~/.ssh.
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "XIAOHE_VPS_SSH=${TARGET_SPEC}" >> "$GITHUB_ENV"
  echo "XIAOHE_VPS_SSH_PORT=${PORT}" >> "$GITHUB_ENV"
  echo "XIAOHE_SSH_HOME=${SSH_HOME}" >> "$GITHUB_ENV"
  echo "XIAOHE_SSH_KEY=${SSH_HOME}/xiaohe_vps" >> "$GITHUB_ENV"
fi
export XIAOHE_VPS_SSH="$TARGET_SPEC"
export XIAOHE_SSH_HOME="$SSH_HOME"
export XIAOHE_SSH_KEY="${SSH_HOME}/xiaohe_vps"

# Refuse non-IP in CI (secrets must not stay as xiaohe-vps).
if [[ ! "$HOST_PART" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && [[ ! "$HOST_PART" =~ ^[0-9a-fA-F:]+$ ]]; then
  echo "ERROR: CI VPS host must be bare IP (got '$HOST_PART'). Set secret XIAOHE_VPS_SSH=ubuntu@159.75.28.184" >&2
  exit 1
fi

echo "Prepared SSH → ${TARGET_SPEC}:${PORT} (config Host ${HOST_PART})"
echo "    HOME=$HOME ssh=$(command -v ssh || true)"

# Check the config we actually wrote. On self-hosted runners $RUNNER_TEMP is
# set, so the file lives outside ~/.ssh — probing the default config would fail
# on any machine that has no prior ~/.ssh/config (a fresh runner).
if ! ssh -F "${SSH_HOME}/config" -G "$HOST_PART" 2>/dev/null | grep -qiE '^hostname[[:space:]]'; then
  echo "ERROR: ssh does not load config for Host ${HOST_PART}" >&2
  ls -la "${SSH_HOME}" 2>&1 >&2 || true
  ssh -V 2>&1 >&2 || true
  ssh -F "${SSH_HOME}/config" -G "$HOST_PART" 2>&1 | head -30 >&2 || true
  exit 1
fi
