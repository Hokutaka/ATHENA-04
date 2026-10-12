// ATHENA-04 v0.6: local and SSH-based Linux/Windows telemetry.
// Remote checks execute fixed read-only probes; no arbitrary commands.
use bufio;
use encoding::base64;
use fmt;
use fs;
use io;
use os;
use os::exec;
use strings;

fn help() void = {
	fmt::println("ATHENA-04 / C4FE")!;
	fmt::println("Usage:")!;
	fmt::println("  athena status")!;
	fmt::println("  athena node add <name> <host> <ssh-user> [linux|windows]")!;
	fmt::println("  athena node list")!;
	fmt::println("  athena node remove <name>")!;
	fmt::println("  athena node os <name> <linux|windows>")!;
	fmt::println("  athena node check <name>")!;
	fmt::println("  athena help")!;
};

fn node_db_path() str = {
	const home = match (os::getenv("HOME")) {
	case let home: str =>
		yield home;
	case void =>
		fmt::fatalf("HOME is not set");
	};
	const dir = strings::concat(home, "/.config/athena-04")!;
	os::mkdirs(dir, 0o700)!;
	const path = strings::concat(dir, "/nodes.tsv")!;
	free(dir);
	return path;
};

fn valid_field(field: str) bool = {
	return field != ""
		&& !strings::contains(field, "\t", "\n", "\r", " ")
		&& !strings::hasprefix(field, "-");
};

fn registered(path: str, name: str) bool = {
	const file = match (os::open(path)) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		return false;
	};
	defer io::close(file)!;

	let scanner = bufio::newscanner(file, 1024 * 1024);
	defer bufio::finish(&scanner);
	for (true) {
		const line = match (bufio::scan_line(&scanner)!) {
		case io::EOF =>
			break;
		case let line: str =>
			yield line;
		};
		const parts = strings::cut(line, "\t");
		if (parts.0 == name) {
			return true;
		};
	};
	return false;
};

fn valid_platform(platform: str) bool = {
    return platform == "linux" || platform == "windows";
};

fn node_add(name: str, host: str, ssh_user: str, platform: str) void = {
	if (!valid_field(name) || !valid_field(host) || !valid_field(ssh_user) || !valid_platform(platform)) {
		fmt::fatalf("Invalid node field: fields cannot be empty or contain whitespace, or begin with '-'");
	};
	const db = node_db_path();
	defer free(db);
	if (registered(db, name)) {
		fmt::fatalf("Node '{}' is already registered", name);
	};
	const file = match (os::create(db, 0o600, fs::flag::WRONLY | fs::flag::APPEND)) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		fmt::fatalf("Cannot write registry: {}", fs::strerror(err));
	};
	defer io::close(file)!;
	fmt::fprintfln(file, "{}\t{}\t{}\t{}", name, host, ssh_user, platform)!;
	fmt::printfln("Registered '{}' ({}, {})", name, host, platform)!;
	fmt::println("Connection status: NOT CHECKED")!;
};

// Remove a registry entry by rewriting to a temporary file and renaming.
// SSH credentials and known_hosts are intentionally left untouched.
fn node_remove(name: str) void = {
    if (!valid_field(name)) fmt::fatalf("Invalid node name");
    const db = node_db_path();
    defer free(db);
    const input = match (os::open(db)) {
    case let file: io::file => yield file;
    case let err: fs::error => fmt::fatalf("Registry does not exist");
    };
    defer io::close(input)!;
    let scanner = bufio::newscanner(input, 1024 * 1024);
    defer bufio::finish(&scanner);
    const tmp = strings::concat(db, ".tmp")!;
    defer free(tmp);
    const output = match (os::create(tmp, 0o600)) {
    case let file: io::file => yield file;
    case let err: fs::error => fmt::fatalf("Cannot create registry staging file: {}", fs::strerror(err));
    };
    let found = false;
    for (true) {
        const row = match (bufio::scan_line(&scanner)!) {
        case io::EOF => break;
        case let row: str => yield row;
        };
        const parts = strings::cut(row, "\t");
        if (parts.0 == name) {
            found = true;
            continue;
        };
        fmt::fprintfln(output, "{}", row)!;
    };
    io::close(output)!;
    if (!found) {
        os::remove(tmp)!;
        fmt::fatalf("Node '{}' not found", name);
    };
    os::rename(tmp, db)!;
    fmt::printfln("Removed node '{}' (registry only)", name)!;
};

// Update only a node's probe type, keeping name, host, user, SSH keys intact.
// Existing three-column entries are treated as Linux until changed.
fn node_os(name: str, platform: str) void = {
    if (!valid_field(name) || !valid_platform(platform)) fmt::fatalf("Invalid node or OS");
    const db = node_db_path();
    defer free(db);
    const input = match (os::open(db)) {
    case let file: io::file => yield file;
    case let err: fs::error => fmt::fatalf("Registry does not exist");
    };
    defer io::close(input)!;
    let scanner = bufio::newscanner(input, 1024 * 1024);
    defer bufio::finish(&scanner);
    const tmp = strings::concat(db, ".tmp")!;
    defer free(tmp);
    const output = match (os::create(tmp, 0o600)) {
    case let file: io::file => yield file;
    case let err: fs::error => fmt::fatalf("Cannot create staging file: {}", fs::strerror(err));
    };
    let found = false;
    for (true) {
        const row = match (bufio::scan_line(&scanner)!) {
        case io::EOF => break;
        case let row: str => yield row;
        };
        const first = strings::cut(row, "\t");
        if (first.0 == name) {
            const second = strings::cut(first.1, "\t");
            const third = strings::cut(second.1, "\t");
            if (second.0 == "" || third.0 == "") {
                io::close(output)!;
                os::remove(tmp)!;
                fmt::fatalf("Malformed node entry");
            };
            fmt::fprintfln(output, "{}\t{}\t{}\t{}", name, second.0, third.0, platform)!;
            found = true;
        } else {
            fmt::fprintfln(output, "{}", row)!;
        };
    };
    io::close(output)!;
    if (!found) {
        os::remove(tmp)!;
        fmt::fatalf("Node '{}' not found", name);
    };
    os::rename(tmp, db)!;
    fmt::printfln("Node '{}' probe OS: {}", name, platform)!;
};

fn node_list() void = {
	const db = node_db_path();
	defer free(db);
	const file = match (os::open(db)) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		fmt::println("No registered nodes yet.")!;
		return;
	};
	defer io::close(file)!;
	let scanner = bufio::newscanner(file, 1024 * 1024);
	defer bufio::finish(&scanner);

	fmt::println("ATHENA-04 / REGISTERED NODES")!;
	let count = 0u;
	for (true) {
		const line = match (bufio::scan_line(&scanner)!) {
		case io::EOF =>
			break;
		case let line: str =>
			yield line;
		};
		const first = strings::cut(line, "\t");
		const second = strings::cut(first.1, "\t");
		if (first.1 == "" || second.1 == "") {
			fmt::fprintln(os::stderr, "Warning: malformed registry entry skipped")!;
			continue;
		};
		const third = strings::cut(second.1, "\t");
        const platform = if (third.1 == "") "linux" else third.1;
        fmt::printfln("  {}  {}  {}  [NOT CHECKED] [{}]", first.0, second.0, third.0, platform)!;
		count += 1;
	};
	fmt::printfln("Total: {} node(s)", count)!;
};

// Check a registered node with existing OpenSSH credentials.
// Never interpolate registry fields into the remote probe.
// The readable PowerShell source is kept in windows/windows-probe.ps1.
// Encode it at runtime so the Hare source never contains an opaque Base64 blob.
// Run ATHENA-04 from the trusted repository root (the UI also uses relative assets).
fn windows_probe_command() str = {
    const file = match (os::open("windows/windows-probe.ps1")) {
    case let f: io::file => yield f;
    case let err: fs::error =>
        fmt::fatalf("Cannot open Windows probe: {}", fs::strerror(err));
    };
    defer io::close(file)!;
    const source = io::drain(file)!;
    defer free(source);
    if (len(source) == 0 || len(source) > 16384) {
        fmt::fatalf("Windows probe must be 1 to 16384 UTF-8 bytes");
    };
    const script = strings::fromutf8(source)!;
    let bytes: []u8 = [];
    defer free(bytes);
    let iter = strings::iter(script);
    for (true) {
        const r = match (strings::next(&iter)) {
        case let r: rune => yield r;
        case done => break;
        };
        const cp = r: u32;
        if (cp <= 0xffff) {
            append(bytes, (cp & 255): u8)!;
            append(bytes, ((cp >> 8) & 255): u8)!;
        } else {
            const point = cp - 0x10000;
            const hi = 0xd800 + (point >> 10);
            const lo = 0xdc00 + (point & 0x3ff);
            append(bytes, (hi & 255): u8)!;
            append(bytes, ((hi >> 8) & 255): u8)!;
            append(bytes, (lo & 255): u8)!;
            append(bytes, ((lo >> 8) & 255): u8)!;
        };
    };
    const encoded = base64::encodestr(
        &base64::std_encoding, bytes)!;
    defer free(encoded);
    return strings::concat(
        "powershell.exe -NoProfile -NonInteractive -EncodedCommand ",
        encoded)!;
};


fn ssh_check(name: str, host: str, ssh_user: str, platform: str) void = {
    if (!valid_field(host) || !valid_field(ssh_user)
        || strings::contains(host, "@", "/", "\\", ":", "'", "\"", ";", "`", "$", "\n")
        || strings::contains(ssh_user, "@", "/", "\\", ":", "'", "\"", ";", "`", "$", "\n")) {
        fmt::fatalf("Invalid SSH destination in registry");
    };
    if (!valid_platform(platform)) fmt::fatalf("Unsupported probe OS");
    const dest = strings::concat(ssh_user, "@", host)!;
    defer free(dest);
    const linux_probe = "set -eu; test -r /proc/uptime; test -r /proc/meminfo; printf 'OS: Linux\n'; printf 'Hostname: '; hostname; printf 'Kernel: '; uname -sr; printf 'Machine: '; uname -m; printf 'CPUs: '; grep -c '^processor' /proc/cpuinfo; printf 'Uptime: '; cat /proc/uptime; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo";
    const remote = if (platform == "windows") windows_probe_command() else strings::dup(linux_probe)!;
    defer free(remote);

    fmt::printfln("ATHENA-04 / REMOTE CHECK: {}", name)!;
    fmt::printfln("Destination: {}", dest)!;
    fmt::printfln("Probe OS: {}", platform)!;
    let command = exec::cmd("timeout", "-k", "3s", "15s", "ssh", "-T",
        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=5", "-o", "ConnectionAttempts=1",
        "-o", "ClearAllForwardings=yes", "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=1", dest, remote)!;
    let proc = exec::start(&command)!;
    let status = exec::wait(&proc)!;
    if (exec::check(&status) is void) {
        if (platform == "windows") {
            fmt::println("Connection: ONLINE / WINDOWS PROBE OK")!;
        } else {
            fmt::println("Connection: ONLINE / LINUX PROBE OK")!;
        };
    } else {
        fmt::fatalf("CHECK FAILED: {} (SSH, authorization, or {} probe)",
            exec::exitstr(exec::exit(&status)), platform);
    };
};

fn node_check(name: str) void = {
	if (!valid_field(name)) {
		fmt::fatalf("Invalid node name");
	};
	const db = node_db_path();
	defer free(db);
	const file = match (os::open(db)) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		fmt::fatalf("No registered nodes; use 'node add' first");
	};
	defer io::close(file)!;
	let scanner = bufio::newscanner(file, 1024 * 1024);
	defer bufio::finish(&scanner);
	for (true) {
		const line = match (bufio::scan_line(&scanner)!) {
		case io::EOF =>
			break;
		case let line: str =>
			yield line;
		};
		const first = strings::cut(line, "\t");
		const second = strings::cut(first.1, "\t");
		if (first.0 == name && second.0 != "" && second.1 != "") {
			const third = strings::cut(second.1, "\t");
            const platform = if (third.1 == "") "linux" else third.1;
            ssh_check(first.0, second.0, third.0, platform);
			return;
		};
	};
	fmt::fatalf("Node '{}' not found", name);
};

fn local_status() void = {
	fmt::println("ATHENA-04 / LOCAL STATUS")!;
	fmt::printfln("  Hostname: {}", os::hostname())!;
	fmt::printfln("  Kernel:   {} {}", os::sysname(), os::release())!;
	fmt::printfln("  Machine:  {}", os::machine())!;
	const cpus = match (os::cpucount()) {
	case let n: size =>
		yield n;
	case =>
		yield 0z;
	};
	fmt::printfln("  CPUs:     {}", cpus)!;

	const uptime = match (os::open("/proc/uptime")) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		fmt::println("  Uptime:   unavailable")!;
		return;
	};
	defer io::close(uptime)!;
	let scanner = bufio::newscanner(uptime, 4096);
	defer bufio::finish(&scanner);
	const line = match (bufio::scan_line(&scanner)!) {
	case let line: str =>
		yield line;
	case io::EOF =>
		fmt::println("  Uptime:   unavailable")!;
		return;
	};
	const first = strings::cut(line, " ");
	fmt::printfln("  Uptime:   {} seconds", first.0)!;

	const meminfo = match (os::open("/proc/meminfo")) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		fmt::println("  Memory:   unavailable")!;
		return;
	};
	defer io::close(meminfo)!;
	let memscan = bufio::newscanner(meminfo, 16384);
	defer bufio::finish(&memscan);
	for (true) {
		const row = match (bufio::scan_line(&memscan)!) {
		case let row: str =>
			yield row;
		case io::EOF =>
			break;
		};
		if (strings::hasprefix(row, "MemTotal:") || strings::hasprefix(row, "MemAvailable:")) {
			fmt::printfln("  {}", row)!;
		};
	};
};

export fn main() void = {
	if (len(os::args) == 2 && os::args[1] == "status") {
		local_status();
	} else if (len(os::args) == 6 && os::args[1] == "node" && os::args[2] == "add") {
		node_add(os::args[3], os::args[4], os::args[5], "linux");
	} else if (len(os::args) == 7 && os::args[1] == "node" && os::args[2] == "add") {
        node_add(os::args[3], os::args[4], os::args[5], os::args[6]);
    } else if (len(os::args) == 5 && os::args[1] == "node" && os::args[2] == "os") {
        node_os(os::args[3], os::args[4]);
    } else if (len(os::args) == 3 && os::args[1] == "node" && os::args[2] == "list") {
		node_list();
	} else if (len(os::args) == 4 && os::args[1] == "node" && os::args[2] == "remove") {
        node_remove(os::args[3]);
    } else if (len(os::args) == 4 && os::args[1] == "node" && os::args[2] == "check") {
		node_check(os::args[3]);
	} else {
		help();
	};
};
