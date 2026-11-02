# Host Check

A small, read-only Bash utility for checking whether a host responds and whether one specified TCP port is reachable.

It is designed for everyday Linux server troubleshooting. It uses common Linux tools and Bash functionality rather than requiring specialist network-scanning or packet-capture packages.

## Usage

```bash
./host_check.sh <IPv4-or-hostname> [port]
```

The port is optional and defaults to `22`.

Examples:

```bash
./host_check.sh 192.168.1.100
./host_check.sh 192.168.1.100 2222
./host_check.sh example.com
./host_check.sh example.com 443
```

No flags, configuration files, or interactive prompts are required.

## Install as the `hostcheck` command

You can install the script into your personal `~/.local/bin` directory. This does not require `sudo`.

From the directory containing `host_check.sh`, run:

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

Make sure `~/.local/bin` is on your `PATH`. For Bash, run:

```bash
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"
```

If you use a login shell that reads `~/.profile` instead, add the same `export PATH=...` line there. Open a new terminal or run `source ~/.bashrc` after updating your Bash configuration.

Verify the installation:

```bash
command -v hostcheck
hostcheck 1.1.1.1
```

Now you can run it from any directory:

```bash
hostcheck 192.168.1.100
hostcheck 192.168.1.100 2222
hostcheck example.com 443
```

### Updating the installed command

After downloading or pulling a newer version of the repository, run this from the updated project directory:

```bash
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

This replaces the installed copy with the new version.

### Uninstalling

```bash
rm -f "$HOME/.local/bin/hostcheck"
```

This removes the command but does not delete the repository or its source script.

## What it checks

The script performs these checks in sequence:

1. Validates the target and optional port.
2. Resolves a hostname with `getent` (when the target is a hostname).
3. Displays the local route using `ip route get`, when available.
4. Sends three ICMP ping requests, with up to five seconds per request.
5. Attempts a TCP connection to the specified port using Bash `/dev/tcp` (up to ten seconds).
6. If the TCP connection succeeds, passively listens briefly for a service banner. It recognises an SSH banner on any supplied port; it does not send a login or application request.
7. Displays default-gateway and ARP/NDP neighbour information where available.
8. Prints a final evidence-based summary.

If the first TCP attempt times out, the script waits ten seconds and retries once. It does not scan other ports.

## Output and reports

Each check displays:

- Check name.
- Command executed.
- Raw command output.
- Exit status.
- Result and a short interpretation.

The complete output is also saved in the current directory as a timestamped text file, for example:

```text
host_check_192.168.1.100_20261102_143000.txt
```

Existing reports are not overwritten. Reports may contain internal IP addresses and infrastructure details; review them before sharing.

## Dependencies

Required:

- Bash 4 or newer.
- `timeout`.
- Standard utilities: `date`, `mktemp`, `awk`, `sed`, `grep`, and `hostname`.

Optional:

- `ping` for ICMP checks.
- `ip` for route, gateway, and neighbour information.
- `getent` for hostname resolution.
- `nc` only as a fallback if Bash TCP support is unavailable.

The script does not install packages and does not require root privileges for normal use. If an optional utility is missing, the corresponding check is reported as not performed where possible.

## Result interpretation

The script distinguishes outcomes such as:

- TCP connection successful.
- Connection refused.
- Connection timed out.
- Network unreachable or no route to host.
- Hostname resolution failure.
- Local diagnostic/tool failure.
- Inconclusive result.

**A timeout is not proof that a server is down.** Firewalls, filtering, an overloaded server, a stalled service, or a network-path problem can all cause a probe not to receive a response. The tool reports what it can observe from the machine running it; it cannot determine the server's power state with certainty.

A successful TCP connection confirms that the specified port accepted a connection. A passive SSH banner check does not verify authentication or prove that an SSH login will succeed.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | TCP connection successful |
| `1` | Connection refused |
| `2` | Invalid input or usage |
| `3` | Hostname resolution failure |
| `4` | Local diagnostic or system problem |
| `5` | No response or inconclusive result |

## Tests

Run the included test suite from the repository root:

```bash
chmod +x tests/test_host_check.sh
./tests/test_host_check.sh
```

The tests use local test endpoints and controlled test conditions. They do not replace testing in your own network environment.

## Limitations

- Only the supplied TCP port is tested; there is no port scanning or automatic service discovery.
- Port `22` is only the default. Supply another port when needed.
- SSH banner detection is passive and does not test authentication.
- Results are based on one network vantage point (the machine running the tool).
- IPv6 behaviour has not been fully validated in the development environment.
- Server-side evidence, such as console access, firewall logs, or server network captures, may be needed to determine why a host is unresponsive.

## Safety

Use this tool only on systems you are authorized to diagnose. It does not attempt authentication, execute remote commands, change server settings, modify firewall rules, restart services, or scan port ranges.

## License

No license is included. Add a license if you intend to permit others to use, modify, or redistribute this project.
