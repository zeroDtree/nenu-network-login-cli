#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# install.sh — installs systemd unit for srun-auto-login.
#
# ExecStart points at THIS repository's auto_login.sh (not copied elsewhere).
# SRUN_BIN / SRUN_CONFIG are left unset in the unit so auto_login.sh defaults
# use SCRIPT_DIR (repo root): target/release/srun and config.json.
#
# Examples
#   sudo ./install.sh --systemd --enable
#   ./install.sh -n --systemd              # dry-run
#
# Environment
#   DESTDIR=/tmp/stage     Optional staging root (unit path under DESTDIR).
#   SYSTEMD_UNIT_DIR=...   Default /etc/systemd/system (also prefixed by DESTDIR).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SRC="${SCRIPT_DIR}/auto_login.sh"
UNIT_SRC="${SCRIPT_DIR}/contrib/systemd/srun-auto-login.service"

DESTDIR="${DESTDIR:-}"
SYSTEMD_UNIT_DIR="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
UNIT_NAME="srun-auto-login.service"

WITH_SYSTEMD=0
ENABLE_SERVICE=0
DRY_RUN=0

die() {
	echo "install.sh: error: $*" >&2
	exit 1
}

log() {
	echo "[install] $*"
}

require_file() {
	[[ -f "$1" ]] || die "missing file: $1"
}

ensure_parent() {
	local f="$1"
	local d
	d="$(dirname "$f")"
	if [[ "$DRY_RUN" -eq 1 ]]; then
		log "would mkdir -p '$d'"
		return
	fi
	mkdir -p "$d"
}

usage() {
	cat >&2 <<'EOF'
Usage: install.sh [options]

Options:
  --systemd         Install systemd unit under SYSTEMD_UNIT_DIR (required)
  --enable          Enable unit and start now: systemctl enable --now (needs root + systemctl)
  --destdir=PATH    Staging root for packaging (default empty; env DESTDIR)
  -n, --dry-run     Print actions only, do not write files
  -h, --help        Show this help

Environment:
  DESTDIR, SYSTEMD_UNIT_DIR

The unit's ExecStart is set to this repo's auto_login.sh. Build srun with
`cargo build --release` and keep config.json (or set SRUN_* in the unit).
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--destdir=*)
			DESTDIR="${1#*=}"
			;;
		--systemd)
			WITH_SYSTEMD=1
			;;
		--enable)
			ENABLE_SERVICE=1
			;;
		-n | --dry-run)
			DRY_RUN=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		--prefix=*)
			die "unsupported: remove --prefix; ExecStart uses this repo's auto_login.sh"
			;;
		*)
			die "unknown option: $1 (try --help)"
			;;
		esac
		shift
	done
}

path_join() {
	local root="${1%/}"
	local sub="${2#/}"
	echo "${root}/${sub}"
}

require_file "$SCRIPT_SRC"
parse_args "$@"
[[ "$WITH_SYSTEMD" -eq 1 ]] || die "use --systemd"

AUTO_LOGIN_ABS="${SCRIPT_DIR}/auto_login.sh"

if [[ "$DRY_RUN" -eq 0 ]]; then
	[[ -x "$AUTO_LOGIN_ABS" ]] || chmod +x "$AUTO_LOGIN_ABS"
fi

require_file "$UNIT_SRC"
if [[ "$DRY_RUN" -eq 0 ]]; then
	[[ "$EUID" -eq 0 || -n "$DESTDIR" ]] || die "--systemd needs root (or set DESTDIR for packaging)"
fi

INSTALL_UNIT="$(path_join "$DESTDIR" "$(path_join "$SYSTEMD_UNIT_DIR" "$UNIT_NAME")")"

ensure_parent "$INSTALL_UNIT"

if [[ "$DRY_RUN" -eq 1 ]]; then
	log "systemd unit: ${UNIT_NAME}"
	log "    install path: $INSTALL_UNIT"
	log "    unit file:"
	log "      ExecStart=${AUTO_LOGIN_ABS}"
else
	TMP_UNIT="$(mktemp)"
	trap 'rm -f "$TMP_UNIT"' EXIT
	awk -v p="$AUTO_LOGIN_ABS" '/^ExecStart=/ {
		print "ExecStart=" p
		next
	}
	{ print }' "$UNIT_SRC" >"$TMP_UNIT"
	install -m644 "$TMP_UNIT" "$INSTALL_UNIT"
	rm -f "$TMP_UNIT"
	trap - EXIT
	log "installed unit: $INSTALL_UNIT"
	log "ExecStart=${AUTO_LOGIN_ABS}"
fi

if [[ "$DRY_RUN" -eq 0 && -z "$DESTDIR" ]]; then
	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload
		log "systemctl daemon-reload"
	else
		log "warning: systemctl not found; reload manually after boot"
	fi
fi

if [[ "$ENABLE_SERVICE" -eq 1 ]]; then
	[[ "$DRY_RUN" -eq 1 ]] && die "--enable cannot be used with --dry-run"
	[[ -z "$DESTDIR" ]] || die "--enable with DESTDIR is not supported"
	command -v systemctl >/dev/null 2>&1 || die "systemctl required for --enable"
	systemctl enable --now "$UNIT_NAME"
	log "enabled and started: $UNIT_NAME (systemctl enable --now)"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
	log "done. Defaults: ${SCRIPT_DIR}/target/release/srun + ${SCRIPT_DIR}/config.json (override via unit Environment=SRUN_* if needed)."
	log "Ensure the repo stays at this path, or reinstall after moving the clone."
fi
