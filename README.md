# HostCheck

A small Bash utility that checks whether a host is reachable and prints exactly one final status: **UP** or **DOWN**.

- **UP**: at least one target check receives a response.
- **DOWN**: none of the target checks receives a response.

A failed ping alone does not make a host DOWN. If ping fails but the TCP port connects, the result is UP. The same applies if an HTTP(S) probe responds.

## 1. Download the project

### Download ZIP from GitHub (browser)

1. Open your HostCheck repository on GitHub.
2. Click **Code** → **Download ZIP**.
3. Extract the ZIP file.
4. Open a terminal in the extracted project directory.

### Download ZIP from the terminal

Replace `OWNER` and `REPOSITORY` with the GitHub account/organization and repository name:

```bash
cd ~/Downloads
curl -L "https://github.com/OWNER/REPOSITORY/archive/refs/heads/main.zip" -o hostcheck.zip
unzip hostcheck.zip
```

If the repository's default branch is `master`, replace `main` with `master`.

Then enter the extracted directory. Its name will normally be `REPOSITORY-main`:

```bash
cd REPOSITORY-main
```

If `curl` or `unzip` is unavailable, download the ZIP using the browser and extract it with your file manager.

### Clone with Git instead

Replace the URL with your repository's actual URL:

```bash
cd ~/Downloads
git clone https://github.com/OWNER/REPOSITORY.git
cd REPOSITORY
```

## 2. Requirements

Required: Bash, `timeout`, `date`, `mktemp`, `awk`, `sed`, `grep`, `tr`, and `find`.

Optional checks use:

- `ping` — ICMP reachability
- `nc` (netcat) — TCP port connection
- Bash `/dev/tcp` — TCP fallback if `nc` is unavailable
- `getent` — hostname resolution
- `curl` — extra HTTP(S) check for ports 80, 443, 8080, and 8443

The script does not install packages automatically and does not need root for normal use.

## 3. Run it from the project folder

```bash
chmod +x host_check.sh
./host_check.sh 192.168.1.100
./host_check.sh 192.168.1.100 443
./host_check.sh example.com 443
```

Usage:

```text
./host_check.sh <IP-or-hostname> [port]
```

The port defaults to `22` if omitted.

## 4. Install as a command available everywhere

Run these commands from the folder containing `host_check.sh`:

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"
```

Verify:

```bash
command -v hostcheck
hostcheck 1.1.1.1
```

After this, use it from any directory:

```bash
hostcheck 192.168.1.100
hostcheck 192.168.1.100 443
hostcheck example.com 22
```

## 5. How UP and DOWN are decided

The final result has only two possible values.

### UP

The target is marked **UP** if any one of these checks succeeds:

1. Ping receives at least one reply.
2. The selected TCP port accepts a connection using `nc`.
3. The TCP fallback using Bash `/dev/tcp` connects.
4. The optional HTTP(S) probe receives a response on supported web ports.

Examples:

- Ping works, TCP fails → **UP**
- Ping fails, TCP connects → **UP**
- Ping and TCP fail, HTTP(S) responds → **UP**
- Any one target check responds → **UP**

### DOWN

The target is marked **DOWN** only when none of the target checks receives a response.

**Important:** DOWN means no tested method received a response from this machine. It does not prove that the remote server is powered off. A firewall, network ACL, ICMP filtering, or routing issue can make a live server appear DOWN.

The gateway is not counted as proof that the target is UP. A working gateway only proves that the local first hop responds.

## 6. Checks performed

1. Validate target and port.
2. Resolve hostname with `getent`, if needed.
3. Ping the target three times.
4. Test the selected TCP port with `nc`.
5. Fall back to Bash `/dev/tcp` if needed.
6. Retry a failed TCP test once after a short delay.
7. If `curl` is available and the selected port is 80, 443, 8080, or 8443, try an HTTP(S) HEAD request.
8. Print the final binary status and save a report.

Only the supplied TCP port is tested. The script does not scan a range of ports.

## 7. Reports

Reports are saved outside the project folder:

```text
~/.cache/hostcheck/reports/
```

If `XDG_CACHE_HOME` is set, that directory is used instead.

Reports older than seven days are deleted when the script runs. The report directory is private (`700`) and report files are private (`600`).

List reports:

```bash
ls -lh "${XDG_CACHE_HOME:-$HOME/.cache}/hostcheck/reports/"
```

Open the newest report:

```bash
latest=$(ls -t "${XDG_CACHE_HOME:-$HOME/.cache}"/hostcheck/reports/host_check_*.txt 2>/dev/null | head -n 1)
[ -n "$latest" ] && less "$latest"
```

Press `q` to exit `less`.

Reports can contain internal hostnames, IP addresses, and network information. Review them before sharing.

## 8. Optional timeout settings

Defaults: three pings, five seconds per ping, ten seconds per TCP attempt, and a five-second delay before the TCP retry.

Override them for one run:

```bash
HC_PING_WAIT=3 HC_TCP_TIMEOUT=8 HC_RETRY_DELAY=3 hostcheck example.com 443
```

## 9. Exit codes

| Exit code | Meaning |
|---:|---|
| `0` | UP |
| `1` | DOWN |
| `2` | Invalid input or usage |
| `4` | Local setup error, such as inability to create a temporary file |

## 10. Update and uninstall

To update the installed command, download/extract the latest project version, enter its directory, and run:

```bash
install -m 755 host_check.sh "$HOME/.local/bin/hostcheck"
```

To uninstall the command:

```bash
rm -f "$HOME/.local/bin/hostcheck"
```

This does not delete the project folder or reports.

## 11. Safety and limitations

- The script performs read-only network checks.
- It does not authenticate, run remote commands, change server configuration, or modify firewall rules.
- It checks only the specified TCP port, not every port.
- ICMP may be blocked even when a server is healthy.
- A firewall may drop TCP probes, so a DOWN result is not conclusive proof of server failure.
- Use it only on systems you are authorized to diagnose.
