#!/usr/bin/env bash
#
# Periodically checks outbound connectivity; on failure runs `srun login`.
# Intended to run under systemd as a long-lived service.
#
# Requires: curl (install the curl package if missing).
#
# Environment (optional):
#   SRUN_BIN             Path to srun binary (default: this script's directory +
#                        target/release/srun, i.e. `cargo build --release` output)
#   SRUN_CONFIG          Config for `srun login -c` (default: this script's directory +
#                        config.json). Optionally set Environment=SRUN_* in the unit file.
#
#   CONNECTIVITY_URL_1   First HTTP probe URL (default: Google generate_204). Empty skips.
#   CONNECTIVITY_URL_2   Second HTTP probe URL (default: Huawei generate_204). Empty skips.
#                        Online iff GET returns HTTP 204 for any listed URL (Android-style
#                        captive-portal check; avoids portal 200/302).
#
#   CONNECT_TIMEOUT      Probe connect / upper-bound timeout in seconds (default: 3)
#
#   OK_INTERVAL          Sleep while online, seconds (default: 120)
#   RETRY_INTERVAL       Sleep after a login attempt (success or failure), seconds (default: 30)
#
# Manual install: sudo ./install.sh --systemd --enable
# (ExecStart points at this file; defaults: ./target/release/srun, ./config.json)
#
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRUN_BIN="${SRUN_BIN:-$SCRIPT_DIR/target/release/srun}"
SRUN_CONFIG="${SRUN_CONFIG:-$SCRIPT_DIR/config.json}"

CONNECTIVITY_URL_1="${CONNECTIVITY_URL_1:-http://connectivitycheck.gstatic.com/generate_204}"
CONNECTIVITY_URL_2="${CONNECTIVITY_URL_2:-http://connectivitycheck.platform.hicloud.com/generate_204}"

CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-3}"
OK_INTERVAL="${OK_INTERVAL:-120}"
RETRY_INTERVAL="${RETRY_INTERVAL:-30}"

CONNECTIVITY_URLS=()
[[ -n "${CONNECTIVITY_URL_1}" ]] && CONNECTIVITY_URLS+=("${CONNECTIVITY_URL_1}")
[[ -n "${CONNECTIVITY_URL_2}" ]] && CONNECTIVITY_URLS+=("${CONNECTIVITY_URL_2}")

is_online() {
	local max_time=$((CONNECT_TIMEOUT + 5))
	local url code

	for url in "${CONNECTIVITY_URLS[@]}"; do
		code="$(
			curl -sS \
				--connect-timeout "${CONNECT_TIMEOUT}" \
				--max-time "${max_time}" \
				-o /dev/null \
				-w '%{http_code}' \
				"$url" 2>/dev/null || true
		)"
		code="${code//$'\r'/}"
		code="${code//$'\n'/}"
		if [[ "${code}" == "204" ]]; then
			return 0
		fi
	done
	return 1
}

log() {
	echo "[$(date -Iseconds)] $*"
}

if [[ ! -x "$SRUN_BIN" ]]; then
	log "error: SRUN_BIN is not executable: $SRUN_BIN"
	exit 1
fi
if [[ ! -r "$SRUN_CONFIG" ]]; then
	log "error: SRUN_CONFIG is not readable: $SRUN_CONFIG"
	exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
	log "error: curl is required for connectivity probe (install curl package)"
	exit 1
fi
if [[ "${#CONNECTIVITY_URLS[@]}" -eq 0 ]]; then
	log "error: need at least one non-empty CONNECTIVITY_URL_1 or CONNECTIVITY_URL_2"
	exit 1
fi

log "start: probe connectivity (curl, expect HTTP 204): ${CONNECTIVITY_URLS[*]}, config ${SRUN_CONFIG}"

while true; do
	if is_online; then
		sleep "${OK_INTERVAL}"
		continue
	fi

	log "offline: running login"
	if "${SRUN_BIN}" login -c "${SRUN_CONFIG}"; then
		log "login: command exited 0"
	else
		log "login: command failed (exit $?)"
	fi
	sleep "${RETRY_INTERVAL}"
done
