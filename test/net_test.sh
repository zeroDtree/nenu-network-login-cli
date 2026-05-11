#!/usr/bin/env bash
#
# Quick outbound connectivity check (same semantics as ../auto_login.sh):
# online iff GET returns HTTP 204 for any probe URL (Android-style captive check).
#
# Usage:
#   ./net_test.sh           # print each probe, exit 0 if online
#   NET_TEST_QUIET=1 ./net_test.sh   # exit code only (no stdout)
#
# Environment (optional):
#   CONNECTIVITY_URL_1   First URL (default: Google generate_204). Empty skips.
#   CONNECTIVITY_URL_2   Second URL (default: Huawei generate_204). Empty skips.
#   CONNECT_TIMEOUT      Seconds for connect / upper-bound (default: 3)
#   NET_TEST_QUIET       Non-empty: suppress normal output (still prints errors to stderr)
#
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONNECTIVITY_URL_1="${CONNECTIVITY_URL_1:-http://connectivitycheck.gstatic.com/generate_204}"
CONNECTIVITY_URL_2="${CONNECTIVITY_URL_2:-http://connectivitycheck.platform.hicloud.com/generate_204}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-3}"

CONNECTIVITY_URLS=()
[[ -n "${CONNECTIVITY_URL_1}" ]] && CONNECTIVITY_URLS+=("${CONNECTIVITY_URL_1}")
[[ -n "${CONNECTIVITY_URL_2}" ]] && CONNECTIVITY_URLS+=("${CONNECTIVITY_URL_2}")

log_err() {
	echo "$*" >&2
}

http_code_for() {
	local url="$1"
	local max_time=$((CONNECT_TIMEOUT + 5))
	local code

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
	echo "${code}"
}

main() {
	if ! command -v curl >/dev/null 2>&1; then
		log_err "error: curl is required"
		exit 2
	fi
	if [[ "${#CONNECTIVITY_URLS[@]}" -eq 0 ]]; then
		log_err "error: need at least one non-empty CONNECTIVITY_URL_1 or CONNECTIVITY_URL_2"
		exit 2
	fi

	local url code any_online=0

	for url in "${CONNECTIVITY_URLS[@]}"; do
		code="$(http_code_for "$url")"
		if [[ -z "${NET_TEST_QUIET:-}" ]]; then
			printf '%s -> %s\n' "$url" "${code:-fail}"
		fi
		if [[ "${code}" == "204" ]]; then
			any_online=1
		fi
	done

	if [[ "${any_online}" -eq 1 ]]; then
		[[ -z "${NET_TEST_QUIET:-}" ]] && echo "online (got HTTP 204 from at least one probe)"
		exit 0
	fi

	[[ -z "${NET_TEST_QUIET:-}" ]] && echo "offline (no probe returned HTTP 204)"
	exit 1
}

main "$@"
