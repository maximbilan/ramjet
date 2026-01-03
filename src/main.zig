//! ramjet - A fast, lightweight CLI tool for macOS that reports system-wide RAM usage.
//!
//! This tool uses Mach APIs to query memory statistics directly from the kernel,
//! providing accurate and fast memory information without external dependencies.
//!
//! Features:
//! - Zero heap allocations (stack-only)
//! - Direct Mach API integration
//! - Process memory monitoring
//! - Memory pressure indicators
//! - Watch mode for continuous monitoring

const std = @import("std");
const builtin = @import("builtin");
const memory = @import("memory.zig");
const cli = @import("cli.zig");
const output = @import("output.zig");
const tui = @import("tui.zig");
const leak_detector = @import("leak_detector.zig");
const process = @import("process.zig");
const format = @import("format.zig");
const colors = @import("colors.zig");

// Only compile on macOS
comptime {
    if (builtin.os.tag != .macos) {
        @compileError("This program only supports macOS");
    }
}

// Global flag for signal handling
var g_should_exit: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn signalHandler(sig: c_int) callconv(.c) void {
    _ = sig;
    g_should_exit.store(true, .seq_cst);
}

/// Print output based on options
fn printOutput(stats: memory.MemoryStats, opts: cli.Options) !void {
    if (opts.json) {
        try output.printJson(stats, opts);
    } else if (opts.compact) {
        try output.printCompact(stats, opts);
    } else {
        try output.printMemoryStats(stats, opts);
    }

    if (opts.breakdown and !opts.json) {
        try output.printBreakdown(stats, opts);
    }

    if (opts.top) |count| {
        try output.printTopProcesses(count, opts);
    }
}

/// Print leaks in watch mode
fn printLeaks(leaks: []const leak_detector.LeakInfo, leak_count: usize, opts: cli.Options) !void {
    if (leak_count == 0) return;

    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [512]u8 = undefined;

    const reset = if (opts.color) colors.Color.RESET else "";
    const red = if (opts.color) colors.Color.RED else "";

    const header = try std.fmt.bufPrint(&output_buf, "\n{s}⚠ Potential Memory Leaks:{s}\n", .{ red, reset });
    try stdout_file.writeAll(header);

    for (leaks[0..leak_count]) |leak| {
        var growth_buf: [32]u8 = undefined;
        var old_buf: [32]u8 = undefined;
        var new_buf: [32]u8 = undefined;

        const growth_str = try format.formatBytes(leak.growth, &growth_buf);
        const old_str = try format.formatBytes(leak.old_size, &old_buf);
        const new_str = try format.formatBytes(leak.new_size, &new_buf);

        const name = leak.name[0..leak.name_len];
        const line = try std.fmt.bufPrint(
            &output_buf,
            "  {s}{d}{s} {s}: {s} → {s} (+{s} over {d}s)\n",
            .{ red, leak.pid, reset, name, old_str, new_str, growth_str, leak.time_span },
        );
        try stdout_file.writeAll(line);
    }
}

/// Main entry point
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const opts = cli.parseArgs(args);
    try opts.validate();

    // Interactive TUI mode
    if (opts.interactive) {
        try tui.runInteractive(opts, opts.detect_leaks, &g_should_exit);
        return;
    }

    if (opts.watch) {
        // Watch mode with signal handling
        g_should_exit.store(false, .seq_cst);

        // Set up signal handler
        const mask = std.posix.sigemptyset();
        const act = std.posix.Sigaction{
            .handler = .{ .handler = signalHandler },
            .mask = mask,
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &act, null);
        std.posix.sigaction(std.posix.SIG.TERM, &act, null);

        // Leak detection setup
        var detector = if (opts.detect_leaks) leak_detector.LeakDetector.init() else undefined;
        var processes_buffer: [process.MAX_PROCESS_BUFFER]process.ProcessInfo = undefined;
        var leak_buffer: [50]leak_detector.LeakInfo = undefined;

        while (!g_should_exit.load(.seq_cst)) {
            output.clearScreen();
            const stats = try memory.getVMStatistics();
            try printOutput(stats, opts);

            // Leak detection in watch mode
            if (opts.detect_leaks) {
                const process_count = try process.getProcessList(&processes_buffer);
                detector.addSnapshot(&processes_buffer, process_count);
                const leak_count = detector.detectLeaks(&leak_buffer, &processes_buffer);
                try printLeaks(&leak_buffer, leak_count, opts);
            }

            std.Thread.sleep(opts.watch_interval * std.time.ns_per_s);
        }
    } else {
        // Single run
        const stats = try memory.getVMStatistics();
        try printOutput(stats, opts);

        // Leak detection in single run (needs at least 2 samples)
        if (opts.detect_leaks) {
            const stderr_file = std.fs.File{ .handle = std.posix.STDERR_FILENO };
            _ = stderr_file.writeAll("Warning: --detect-leaks requires watch or interactive mode\n") catch {};
        }
    }
}
