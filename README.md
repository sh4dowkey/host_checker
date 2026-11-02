# HostCheck

A lightweight Bash utility that checks whether a host responds over the network and reports one final result:

- **UP** — at least one target check receives a response.
- **DOWN** — none of the target checks receives a response.

HostCheck is designed for quick server-accessibility checks on Linux systems without requiring heavyweight network diagnostic tools.

**Repository:** https://github.com/sh4dowkey/host_checker

---

## Features

- Simple command-line usage: `hostcheck <host> [port]`
- ICMP reachability check using `ping`
- TCP port check using `nc` (netcat)
- Bash `/dev/tcp` fallback if `nc` is unavailable
- One automatic TCP retry
- Optional HTTP/HTTPS check using `curl` on common web ports
- Hostname resolution using `getent`
- Saves diagnostic reports outside the project directory
- Automatically removes reports older than seven days
- No root privileges required for normal use

## How the UP/DOWN status works

HostCheck uses an **any-success rule**.

| Ping | TCP check | HTTP(S) check | Final status |
|---|---|---|---|
| Responds | Fails | No response | **UP** |
| No reply | Connects | No response | **UP** |
| No reply | Fails | Responds | **UP** |
| No reply | Fails | No response | **DOWN** |

A single successful target check is enough to mark the host **UP**. A failed ping does not make the host DOWN if another check succeeds.

**Important:** DOWN means that none of the checks received a response from the machine running HostCheck. It does not prove that the remote server is powered off. Firewalls, network ACLs, routing problems, or filtered probes can make a live server appear DOWN.

The local gateway is not counted as proof that the target is UP.

---

## Download

### Option 1: Download ZIP using the terminal

The following commands download the `main` branch of this repository and extract it:

```bash
cd ~/Downloads

curl -L "https://github.com/sh4dowkey/host_checker/archive/refs/heads/main.zip" -o host_checker.zip

unzip host_checker.zip

cd host_checker-main
```

If `curl` or `unzip` is unavailable, use the browser method below.

### Option 2: Download ZIP using GitHub

1. Open the [HostCheck repository](https://github.com/sh4dowkey/host_checker).
2. Click the green **Code** button.
3. Select **Download ZIP**.
4. Extract the downloaded ZIP file.
5. Open a terminal in the extracted `host_checker-main` folder.

### Option 3: Clone using Git

If Git is installed:

```bash
cd ~/Downloads

git clone https://github.com/sh4dowkey/host_checker.git

cd host_checker
```

---

## Requirements

HostCheck is written in Bash and uses common Linux command-line utilities.

### Core utilities

The script expects these commands to be available:

- `bash`
- `timeout`
- `mktemp`
- `date`
- `awk`
- `tr`
- `grep`
- `sed`
- `find`
- `sleep`

These are normally available on common Linux distributions.

### Optional network utilities

| Utility | Purpose | Behaviour if unavailable |
|---|---|---|
| `ping` | ICMP reachability check | Ping check is skipped |
| `nc` | TCP port connection test | Uses Bash `/dev/tcp` fallback |
| Bash `/dev/tcp` | TCP fallback | TCP fallback cannot run if unsupported |
| `getent` | Hostname resolution | Hostname cannot be resolved by the script |
| `curl` | HTTP(S) check on ports 80, 443, 8080, 8443 | HTTP(S) check is skipped |

The script does not install packages automatically. It does not require Nmap, tcpdump, Python, or root privileges.

---

## Run directly

From the project directory:

```bash
chmod +x host_check.sh
```

Check a host using the default port (`22`):

```bash
./host_check.sh 192.168.1.100
```

Check a host using a specific port:

```bash
./host_check.sh 192.168.1.100 443
```

Check a hostname:

```bash
./host_check.sh example.com
```

Check a web server:

```bash
./host_check.sh example.com 443
```

### Usage

```text
./host_check.sh <IP-or-hostname> [port]
```

- `IP-or-hostname` is required.
- `port` is optional and defaults to `22`.
- Valid ports are from `1` to `65535`.

---

## Install as a command (`hostcheck`)

You can install HostCheck in your user account so that it can be run from any directory. No `sudo` is needed.

Run these commands **from the directory containing `host_check.sh`**:

```bash
mkdir -p "$HOME/.local/bin"

install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"

grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

export PATH="$HOME/.local/bin:$PATH"
```

The final `export` makes the command available in the current terminal. The `.bashrc` entry makes it available in new Bash terminals.

To reload your Bash configuration:

```bash
source ~/.bashrc
```

Verify the installation:

```bash
command -v hostcheck
```

You should see a path similar to:

```text
/home/your-user/.local/bin/hostcheck
```

Now run it from anywhere:

```bash
hostcheck 192.168.1.100
hostcheck 192.168.1.100 443
hostcheck example.com 22
```

---

## Checks performed

HostCheck runs the following checks:

1. **Input validation** — checks the supplied hostname/IP and port.
2. **DNS resolution** — resolves hostnames using `getent`, when available.
3. **Ping** — sends three ICMP echo requests, with a default wait of five seconds per request.
4. **TCP connection** — tests the specified port using `nc -z -w`.
5. **TCP fallback** — if `nc` is unavailable or the initial TCP attempt does not connect, tries Bash `/dev/tcp`.
6. **TCP retry** — if the first TCP attempt fails, waits five seconds and tries once more.
7. **HTTP(S) probe** — if `curl` is installed and the selected port is `80`, `443`, `8080`, or `8443`, sends an HTTP(S) HEAD request.
8. **Final status** — prints `STATUS: UP` or `STATUS: DOWN`.

Only the supplied TCP port is tested. HostCheck does not scan a port range.

### Default timing

| Setting | Default |
|---|---:|
| Ping attempts | 3 |
| Ping wait | 5 seconds |
| TCP timeout per attempt | 10 seconds |
| Delay before TCP retry | 5 seconds |

---

## Reports

HostCheck saves reports outside the project directory.

Default report directory:

```text
~/.cache/hostcheck/reports/
```

If `XDG_CACHE_HOME` is set, it uses:

```text
$XDG_CACHE_HOME/hostcheck/reports/
```

Reports older than **seven days** are automatically deleted when HostCheck runs.

The report directory is created with permissions `700`, and report files are created with permissions `600`, restricting access to the current user.

### List saved reports

```bash
ls -lh "${XDG_CACHE_HOME:-$HOME/.cache}/hostcheck/reports/"
```

### Open the latest report

```bash
latest=$(ls -t "${XDG_CACHE_HOME:-$HOME/.cache}"/hostcheck/reports/host_check_*.txt 2>/dev/null | head -n 1)

if [ -n "$latest" ]; then
    less "$latest"
else
    echo "No reports found."
fi
```

Press `q` to exit `less`.

Reports may contain hostnames, IP addresses, and diagnostic output. Review them before sharing. When color output is enabled in an interactive terminal, the report may also contain terminal color escape sequences.

---

## Optional timeout configuration

You can override the default timing values for a single run using environment variables.

```bash
HC_PING_WAIT=3 HC_TCP_TIMEOUT=8 HC_RETRY_DELAY=3 hostcheck example.com 443
```

Available variables:

| Variable | Default | Description |
|---|---:|---|
| `HC_PING_WAIT` | `5` | Ping wait in seconds |
| `HC_TCP_TIMEOUT` | `10` | TCP timeout in seconds |
| `HC_RETRY_DELAY` | `5` | Delay before the TCP retry |

---

## Exit codes

| Exit code | Meaning |
|---:|---|
| `0` | UP — at least one target check received a response |
| `1` | DOWN — no target check received a response |
| `2` | Invalid input or incorrect usage |
| `4` | Local setup error, such as failure to create a temporary file |

You can use the exit code in shell scripts:

```bash
hostcheck 192.168.1.100 22

if [ $? -eq 0 ]; then
    echo "Host is UP"
else
    echo "Host is DOWN or the check could not complete"
fi
```

---

## Update HostCheck

To update an existing installation:

1. Download or clone the latest repository version.
2. Open a terminal in the updated project directory.
3. Run:

```bash
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

This replaces the installed command with the updated script.

## Uninstall

Remove the installed command:

```bash
rm -f "$HOME/.local/bin/hostcheck"
```

This does not delete the downloaded project directory or saved reports.

---

## Limitations

- A DOWN result is not definitive proof that a server is powered off.
- ICMP may be blocked even when a TCP service is reachable.
- TCP connections may be filtered or dropped by a firewall.
- Only the specified TCP port is tested.
- HTTP(S) checks are only attempted on ports `80`, `443`, `8080`, and `8443`, and only when `curl` is installed.
- Hostname checks require `getent`.
- The result reflects connectivity from the machine where HostCheck is executed.

## Safety

HostCheck performs basic, read-only network checks. It does not attempt authentication, execute remote commands, change server settings, modify firewall rules, or scan port ranges.

Use it only against systems you own or are authorized to diagnose.

---

## License

HostCheck is licensed under the [MIT License](LICENSE).

You are free to use, modify, and distribute this software, subject to the terms of the license.
