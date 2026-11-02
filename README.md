# host_check.sh

One Bash script that tests **one host and one TCP port** and tells you what the evidence supports.
It never says "server down" just because something timed out.

```
./host_check.sh <IPv4-or-hostname> [port]        # port defaults to 22
./host_check.sh 192.168.1.100
./host_check.sh 192.168.1.100 2222
./host_check.sh example.com
./host_check.sh example.com 443
```
No flags, config files or prompts. Read-only: it sends ping, one TCP connect (plus one delayed retry if
that times out) and, if the port opens, passively *listens* for a banner. It never logs in or sends data.

## What it checks (in order)
1. Validates the target and port.  2. Resolves a hostname with `getent`.  3. `ip route get` (local route).
4. `ping` - 3 attempts, up to 5 s each.  5. TCP connect via Bash `/dev/tcp` - up to 10 s, one retry after 10 s
if it timed out.  6. Passive banner read (up to 3 s) - recognises SSH on any port.
7. Gateway: default route, gateway ping, ARP/NDP entry.  8. Final summary.

Each check prints its name, the exact command, the raw output, a RESULT and a short interpretation.
Everything is also saved to `host_check_<target>_<date>_<time>.txt` in the current directory
(existing files are never overwritten).

## Dependencies
Required: `bash` (4+), `timeout`, `date`, `mktemp`, `awk`, `sed`, `grep` (all standard).
Optional (the check is reported as "NOT PERFORMED" if missing): `ping`, `ip`, `getent` (needed only for
hostnames), `nc` (used only if bash has no `/dev/tcp`).
Nothing is installed and no root is needed.

## Results it distinguishes
`CONNECTION SUCCESSFUL` | `CONNECTION REFUSED` | `CONNECTION TIMED OUT` | `NETWORK UNREACHABLE (local)` |
`NO ROUTE TO HOST` | `HOSTNAME RESOLUTION FAILURE` | `LOCAL TOOL FAILURE` | `INCONCLUSIVE`.

Exit codes: `0` TCP connected | `1` host answered, port refused | `2` bad input | `3` name did not resolve |
`4` local problem (no route / tool failure) | `5` no response or inconclusive (**not** proof the server is down).

## Reading the conclusion
* **Timed out, ping answers:** host is reachable; port is probably filtered, or the service is overloaded/hung.
* **Timed out, ping silent:** no response within the deadline. Fits powered-off, but equally a firewall,
  overload or path problem; the tool says it cannot tell which.
* **Refused:** the host is alive; nothing listens on that port (check the real SSH port).
* **Network unreachable:** this machine has no route - fix locally before blaming the server.

## Tests
```
tests/test_host_check.sh      # about a minute; uses only loopback endpoints it starts itself
```
Covers input validation, success + SSH banner on a non-standard port, refused, silent service, a genuinely
silent port (timeout + retry), no-ping timeout, name-resolution failure, network unreachable (empty network
namespace), and running with `ping`/`ip` missing. 41 checks pass in the development sandbox.

## Limits
Tested only against loopback and a sandbox without IPv6; IPv4 is the supported case (a hostname that resolves
only to IPv6 is attempted but untested). Only TCP is tested, only the port you give. One vantage point:
server-side evidence (console, hypervisor, firewall logs) is needed to say *why* a host is silent.
