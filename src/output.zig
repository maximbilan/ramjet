//! Output formatting and printing functions.
//!
//! This module provides functions for printing memory statistics,
//! process lists, and formatted output to the terminal.

const std = @import("std");
const memory = @import("memory.zig");
const process = @import("process.zig");
const format = @import("format.zig");
const colors = @import("colors.zig");
const cli = @import("cli.zig");

/// Print compact single-line output
pub fn printCompact(stats: memory.MemoryStats, opts: cli.Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [512]u8 = undefined;

    var total_buf: [16]u8 = undefined;
    var used_buf: [16]u8 = undefined;
    var free_buf: [16]u8 = undefined;
    var cached_buf: [16]u8 = undefined;

    const total_str = try format.formatBytesCompact(stats.total, &total_buf);
    const used_str = try format.formatBytesCompact(stats.used, &used_buf);
    const free_str = try format.formatBytesCompact(stats.free, &free_buf);
    const cached_str = try format.formatBytesCompact(stats.cached, &cached_buf);

    const usage_percent = stats.usagePercent();

    const color = colors.getUsageColor(usage_percent, opts.color);
    const reset = if (opts.color) colors.Color.RESET else "";

    const line = try std.fmt.bufPrint(
        &output_buf,
        "{s}{s}{s} total, {s}{s}{s} used ({d:.1}%), {s} free, {s} cached{s}\n",
        .{ color, total_str, reset, color, used_str, reset, usage_percent, free_str, cached_str, reset },
    );

    try stdout_file.writeAll(line);
}

/// Print detailed memory breakdown
pub fn printBreakdown(stats: memory.MemoryStats, opts: cli.Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [256]u8 = undefined;

    var active_buf: [32]u8 = undefined;
    var wired_buf: [32]u8 = undefined;
    var inactive_buf: [32]u8 = undefined;
    var speculative_buf: [32]u8 = undefined;
    var compressed_buf: [32]u8 = undefined;

    const active_str = try format.formatBytes(stats.active, &active_buf);
    const wired_str = try format.formatBytes(stats.wired, &wired_buf);
    const inactive_str = try format.formatBytes(stats.inactive, &inactive_buf);
    const speculative_str = try format.formatBytes(stats.speculative, &speculative_buf);
    const compressed_str = try format.formatBytes(stats.compressed, &compressed_buf);

    const reset = if (opts.color) colors.Color.RESET else "";
    const bold = if (opts.color) colors.Color.BOLD else "";

    // Empty line before section
    try stdout_file.writeAll("\n");

    const header = try std.fmt.bufPrint(&output_buf, "{s}Memory Breakdown:{s}\n", .{ bold, reset });
    try stdout_file.writeAll(header);

    // Find maximum width for alignment
    const max_width = @max(
        @max(active_str.len, wired_str.len),
        @max(@max(inactive_str.len, speculative_str.len), compressed_str.len),
    );

    // Helper to pad string to right-align
    var padded_buf: [64]u8 = undefined;

    const padAndPrint = struct {
        fn pad(str: []const u8, width: usize, buf: []u8) []const u8 {
            if (str.len >= width) return str;
            const pad_len = width - str.len;
            @memset(buf[0..pad_len], ' ');
            @memcpy(buf[pad_len..][0..str.len], str);
            return buf[0..width];
        }
    }.pad;

    const active_padded = padAndPrint(active_str, max_width, &padded_buf);
    const line1 = try std.fmt.bufPrint(&output_buf, "  Active:      {s}\n", .{active_padded});
    try stdout_file.writeAll(line1);

    const wired_padded = padAndPrint(wired_str, max_width, &padded_buf);
    const line2 = try std.fmt.bufPrint(&output_buf, "  Wired:       {s}\n", .{wired_padded});
    try stdout_file.writeAll(line2);

    const inactive_padded = padAndPrint(inactive_str, max_width, &padded_buf);
    const line3 = try std.fmt.bufPrint(&output_buf, "  Inactive:    {s}\n", .{inactive_padded});
    try stdout_file.writeAll(line3);

    const speculative_padded = padAndPrint(speculative_str, max_width, &padded_buf);
    const line4 = try std.fmt.bufPrint(&output_buf, "  Speculative: {s}\n", .{speculative_padded});
    try stdout_file.writeAll(line4);

    const compressed_padded = padAndPrint(compressed_str, max_width, &padded_buf);
    const line5 = try std.fmt.bufPrint(&output_buf, "  Compressed:  {s}\n", .{compressed_padded});
    try stdout_file.writeAll(line5);
}

/// Print top processes by memory usage.
/// Collects all accessible processes, sorts them by memory usage, and displays the top N.
pub fn printTopProcesses(count: usize, opts: cli.Options) !void {
    var processes: [process.MAX_PROCESS_BUFFER]process.ProcessInfo = undefined;
    const actual_count = try process.getProcessList(&processes);

    if (actual_count == 0) {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout_file.writeAll("(Unable to access process information - may need root privileges)\n");
        return;
    }

    // Sort by resident size (descending)
    process.sortProcessesByMemory(processes[0..actual_count]);

    // Only display the top 'count' processes
    const display_count = @min(count, actual_count);

    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [512]u8 = undefined;
    var mem_buf: [32]u8 = undefined;

    const reset = if (opts.color) colors.Color.RESET else "";
    const bold = if (opts.color) colors.Color.BOLD else "";
    const cyan = if (opts.color) colors.Color.CYAN else "";

    // Empty line before section
    try stdout_file.writeAll("\n");

    const header = try std.fmt.bufPrint(&output_buf, "{s}Top {d} Processes by Memory:{s}\n", .{ bold, display_count, reset });
    try stdout_file.writeAll(header);

    // Find the maximum width of memory strings for alignment
    var max_mem_width: usize = 0;
    for (0..display_count) |i| {
        const proc = processes[i];
        const mem_str = try format.formatBytes(proc.resident_size, &mem_buf);
        max_mem_width = @max(max_mem_width, mem_str.len);
    }

    // Helper buffers for padding
    var mem_padded_buf: [64]u8 = undefined;
    var name_padded_buf: [64]u8 = undefined;

    for (0..display_count) |i| {
        const proc = processes[i];
        const mem_str = try format.formatBytes(proc.resident_size, &mem_buf);
        var name = proc.name[0..proc.name_len];

        // Truncate name if too long
        if (name.len > process.MAX_PROCESS_NAME_WIDTH) {
            @memcpy(name_padded_buf[0..process.MAX_PROCESS_NAME_WIDTH-3], name[0..process.MAX_PROCESS_NAME_WIDTH-3]);
            @memcpy(name_padded_buf[process.MAX_PROCESS_NAME_WIDTH-3..process.MAX_PROCESS_NAME_WIDTH], "...");
            name = name_padded_buf[0..process.MAX_PROCESS_NAME_WIDTH];
        }

        // Pad name to fixed width (left-aligned)
        var name_padded: []const u8 = name;
        if (name.len < process.MAX_PROCESS_NAME_WIDTH) {
            @memcpy(name_padded_buf[0..name.len], name);
            @memset(name_padded_buf[name.len..process.MAX_PROCESS_NAME_WIDTH], ' ');
            name_padded = name_padded_buf[0..process.MAX_PROCESS_NAME_WIDTH];
        }

        // Right-align memory value
        const pad_len = if (mem_str.len < max_mem_width) max_mem_width - mem_str.len else 0;
        var mem_padded: []const u8 = mem_str;
        if (pad_len > 0) {
            @memset(mem_padded_buf[0..pad_len], ' ');
            @memcpy(mem_padded_buf[pad_len..][0..mem_str.len], mem_str);
            mem_padded = mem_padded_buf[0..max_mem_width];
        }

        const line = try std.fmt.bufPrint(
            &output_buf,
            "  {s}{d:>6}{s}  {s}{s}{s}  {s}{s}\n",
            .{ cyan, proc.pid, reset, cyan, name_padded, reset, mem_padded, reset },
        );
        try stdout_file.writeAll(line);
    }
}

/// Print memory statistics in a formatted table
pub fn printMemoryStats(stats: memory.MemoryStats, opts: cli.Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [256]u8 = undefined;

    // Format each value
    var total_buf: [32]u8 = undefined;
    var used_buf: [32]u8 = undefined;
    var free_buf: [32]u8 = undefined;
    var cached_buf: [32]u8 = undefined;
    var swap_used_buf: [32]u8 = undefined;
    var swap_total_buf: [32]u8 = undefined;

    const total_str = try format.formatBytes(stats.total, &total_buf);
    const used_str = try format.formatBytes(stats.used, &used_buf);
    const free_str = try format.formatBytes(stats.free, &free_buf);
    const cached_str = try format.formatBytes(stats.cached, &cached_buf);
    const swap_used_str = try format.formatBytes(stats.swap_used, &swap_used_buf);
    const swap_total_str = try format.formatBytes(stats.swap_total, &swap_total_buf);

    // Calculate usage percentage
    const usage_percent = stats.usagePercent();

    const usage_color = colors.getUsageColor(usage_percent, opts.color);
    const reset = if (opts.color) colors.Color.RESET else "";
    const bold = if (opts.color) colors.Color.BOLD else "";
    const pressure_color = colors.getPressureColor(stats.pressure, opts.color);
    const pressure_str = stats.pressure.toString();

    // Print formatted output
    const line1 = try std.fmt.bufPrint(&output_buf, "Total:    {s}\n", .{total_str});
    try stdout_file.writeAll(line1);

    const line2 = try std.fmt.bufPrint(
        &output_buf,
        "Used:     {s}{s}{s} ({s}{d:.1}%{s})\n",
        .{ usage_color, used_str, reset, usage_color, usage_percent, reset },
    );
    try stdout_file.writeAll(line2);

    const line3 = try std.fmt.bufPrint(&output_buf, "Free:     {s}\n", .{free_str});
    try stdout_file.writeAll(line3);

    const line4 = try std.fmt.bufPrint(&output_buf, "Cached:   {s}\n", .{cached_str});
    try stdout_file.writeAll(line4);

    const line5 = try std.fmt.bufPrint(
        &output_buf,
        "Swap:     {s} / {s}\n",
        .{ swap_used_str, swap_total_str },
    );
    try stdout_file.writeAll(line5);

    const line6 = try std.fmt.bufPrint(
        &output_buf,
        "Pressure: {s}{s}{s}{s}{s}\n",
        .{ pressure_color, bold, pressure_str, reset, reset },
    );
    try stdout_file.writeAll(line6);
}

/// Print memory statistics in JSON format
pub fn printJson(stats: memory.MemoryStats, _: cli.Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&output_buf);
    const writer = stream.writer();

    try writer.writeAll("{\n");
    try writer.print("  \"total\": {d},\n", .{stats.total});
    try writer.print("  \"used\": {d},\n", .{stats.used});
    try writer.print("  \"free\": {d},\n", .{stats.free});
    try writer.print("  \"cached\": {d},\n", .{stats.cached});
    try writer.print("  \"usage_percent\": {d:.2},\n", .{stats.usagePercent()});
    try writer.print("  \"active\": {d},\n", .{stats.active});
    try writer.print("  \"wired\": {d},\n", .{stats.wired});
    try writer.print("  \"inactive\": {d},\n", .{stats.inactive});
    try writer.print("  \"speculative\": {d},\n", .{stats.speculative});
    try writer.print("  \"compressed\": {d},\n", .{stats.compressed});
    try writer.print("  \"swap_used\": {d},\n", .{stats.swap_used});
    try writer.print("  \"swap_total\": {d},\n", .{stats.swap_total});
    try writer.print("  \"pressure\": \"{s}\"\n", .{stats.pressure.toString()});
    try writer.writeAll("}\n");

    try stdout_file.writeAll(stream.getWritten());
}

/// Clear screen (for watch mode)
pub fn clearScreen() void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout_file.writeAll("\x1b[2J\x1b[H") catch {};
}
