#!/usr/bin/env bash

# Host Check - Simple server accessibility diagnostic
# Usage: hostcheck <IP-or-hostname> [port]\n# Reports: ~/.cache/hostcheck/reports/ (automatically pruned after 7 days)

export LC_ALL=C

PING_COUNT=3
PING_WAIT=${HC_PING_WAIT:-5}
TCP_TIMEOUT=${HC_TCP_TIMEOUT:-10}
RETRY_DELAY=${HC_RETRY_DELAY:-10}
BANNER_WAIT=3

# ---------------- COLORS ----------------

COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    COLOR=1
fi

RESET=''
BOLD=''
DIM=''
RED=''
GREEN=''
YELLOW=''
BLUE=''
CYAN=''
MAGENTA=''
WHITE=''

if (( COLOR )); then
    RESET='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    CYAN='\033[1;36m'
    MAGENTA='\033[1;35m'
    WHITE='\033[1;37m'
fi

# ---------------- INPUT ----------------

usage() {
    echo "Usage: $0 <IP-or-hostname> [port]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

TARGET=$1
PORT=${2:-22}

if ! [[ $PORT =~ ^[0-9]{1,5}$ ]] ||
   (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
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

KIND=hostname

if is_ipv4 "$TARGET"; then
    KIND=ip
elif [[ $TARGET =~ ^[0-9.]+$ ]]; then
    echo "Invalid IPv4 address: $TARGET" >&2
    exit 2
elif ! [[ $TARGET =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,251}[A-Za-z0-9])?$ ]] ||
     [[ $TARGET == *..* ]]; then
    echo "Invalid hostname or IP address: $TARGET" >&2
    exit 2
fi

# ---------------- REPORT ----------------

SAFE=$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '_')

# Keep reports outside the project directory.
REPORT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hostcheck/reports"
REPORT=""

if mkdir -p "$REPORT_DIR" 2>/dev/null && chmod 700 "$REPORT_DIR" 2>/dev/null; then
    # Remove reports older than seven days each time hostcheck runs.
    find "$REPORT_DIR" -maxdepth 1 -type f -name 'host_check_*.txt' -mmin +10080 -delete 2>/dev/null

    REPORT="$REPORT_DIR/host_check_${SAFE}_$(date +%Y%m%d_%H%M%S).txt"

    n=0
    while ! (set -o noclobber; : > "$REPORT") 2>/dev/null; do
        ((n++))
        REPORT="$REPORT_DIR/host_check_${SAFE}_$(date +%Y%m%d_%H%M%S)_$n.txt"
        if (( n > 99 )); then
            REPORT=""
            break
        fi
    done

    [[ -n $REPORT ]] && chmod 600 "$REPORT" 2>/dev/null
else
    echo "Warning: could not create report directory; continuing without a report." >&2
fi

# ---------------- OUTPUT ENGINE ----------------

paint() {
    local line=$1 code=""

    (( COLOR )) || {
        printf '%s' "$line"
        return
    }

    case "$line" in
        "host_check "*) code=$CYAN ;;
        "=== CHECK:"*) code=$BLUE ;;
        "Command:"*) code=$DIM ;;
        "--- raw output ---"*) code=$DIM ;;
        "--- exit code"*) code=$DIM ;;

        "RESULT: CONNECTION SUCCESSFUL"* | \
        "RESULT: resolved"* | \
        "RESULT: route found"* | \
        "RESULT: default route present"* | \
        "RESULT: entry present"*)
            code=$GREEN
            ;;

        "RESULT: CONNECTION REFUSED"* | \
        "RESULT: CONNECTION TIMED OUT"* | \
        "RESULT: NETWORK UNREACHABLE"* | \
        "RESULT: NO ROUTE"* | \
        "RESULT: HOSTNAME RESOLUTION FAILURE"* | \
        "RESULT: LOCAL TOOL FAILURE"*)
            code=$RED
            ;;

        "RESULT: INCONCLUSIVE"* | \
        "RESULT: no "* | \
        "RESULT: NOT PERFORMED"* | \
        "RESULT: banner received"* | \
        "RESULT: no banner"*)
            code=$YELLOW
            ;;

        "Interpretation:"*)
            code=$CYAN
            ;;

        "================ FINAL SUMMARY"* | "CONCLUSION:"*)
            code=$MAGENTA
            ;;

        "Saving to:"* | "Report saved:"* | "Finished:"*)
            code=$DIM
            ;;
    esac

    if [[ -n $code ]]; then
        printf '%b%s%b' "$code" "$line" "$RESET"
    else
        printf '%s' "$line"
    fi
}

say() {
    paint "$*"
    printf '\n'

    if [[ -n $REPORT ]]; then
        printf '%s\n' "$*" >> "$REPORT" 2>/dev/null || {
            echo "Warning: could not write report." >&2
            REPORT=""
        }
    fi
}

# ---------------- HELPERS ----------------

TMP=$(mktemp) || exit 4
trap 'rm -f "$TMP"' EXIT

have() {
    command -v "$1" >/dev/null 2>&1
}

have timeout || {
    echo "Error: timeout command is required." >&2
    exit 4
}

RC=0
OUT=""

show_cmd() {
    local arg output=""

    for arg in "$@"; do
        if [[ $arg =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
            output+="$arg "
        else
            output+="'${arg//\'/\'\\\'\'}' "
        fi
    done

    printf '%s' "${output% }"
}

run() {
    local name=$1 limit=$2
    shift 2

    say ""
    say "=== CHECK: $name ==="
    say "Command: $(show_cmd "$@")  [limit ${limit}s]"

    local start=$SECONDS

    timeout "$limit" "$@" > "$TMP" 2>&1 </dev/null
    RC=$?

    OUT=$(cat -v "$TMP")

    say "--- raw output ---"

    if [[ -n $OUT ]]; then
        say "$OUT"
    else
        say "(no output)"
    fi

    say "--- exit code $RC$([[ $RC -eq 124 ]] && echo ' (timed out)'), $((SECONDS-start))s ---"
}

# ---------------- START ----------------

say ""
say "============================================================"
say " HOST CHECK - SERVER ACCESSIBILITY DIAGNOSTICS"
say "============================================================"
say ""
say "Target : $TARGET"
say "Port   : $PORT"
say "Time   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
say "Mode   : Read-only diagnostics"
say ""

say "No authentication, remote commands or remediation."
[[ -n $REPORT ]] && say "Saving report: $REPORT"

# ---------------- DNS ----------------

ADDR=$TARGET
DNS_NOTE="IP address supplied; no DNS lookup required"

if [[ $KIND == hostname ]]; then

    if ! have getent; then
        say ""
        say "=== CHECK: Hostname resolution ==="
        say "RESULT: LOCAL TOOL FAILURE - getent unavailable."
        exit 4
    fi

    run "Hostname resolution" 10 getent ahosts "$TARGET"

    ADDR=$(printf '%s\n' "$OUT" | awk '$1 !~ /:/ && NF {print $1; exit}')

    if [[ -z $ADDR ]]; then
        ADDR=$(printf '%s\n' "$OUT" | awk 'NF {print $1; exit}')
    fi

    if [[ $RC -ne 0 || -z $ADDR ]]; then
        say "RESULT: HOSTNAME RESOLUTION FAILURE"
        say "Interpretation: hostname could not be resolved."
        say "CONCLUSION: DNS/local resolution problem."
        exit 3
    fi

    DNS_NOTE="resolved to $ADDR"

    say "RESULT: resolved"
    say "Interpretation: $TARGET resolves to $ADDR"
fi

FAM=4
[[ $ADDR == *:* ]] && FAM=6

# ---------------- ROUTE ----------------

ROUTE_NOTE="not checked"
VIA=""
DEV=""
ROUTE_BAD=0

if have ip; then

    run "Local route to $ADDR" 5 ip "-$FAM" route get "$ADDR"

    if [[ $RC -eq 0 ]]; then

        VIA=$(printf '%s\n' "$OUT" |
            awk '{for(i=1;i<NF;i++) if($i=="via"){print $(i+1); exit}}')

        DEV=$(printf '%s\n' "$OUT" |
            awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')

        if [[ -n $VIA ]]; then
            ROUTE_NOTE="via $VIA on ${DEV:-unknown}"
        else
            ROUTE_NOTE="on-link via ${DEV:-unknown}"
        fi

        say "RESULT: route found"
        say "Interpretation: traffic leaves through $ROUTE_NOTE"

    elif [[ $OUT =~ unreachable ]]; then

        ROUTE_BAD=1
        ROUTE_NOTE="no route from this machine"

        say "RESULT: NETWORK UNREACHABLE"
        say "Interpretation: local routing problem."

    else

        say "RESULT: INCONCLUSIVE"
        say "Interpretation: route lookup failed."
    fi

else
    say ""
    say "=== CHECK: Local route ==="
    say "RESULT: NOT PERFORMED - ip unavailable."
fi

# ---------------- PING ----------------

PING_STATE="not performed"
PING_RX=0

if have ping; then

    PCMD=(ping -n -c "$PING_COUNT" -W "$PING_WAIT")
    [[ $FAM -eq 6 ]] && PCMD+=(-6)

    PLIM=$((PING_COUNT * (PING_WAIT+1) + 5))

    run "ICMP ping ($PING_COUNT attempts)" "$PLIM" "${PCMD[@]}" "$ADDR"

    if [[ $RC -ne 0 ]] &&
       grep -qiE 'invalid option|unrecognized option|usage:' <<< "$OUT"; then

        PCMD=(ping -c "$PING_COUNT" -W "$PING_WAIT")
        [[ $FAM -eq 6 ]] && PCMD+=(-6)

        run "ICMP ping fallback" "$PLIM" "${PCMD[@]}" "$ADDR"
    fi

    PING_RX=$(sed -n -E \
        's/.* ([0-9]+) (packets )?received.*/\1/p' <<< "$OUT" |
        head -n1)

    PING_RX=${PING_RX:-0}

    if (( PING_RX > 0 )); then

        PING_STATE="replies received ($PING_RX of $PING_COUNT)"

        say "RESULT: CONNECTION SUCCESSFUL (ICMP)"
        say "Interpretation: target responds to ICMP."

    elif grep -qi 'Network is unreachable' <<< "$OUT"; then

        PING_STATE="network unreachable"

        say "RESULT: NETWORK UNREACHABLE"
        say "Interpretation: local routing failure."

    elif grep -qiE 'Operation not permitted|Permission denied|socket|Address family' <<< "$OUT"; then

        PING_STATE="local ping failure"

        say "RESULT: LOCAL TOOL FAILURE"
        say "Interpretation: ping could not execute correctly."

    elif grep -qiE 'Destination (Host|Net) Unreachable|Packet filtered|prohibited' <<< "$OUT"; then

        PING_STATE="ICMP error received"

        say "RESULT: INCONCLUSIVE"
        say "Interpretation: an intermediate device reported unreachable or filtered."

    else

        PING_STATE="no replies"

        say "RESULT: CONNECTION TIMED OUT (ICMP)"
        say "Interpretation: no ICMP reply. This does not prove the server is down."
    fi

else

    say ""
    say "=== CHECK: ICMP ping ==="
    say "RESULT: NOT PERFORMED - ping unavailable."

fi

# ---------------- TCP ----------------

TCP_STATE=""
TCP_TRIES=0
TCP_FIRST=""

tcp_try() {

    ((TCP_TRIES++))

    run "TCP connection to $ADDR:$PORT (attempt $TCP_TRIES)" \
        "$TCP_TIMEOUT" \
        bash -c 'exec 3<>"/dev/tcp/$1/$2" && echo "TCP connection established"' \
        _ "$ADDR" "$PORT"

    if [[ $RC -eq 0 ]]; then
        TCP_STATE=OPEN

    elif [[ $RC -eq 124 ]]; then
        TCP_STATE=TIMEOUT

    elif grep -qi 'refused' <<< "$OUT"; then
        TCP_STATE=REFUSED

    elif grep -qi 'Network is unreachable' <<< "$OUT"; then
        TCP_STATE=NETUNREACH

    elif grep -qiE 'No route to host|Host is unreachable' <<< "$OUT"; then
        TCP_STATE=NOROUTE

    elif grep -qiE 'No such file or directory' <<< "$OUT"; then
        TCP_STATE=NODEVTCP

    elif grep -qiE 'Permission denied|Address family|Invalid argument|Operation not permitted' <<< "$OUT"; then
        TCP_STATE=LOCALERR

    else
        TCP_STATE=OTHER
    fi
}

say_tcp_result() {

    case $TCP_STATE in

        OPEN)
            say "RESULT: CONNECTION SUCCESSFUL"
            say "Interpretation: TCP handshake completed on port $PORT."
            ;;

        REFUSED)
            say "RESULT: CONNECTION REFUSED"
            say "Interpretation: connection was actively rejected."
            ;;

        TIMEOUT)
            say "RESULT: CONNECTION TIMED OUT"
            say "Interpretation: no response within ${TCP_TIMEOUT}s. Could be filtering, overload or network failure. Not proof of server downtime."
            ;;

        NETUNREACH)
            say "RESULT: NETWORK UNREACHABLE"
            say "Interpretation: local routing problem."
            ;;

        NOROUTE)
            say "RESULT: NO ROUTE TO HOST"
            say "Interpretation: a network device or local neighbour lookup reported the host unreachable."
            ;;

        NODEVTCP|LOCALERR)
            say "RESULT: LOCAL TOOL FAILURE"
            say "Interpretation: TCP test could not be performed."
            ;;

        *)
            say "RESULT: INCONCLUSIVE"
            say "Interpretation: see raw output."
            ;;
    esac
}

say ""
tcp_try
say_tcp_result

if [[ $TCP_STATE == NODEVTCP ]]; then

    if have nc; then

        run "TCP connection using nc" "$((TCP_TIMEOUT+2))" \
            nc -z -w "$TCP_TIMEOUT" "$ADDR" "$PORT"

        if [[ $RC -eq 0 ]]; then
            TCP_STATE=OPEN
        elif grep -qi refused <<< "$OUT"; then
            TCP_STATE=REFUSED
        elif [[ $RC -eq 124 ]] || grep -qi 'timed out' <<< "$OUT"; then
            TCP_STATE=TIMEOUT
        else
            TCP_STATE=OTHER
        fi

        say_tcp_result

    else
        say "TCP CHECK COULD NOT BE PERFORMED."
    fi
fi

if [[ $TCP_STATE == TIMEOUT || $TCP_STATE == NOROUTE ]]; then

    TCP_FIRST=$TCP_STATE

    say ""
    say "Waiting ${RETRY_DELAY}s before one retry..."
    sleep "$RETRY_DELAY"

    tcp_try
    say_tcp_result

    if [[ $TCP_STATE == OPEN ]]; then
        say "Note: retry succeeded. The service may be intermittent."
    fi
fi

# ---------------- SSH BANNER ----------------

BANNER_NOTE="not attempted"

if [[ $TCP_STATE == OPEN ]]; then

    run "Passive service banner check" "$((BANNER_WAIT+3))" \
        bash -c 'exec 3<>"/dev/tcp/$1/$2" || exit 1; IFS= read -r -t "$3" -n 255 line <&3; printf "%s\n" "$line"' \
        _ "$ADDR" "$PORT" "$BANNER_WAIT"

    if [[ $OUT == SSH-* ]]; then

        BANNER_NOTE="SSH banner received"

        say "RESULT: CONNECTION SUCCESSFUL - SSH banner"
        say "Interpretation: SSH service is responding. No authentication attempted."

    elif [[ -n $OUT ]]; then

        BANNER_NOTE="non-SSH banner received"

        say "RESULT: BANNER RECEIVED"
        say "Interpretation: service returned a banner, but it is not SSH."

    else

        BANNER_NOTE="no banner received"

        say "RESULT: NO BANNER"
        say "Interpretation: service did not send an immediate banner. Normal for many protocols."
    fi
fi

# ---------------- GATEWAY ----------------

GW_NOTE="not checked"

if have ip && (( ROUTE_BAD == 0 )); then

    run "Default route" 5 ip "-$FAM" route show default

    if [[ -n $OUT ]]; then
        say "RESULT: default route present"
        say "Interpretation: default gateway information is available."
    else
        say "RESULT: no default route"
        say "Interpretation: no default route was found."
    fi

    if [[ -n $VIA ]]; then

        if have ping; then

            GWP=(ping -n -c 2 -W 2)
            [[ $FAM -eq 6 ]] && GWP+=(-6)

            run "Gateway ping ($VIA)" 12 "${GWP[@]}" "$VIA"

            if grep -qE '[1-9][0-9]* (packets )?received' <<< "$OUT"; then
                GW_NOTE="$VIA responds"
                say "RESULT: CONNECTION SUCCESSFUL (gateway)"
                say "Interpretation: first hop responds."
            else
                GW_NOTE="$VIA did not respond"
                say "RESULT: NO PING REPLY FROM GATEWAY"
                say "Interpretation: gateway may block ICMP."
            fi
        fi

        NEIGH_TARGET=$VIA

    else
        NEIGH_TARGET=$ADDR
        GW_NOTE="no separate gateway required"
    fi

    run "Neighbour ARP/NDP entry" 5 \
        bash -c 'ip neigh show | grep -F -- "$1 " || echo "(no entry)"' \
        _ "$NEIGH_TARGET"

    if grep -qE 'FAILED|INCOMPLETE' <<< "$OUT"; then

        say "RESULT: INCONCLUSIVE - neighbour lookup failed"
        say "Interpretation: no successful local link-layer resolution."

    elif grep -q 'no entry' <<< "$OUT"; then

        say "RESULT: NO ENTRY"
        say "Interpretation: no neighbour entry is currently recorded."

    else

        say "RESULT: ENTRY PRESENT"
        say "Interpretation: neighbour information is available."
    fi

fi

# ---------------- FINAL SUMMARY ----------------

say ""
say ""
say "============================================================"
say " FINAL SUMMARY"
say "============================================================"

say "Target       : $TARGET ($DNS_NOTE)"
say "Port         : $PORT"
say "Route        : $ROUTE_NOTE"
say "Ping         : $PING_STATE"
say "TCP          : $TCP_STATE"
say "Banner       : $BANNER_NOTE"
say "Gateway      : $GW_NOTE"

say ""

EXIT=5

case $TCP_STATE in

    OPEN)
        say "CONCLUSION: CONNECTION SUCCESSFUL"
        say "$ADDR:$PORT accepts TCP connections."
        EXIT=0
        ;;

    REFUSED)
        say "CONCLUSION: HOST REACHABLE, PORT REFUSED"
        say "The connection was explicitly rejected."
        EXIT=1
        ;;

    NETUNREACH)
        say "CONCLUSION: LOCAL ROUTING PROBLEM"
        EXIT=4
        ;;

    NODEVTCP|LOCALERR)
        say "CONCLUSION: LOCAL TOOL FAILURE"
        EXIT=4
        ;;

    TIMEOUT|NOROUTE|OTHER)

        if (( PING_RX > 0 )); then

            say "CONCLUSION: INCONCLUSIVE - HOST ANSWERS PING"
            say "ICMP works, but TCP port $PORT did not respond."
            say "Possible filtering, service overload or network issue."

        else

            say "CONCLUSION: INCONCLUSIVE - NO RESPONSE"
            say "Neither ping nor TCP produced a usable response."
            say "The server is NOT proven down."

        fi

        EXIT=5
        ;;

    *)
        say "CONCLUSION: INCONCLUSIVE"
        EXIT=5
        ;;
esac

say ""
say "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
say "Exit code: $EXIT"

[[ -n $REPORT ]] && say "Report saved: $REPORT"

exit "$EXIT"
