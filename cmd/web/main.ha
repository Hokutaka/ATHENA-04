// ATHENA-04 v0.6: version-tagged Web Console with guarded node mutations.
// Run from the project directory after: hare build -o athena main.ha
// The Web Console invokes the CLI with fixed executable names; it never runs a shell.
use fmt;
use fs;
use io;
use net;
use net::ip;
use net::tcp;
use os;
use os::exec;
use strings;

const PORT: u16 = 8765;

fn header(sock: net::socket, status: str, content_type: str) void = {
	fmt::fprintf(sock, "HTTP/1.1 {}\r\n", status)!;
	fmt::fprintf(sock, "Content-Type: {}\r\n", content_type)!;
	fmt::fprintf(sock, "Cache-Control: no-store\r\n")!;
	fmt::fprintf(sock, "X-Content-Type-Options: nosniff\r\n")!;
	fmt::fprintf(sock, "X-Frame-Options: DENY\r\n")!;
	fmt::fprintf(sock, "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'\r\n")!;
	fmt::fprintf(sock, "Connection: close\r\n\r\n")!;
};

fn write_text(sock: net::socket, value: str) void = {
	io::writeall(sock, strings::toutf8(value))!;
};

// Encode untrusted command output for JSON. No HTML interpolation.
fn json_string(sock: net::socket, value: str) void = {
	write_text(sock, "\"");
	const input = strings::toutf8(value);
	const hex = strings::toutf8("0123456789abcdef");
	for (let i = 0z; i < len(input); i += 1) {
		const b = input[i];
		if (b == 34) {
			write_text(sock, "\\\"");
		} else if (b == 92) {
			write_text(sock, "\\\\");
		} else if (b == 10) {
			write_text(sock, "\\n");
		} else if (b == 13) {
			write_text(sock, "\\r");
		} else if (b == 9) {
			write_text(sock, "\\t");
		} else if (b < 32) {
			write_text(sock, "\\u00");
			const hi = (b / 16): size;
			const lo = (b % 16): size;
			io::writeall(sock, hex[hi..hi + 1])!;
			io::writeall(sock, hex[lo..lo + 1])!;
		} else {
			io::writeall(sock, input[i..i + 1])!;
		};
	};
	write_text(sock, "\"");
};

// Prevent request path from being interpreted as an SSH option or URL.
// Node names in the Web Console are intentionally restricted to ASCII.
fn valid_name(name: str) bool = {
	const input = strings::toutf8(name);
	if (len(input) == 0 || len(input) > 80) return false;
	for (let b .. input) {
		if (!((b >= 48 && b <= 57) || (b >= 65 && b <= 90)
			|| (b >= 97 && b <= 122) || b == 45 || b == 95 || b == 46)) {
			return false;
		};
	};
	return true;
};

// Use the already-working Hare CLI as a subprocess. The output pipe is
// drained before waiting to avoid blocking on a full pipe.
fn capture(op: str, name: str) ([]u8, bool) = {
	let command = if (op == "status") {
		yield exec::cmd("./athena", "status")!;
	} else if (op == "nodes") {
		yield exec::cmd("./athena", "node", "list")!;
	} else {
		yield exec::cmd("./athena", "node", "check", name)!;
	};
	const (read, write) = exec::pipe();
	exec::addfile(&command, os::stdout_file, write)!;
	exec::addfile(&command, os::stderr_file, write)!;
	let proc = exec::start(&command)!;
	io::close(write)!;
	const output = io::drain(read)!;
	io::close(read)!;
	const result = exec::wait(&proc)!;
	return (output, exec::check(&result) is void);
};

// Node registry mutation: fixed commands, untrusted fields are distinct argv.
// No command shell and no string-interpolated remote commands.
fn capture_mutation(op: str, name: str, host: str, user: str, platform: str) ([]u8, bool) = {
    let command = if (op == "add") {
        yield exec::cmd("./athena", "node", "add", name, host, user, platform)!;
    } else if (op == "os") {
        yield exec::cmd("./athena", "node", "os", name, platform)!;
    } else {
        yield exec::cmd("./athena", "node", "remove", name)!;
    };
    const (read, write) = exec::pipe();
    exec::addfile(&command, os::stdout_file, write)!;
    exec::addfile(&command, os::stderr_file, write)!;
    let proc = exec::start(&command)!;
    io::close(write)!;
    const output = io::drain(read)!;
    io::close(read)!;
    const result = exec::wait(&proc)!;
    return (output, exec::check(&result) is void);
};

// ASCII whitelist only: DNS/IPv4 hostnames and portable SSH usernames.
// IPv6 and non-ASCII names are intentionally deferred.
fn safe_component(value: str, max: size) bool = {
    const bytes = strings::toutf8(value);
    if (len(bytes) == 0 || len(bytes) > max || bytes[0] == 45) return false;
    for (let b .. bytes) {
        if (!((b >= 48 && b <= 57) || (b >= 65 && b <= 90)
            || (b >= 97 && b <= 122) || b == 45 || b == 95 || b == 46)) {
            return false;
        };
    };
    return true;
};

// Validate the entire route, not just a prefix, before passing it to exec.
fn mutation_route(sock: net::socket, route: str) void = {
    if (strings::hasprefix(route, "/api/node/add/")) {
        const rest = strings::trimprefix(route, "/api/node/add/");
        const first = strings::cut(rest, "/");
        const second = strings::cut(first.1, "/");
        const third = strings::cut(second.1, "/");
        if (!safe_component(first.0, 80) || !safe_component(second.0, 253)
            || !safe_component(third.0, 64)
            || !(third.1 == "linux" || third.1 == "windows")) {
            json_error(sock, "400 Bad Request", "Invalid name, host, or SSH username");
            return;
        };
        send_mutation(sock, "add", first.0, second.0, third.0, third.1);
    } else if (strings::hasprefix(route, "/api/node/remove/")) {
        const name = strings::trimprefix(route, "/api/node/remove/");
        if (!safe_component(name, 80)) {
            json_error(sock, "400 Bad Request", "Invalid node name");
            return;
        };
        send_mutation(sock, "remove", name, "", "", "");
    } else if (strings::hasprefix(route, "/api/node/os/")) {
        const rest = strings::trimprefix(route, "/api/node/os/");
        const first = strings::cut(rest, "/");
        if (!safe_component(first.0, 80) || !(first.1 == "linux" || first.1 == "windows")) {
            json_error(sock, "400 Bad Request", "Invalid node name or probe OS");
            return;
        };
        send_mutation(sock, "os", first.0, "", "", first.1);
    } else {
        json_error(sock, "404 Not Found", "Unknown operation");
    };
};

fn send_mutation(sock: net::socket, op: str, name: str, host: str, user: str, platform: str) void = {
    const (data, ok) = capture_mutation(op, name, host, user, platform);
    defer free(data);
    const message = match (strings::fromutf8(data)) {
    case let s: str => yield s;
    case =>
        json_error(sock, "502 Bad Gateway", "Registry output was not UTF-8");
        return;
    };
    header(sock, "200 OK", "application/json; charset=utf-8");
    if (ok) {
        write_text(sock, "{\"ok\":true,\"output\":");
    } else {
        write_text(sock, "{\"ok\":false,\"output\":");
    };
    json_string(sock, message);
    write_text(sock, "}");
};

fn json_error(sock: net::socket, status: str, msg: str) void = {
	header(sock, status, "application/json; charset=utf-8");
	write_text(sock, "{\"ok\":false,\"output\":");
	json_string(sock, msg);
	write_text(sock, "}");
};

fn send_command(sock: net::socket, op: str, name: str) void = {
	const (data, ok) = capture(op, name);
	defer free(data);
	const message = match (strings::fromutf8(data)) {
	case let s: str =>
		yield s;
	case =>
		json_error(sock, "502 Bad Gateway", "Probe output was not valid UTF-8");
		return;
	};
	header(sock, "200 OK", "application/json; charset=utf-8");
	if (ok) {
		write_text(sock, "{\"ok\":true,\"output\":");
	} else {
		write_text(sock, "{\"ok\":false,\"output\":");
	};
	json_string(sock, message);
	write_text(sock, "}");
};

fn serve_static(sock: net::socket, path: str, mime: str) void = {
	const file = match (os::open(path)) {
	case let file: io::file =>
		yield file;
	case let err: fs::error =>
		json_error(sock, "404 Not Found", "Web asset not found. Start ATHENA-04 from the project directory.");
		return;
	};
	defer io::close(file)!;
	header(sock, "200 OK", mime);
	io::copy(sock, file)!;
};

fn handle(sock: net::socket) void = {
	defer net::close(sock)!;
    // Read complete HTTP headers. Reject oversized requests and all request
    // bodies (the only mutations use zero-byte POST with URL path parameters).
    let buffer: [8192]u8 = [0...];
    let used = 0z;
    for (true) {
        if (used == len(buffer)) {
            json_error(sock, "431 Request Header Fields Too Large", "Header limit exceeded");
            return;
        };
        const n = match (io::read(sock, buffer[used..])) {
        case let n: size => yield n;
        case => return; // Client closed connection or read failed.
        };
        used += n;
        const candidate = match (strings::fromutf8(buffer[..used])) {
        case let text: str => yield text;
        case =>
            json_error(sock, "400 Bad Request", "Invalid header UTF-8");
            return;
        };
        if (strings::contains(candidate, "\r\n\r\n")) break;
    };
    const data = match (strings::fromutf8(buffer[..used])) {
    case let text: str => yield text;
    case => return;
    };
    const (method, tail) = strings::cut(data, " ");
    const (route, rest) = strings::cut(tail, " ");
    if (!strings::hasprefix(rest, "HTTP/1.1\r\n")) {
        json_error(sock, "400 Bad Request", "HTTP/1.1 required");
        return;
    };
    // Reject DNS-rebinding Host headers. Browser access is 127.0.0.1 only.
    if (!strings::contains(data, "\r\nHost: 127.0.0.1:8765\r\n")) {
        json_error(sock, "403 Forbidden", "Host must be 127.0.0.1:8765");
        return;
    };
    if (method == "POST") {
        // No permissive CORS. A non-simple custom header and exact Origin
        // prevent other sites from submitting registry writes with a browser.
        if (!strings::contains(data, "\r\nOrigin: http://127.0.0.1:8765\r\n")
            || !strings::contains(data, "\r\nX-Athena-Console: 1\r\n")
            || strings::contains(data, "\r\nTransfer-Encoding:")
            || strings::contains(data, "\r\nContent-Length: ")
                && !strings::contains(data, "\r\nContent-Length: 0\r\n")) {
            json_error(sock, "403 Forbidden", "Invalid mutation request origin or headers");
            return;
        };
        mutation_route(sock, route);
        return;
    };
    if (method != "GET") {
        json_error(sock, "405 Method Not Allowed", "GET or guarded POST only");
        return;
    };
    if (route == "/" || route == "/index.html") {
		serve_static(sock, "web/index.html", "text/html; charset=utf-8");
	} else if (route == "/app.js") {
		serve_static(sock, "web/app.js", "text/javascript; charset=utf-8");
	} else if (route == "/styles.css") {
		serve_static(sock, "web/styles.css", "text/css; charset=utf-8");
	} else if (route == "/api/status") {
		send_command(sock, "status", "");
	} else if (route == "/api/nodes") {
		send_command(sock, "nodes", "");
	} else if (strings::hasprefix(route, "/api/check/")) {
		const name = strings::trimprefix(route, "/api/check/");
		if (valid_name(name)) {
			send_command(sock, "check", name);
		} else {
			json_error(sock, "400 Bad Request", "Invalid node name");
		};
	} else {
		json_error(sock, "404 Not Found", "Unknown endpoint");
	};
};

export fn main() void = {
	const listener = tcp::listen(ip::LOCAL_V4, PORT)!;
	defer net::close(listener)!;
	fmt::printfln("ATHENA-04 / WEB CONSOLE v0.6.2 / WINDOWS READY")!;
	fmt::printfln("Open http://127.0.0.1:{} in your browser", PORT)!;
	fmt::println("Listening on loopback only. Ctrl+C to stop.")!;
	for (true) {
		const conn = tcp::accept(listener)!;
		handle(conn);
	};
};
