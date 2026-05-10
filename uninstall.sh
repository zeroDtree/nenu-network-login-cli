#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# uninstall.sh — removes srun-auto-login systemd unit installed by install.sh
#
#   · With --systemd: systemctl disable --now (stop + disable), removes unit under
#     SYSTEMD_UNIT_DIR, then daemon-reload
#
# Examples
#   sudo ./uninstall.sh --systemd
#   ./uninstall.sh -n --systemd              # dry-run
#
# Environment
#   DESTDIR, SYSTEMD_UNIT_DIR
# -----------------------------------------------------------------------------

set -euo pipefail

DESTDIR="${DESTDIR:-}"
SYSTEMD_UNIT_DIR="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
UNIT_NAME="srun-auto-login.service"

WITH_SYSTEMD=0
DRY_RUN=0

die() {
	echo "uninstall.sh: error: $*" >&2
	exit 1
}

log() {
	echo "[uninstall] $*"
}

usage() {
	cat >&2 <<'EOF'
Usage: uninstall.sh [options]

Options:
  --systemd         Remove unit; stop/disable with systemctl disable --now (required)
  --destdir=PATH    Staging root if you staged an install (env DESTDIR)
  -n, --dry-run     Print actions only
  -h, --help        Show this help

Environment:
  DESTDIR, SYSTEMD_UNIT_DIR

Note: Config files in the repo or /etc are not removed. Legacy
$PREFIX/sbin/srun-auto-login from older installs is not removed; delete it
manually if present.
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
		-n | --dry-run)
			DRY_RUN=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		--prefix=*)
			die "unsupported: remove --prefix; reinstall with install.sh --systemd if you moved the repo"
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

rm_path() {
	local path="$1"
	if [[ "$DRY_RUN" -eq 1 ]]; then
		log "would rm -f '$path'"
		return
	fi
	if [[ -e "$path" ]]; then
		rm -f "$path"
		log "removed: $path"
	else
		log "skip (not found): $path"
	fi
}

parse_args "$@"
[[ "$WITH_SYSTEMD" -eq 1 ]] || die "use --systemd"

INSTALL_UNIT="$(path_join "$DESTDIR" "$(path_join "$SYSTEMD_UNIT_DIR" "$UNIT_NAME")")"

if [[ "$DRY_RUN" -eq 0 ]]; then
	[[ "$EUID" -eq 0 || -n "$DESTDIR" ]] || die "--systemd needs root (or set DESTDIR for staged tree)"
fi

if [[ "$DRY_RUN" -eq 0 && -z "$DESTDIR" ]] && command -v systemctl >/dev/null 2>&1; then
	systemctl disable --now "$UNIT_NAME" 2>/dev/null || true
	log "stopped and disabled: $UNIT_NAME (systemctl disable --now; if it was installed)"
fi

rm_path "$INSTALL_UNIT"

if [[ "$DRY_RUN" -eq 0 && -z "$DESTDIR" ]] && command -v systemctl >/dev/null 2>&1; then
	systemctl daemon-reload 2>/dev/null || true
	log "systemctl daemon-reload"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
	log "done."
fi
