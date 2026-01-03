//! Terminal User Interface (TUI) for interactive mode.
//!
//! This module provides an interactive terminal interface with keyboard controls
//! for navigating and viewing memory statistics.

const std = @import("std");
const c = std.c;
const memory = @import("memory.zig");
const process = @import("process.zig");
const format = @import("format.zig");
const colors = @import("colors.zig");
const cli = @import("cli.zig");
const leak_detector = @import("leak_detector.zig");

/// TUI state
pub const TUIState = struct {
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    sort_by: SortMode = .memory,
    show_leaks: bool = false,
    show_help: bool = false,
    process_count: usize = 20,
};

/// Sort modes
pub const SortMode = enum {
    memory,
    pid,
    name,
};

/// ANSI escape codes for terminal control
const ESC = "\x1b";
const CLEAR_SCREEN = ESC ++ "[2J" ++ ESC ++ "[H";
const HIDE_CURSOR = ESC ++ "[?25l";
const SHOW_CURSOR = ESC ++ "[?25h";
const SAVE_CURSOR = ESC ++ "[s";
const RESTORE_CURSOR = ESC ++ "[u";

// Store original terminal state for restoration
var original_termios: ?std.posix.termios = null;

/// Enable raw terminal mode - keys are read immediately without pressing Return
pub fn enableRawMode() !void {
    const stdin_fd = std.posix.STDIN_FILENO;

    // Save original terminal state
    original_termios = try std.posix.tcgetattr(stdin_fd);

    // Get current terminal state
    var termios = original_termios.?;

    // On macOS, termios.lflag is a struct with boolean fields
    // We need to disable canonical mode and echo for immediate key input

    // Disable canonical mode (line buffering) - this allows immediate key reading
    // Without this, terminal waits for Enter before sending input
    // Try different field name variations for macOS
    const lflag_type = @TypeOf(termios.lflag);
    if (@hasField(lflag_type, "ICANON")) {
        @field(termios.lflag, "ICANON") = false;
    } else if (@hasField(lflag_type, "icanon")) {
        @field(termios.lflag, "icanon") = false;
    } else {
        // If it's an integer bitfield, use bitwise operations
        // ICANON is typically bit 1 (0x00000002), ECHO is bit 3 (0x00000008)
        if (@typeInfo(lflag_type) == .Int) {
            const ICANON: @TypeOf(termios.lflag) = 0x00000002;
            const ECHO: @TypeOf(termios.lflag) = 0x00000008;
            termios.lflag &= ~ICANON;
            termios.lflag &= ~ECHO;
        }
    }

    // Disable echo - we don't want keys to be printed to screen
    if (@hasField(lflag_type, "ECHO")) {
        @field(termios.lflag, "ECHO") = false;
    } else if (@hasField(lflag_type, "echo")) {
        @field(termios.lflag, "echo") = false;
    }

    // Set VMIN and VTIME for immediate character input (non-blocking)
    // VMIN = 0: don't wait for any characters
    // VTIME = 0: return immediately if no data available
    // On POSIX systems, VMIN is typically index 4, VTIME is index 5
    if (termios.cc.len > 4) {
        termios.cc[4] = 0; // VMIN - minimum number of characters
    }
    if (termios.cc.len > 5) {
        termios.cc[5] = 0; // VTIME - timeout in deciseconds
    }

    // Apply the new terminal settings
    try std.posix.tcsetattr(stdin_fd, .FLUSH, termios);
}

/// Disable raw terminal mode - restore original terminal state
pub fn disableRawMode() void {
    if (original_termios) |orig| {
        const stdin_fd = std.posix.STDIN_FILENO;
        _ = std.posix.tcsetattr(stdin_fd, .FLUSH, orig) catch {};
        original_termios = null;
    }
}

/// Get terminal size
pub fn getTerminalSize() struct { width: u16, height: u16 } {
    // Use environment variables or default
    if (std.posix.getenv("COLUMNS")) |cols_str| {
        if (std.fmt.parseInt(u16, cols_str, 10)) |cols| {
            if (std.posix.getenv("LINES")) |lines_str| {
                if (std.fmt.parseInt(u16, lines_str, 10)) |lines| {
                    return .{ .width = cols, .height = lines };
                } else |_| {}
            }
            return .{ .width = cols, .height = 24 };
        } else |_| {}
    }
    return .{ .width = 80, .height = 24 }; // Default
}

/// Read a single character from stdin (non-blocking)
/// Uses a simple approach - in practice, the 200ms sleep in the main loop
/// makes this effectively non-blocking for the TUI
pub fn readChar() ?u8 {
    var buf: [1]u8 = undefined;
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };

    // Try to read - in raw mode with VMIN=0 and VTIME=0, this should return immediately
    // if no data is available. However, if it blocks, the main loop delay helps.
    const bytes_read = stdin_file.read(&buf) catch return null;
    if (bytes_read == 0) return null;
    return buf[0];
}

/// Read arrow key sequences
pub fn readKey() ?Key {
    const ch = readChar() orelse return null;

    if (ch == 27) { // ESC
        const ch2 = readChar() orelse return .escape;
        if (ch2 == '[') {
            const ch3 = readChar() orelse return .escape;
            return switch (ch3) {
                'A' => .arrow_up,
                'B' => .arrow_down,
                'C' => .arrow_right,
                'D' => .arrow_left,
                else => .escape,
            };
        }
        return .escape;
    }

    return switch (ch) {
        'q', 'Q' => .quit,
        'r', 'R' => .refresh,
        's', 'S' => .sort,
        'l', 'L' => .toggle_leaks,
        'h', 'H' => .help,
        '\n', '\r' => .enter,
        ' ' => .space,
        else => .unknown,
    };
}

/// Key types
pub const Key = enum {
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    quit,
    refresh,
    sort,
    toggle_leaks,
    help,
    enter,
    space,
    escape,
    unknown,
};

/// Sort processes based on current sort mode
pub fn sortProcesses(processes: []process.ProcessInfo, count: usize, mode: SortMode) void {
    switch (mode) {
        .memory => process.sortProcessesByMemory(processes[0..count]),
        .pid => {
            // Sort by PID
            std.sort.block(process.ProcessInfo, processes[0..count], {}, struct {
                fn lessThan(_: void, a: process.ProcessInfo, b: process.ProcessInfo) bool {
                    return a.pid < b.pid;
                }
            }.lessThan);
        },
        .name => {
            // Sort by name
            std.sort.block(process.ProcessInfo, processes[0..count], {}, struct {
                fn lessThan(_: void, a: process.ProcessInfo, b: process.ProcessInfo) bool {
                    const a_name = a.name[0..a.name_len];
                    const b_name = b.name[0..b.name_len];
                    return std.mem.order(u8, a_name, b_name) == .lt;
                }
            }.lessThan);
        },
    }
}

test "sortProcesses sorts by memory correctly" {
    var processes = [_]process.ProcessInfo{
        .{ .pid = 1, .name = undefined, .name_len = 0, .resident_size = 100 },
        .{ .pid = 2, .name = undefined, .name_len = 0, .resident_size = 300 },
        .{ .pid = 3, .name = undefined, .name_len = 0, .resident_size = 200 },
    };

    sortProcesses(&processes, 3, .memory);

    try std.testing.expectEqual(@as(u64, 300), processes[0].resident_size);
    try std.testing.expectEqual(@as(u64, 200), processes[1].resident_size);
    try std.testing.expectEqual(@as(u64, 100), processes[2].resident_size);
}

test "sortProcesses sorts by PID correctly" {
    var processes = [_]process.ProcessInfo{
        .{ .pid = 300, .name = undefined, .name_len = 0, .resident_size = 100 },
        .{ .pid = 100, .name = undefined, .name_len = 0, .resident_size = 200 },
        .{ .pid = 200, .name = undefined, .name_len = 0, .resident_size = 300 },
    };

    sortProcesses(&processes, 3, .pid);

    const mach = @import("mach.zig");
    try std.testing.expectEqual(@as(mach.pid_t, 100), processes[0].pid);
    try std.testing.expectEqual(@as(mach.pid_t, 200), processes[1].pid);
    try std.testing.expectEqual(@as(mach.pid_t, 300), processes[2].pid);
}

test "sortProcesses sorts by name correctly" {
    const name1 = "zebra".*;
    const name2 = "apple".*;
    const name3 = "banana".*;

    var processes = [_]process.ProcessInfo{
        .{ .pid = 1, .name = name1, .name_len = name1.len, .resident_size = 100 },
        .{ .pid = 2, .name = name2, .name_len = name2.len, .resident_size = 200 },
        .{ .pid = 3, .name = name3, .name_len = name3.len, .resident_size = 300 },
    };

    sortProcesses(&processes, 3, .name);

    try std.testing.expectEqualStrings("apple", processes[0].name[0..processes[0].name_len]);
    try std.testing.expectEqualStrings("banana", processes[1].name[0..processes[1].name_len]);
    try std.testing.expectEqualStrings("zebra", processes[2].name[0..processes[2].name_len]);
}

/// Render the TUI
pub fn render(
    stats: memory.MemoryStats,
    processes: []const process.ProcessInfo,
    process_count: usize,
    state: *TUIState,
    leaks: []const leak_detector.LeakInfo,
    leak_count: usize,
    opts: cli.Options,
) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const term_size = getTerminalSize();

    // Clear screen and hide cursor
    try stdout_file.writeAll(CLEAR_SCREEN);
    try stdout_file.writeAll(HIDE_CURSOR);

    // Header with memory stats
    var header_buf: [512]u8 = undefined;
    try renderHeader(stdout_file, stats, opts, &header_buf);

    // Memory leaks section (if enabled)
    if (state.show_leaks and leak_count > 0) {
        var leak_buf: [512]u8 = undefined;
        try renderLeaks(stdout_file, leaks, leak_count, opts, &leak_buf);
    }

    // Help screen (if enabled)
    if (state.show_help) {
        var help_buf: [512]u8 = undefined;
        try renderHelp(stdout_file, opts, &help_buf);
    }

    // Process list header
    var header_buf2: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf2, "\nProcesses (Sorted by: {s}) - {d} shown\n", .{ @tagName(state.sort_by), @min(process_count, state.process_count) });
    try stdout_file.writeAll(header);
    var line_buf: [200]u8 = undefined;
    const line = repeat('-', @min(term_size.width, line_buf.len), &line_buf);
    try stdout_file.writeAll(line);
    try stdout_file.writeAll("\n");

    // Process list
    const display_count = @min(process_count, state.process_count);
    const start_idx = @min(state.scroll_offset, process_count);
    const end_idx = @min(start_idx + display_count, process_count);

    var process_buf: [512]u8 = undefined;
    for (start_idx..end_idx) |i| {
        const proc = processes[i];
        const is_selected = (i == state.selected_index);

        try renderProcess(stdout_file, proc, is_selected, opts, &process_buf);
    }

    // Footer with controls
    var footer_buf: [256]u8 = undefined;
    try renderFooter(stdout_file, &footer_buf);
}

/// Render header with memory statistics
fn renderHeader(stdout_file: std.fs.File, stats: memory.MemoryStats, opts: cli.Options, buf: []u8) !void {
    var total_buf: [32]u8 = undefined;
    var used_buf: [32]u8 = undefined;
    var free_buf: [32]u8 = undefined;

    const total_str = try format.formatBytes(stats.total, &total_buf);
    const used_str = try format.formatBytes(stats.used, &used_buf);
    const free_str = try format.formatBytes(stats.free, &free_buf);

    const usage_percent = stats.usagePercent();
    const usage_color = colors.getUsageColor(usage_percent, opts.color);
    const reset = if (opts.color) colors.Color.RESET else "";
    const bold = if (opts.color) colors.Color.BOLD else "";

    const header = try std.fmt.bufPrint(
        buf,
        "{s}ramjet - Memory Monitor{s}\n",
        .{ bold, reset },
    );
    try stdout_file.writeAll(header);

    const line1 = try std.fmt.bufPrint(buf, "Total: {s}  ", .{total_str});
    try stdout_file.writeAll(line1);

    const line2 = try std.fmt.bufPrint(
        buf,
        "Used: {s}{s}{s} ({s}{d:.1}%{s})  ",
        .{ usage_color, used_str, reset, usage_color, usage_percent, reset },
    );
    try stdout_file.writeAll(line2);

    const line3 = try std.fmt.bufPrint(buf, "Free: {s}\n", .{free_str});
    try stdout_file.writeAll(line3);

    const pressure_str = stats.pressure.toString();
    const pressure_color = colors.getPressureColor(stats.pressure, opts.color);
    const line4 = try std.fmt.bufPrint(
        buf,
        "Pressure: {s}{s}{s}{s}{s}\n",
        .{ pressure_color, bold, pressure_str, reset, reset },
    );
    try stdout_file.writeAll(line4);
}

/// Repeat a character N times (helper for drawing lines)
fn repeat(char: u8, count: usize, buf: []u8) []const u8 {
    const actual_count = @min(count, buf.len);
    @memset(buf[0..actual_count], char);
    return buf[0..actual_count];
}

/// Render memory leaks section
fn renderLeaks(stdout_file: std.fs.File, leaks: []const leak_detector.LeakInfo, leak_count: usize, opts: cli.Options, buf: []u8) !void {
    const reset = if (opts.color) colors.Color.RESET else "";
    const red = if (opts.color) colors.Color.RED else "";

    const header = try std.fmt.bufPrint(buf, "\n{s}⚠ Potential Memory Leaks:{s}\n", .{ red, reset });
    try stdout_file.writeAll(header);

    var leak_line_buf: [256]u8 = undefined;
    for (leaks[0..leak_count]) |leak| {
        var growth_buf: [32]u8 = undefined;
        var old_buf: [32]u8 = undefined;
        var new_buf: [32]u8 = undefined;

        const growth_str = try format.formatBytes(leak.growth, &growth_buf);
        const old_str = try format.formatBytes(leak.old_size, &old_buf);
        const new_str = try format.formatBytes(leak.new_size, &new_buf);

        const name = leak.name[0..leak.name_len];
        const line = try std.fmt.bufPrint(
            &leak_line_buf,
            "  {s}{d}{s} {s}: {s} -> {s} (+{s} over {d}s)\n",
            .{ red, leak.pid, reset, name, old_str, new_str, growth_str, leak.time_span },
        );
        try stdout_file.writeAll(line);
    }
}

/// Render a single process line
fn renderProcess(stdout_file: std.fs.File, proc: process.ProcessInfo, selected: bool, opts: cli.Options, buf: []u8) !void {
    var mem_buf: [32]u8 = undefined;
    const mem_str = try format.formatBytes(proc.resident_size, &mem_buf);

    const reset = if (opts.color) colors.Color.RESET else "";
    const cyan = if (opts.color) colors.Color.CYAN else "";
    const reverse = if (opts.color) ESC ++ "[7m" else "";
    const normal = if (opts.color) ESC ++ "[0m" else "";

    const name = proc.name[0..proc.name_len];
    var name_display: [process.MAX_PROCESS_NAME_WIDTH]u8 = undefined;
    const name_len = @min(name.len, name_display.len);
    @memcpy(name_display[0..name_len], name[0..name_len]);
    if (name_len < name_display.len) {
        @memset(name_display[name_len..], ' ');
    }

    const marker = if (selected) ">" else " ";
    const style = if (selected) reverse else "";
    const style_end = if (selected) normal else "";

    const line = try std.fmt.bufPrint(
        buf,
        "{s}{s}{s} {s}{d:>6}{s}  {s}  {s}{s}\n",
        .{ style, marker, style_end, cyan, proc.pid, reset, name_display[0..process.MAX_PROCESS_NAME_WIDTH], mem_str, reset },
    );
    try stdout_file.writeAll(line);
}

/// Render footer with controls
fn renderFooter(stdout_file: std.fs.File, buf: []u8) !void {
    const footer = try std.fmt.bufPrint(
        buf,
        "\nControls: [↑↓] Navigate  [s] Sort  [l] Toggle Leaks  [r] Refresh  [q] Quit  [h] Help\n",
        .{},
    );
    try stdout_file.writeAll(footer);
}

/// Render help screen
fn renderHelp(stdout_file: std.fs.File, opts: cli.Options, buf: []u8) !void {
    const reset = if (opts.color) colors.Color.RESET else "";
    const bold = if (opts.color) colors.Color.BOLD else "";
    const cyan = if (opts.color) colors.Color.CYAN else "";

    const help_text = try std.fmt.bufPrint(
        buf,
        "\n{s}Keyboard Controls:{s}\n",
        .{ bold, reset },
    );
    try stdout_file.writeAll(help_text);

    var help_line_buf: [256]u8 = undefined;

    // Line 1: Arrow keys
    const line1 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}↑{s} / {s}↓{s}     Navigate up/down through process list\n",
        .{ cyan, reset, cyan, reset },
    );
    try stdout_file.writeAll(line1);

    // Line 2: Sort
    const line2 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}s{s}              Cycle sort mode (memory -> PID -> name)\n",
        .{ cyan, reset },
    );
    try stdout_file.writeAll(line2);

    // Line 3: Toggle leaks
    const line3 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}l{s}              Toggle leak detection display\n",
        .{ cyan, reset },
    );
    try stdout_file.writeAll(line3);

    // Line 4: Refresh
    const line4 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}r{s}              Refresh data immediately\n",
        .{ cyan, reset },
    );
    try stdout_file.writeAll(line4);

    // Line 5: Help
    const line5 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}h{s}              Toggle this help screen\n",
        .{ cyan, reset },
    );
    try stdout_file.writeAll(line5);

    // Line 6: Quit
    const line6 = try std.fmt.bufPrint(
        &help_line_buf,
        "  {s}q{s} / {s}ESC{s}     Quit and return to terminal\n",
        .{ cyan, reset, cyan, reset },
    );
    try stdout_file.writeAll(line6);

    // Line 7: Empty
    try stdout_file.writeAll("\n");

    // Line 8: Note
    const line8 = try std.fmt.bufPrint(
        &help_line_buf,
        "Note: Keys are detected immediately - no need to press Enter!\n",
        .{},
    );
    try stdout_file.writeAll(line8);
}

/// Run interactive TUI mode
pub fn runInteractive(opts: cli.Options, detect_leaks: bool, should_exit: *std.atomic.Value(bool)) !void {
    var state = TUIState{};
    var detector = if (detect_leaks) leak_detector.LeakDetector.init() else undefined;
    var processes_buffer: [process.MAX_PROCESS_BUFFER]process.ProcessInfo = undefined;
    var leak_buffer: [50]leak_detector.LeakInfo = undefined;

    // Enable raw mode for immediate key input (no need to press Return)
    try enableRawMode();
    defer disableRawMode();
    defer {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        _ = stdout_file.writeAll(SHOW_CURSOR) catch {};
    }

    while (!should_exit.load(.seq_cst)) {
        // Get memory stats
        const stats = try memory.getVMStatistics();

        // Get process list
        const process_count = try process.getProcessList(&processes_buffer);

        // Sort processes
        sortProcesses(&processes_buffer, process_count, state.sort_by);

        // Update selected index bounds
        if (state.selected_index >= process_count) {
            state.selected_index = if (process_count > 0) process_count - 1 else 0;
        }

        // Update scroll offset
        if (state.selected_index < state.scroll_offset) {
            state.scroll_offset = state.selected_index;
        } else if (state.selected_index >= state.scroll_offset + state.process_count) {
            state.scroll_offset = state.selected_index - state.process_count + 1;
        }

        // Detect leaks if enabled
        var leak_count: usize = 0;
        if (detect_leaks) {
            detector.addSnapshot(&processes_buffer, process_count);
            leak_count = detector.detectLeaks(&leak_buffer, &processes_buffer);
        }

        // Render UI (only if help is not showing, or show both)
        if (!state.show_help) {
            try render(stats, &processes_buffer, process_count, &state, &leak_buffer, leak_count, opts);
        } else {
            // Show help screen
            const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
            try stdout_file.writeAll(CLEAR_SCREEN);
            var help_buf: [512]u8 = undefined;
            try renderHelp(stdout_file, opts, &help_buf);
        }

        // Handle input (non-blocking)
        if (readKey()) |key| {
            switch (key) {
                .quit, .escape => break,
                .arrow_up => {
                    if (state.selected_index > 0) {
                        state.selected_index -= 1;
                    }
                },
                .arrow_down => {
                    if (state.selected_index < process_count - 1) {
                        state.selected_index += 1;
                    }
                },
                .sort => {
                    state.sort_by = switch (state.sort_by) {
                        .memory => .pid,
                        .pid => .name,
                        .name => .memory,
                    };
                },
                .toggle_leaks => {
                    state.show_leaks = !state.show_leaks;
                },
                .refresh => {
                    // Force refresh by continuing loop
                },
                .help => {
                    state.show_help = !state.show_help;
                },
                else => {},
            }
        }

        // Small delay to prevent CPU spinning and allow input processing
        std.Thread.sleep(200_000_000); // 200ms - good balance for responsiveness
    }
}

