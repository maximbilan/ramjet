//! Command-line argument parsing.
//!
//! This module handles parsing command-line arguments and building
//! an Options structure for the application.

const std = @import("std");

/// Sort mode for process listing
pub const SortMode = enum {
    memory, // Sort by memory (descending)
    pid,    // Sort by PID (ascending)
    name,   // Sort by name (alphabetical)
};

/// Export format
pub const ExportFormat = enum {
    json,
    csv,
};

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
    min_memory: ?u64 = null,      // Minimum memory in bytes to show process
    sort: SortMode = .memory,      // Sort mode for processes
    quiet: bool = false,           // Quiet mode (suppress non-essential output)
    export_format: ?ExportFormat = null,  // Export format (JSON/CSV)

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
pub const VERSION = "0.2.1";

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
                        } else |_| {
                            // Buffer too small - unlikely but handle gracefully
                            _ = stderr_file.writeAll("Warning: --top count out of range\n") catch {};
                        }
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
        } else if (std.mem.eql(u8, arg, "--min-memory")) {
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(u64, args[i + 1], 10)) |min_bytes| {
                    opts.min_memory = min_bytes;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--sort")) {
            if (i + 1 < args.len) {
                const sort_str = args[i + 1];
                if (std.mem.eql(u8, sort_str, "memory")) {
                    opts.sort = .memory;
                } else if (std.mem.eql(u8, sort_str, "pid")) {
                    opts.sort = .pid;
                } else if (std.mem.eql(u8, sort_str, "name")) {
                    opts.sort = .name;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            opts.quiet = true;
        } else if (std.mem.eql(u8, arg, "--export")) {
            if (i + 1 < args.len) {
                const format_str = args[i + 1];
                if (std.mem.eql(u8, format_str, "json")) {
                    opts.export_format = .json;
                } else if (std.mem.eql(u8, format_str, "csv")) {
                    opts.export_format = .csv;
                }
                i += 1;
            }
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
            } else |_| {
                // Buffer too small - unlikely but handle gracefully
                _ = stderr_file.writeAll("Warning: unknown argument\n") catch {};
            }
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
        \\                            Example: ramjet --watch 5
        \\  -c, --compact             Compact single-line output
        \\                            Example: ramjet --compact
        \\  --top N                   Show top N processes by memory usage (1-100)
        \\                            Example: ramjet --top 10
        \\  --min-memory BYTES        Filter processes with memory >= BYTES
        \\                            Example: ramjet --top 20 --min-memory 104857600 (100MB)
        \\  --sort MODE               Sort processes: memory, pid, or name
        \\                            Example: ramjet --top 10 --sort name
        \\  -b, --breakdown           Show detailed memory breakdown
        \\                            Example: ramjet --breakdown
        \\  --json                     Output in JSON format
        \\                            Example: ramjet --json
        \\  --export FORMAT            Export to JSON or CSV file
        \\                            Example: ramjet --export json > output.json
        \\                            Example: ramjet --export csv > output.csv
        \\  -i, --interactive          Interactive TUI mode
        \\                            Example: ramjet --interactive
        \\  --detect-leaks             Detect memory leaks (requires watch/interactive mode)
        \\                            Example: ramjet --watch --detect-leaks
        \\  -q, --quiet                Quiet mode (suppress non-essential output)
        \\                            Example: ramjet --quiet --json
        \\  --no-color                Disable colored output
        \\                            Example: ramjet --no-color
        \\  -v, --version             Show version information
        \\  -h, --help                Show this help message
        \\
        \\Examples:
        \\  ramjet                                    # Basic memory stats
        \\  ramjet --watch 3 --top 5                  # Watch mode, top 5 processes every 3s
        \\  ramjet --top 20 --min-memory 52428800     # Top 20 processes using >= 50MB
        \\  ramjet --top 10 --sort name               # Top 10 processes sorted by name
        \\  ramjet --json --quiet > stats.json        # JSON output, quiet mode
        \\  ramjet --export csv > processes.csv       # Export to CSV
        \\
    ) catch {};
}

// Note: Testing parseArgs with actual string arrays is complex in Zig due to
// null-terminated string requirements. These tests are skipped in favor of
// integration testing via the actual executable.
// The parseArgs function is tested implicitly through the main executable.
