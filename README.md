# HostCheck

A lightweight Bash-based server connectivity diagnostic tool for Linux.

HostCheck helps infrastructure engineers quickly investigate whether a remote server is reachable and whether a specified TCP port accepts connections.

It displays actual command output, provides a simple interpretation of each check, and automatically saves a timestamped diagnostic report.

**Simple usage. No complicated options. No unnecessary dependencies.**

## Features

- IPv4 address and hostname support.
- Optional TCP port (default: `22`).
- DNS resolution using `getent`.
- Local routing inspection using `ip`.
- ICMP connectivity testing using `ping`.
- TCP connection testing using Bash `/dev/tcp`.
- Passive SSH banner detection.
- Gateway reachability checks.
- ARP/NDP neighbour information.
- Configurable timeouts through environment variables.
- One delayed retry for TCP timeouts.
- Colour-coded terminal output.
- Complete raw command output.
- Automatic timestamped `.txt` reports.
- No automatic installation of dependencies.
- No server modifications or authentication attempts.

## Requirements

HostCheck is designed for standard Linux environments.

**Required:**
- Bash 4 or newer
- `timeout`
- Standard Linux command-line utilities

**Optional:**
- `ping` – ICMP connectivity checks.
- `ip` – routing and gateway information.
- `getent` – hostname resolution.
- `nc` – TCP fallback if Bash `/dev/tcp` is unavailable.

No Python, Nmap, tcpdump, MTR, or other specialist network tools are required.

Root privileges are not required for normal operation.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/host-checker.git
```

### 2. Enter the directory

```bash
cd host-checker
```

### 3. Make the script executable

```bash
chmod +x host_check.sh
```

### 4. Install as a Linux command

You can install HostCheck as `hostcheck` so it can be executed from any directory.

```bash
mkdir -p ~/.local/bin

install -m 755 host_check.sh ~/.local/bin/hostcheck
```

Add `~/.local/bin` to your PATH if it is not already included:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Verify the installation:

```bash
which hostcheck
```

You can now run HostCheck from anywhere.

## Usage

HostCheck accepts one required argument and one optional argument.

```bash
hostcheck <IP-or-hostname> [port]
```

### Examples

**Check a server using the default port 22:**

```bash
hostcheck 192.168.1.100
```

**Check a non-standard SSH port:**

```bash
hostcheck 192.168.1.100 2222
```

**Check a hostname:**

```bash
hostcheck example.com
```

**Check HTTPS connectivity:**

```bash
hostcheck example.com 443
```

The default port is `22` when no port is supplied.

No flags, configuration files, or interactive prompts are required.

## Diagnostic checks

HostCheck performs its checks in sequence.

| Check | Utility | Purpose |
|---|---|---|
| Input validation | Bash | Validates the supplied IP/hostname and port |
| DNS resolution | `getent` | Resolves the supplied hostname |
| Local route | `ip route get` | Identifies the route to the destination |
| ICMP connectivity | `ping` | Checks whether the destination responds to ICMP |
| TCP connectivity | Bash `/dev/tcp` | Attempts a connection to the specified TCP port |
| SSH banner | Bash TCP connection | Passively checks whether an SSH banner is returned |
| Default gateway | `ip route` | Identifies the configured default gateway |
| Gateway connectivity | `ping` | Checks whether the gateway responds to ICMP |
| Neighbour information | `ip neigh` | Displays available ARP/NDP information |

## Timeout and retry behaviour

The default limits are:

| Check | Configuration |
|---|---|
| ICMP ping | 3 attempts, up to 5 seconds per attempt |
| TCP connection | Up to 10 seconds |
| TCP retry | One retry after a 10-second delay if the first attempt times out |
| SSH banner | Up to 3 seconds |

TCP timeout settings can be adjusted using environment variables:

```bash
HC_PING_WAIT=5 HC_TCP_TIMEOUT=15 HC_RETRY_DELAY=10 hostcheck 192.168.1.100
```

These settings apply to that execution only.

## Output and reports

Each check displays:

- Check name.
- Command executed.
- Raw command output.
- Exit code.
- Result classification.
- Short interpretation.

Terminal output uses colours to distinguish results:

| Colour | Meaning |
|---|---|
| Green | Successful checks |
| Red | Connection failures or local errors |
| Yellow | Warnings and inconclusive results |
| Blue | Check headings |
| Cyan | Interpretations |
| Magenta | Final conclusion |

Colour is automatically disabled when output is redirected or when `NO_COLOR` is set.

### Diagnostic reports

Every execution automatically generates a timestamped text report in the current working directory.

Example:

```text
host_check_192.168.1.100_20261102_143000.txt
```

Reports contain the diagnostic commands, raw output, results, and final interpretation.

Existing reports are not overwritten.

The generated reports may contain internal IP addresses and network information. Review them before sharing publicly.

## Understanding results

HostCheck distinguishes between different connectivity outcomes.

| Result | Meaning |
|---|---|
| Connection successful | TCP connection was established |
| Connection refused | Connection was explicitly rejected |
| Connection timed out | No response arrived within the configured deadline |
| Network unreachable | The local system or network reported an unreachable network |
| No route to host | A route or reachability error was reported |
| Hostname resolution failure | The supplied hostname could not be resolved |
| Local tool failure | A diagnostic utility or local operation failed |
| Inconclusive | Available evidence is insufficient for a reliable conclusion |

**Important:** A timeout does not prove that a server is powered off.

Firewalls, packet filtering, network congestion, server overload, unavailable services, and routing problems can produce similar symptoms.

For example, a server may respond to ICMP ping while its SSH port remains unavailable.

HostCheck reports the evidence it can observe from the machine running the tool. It does not claim to establish the server's actual power state.

## Exit codes

| Exit code | Meaning |
|---:|---|
| `0` | TCP connection successful |
| `1` | Connection refused |
| `2` | Invalid input or usage |
| `3` | Hostname resolution failure |
| `4` | Local diagnostic or routing problem |
| `5` | No response or inconclusive result |

## Testing

The repository includes an automated test script.

Run:

```bash
chmod +x test_host_check.sh
./test_host_check.sh
```

The test suite uses controlled local endpoints and test scenarios.

## Safety and limitations

HostCheck is intended for authorized server connectivity diagnostics.

It does not:

- Attempt SSH authentication.
- Execute remote commands.
- Modify server configurations.
- Restart services or servers.
- Change firewall rules.
- Perform port scanning.
- Install software automatically.
- Capture network packets.

Additional limitations:

- Only the supplied TCP port is tested.
- SSH banner detection does not establish successful authentication.
- ICMP may be blocked even when TCP services are accessible.
- Client-side diagnostics cannot independently determine whether a silent server is powered off, overloaded, or filtering traffic.
- IPv6 behaviour depends on the available system utilities and has not been fully validated in the development environment.

## Project structure

```text
host-checker/
├── host_check.sh
├── README.md
├── .gitignore
└── test_host_check.sh
```

## License

No license has been assigned yet. A license should be added before others are permitted to reuse, modify, or redistribute the project.

---

**HostCheck — Simple. Lightweight. Practical.**
