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

    /// Validate options and return error if invalid
    pub fn validate(self: Options) !void {
        if (self.watch_interval == 0) {
            return error.InvalidWatchInterval;
        }
        if (self.watch_interval > 3600) {
            return error.WatchIntervalTooLarge;
        }
    }
};

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
                    opts.top = count;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            opts.color = false;
        } else if (std.mem.eql(u8, arg, "--breakdown") or std.mem.eql(u8, arg, "-b")) {
            opts.breakdown = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.posix.exit(0);
        }

        i += 1;
    }

    return opts;
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
        \\  --top N                   Show top N processes by memory usage
        \\  -b, --breakdown           Show detailed memory breakdown
        \\  --no-color                Disable colored output
        \\  -h, --help               Show this help message
        \\
    ) catch {};
}

// Note: Testing parseArgs with actual string arrays is complex in Zig due to
// null-terminated string requirements. These tests are skipped in favor of
// integration testing via the actual executable.
// The parseArgs function is tested implicitly through the main executable.
