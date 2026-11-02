#!/usr/bin/env bash
# HostCheck - simple UP/DOWN host reachability check
# Usage: hostcheck <IP-or-hostname> [port]

export LC_ALL=C

PING_COUNT=3
PING_WAIT=${HC_PING_WAIT:-5}
TCP_TIMEOUT=${HC_TCP_TIMEOUT:-10}
RETRY_DELAY=${HC_RETRY_DELAY:-5}

usage() {
    echo "Usage: $0 <IP-or-hostname> [port]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

TARGET=$1
PORT=${2:-22}

if ! [[ $PORT =~ ^[0-9]{1,5}$ ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
    echo "Invalid port: $PORT" >&2
    exit 2
fi
PORT=$((10#$PORT))

is_ipv4() {
    [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local octet
    for octet in "${BASH_REMATCH[@]:1}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

if is_ipv4 "$TARGET"; then
    KIND=ip
elif [[ $TARGET =~ ^[0-9.]+$ ]] ||
     ! [[ $TARGET =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,251}[A-Za-z0-9])?$ ]] ||
     [[ $TARGET == *..* ]]; then
    echo "Invalid hostname or IP address: $TARGET" >&2
    exit 2
else
    KIND=hostname
fi

# Reports are private and kept outside the project directory.
CACHE_BASE=${XDG_CACHE_HOME:-"$HOME/.cache"}
REPORT_DIR="$CACHE_BASE/hostcheck/reports"
mkdir -p "$REPORT_DIR" || {
    echo "Warning: cannot create report directory; continuing without a report." >&2
    REPORT_DIR=""
}
if [[ -n $REPORT_DIR ]]; then
    chmod 700 "$REPORT_DIR" 2>/dev/null || true
    find "$REPORT_DIR" -maxdepth 1 -type f -name 'host_check_*.txt' -mmin +10080 -delete 2>/dev/null || true
    SAFE=$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '_')
    REPORT="$REPORT_DIR/host_check_${SAFE}_$(date +%Y%m%d_%H%M%S)_$$.txt"
    (umask 077; : > "$REPORT") 2>/dev/null || REPORT=""
else
    REPORT=""
fi

COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then COLOR=1; fi
if (( COLOR )); then
    R=$'\033[0m'; B=$'\033[1m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; C=$'\033[1;36m'
else
    R=''; B=''; G=''; Y=''; C=''
fi

say() {
    printf '%s\n' "$*"
    if [[ -n $REPORT ]]; then printf '%s\n' "$*" >> "$REPORT" || REPORT=""; fi
}
section() { say ""; say "${B}[$*]${R}"; }
have() { command -v "$1" >/dev/null 2>&1; }

TMP=$(mktemp) || { echo "Error: mktemp is required." >&2; exit 4; }
trap 'rm -f "$TMP"' EXIT

UP=0
REASONS=()
ADDR=""

say "${C}HOSTCHECK${R}"
say "Target : $TARGET"
say "Port   : $PORT"
say "Time   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
[[ -n $REPORT ]] && say "Report : $REPORT"

# Resolve hostname.
section "DNS"
if [[ $KIND == ip ]]; then
    ADDR=$TARGET
    say "IP address supplied; DNS lookup not needed."
elif have getent; then
    getent ahosts "$TARGET" >"$TMP" 2>&1
    rc=$?
    ADDR=$(awk 'NF {print $1; exit}' "$TMP")
    if [[ $rc -eq 0 && -n $ADDR ]]; then
        say "Resolved: $ADDR"
    else
        say "Could not resolve hostname."
    fi
else
    say "getent unavailable; cannot resolve hostname."
fi

if [[ -n $ADDR ]]; then
    # Ping the target. Any reply is enough to mark the host UP.
    section "PING"
    if have ping; then
        ping -n -c "$PING_COUNT" -W "$PING_WAIT" "$ADDR" >"$TMP" 2>&1
        rc=$?
        cat "$TMP" | while IFS= read -r line; do say "$line"; done
        if grep -qE '[1-9][0-9]* (packets )?received' "$TMP"; then
            UP=1
            REASONS+=("ping replied")
            say "Ping: reply received."
        else
            say "Ping: no reply."
        fi
    else
        say "ping command unavailable; skipped."
    fi

    # Test requested TCP port with nc first; Bash /dev/tcp is fallback.
    section "TCP PORT $PORT"
    tcp_ok=0
    if have nc; then
        nc -z -w "$TCP_TIMEOUT" "$ADDR" "$PORT" >"$TMP" 2>&1
        rc=$?
        if [[ $rc -eq 0 ]]; then
            tcp_ok=1
        else
            say "nc: no connection on $ADDR:$PORT."
            sed -n '1,4p' "$TMP" | while IFS= read -r line; do say "$line"; done
        fi
    else
        say "nc unavailable; trying Bash TCP support."
    fi

    if (( tcp_ok == 0 )); then
        timeout "$((TCP_TIMEOUT+2))" bash -c \
            'exec 3<>"/dev/tcp/$1/$2"' _ "$ADDR" "$PORT" >/dev/null 2>&1
        [[ $? -eq 0 ]] && tcp_ok=1
    fi

    if (( tcp_ok )); then
        UP=1
        REASONS+=("TCP port $PORT accepted a connection")
        say "TCP: connection successful."
    else
        say "TCP: no connection."
        # One retry helps with transient packet loss.
        say "Retrying TCP once after ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        if have nc; then
            nc -z -w "$TCP_TIMEOUT" "$ADDR" "$PORT" >/dev/null 2>&1 && tcp_ok=1
        fi
        if (( tcp_ok == 0 )); then
            timeout "$((TCP_TIMEOUT+2))" bash -c \
                'exec 3<>"/dev/tcp/$1/$2"' _ "$ADDR" "$PORT" >/dev/null 2>&1 && tcp_ok=1
        fi
        if (( tcp_ok )); then
            UP=1
            REASONS+=("TCP port $PORT accepted a connection on retry")
            say "TCP retry: connection successful."
        else
            say "TCP retry: no connection."
        fi
    fi

    # Optional HTTP(S) probe on the supplied port, if curl exists.
    # This can identify a web service even when ICMP is blocked.
    if have curl && { [[ $PORT -eq 80 ]] || [[ $PORT -eq 443 ]] || [[ $PORT -eq 8080 ]] || [[ $PORT -eq 8443 ]]; }; then
        section "HTTP SERVICE"
        scheme=http
        [[ $PORT -eq 443 || $PORT -eq 8443 ]] && scheme=https
        if curl -k -sS -I --connect-timeout "$TCP_TIMEOUT" --max-time "$((TCP_TIMEOUT+2))" \
            "$scheme://$ADDR:$PORT/" -o /dev/null >/dev/null 2>&1; then
            UP=1
            REASONS+=("HTTP(S) server responded")
            say "HTTP(S): response received."
        else
            say "HTTP(S): no response."
        fi
    fi
else
    say "Target checks skipped because no address was available."
fi

# Final output is intentionally binary: UP or DOWN.
section "FINAL STATUS"
if (( UP )); then
    say "${G}STATUS: UP${R}"
    say "At least one target check received a response:"
    for reason in "${REASONS[@]}"; do say "- $reason"; done
    EXIT=0
else
    say "${Y}STATUS: DOWN${R}"
    say "None of the target checks received a response."
    say "This means DOWN from this machine's network path; filtering or a firewall can also cause this result."
    EXIT=1
fi

say "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
[[ -n $REPORT ]] && say "Report saved: $REPORT"
exit "$EXIT"
