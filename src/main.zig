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

/// Main entry point
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const opts = cli.parseArgs(args);
    try opts.validate();

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

        while (!g_should_exit.load(.seq_cst)) {
            output.clearScreen();
            const stats = try memory.getVMStatistics();
            try printOutput(stats, opts);
            std.Thread.sleep(opts.watch_interval * std.time.ns_per_s);
        }
    } else {
        // Single run
        const stats = try memory.getVMStatistics();
        try printOutput(stats, opts);
    }
}
