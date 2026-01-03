//! Command-line argument parsing.
//!
//! This module handles parsing command-line arguments and building
//! an Options structure for the application.

const std = @import("std");

/// Command-line options
pub const Options = struct {
    watch: bool = false,
    watch_interval: u64 = 2,
    compact: bool = false,
    top: ?usize = null,
    color: bool = true,
    breakdown: bool = false,
    json: bool = false,
    interactive: bool = false,
    detect_leaks: bool = false,

    /// Validate options and return error if invalid
    pub fn validate(self: Options) !void {
        if (self.watch_interval == 0) {
            return error.InvalidWatchInterval;
        }
        if (self.watch_interval > 3600) {
            return error.WatchIntervalTooLarge;
        }
        if (self.top) |count| {
            if (count == 0) {
                return error.InvalidTopCount;
            }
            if (count > 100) {
                return error.TopCountTooLarge;
            }
        }
    }
};

test "Options validate accepts valid options" {
    var opts = Options{
        .watch_interval = 5,
        .top = 10,
    };
    try opts.validate();
}

test "Options validate rejects zero watch interval" {
    var opts = Options{
        .watch_interval = 0,
    };
    try std.testing.expectError(error.InvalidWatchInterval, opts.validate());
}

test "Options validate rejects too large watch interval" {
    var opts = Options{
        .watch_interval = 3601,
    };
    try std.testing.expectError(error.WatchIntervalTooLarge, opts.validate());
}

test "Options validate rejects zero top count" {
    var opts = Options{
        .top = 0,
    };
    try std.testing.expectError(error.InvalidTopCount, opts.validate());
}

test "Options validate rejects too large top count" {
    var opts = Options{
        .top = 101,
    };
    try std.testing.expectError(error.TopCountTooLarge, opts.validate());
}

test "Options validate accepts valid top count" {
    var opts = Options{
        .top = 50,
    };
    try opts.validate();
}

// Version constant
pub const VERSION = "0.2.0";

/// Parse command-line arguments
pub fn parseArgs(args: [][:0]u8) Options {
    var opts = Options{};
    var i: usize = 1;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
            opts.watch = true;
            // Check for interval
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(u64, args[i + 1], 10)) |interval| {
                    opts.watch_interval = interval;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--compact") or std.mem.eql(u8, arg, "-c")) {
            opts.compact = true;
        } else if (std.mem.eql(u8, arg, "--top")) {
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(usize, args[i + 1], 10)) |count| {
                    if (count > 0 and count <= 100) {
                        opts.top = count;
                    } else {
                        const stderr_file = std.fs.File{ .handle = std.posix.STDERR_FILENO };
                        var buf: [256]u8 = undefined;
                        if (std.fmt.bufPrint(&buf, "Warning: --top count must be between 1 and 100, got {d}\n", .{count})) |msg| {
                            _ = stderr_file.writeAll(msg) catch {};
                        } else |_| {}
                    }
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            opts.color = false;
        } else if (std.mem.eql(u8, arg, "--breakdown") or std.mem.eql(u8, arg, "-b")) {
            opts.breakdown = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            opts.json = true;
        } else if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            opts.interactive = true;
        } else if (std.mem.eql(u8, arg, "--detect-leaks")) {
            opts.detect_leaks = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            std.posix.exit(0);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.posix.exit(0);
        } else {
            // Warn about unknown arguments
            const stderr_file = std.fs.File{ .handle = std.posix.STDERR_FILENO };
            var buf: [256]u8 = undefined;
            if (std.fmt.bufPrint(&buf, "Warning: unknown argument '{s}'\n", .{arg})) |msg| {
                _ = stderr_file.writeAll(msg) catch {};
            } else |_| {}
        }

        i += 1;
    }

    return opts;
}

/// Print version information
fn printVersion() void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout_file.writeAll("ramjet version " ++ VERSION ++ "\n") catch {};
}

/// Print help message
fn printHelp() void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout_file.writeAll(
        \\Usage: ramjet [OPTIONS]
        \\
        \\Options:
        \\  -w, --watch [SECONDS]    Watch mode (update every N seconds, default: 2)
        \\  -c, --compact             Compact single-line output
        \\  --top N                   Show top N processes by memory usage (1-100)
        \\  -b, --breakdown           Show detailed memory breakdown
        \\  --json                     Output in JSON format
        \\  -i, --interactive          Interactive TUI mode
        \\  --detect-leaks             Detect memory leaks (requires watch/interactive mode)
        \\  --no-color                Disable colored output
        \\  -v, --version             Show version information
        \\  -h, --help               Show this help message
        \\
    ) catch {};
}

// Note: Testing parseArgs with actual string arrays is complex in Zig due to
// null-terminated string requirements. These tests are skipped in favor of
// integration testing via the actual executable.
// The parseArgs function is tested implicitly through the main executable.
