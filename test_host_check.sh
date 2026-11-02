#!/usr/bin/env bash
# Basic tests for host_check.sh. Uses only loopback endpoints started here (nothing external is contacted).
# Usage: tests/test_host_check.sh        (takes about a minute)
HERE=$(cd "$(dirname "$0")" && pwd); SCRIPT=$HERE/../host_check.sh
W=$(mktemp -d); PASS=0; FAIL=0; PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$W"' EXIT
export HC_TCP_TIMEOUT=3 HC_RETRY_DELAY=2 HC_PING_WAIT=2        # speed only; real defaults are 10/10/5

ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
t()   { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
has() { grep -qF -- "$2" "$1"; }

# --- local test endpoints
cat >"$W/srv.py" <<'PY'
import socket, sys, time, threading
mode, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(0 if mode == "blackhole" else 20)
if mode == "blackhole":              # full accept queue: the kernel drops further SYNs -> silent port
    fill = []
    for _ in range(4):
        c = socket.socket(); c.setblocking(False)
        try: c.connect(("127.0.0.1", port))
        except BlockingIOError: pass
        fill.append(c)
    time.sleep(100000)
while True:
    c, _ = s.accept()
    if mode == "ssh": c.send(b"SSH-2.0-TestSSH_1.0\r\n")
    threading.Thread(target=lambda c=c: (time.sleep(20), c.close()), daemon=True).start()
PY
for spec in "ssh 19022" "silent 19023" "blackhole 19090"; do
  setsid python3 "$W/srv.py" $spec >/dev/null 2>&1 </dev/null & PIDS+=($!)
done
sleep 1.5

run() { OUTD=$(mktemp -d -p "$W"); ( cd "$OUTD" && bash "$SCRIPT" "$@" >out.txt 2>err.txt </dev/null ); EC=$?; OUT=$OUTD/out.txt; ERR=$OUTD/err.txt; REP=$(ls "$OUTD"/host_check_*.txt 2>/dev/null | head -n1); }

echo "== input validation"
for bad_in in "" "999.1.1.1" "1.2.3" "a b" 'x;id' '$(id)' "-oX" "bad_host!"; do
  run "$bad_in"; t "rejects target '$bad_in' (exit 2, no probing)" bash -c "[ $EC -eq 2 ] && [ -z '$REP' ]"
done
run 127.0.0.1 0;      t "port 0 rejected" test $EC -eq 2
run 127.0.0.1 70000;  t "port 70000 rejected" test $EC -eq 2
run 127.0.0.1 abc;    t "port 'abc' rejected" test $EC -eq 2
run 127.0.0.1 22 x;   t "extra argument rejected" test $EC -eq 2
run;                  t "no argument -> usage, exit 2" test $EC -eq 2

echo "== connection successful + SSH banner on a non-standard port"
run 127.0.0.1 19022
t "exit code 0" test $EC -eq 0
t "TCP shown as CONNECTION SUCCESSFUL" has "$OUT" "RESULT: CONNECTION SUCCESSFUL"
t "SSH banner read without login" has "$OUT" "SSH server: SSH-2.0-TestSSH_1.0"
t "command and raw output are displayed" bash -c "grep -q '^Command: ' '$OUT' && grep -q -- '--- raw output ---' '$OUT'"
t "timestamped report file saved, identical to screen" bash -c "[ -n '$REP' ] && cmp -s '$OUT' '$REP'"

echo "== connection refused"
run 127.0.0.1 19099
t "exit code 1" test $EC -eq 1
t "reported as CONNECTION REFUSED" has "$OUT" "RESULT: CONNECTION REFUSED"
t "says host is alive, port closed" has "$OUT" "HOST REACHABLE, PORT CLOSED"

echo "== silent service (accepts, sends nothing)"
run 127.0.0.1 19023
t "TCP ok, banner step reports silence" has "$OUT" "no banner"

echo "== connection timed out (silent port; ping works on loopback)"
run 127.0.0.1 19090
t "exit code 5 (inconclusive)" test $EC -eq 5
t "reported as CONNECTION TIMED OUT" has "$OUT" "RESULT: CONNECTION TIMED OUT"
t "one delayed retry performed" has "$OUT" "waiting 2s, then one delayed retry"
t "exactly two TCP attempts" bash -c "[ \$(grep -c '^=== CHECK: TCP connect' '$OUT') -eq 2 ]"
t "ping answers -> 'host answers ping', not down" has "$OUT" "NOT shown to be down"
t "never asserts the server is down (negated wording only)" bash -c "! grep -iE 'server is down|is powered off|host is down' '$OUT' | grep -viE 'not (proof|shown|proven)|does not'"

echo "== timeout with no ping replies (ping mocked to fail)"
mkdir -p "$W/mock"; printf '#!/bin/bash\necho "3 packets transmitted, 0 received, 100%% packet loss"; exit 1\n' >"$W/mock/ping"; chmod +x "$W/mock/ping"
PATH="$W/mock:$PATH" run 127.0.0.1 19090
t "inconclusive wording, server NOT proven down" has "$OUT" "the server is NOT proven down"
t "lists alternatives (firewall / overloaded / path)" has "$OUT" "overloaded host"

echo "== hostname resolution"
run nonexistent-host.invalid 22
t "resolution failure -> exit 3" test $EC -eq 3
t "reported as HOSTNAME RESOLUTION FAILURE" has "$OUT" "HOSTNAME RESOLUTION FAILURE"
t "no TCP probe was sent" bash -c "! grep -q '^=== CHECK: TCP' '$OUT'"
run localhost 19022
t "hostname resolved via getent then connected" bash -c "grep -q 'RESULT: resolved' '$OUT' && [ $EC -eq 0 ]"

echo "== network unreachable (empty network namespace)"
if unshare -n true 2>/dev/null; then
  OUTD=$(mktemp -d -p "$W"); ( cd "$OUTD" && unshare -n bash "$SCRIPT" 192.0.2.50 22 >out.txt 2>err.txt </dev/null ); EC=$?
  t "reported as NETWORK UNREACHABLE (local)" has "$OUTD/out.txt" "NETWORK UNREACHABLE (local)"
  t "blamed on local routing, not the server" has "$OUTD/out.txt" "LOCAL ROUTING PROBLEM"
  t "exit code 4 (local problem)" test $EC -eq 4
else echo "  SKIP  cannot create a network namespace here"; fi

echo "== missing optional tools"
MIN=$W/min; mkdir -p "$MIN"
for c in bash env cat date tr wc head sort uniq rm mktemp sleep hostname awk sed grep timeout printf; do p=$(command -v $c) && ln -sf "$p" "$MIN/$c"; done
PATH=$MIN run 127.0.0.1 19022
t "still works with only bash/coreutils (exit 0)" test $EC -eq 0
t "missing ping reported as NOT PERFORMED" has "$OUT" "'ping' is not installed"
t "missing ip reported as NOT PERFORMED" has "$OUT" "'ip' is not installed"
t "TCP result still produced" has "$OUT" "RESULT: CONNECTION SUCCESSFUL"

echo; echo "RESULT: $PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
