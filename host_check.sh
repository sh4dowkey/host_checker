#!/usr/bin/env bash
#
# host_check.sh - quick, read-only reachability check for ONE host and ONE TCP port.
#
#   Usage: ./host_check.sh <IPv4-or-hostname> [port]        (default port: 22)
#
# Shows the command, raw output, result and a short interpretation for each check, and saves
# everything to host_check_<target>_<timestamp>.txt in the current directory.
# A timeout is never treated as proof that a server is down.
#
# Exit codes: 0 TCP connection succeeded | 1 host answered but port refused | 2 bad usage/input
#             3 hostname did not resolve | 4 local tool/system problem | 5 no response / inconclusive

export LC_ALL=C
# Fixed defaults (the HC_* environment overrides exist only so the tests run quickly)
PING_COUNT=3; PING_WAIT=${HC_PING_WAIT:-5}; TCP_TIMEOUT=${HC_TCP_TIMEOUT:-10}; RETRY_DELAY=${HC_RETRY_DELAY:-10}; BANNER_WAIT=3
DEVTCP=1

usage() { echo "Usage: $0 <IPv4-or-hostname> [port]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
TARGET=$1
PORT=${2:-22}

# ---------------------------------------------------------------- 1. validate input
if ! [[ $PORT =~ ^[0-9]{1,5}$ ]] || [ $((10#$PORT)) -lt 1 ] || [ $((10#$PORT)) -gt 65535 ]; then
  echo "Error: port must be a number from 1 to 65535 (got '$PORT')" >&2; exit 2
fi
PORT=$((10#$PORT))

is_ipv4() {
  local o; [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do [ $((10#$o)) -le 255 ] || return 1; done
}
KIND=hostname
if is_ipv4 "$TARGET"; then KIND=ip
elif [[ $TARGET =~ ^[0-9.]+$ ]]; then echo "Error: '$TARGET' is not a valid IPv4 address" >&2; exit 2
elif ! [[ $TARGET =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,251}[A-Za-z0-9])?$ ]] || [[ $TARGET == *..* ]]; then
  echo "Error: '$TARGET' is not a valid IPv4 address or hostname" >&2; exit 2
fi

# ---------------------------------------------------------------- output (screen + file)
SAFE=$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9._-' '_')
REPORT="host_check_${SAFE}_$(date +%Y%m%d_%H%M%S).txt"
n=0
while ! ( set -o noclobber; : >"$REPORT" ) 2>/dev/null; do
  n=$((n+1)); [ $n -gt 99 ] && { REPORT=""; break; }
  REPORT="host_check_${SAFE}_$(date +%Y%m%d_%H%M%S)_$n.txt"
done
[ -z "$REPORT" ] && echo "Warning: cannot create a report file here; output is on screen only." >&2

say() { printf '%s\n' "$*"; [ -n "$REPORT" ] && { printf '%s\n' "$*" >>"$REPORT" 2>/dev/null || { echo "Warning: cannot write $REPORT" >&2; REPORT=""; }; }; }
TMP=$(mktemp 2>/dev/null) || { echo "Error: mktemp failed" >&2; exit 4; }
trap 'rm -f "$TMP"' EXIT
have() { command -v "$1" >/dev/null 2>&1; }
have timeout || { echo "Error: 'timeout' is required but not installed" >&2; exit 4; }

RC=0; OUT=""
# Show a command line the way you could paste it into a shell (single-quote anything unusual).
show_cmd() {
  local a out=""
  for a in "$@"; do
    if [[ $a =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then out+="$a "; else out+="'${a//\'/\'\\\'\'}' "; fi
  done
  printf '%s' "${out% }"
}
# run NAME LIMIT CMD...   -> prints name/command/raw output/exit code; sets RC and OUT (raw text)
run() {
  local name=$1 limit=$2; shift 2
  say ""; say "=== CHECK: $name ==="
  say "Command: $(show_cmd "$@")  [limit ${limit}s]"
  local t0=$SECONDS
  timeout "$limit" "$@" >"$TMP" 2>&1 </dev/null; RC=$?
  OUT=$(cat -v "$TMP")                      # cat -v: neutralise control characters from remote data
  say "--- raw output ---"; [ -n "$OUT" ] && say "$OUT" || say "(no output)"
  say "--- exit code $RC$([ $RC -eq 124 ] && echo ' (timed out)'), $((SECONDS - t0))s ---"
}

say "host_check  target=$TARGET  port=$PORT  started=$(date '+%Y-%m-%d %H:%M:%S %Z')  from=$(hostname 2>/dev/null)"
say "Read-only: sends ICMP echo, one TCP connect (+ one delayed retry if it times out), no authentication."
[ -n "$REPORT" ] && say "Saving to: $REPORT"

# ---------------------------------------------------------------- 2. resolve
ADDR=$TARGET; DNS_NOTE="target is an IP address, no lookup needed"
if [ "$KIND" = hostname ]; then
  if ! have getent; then
    say ""; say "=== CHECK: Hostname resolution ==="
    say "RESULT: LOCAL TOOL FAILURE - 'getent' is not installed, so the name cannot be resolved. Retry with an IP address."
    exit 4
  fi
  run "Hostname resolution" 10 getent ahosts "$TARGET"
  ADDR=$(printf '%s\n' "$OUT" | awk '$1 !~ /:/ && NF {print $1; exit}')
  [ -z "$ADDR" ] && ADDR=$(printf '%s\n' "$OUT" | awk 'NF {print $1; exit}')
  if [ $RC -ne 0 ] || [ -z "$ADDR" ]; then
    say "RESULT: HOSTNAME RESOLUTION FAILURE"
    say "Interpretation: this machine could not resolve '$TARGET'$([ $RC -eq 124 ] && echo ' (resolver timed out)'). No probe was sent, so nothing is known about the server. Check the spelling, DNS settings (/etc/resolv.conf) or try the IP."
    say ""; say "FINAL SUMMARY: hostname resolution failed - this is a DNS/local problem, not evidence about the server."
    exit 3
  fi
  DNS_NOTE="resolved to $ADDR (first address of $(printf '%s\n' "$OUT" | awk '{print $1}' | sort -u | wc -l) returned)"
  say "RESULT: resolved"; say "Interpretation: '$TARGET' -> $ADDR. Further checks use this address."
fi
FAM=4; [[ $ADDR == *:* ]] && FAM=6

# ---------------------------------------------------------------- 3. local route
ROUTE_NOTE="not checked ('ip' not installed)"; VIA=""; DEV=""; ROUTE_BAD=0
if have ip; then
  run "Local route to $ADDR" 5 ip -"$FAM" route get "$ADDR"
  if [ $RC -eq 0 ]; then
    VIA=$(printf '%s\n' "$OUT" | awk '{for(i=1;i<NF;i++) if($i=="via"){print $(i+1); exit}}')
    DEV=$(printf '%s\n' "$OUT" | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')
    if [ -n "$VIA" ]; then ROUTE_NOTE="via gateway $VIA on ${DEV:-?}"; else ROUTE_NOTE="on-link via ${DEV:-?} (no gateway)"; fi
    say "RESULT: route found"; say "Interpretation: traffic leaves this machine $ROUTE_NOTE."
  elif printf '%s' "$OUT" | grep -qi 'unreachable'; then
    ROUTE_BAD=1; ROUTE_NOTE="NO ROUTE from this machine"
    say "RESULT: NETWORK UNREACHABLE (local)"; say "Interpretation: this machine has no route to $ADDR. That is a local routing problem, not a server problem."
  else
    ROUTE_NOTE="route lookup failed (rc $RC)"
    say "RESULT: LOCAL TOOL FAILURE / INCONCLUSIVE"; say "Interpretation: 'ip route get' did not give a route; see raw output."
  fi
else
  say ""; say "=== CHECK: Local route ==="; say "RESULT: NOT PERFORMED - 'ip' is not installed. The TCP/ping results below still show routing errors if they occur."
fi

# ---------------------------------------------------------------- 4. ping
PING_STATE="not performed"; PING_RX=0
if have ping; then
  PCMD=(ping -n -c "$PING_COUNT" -W "$PING_WAIT"); [ $FAM -eq 6 ] && PCMD+=(-6)
  PLIM=$((PING_COUNT * (PING_WAIT + 1) + 5))
  run "ICMP ping ($PING_COUNT attempts, up to ${PING_WAIT}s each)" $PLIM "${PCMD[@]}" "$ADDR"
  if [ $RC -ne 0 ] && printf '%s' "$OUT" | grep -qiE 'invalid option|unrecognized option|usage:'; then
    say "(this ping does not accept -n; retrying without it)"
    PCMD=(ping -c "$PING_COUNT" -W "$PING_WAIT"); [ $FAM -eq 6 ] && PCMD+=(-6)
    run "ICMP ping, retry without -n" $PLIM "${PCMD[@]}" "$ADDR"
  fi
  PING_RX=$(printf '%s\n' "$OUT" | sed -n -E 's/.* ([0-9]+) (packets )?received.*/\1/p' | head -n1); PING_RX=${PING_RX:-0}
  if [ "$PING_RX" -gt 0 ]; then
    PING_STATE="replies received ($PING_RX of $PING_COUNT)"
    say "RESULT: CONNECTION SUCCESSFUL (ICMP) - $PING_STATE"
    say "Interpretation: something at $ADDR answers ping, so the network path works at least for ICMP."
  elif printf '%s' "$OUT" | grep -qiE 'Network is unreachable'; then
    PING_STATE="network unreachable (local)"
    say "RESULT: NETWORK UNREACHABLE (local)"; say "Interpretation: this machine cannot route to $ADDR; not a server problem."
  elif printf '%s' "$OUT" | grep -qiE 'Operation not permitted|Permission denied|socket|Address family'; then
    PING_STATE="local ping failure"
    say "RESULT: LOCAL TOOL FAILURE"; say "Interpretation: ping could not run here (permissions/socket problem). This says nothing about the server."
  elif printf '%s' "$OUT" | grep -qiE 'Destination (Host|Net) Unreachable|Packet filtered|prohibited'; then
    PING_STATE="ICMP error returned (host/net unreachable or filtered)"
    say "RESULT: INCONCLUSIVE - an ICMP error came back instead of a reply"
    say "Interpretation: a router (or this machine's own ARP lookup) reported the destination unreachable/filtered. The 'From' address in the output says who. This is not proof the server is off."
  else
    PING_STATE="no replies within ${PING_WAIT}s x $PING_COUNT"
    say "RESULT: CONNECTION TIMED OUT (ICMP) - no replies"
    say "Interpretation: no ping reply was received before the deadline. Many servers/firewalls block or rate-limit ping, and a loaded host may not answer in time, so this does NOT show the server is down."
  fi
else
  say ""; say "=== CHECK: ICMP ping ==="; say "RESULT: NOT PERFORMED - 'ping' is not installed."
fi

# ---------------------------------------------------------------- 5. TCP connect
TCP_STATE=""; TCP_TRIES=0; TCP_FIRST=""
tcp_try() {
  TCP_TRIES=$((TCP_TRIES+1))
  local label="TCP connect to $ADDR port $PORT (attempt $TCP_TRIES, up to ${TCP_TIMEOUT}s)"
  run "$label" "$TCP_TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2" && echo "TCP connection established"' _ "$ADDR" "$PORT"
  if [ $RC -eq 0 ]; then TCP_STATE=OPEN
  elif [ $RC -eq 124 ]; then TCP_STATE=TIMEOUT
  elif printf '%s' "$OUT" | grep -qi 'refused'; then TCP_STATE=REFUSED
  elif printf '%s' "$OUT" | grep -qi 'Network is unreachable'; then TCP_STATE=NETUNREACH
  elif printf '%s' "$OUT" | grep -qiE 'No route to host|Host is unreachable'; then TCP_STATE=NOROUTE
  elif printf '%s' "$OUT" | grep -qiE 'No such file or directory'; then TCP_STATE=NODEVTCP
  elif printf '%s' "$OUT" | grep -qiE 'Permission denied|Address family|Invalid argument|Operation not permitted'; then TCP_STATE=LOCALERR
  else TCP_STATE=OTHER; fi
}
say_tcp_result() {
  case $TCP_STATE in
    OPEN) say "RESULT: CONNECTION SUCCESSFUL"; say "Interpretation: the TCP handshake to $ADDR:$PORT completed - the host is reachable and something is listening on that port." ;;
    REFUSED) say "RESULT: CONNECTION REFUSED"; say "Interpretation: the host (or a firewall in front of it) actively replied 'no' - so the host/path is alive, but nothing accepts connections on port $PORT (service stopped, wrong port, or a REJECT rule)." ;;
    TIMEOUT) say "RESULT: CONNECTION TIMED OUT"; say "Interpretation: no reply of any kind within ${TCP_TIMEOUT}s. Possible: packets dropped by a firewall, host overloaded/busy, host off, or a path problem. A timeout alone does not tell these apart and is NOT proof the server is down." ;;
    NETUNREACH) say "RESULT: NETWORK UNREACHABLE (local)"; say "Interpretation: this machine has no route to $ADDR. Local routing problem, not a server problem." ;;
    NOROUTE) say "RESULT: NO ROUTE TO HOST (ICMP unreachable received)"; say "Interpretation: a router, or this machine's own ARP lookup on a local network, reported the host unreachable. Suggests the target is not answering on the network, but cannot distinguish powered off from a routing/filtering problem." ;;
    NODEVTCP) say "RESULT: LOCAL TOOL FAILURE"; say "Interpretation: this bash has no /dev/tcp support." ;;
    LOCALERR) say "RESULT: LOCAL TOOL FAILURE"; say "Interpretation: the connection could not even be attempted (permissions or socket error). Says nothing about the server." ;;
    *) say "RESULT: INCONCLUSIVE"; say "Interpretation: unrecognised failure; read the raw output above." ;;
  esac
}

tcp_try; say_tcp_result
if [ "$TCP_STATE" = NODEVTCP ]; then
  DEVTCP=0
  if have nc; then
    run "TCP connect via nc (fallback, up to ${TCP_TIMEOUT}s)" "$((TCP_TIMEOUT+2))" nc -z -w "$TCP_TIMEOUT" "$ADDR" "$PORT"
    if [ $RC -eq 0 ]; then TCP_STATE=OPEN; elif printf '%s' "$OUT" | grep -qi 'refused'; then TCP_STATE=REFUSED
    elif [ $RC -eq 124 ] || printf '%s' "$OUT" | grep -qi 'timed out'; then TCP_STATE=TIMEOUT; else TCP_STATE=OTHER; fi
    say_tcp_result
  else
    say "RESULT: TCP CHECK COULD NOT BE PERFORMED - no /dev/tcp and no nc."
  fi
fi
if [ "$TCP_STATE" = TIMEOUT ] || [ "$TCP_STATE" = NOROUTE ]; then
  TCP_FIRST=$TCP_STATE
  say ""; say "(waiting ${RETRY_DELAY}s, then one delayed retry)"; sleep "$RETRY_DELAY"
  tcp_try; say_tcp_result
  if [ "$TCP_STATE" = OPEN ]; then say "Note: the retry succeeded after the first attempt failed - the service is slow or intermittent."; fi
fi

# ---------------------------------------------------------------- 6. banner (passive)
BANNER_NOTE="not attempted (port not open)"; [ "$TCP_STATE" = OPEN ] && [ $DEVTCP -eq 0 ] && BANNER_NOTE="not attempted (no /dev/tcp in this bash)"
if [ "$TCP_STATE" = OPEN ] && [ $DEVTCP -eq 1 ]; then
  run "Passive banner read on port $PORT (waits up to ${BANNER_WAIT}s, sends nothing)" $((BANNER_WAIT+3)) \
    bash -c 'exec 3<>"/dev/tcp/$1/$2" || exit 1; IFS= read -r -t "$3" -n 255 line <&3; printf "%s\n" "$line"' _ "$ADDR" "$PORT" "$BANNER_WAIT"
  if [[ $OUT == SSH-* ]]; then
    BANNER_NOTE="SSH server: ${OUT%%$'\n'*}"
    say "RESULT: CONNECTION SUCCESSFUL - SSH banner received"
    say "Interpretation: an SSH server is answering on port $PORT. No login was attempted."
  elif [ -n "$OUT" ]; then
    BANNER_NOTE="service sent: ${OUT%%$'\n'*}"
    say "RESULT: banner received (not SSH)"; say "Interpretation: the service greets with the text above; port $PORT is not (or not only) SSH."
  else
    BANNER_NOTE="no banner within ${BANNER_WAIT}s"
    say "RESULT: no banner"; say "Interpretation: the service stayed silent. Normal for HTTP/TLS/databases (they wait for the client). For an SSH port a silent server can mean it is overloaded or stalled."
  fi
fi

# ---------------------------------------------------------------- 7. gateway
GW_NOTE="not checked"
if have ip && [ $ROUTE_BAD -eq 0 ]; then
  run "Default route" 5 ip -"$FAM" route show default
  if [ -n "$OUT" ]; then say "RESULT: default route present"; say "Interpretation: this machine has a default gateway for $ADDR-style traffic (shown above)."
  else say "RESULT: no default route"; say "Interpretation: only directly connected/specific routes exist; off-network targets will be unreachable (local configuration)."; fi
  if [ -n "$VIA" ]; then
    NEIGH_TARGET=$VIA
    if have ping; then
      GWP=(ping -n -c 2 -W 2); [ $FAM -eq 6 ] && GWP+=(-6)
      run "Gateway ping ($VIA)" 12 "${GWP[@]}" "$VIA"
      if printf '%s' "$OUT" | grep -qiE '[1-9][0-9]* (packets )?received'; then GW_NOTE="gateway $VIA answers ping"; say "RESULT: CONNECTION SUCCESSFUL (gateway answers)"; say "Interpretation: the first hop is alive."
      else GW_NOTE="gateway $VIA did not answer ping"; say "RESULT: no ping reply from gateway"; say "Interpretation: many gateways ignore ping, so this is not proof of a problem."; fi
    fi
  else
    NEIGH_TARGET=$ADDR; GW_NOTE="none needed (target is on the local network)"
  fi
  run "Neighbour (ARP/NDP) entry for $NEIGH_TARGET" 5 bash -c 'ip neigh show | grep -F -- "$1 " || echo "(no entry)"' _ "$NEIGH_TARGET"
  if printf '%s' "$OUT" | grep -qE 'FAILED|INCOMPLETE'; then
    GW_NOTE="$GW_NOTE; ARP/NDP for $NEIGH_TARGET FAILED/INCOMPLETE"
    say "RESULT: INCONCLUSIVE - link-layer lookup failed"; say "Interpretation: nobody on the local network answered ARP/NDP for $NEIGH_TARGET (it may be off, absent or on another VLAN)."
  elif printf '%s' "$OUT" | grep -q 'no entry'; then say "RESULT: no entry"; say "Interpretation: no neighbour has been recorded for $NEIGH_TARGET yet."
  else say "RESULT: entry present"; say "Interpretation: the link-layer address was resolved at some point (see state above)."; fi
else
  say ""; say "=== CHECK: Gateway ==="; say "RESULT: NOT PERFORMED - $(have ip && echo 'no usable route' || echo "'ip' not installed")."
fi

# ---------------------------------------------------------------- 8. summary
say ""; say "================ FINAL SUMMARY ================"
say "Target        : $TARGET ($DNS_NOTE)"
say "Port          : $PORT"
say "Route         : $ROUTE_NOTE"
say "Ping          : $PING_STATE"
say "TCP port      : ${TCP_STATE:-not tested}$([ -n "$TCP_FIRST" ] && echo " (first attempt: $TCP_FIRST, after delayed retry)")"
say "Banner        : $BANNER_NOTE"
say "Gateway       : $GW_NOTE"
say ""
EXIT=5
case $TCP_STATE in
  OPEN) say "CONCLUSION: CONNECTION SUCCESSFUL. $ADDR:$PORT accepts TCP connections, so the server is reachable from this machine."; EXIT=0 ;;
  REFUSED) say "CONCLUSION: HOST REACHABLE, PORT CLOSED. $ADDR answered but refused port $PORT. The server is alive; the service is not listening there (or a firewall rejects it). Check which port the service really uses."; EXIT=1 ;;
  NETUNREACH) say "CONCLUSION: LOCAL ROUTING PROBLEM. This machine has no route to $ADDR. Nothing can be said about the server."; EXIT=4 ;;
  NODEVTCP|LOCALERR) say "CONCLUSION: LOCAL TOOL FAILURE. The TCP test could not be performed here. Nothing can be said about the server from this run."; EXIT=4 ;;
  TIMEOUT|NOROUTE|OTHER)
    if [ "$PING_RX" -gt 0 ]; then
      say "CONCLUSION: INCONCLUSIVE, BUT HOST ANSWERS PING. ICMP replies arrived while port $PORT gave no usable TCP answer within ${TCP_TIMEOUT}s (twice). The machine is reachable; the port is probably firewalled/dropped, or the service is overloaded or hung. It is NOT shown to be down."
    else
      say "CONCLUSION: INCONCLUSIVE - NO RESPONSE WITHIN THE DEADLINE. Neither ping nor TCP port $PORT answered from this machine. That fits a powered-off host, but equally a firewall dropping everything, an overloaded host, or a network-path problem. This tool cannot tell which; the server is NOT proven down. Try from another machine and check console/hypervisor/firewall logs."
    fi
    EXIT=5 ;;
  *) say "CONCLUSION: INCONCLUSIVE. The TCP check did not produce a usable result."; EXIT=5 ;;
esac
say ""; say "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')  exit code $EXIT"
[ -n "$REPORT" ] && say "Report saved: $REPORT"
exit $EXIT
