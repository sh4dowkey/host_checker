# HostCheck

A small, read-only Bash utility for checking whether a host responds and whether one specified TCP port is reachable.

It is designed for everyday Linux server troubleshooting. It uses Bash and common Linux utilities instead of requiring specialist network-scanning or packet-capture packages.

## 1. Download

### Option A — Download ZIP from GitHub

1. Open the HostCheck repository page on GitHub.
2. Click the green **Code** button.
3. Select **Download ZIP**.
4. Once downloaded, extract the ZIP file.
5. Open a terminal in the extracted `host-check` project folder.

If the extracted folder is in Downloads, for example:

```bash
cd ~/Downloads/host-check
```

The folder name may differ depending on the repository name and ZIP filename.

### Option B — Clone with Git

If Git is installed, run this from the directory where you want the project:

```bash
git clone <REPOSITORY-URL>
cd <REPOSITORY-FOLDER>
```

Replace the placeholders with the actual GitHub repository URL and folder name.

## 2. Requirements

Required:

- Bash 4 or newer
- `timeout`
- Common utilities: `date`, `mktemp`, `awk`, `sed`, `grep`, `tr`, `find`

Optional:

- `getent` for hostname resolution
- `ip` for route, gateway, and neighbour information
- `ping` for ICMP checks
- `nc` as a fallback if Bash TCP support is unavailable

No Nmap, tcpdump, Python, or package installation is required. Optional checks are skipped when their utilities are unavailable. The script does not require root privileges for normal use.

## 3. Run directly

From the project directory:

```bash
chmod +x host_check.sh
./host_check.sh 192.168.1.100
```

Usage:

```bash
./host_check.sh <IP-or-hostname> [port]
```

Examples:

```bash
./host_check.sh 192.168.1.100
./host_check.sh 192.168.1.100 2222
./host_check.sh example.com
./host_check.sh example.com 443
```

The port is optional and defaults to `22`. No flags, configuration files, or interactive prompts are required.

## 4. Install as the `hostcheck` command

This installs the script into your personal `~/.local/bin` directory. It does not require `sudo`.

Run these commands from the directory containing `host_check.sh`:

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

Add that directory to your PATH. For Bash:

```bash
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

export PATH="$HOME/.local/bin:$PATH"
```

The `export` command makes it available in the current terminal. The `.bashrc` change makes it available in future Bash terminals. Alternatively, open a new terminal or run:

```bash
source ~/.bashrc
```

If you use another shell, add the PATH line to that shell's startup file.

Verify the installation:

```bash
command -v hostcheck
hostcheck 1.1.1.1
```

You can now run it from any directory:

```bash
hostcheck 192.168.1.100
hostcheck 192.168.1.100 2222
hostcheck example.com 443
```

### Updating the installed command

After downloading or pulling an updated version, go to the updated project directory and run:

```bash
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

This replaces the installed command with the updated script.

### Uninstalling

```bash
rm -f "$HOME/.local/bin/hostcheck"
```

This removes the installed command. It does not delete the project folder or saved reports.

## 5. What it checks

The script performs these checks in sequence:

1. Validates the target and optional port.
2. Resolves a hostname with `getent`, when the target is a hostname.
3. Displays the local route using `ip route get`, when available.
4. Sends three ICMP ping requests, with up to five seconds per request.
5. Attempts a TCP connection to the selected port using Bash `/dev/tcp`, with a ten-second default timeout.
6. If the TCP connection succeeds, passively waits briefly for a service banner. It recognises an SSH banner; it does not send a login or application request.
7. If the TCP test times out or reports no route, waits ten seconds and retries once.
8. Displays default-route, gateway, and ARP/NDP neighbour information where available.
9. Prints a final summary and returns an exit status.

The script does not scan other ports.

## 6. Output and reports

The terminal output uses color when run interactively:

- **Cyan:** run header and interpretations
- **Blue:** individual check headings
- **Green:** successful checks
- **Yellow:** inconclusive results and warnings
- **Red:** connection failures and local errors
- **Magenta:** final summary and conclusion
- **Dim text:** commands and metadata

Color is automatically disabled when output is redirected or piped. Set `NO_COLOR=1` to disable it manually:

```bash
NO_COLOR=1 hostcheck 192.168.1.100
```

Saved reports contain plain text without terminal color codes. Each check displays the command executed, raw output, exit status, result, and a short interpretation.

### Report location

Reports are saved outside the project directory:

```text
~/.cache/hostcheck/reports/
```

If `XDG_CACHE_HOME` is set, the reports are saved under:

```text
$XDG_CACHE_HOME/hostcheck/reports/
```

The script automatically removes its own report files older than seven days whenever it runs.

- Report directory permissions: `700` (current user only)
- Report file permissions: `600` (current user only)

List saved reports:

```bash
ls -lh "${XDG_CACHE_HOME:-$HOME/.cache}/hostcheck/reports/"
```

Open the latest report:

```bash
latest=$(ls -t "${XDG_CACHE_HOME:-$HOME/.cache}"/hostcheck/reports/host_check_*.txt 2>/dev/null | head -n 1)
if [ -n "$latest" ]; then
    less "$latest"
else
    echo "No reports found."
fi
```

Press `q` to exit `less`.

Reports may contain internal IP addresses, hostnames, routes, and infrastructure details. Review them before sharing.

## 7. Optional timeout tuning

The defaults are three pings, a five-second per-ping wait, a ten-second TCP timeout, and one ten-second retry delay.

You can override the timing for one run with environment variables:

```bash
HC_PING_WAIT=3 HC_TCP_TIMEOUT=8 HC_RETRY_DELAY=5 hostcheck example.com 443
```

These settings affect only that invocation.

## 8. Understanding the results

The script distinguishes outcomes such as:

- **Connection successful:** the TCP handshake completed on the selected port.
- **Connection refused:** the connection was actively rejected by the target or an intervening device.
- **Connection timed out:** no response arrived within the timeout.
- **Network unreachable / no route:** the local system or a network device reported a routing or reachability problem.
- **Hostname resolution failure:** the hostname could not be resolved.
- **Local tool failure:** a required local diagnostic could not run correctly.
- **Inconclusive:** available checks did not establish whether the service is reachable.

**A timeout is not proof that a server is down.** Firewalls, filtering, an overloaded server, a stalled service, or a network-path problem can all prevent a response.

A successful ping does not prove that a particular TCP port is open. ICMP may also be blocked while the TCP service is working.

A successful TCP connection confirms that the selected port accepted a connection. A passive SSH banner check does not verify authentication or prove that an SSH login will succeed.

## 9. Exit codes

| Code | Meaning |
|---:|---|
| `0` | TCP connection successful |
| `1` | Connection refused |
| `2` | Invalid input or usage |
| `3` | Hostname resolution failure |
| `4` | Local diagnostic or system problem |
| `5` | No response or inconclusive result |

## 10. Limitations

- Only the supplied TCP port is tested; there is no port scanning or automatic service discovery.
- Port `22` is the default. Supply another port when needed.
- SSH banner detection is passive and does not test authentication.
- Results are based on the network path from the machine running the tool.
- IPv6 behaviour may depend on the available local utilities and has not been fully validated in every environment.
- Server-side evidence, such as console access, firewall logs, or packet captures on the server, may be needed to determine why a host is unresponsive.

## 11. Safety

Use this tool only on systems you are authorized to diagnose.

It does not attempt authentication, execute remote commands, change server settings, modify firewall rules, restart services, or scan port ranges.

## 12. License

No license is included. Add a license if you intend to permit others to use, modify, or redistribute this project.
