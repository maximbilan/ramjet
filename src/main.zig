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

/// Main entry point
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const opts = cli.parseArgs(args);

    if (opts.watch) {
        // Watch mode
        while (true) {
            output.clearScreen();

            const stats = try memory.getVMStatistics();

            if (opts.compact) {
                try output.printCompact(stats, opts);
            } else {
                try output.printMemoryStats(stats, opts);
            }

            if (opts.breakdown) {
                try output.printBreakdown(stats, opts);
            }

            if (opts.top) |count| {
                try output.printTopProcesses(count, opts);
            }

            // Sleep for interval
            std.Thread.sleep(opts.watch_interval * std.time.ns_per_s);
        }
    } else {
        // Single run
        const stats = try memory.getVMStatistics();

        if (opts.compact) {
            try output.printCompact(stats, opts);
        } else {
            try output.printMemoryStats(stats, opts);
        }

        if (opts.breakdown) {
            try output.printBreakdown(stats, opts);
        }

        if (opts.top) |count| {
            try output.printTopProcesses(count, opts);
        }
    }
}
