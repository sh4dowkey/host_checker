# HostCheck

A small, read-only Bash utility for checking whether a host and a TCP service are reachable.

## Requirements

- Bash
- `timeout` (required)
- Common Linux utilities: `date`, `mktemp`, `awk`, `sed`, `grep`, `tr`, `find`
- Optional: `getent` for hostname resolution, `ip` for route/neighbour checks, and `ping` for ICMP checks

No Nmap, tcpdump, Python, or package installation is required. Optional checks are skipped when their utilities are unavailable.

## Install

From the directory containing `host_check.sh`:

```bash
mkdir -p ~/.local/bin
install -m 755 host_check.sh ~/.local/bin/hostcheck
```

Add `~/.local/bin` to your PATH if it is not already there:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

If you use a different shell, add the PATH line to that shell's startup file.

## Usage

```bash
hostcheck <IP-or-hostname> [port]
```

Examples:

```bash
hostcheck 192.168.1.100
hostcheck example.com
hostcheck example.com 443
```

The default port is `22`.

## What it checks

1. Validates the target and port.
2. Resolves hostnames using `getent`.
3. Checks the local route using `ip route get`, when available.
4. Sends three ICMP ping attempts, when `ping` is available.
5. Tests a TCP connection to the selected port.
6. Retries a TCP timeout or no-route result once after 10 seconds.
7. If TCP connects, attempts to read a passive service banner. It does not authenticate.
8. Displays default-route, gateway, and neighbour information when available.
9. Prints a final summary and returns an exit status.

The script performs read-only diagnostics. It does not log in, run remote commands, change firewall rules, or remediate the target.

## Reports

Reports are stored outside the project directory:

```text
~/.cache/hostcheck/reports/
```

If `XDG_CACHE_HOME` is set, reports are stored under:

```text
$XDG_CACHE_HOME/hostcheck/reports/
```

- Reports older than seven days are automatically deleted whenever `hostcheck` runs.
- The report directory is restricted to the current user (`700`).
- Report files are restricted to the current user (`600`).

List reports:

```bash
ls -lh ~/.cache/hostcheck/reports/
```

Open the newest report:

```bash
latest=$(ls -t ~/.cache/hostcheck/reports/host_check_*.txt 2>/dev/null | head -n 1)
[ -n "$latest" ] && less "$latest"
```

Press `q` to exit `less`.

## Optional timeout tuning

The defaults are three pings, a five-second per-ping wait, a ten-second TCP timeout, and one ten-second TCP retry delay. You can override the timing for one run with environment variables:

```bash
HC_PING_WAIT=3 HC_TCP_TIMEOUT=8 HC_RETRY_DELAY=5 hostcheck example.com 443
```

## Interpreting results

- **Connection successful:** the TCP handshake completed on the selected port.
- **Connection refused:** the target or an intervening device actively rejected the connection.
- **Connection timed out:** no response arrived within the timeout. This does not prove the server is down.
- **Network unreachable / no route:** the local system or a network device reported a routing or reachability problem.
- **Inconclusive:** available checks did not establish whether the service is reachable.

ICMP may be blocked even when a TCP service is working. Conversely, a successful ping does not prove that a particular TCP port is open.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | TCP connection successful |
| `1` | Connection refused |
| `2` | Invalid usage or input |
| `3` | Hostname resolution failure |
| `4` | Local tool or routing failure |
| `5` | Inconclusive result |

## Limitations

This is a basic connectivity checker, not a port scanner or full network diagnostic suite. It tests only the selected TCP port. A timeout is deliberately reported as inconclusive rather than declaring the host down.
