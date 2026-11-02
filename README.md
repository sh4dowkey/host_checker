# Host Check

A lightweight Bash-based server accessibility diagnostic tool for Linux.

`host_check.sh` checks whether a remote host is reachable and whether a specified TCP port accepts connections. It displays the actual command output, provides a basic interpretation, and automatically saves a timestamped diagnostic report.

Designed for simple infrastructure troubleshooting without requiring specialist network diagnostic packages.

## Features

- IPv4 address and hostname support.
- Optional TCP port selection (default: `22`).
- Hostname resolution using `getent`.
- Local routing information using `ip`.
- ICMP reachability checks using `ping`.
- TCP connectivity testing using Bash `/dev/tcp`.
- Passive SSH banner detection, including non-standard SSH ports.
- Gateway and ARP/NDP information where available.
- Reasonable timeouts and a limited retry for TCP timeouts.
- Complete raw command output displayed in the terminal.
- Automatic timestamped text report generation.
- Evidence-based results that do not automatically classify a timeout as a server outage.

## Requirements

### Required

- Linux
- Bash 4 or newer
- GNU-compatible `timeout`
- Standard command-line utilities: `date`, `mktemp`, `awk`, `sed`, `grep`, and other standard core utilities.

### Optional

- `ping` – ICMP connectivity checks.
- `ip` – routing and gateway information.
- `getent` – hostname resolution.
- `nc` – TCP fallback if Bash `/dev/tcp` is unavailable.

The script does not install packages automatically and does not require root privileges for normal operation.

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/host-check.git
```

Enter the directory:

```bash
cd host-check
```

Make the script executable:

```bash
chmod +x host_check.sh
```

Check Bash syntax:

```bash
bash -n host_check.sh
```

## Usage

The tool accepts one required argument and one optional argument.

```bash
./host_check.sh <IP-or-hostname> [port]
```

### Examples

Check a server using the default port 22:

```bash
./host_check.sh 192.168.1.100
```

Check SSH on a non-standard port:

```bash
./host_check.sh 192.168.1.100 2222
```

Check a hostname:

```bash
./host_check.sh example.com
```

Check HTTPS connectivity:

```bash
./host_check.sh example.com 443
```

No flags, configuration files, or interactive prompts are required.

## Diagnostic checks

The script performs the following checks in sequence:

| Check | Utility | Purpose |
|---|---|---|
| Input validation | Bash | Validates the IP/hostname and port |
| DNS resolution | `getent` | Resolves hostnames |
| Local routing | `ip route get` | Identifies the route to the target |
| ICMP connectivity | `ping` | Checks whether the target responds to ping |
| TCP connectivity | Bash `/dev/tcp` | Attempts a TCP connection to the specified port |
| SSH banner | Bash TCP connection | Passively checks for an SSH protocol banner |
| Gateway | `ip` and `ping` | Checks gateway reachability where applicable |
| ARP/NDP | `ip` | Displays available neighbour information |

### Timeout behaviour

| Check | Limit |
|---|---|
| Ping | 3 attempts, up to 5 seconds each |
| TCP connection | Up to 10 seconds |
| TCP retry | One retry after a 10-second delay if the first attempt times out |
| SSH banner | Up to 3 seconds |

These limits are fixed defaults in the current implementation.

## Output and reports

Every diagnostic check displays:

- Check name.
- Command executed.
- Raw command output.
- Exit code.
- Result classification.
- Short interpretation.

A complete copy of the output is automatically saved in the current working directory.

Example filename:

```text
host_check_192.168.1.100_20261102_143000.txt
```

The report is created with restrictive file permissions and existing reports are not overwritten.

## Result interpretation

The tool distinguishes between:

- `CONNECTION SUCCESSFUL`
- `CONNECTION REFUSED`
- `CONNECTION TIMED OUT`
- `NETWORK UNREACHABLE (local)`
- `NO ROUTE TO HOST`
- `HOSTNAME RESOLUTION FAILURE`
- `LOCAL TOOL FAILURE`
- `INCONCLUSIVE`

**Important:** A timeout does not prove that a server is powered off. Firewalls, network filtering, server overload, unavailable services, and routing problems can produce similar symptoms.

The tool reports what it can establish from the machine running the diagnostic.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | TCP connection successful |
| 1 | Connection refused |
| 2 | Invalid input or usage |
| 3 | Hostname resolution failure |
| 4 | Local system or diagnostic problem |
| 5 | No response or inconclusive result |

## Running tests

The repository includes a basic automated test suite.

```bash
chmod +x test_host_check.sh
./test_host_check.sh
```

The tests use local loopback endpoints and do not intentionally contact external servers.

## Limitations

- Only the specified TCP port is tested; no port scanning is performed.
- The default port is 22, but other ports can be supplied.
- SSH banner detection does not verify authentication or successful login.
- Only client-side network evidence is available.
- IPv6 behaviour has not been fully validated in the development environment.
- A definitive diagnosis of server power state or firewall behaviour requires server-side or provider-side evidence.

## Safety

This is a read-only connectivity diagnostic utility.

It does not:
- Attempt SSH authentication.
- Execute remote commands.
- Change server configurations.
- Modify firewall rules.
- Restart services or servers.
- Perform port scanning.
- Install software.

Use only against systems you are authorized to diagnose.

## License

No license has been specified yet. Add a license before permitting others to redistribute or reuse this project.
