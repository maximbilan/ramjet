//! Process listing and information functionality.
//!
//! This module provides functions for collecting process information
//! and sorting processes by memory usage.

const std = @import("std");
const mach = @import("mach.zig");

/// Process information
pub const ProcessInfo = struct {
    pid: mach.pid_t,
    name: [256]u8,
    name_len: usize,
    resident_size: u64,

    /// Compare two processes by resident size (descending, for top-N)
    pub fn greaterThan(context: void, a: ProcessInfo, b: ProcessInfo) bool {
        _ = context;
        return a.resident_size > b.resident_size;
    }

    /// Compare two processes by PID (ascending)
    pub fn lessThanByPid(context: void, a: ProcessInfo, b: ProcessInfo) bool {
        _ = context;
        return a.pid < b.pid;
    }

    /// Compare two processes by name (alphabetical)
    pub fn lessThanByName(context: void, a: ProcessInfo, b: ProcessInfo) bool {
        _ = context;
        const a_name = a.name[0..a.name_len];
        const b_name = b.name[0..b.name_len];
        return std.mem.lessThan(u8, a_name, b_name);
    }
};

pub const MAX_PROCESS_BUFFER: usize = 2000; // Maximum processes to collect
pub const MAX_PROCESS_NAME_WIDTH: usize = 45; // Maximum process name width before truncation

/// Get process list and their memory usage.
/// Collects all accessible processes up to the buffer size.
/// Returns the number of processes successfully collected.
pub fn getProcessList(processes: []ProcessInfo) mach.MachError!usize {
    // First, get all PIDs
    var pid_buffer: [4096]mach.pid_t = undefined;
    const actual_pid_count = try mach.getAllPids(&pid_buffer);

    var process_count: usize = 0;

    // Collect all accessible processes
    for (0..actual_pid_count) |i| {
        // Stop if we've filled our buffer
        if (process_count >= processes.len) break;

        const pid = pid_buffer[i];
        if (pid <= 0) continue;

        // Get process task info
        const task_info = mach.getProcessTaskInfo(pid);
        if (task_info == null) {
            continue; // Skip processes we can't access
        }

        const resident_size = task_info.?.pti_resident_size;

        // Get process name
        var name: [256]u8 = undefined;
        var name_len: usize = 0;

        if (mach.getProcessPath(pid)) |path| {
            // Extract basename from path
            var start: usize = 0;
            for (0..path.len) |j| {
                if (path[j] == '/') {
                    start = j + 1;
                }
            }
            const basename = path[start..];
            name_len = @min(basename.len, name.len - 1);
            @memcpy(name[0..name_len], basename[0..name_len]);
            name[name_len] = 0;
        } else {
            // Fallback to PID as string
            if (std.fmt.bufPrint(&name, "pid-{}", .{pid})) |pid_str| {
                name_len = pid_str.len;
            } else |_| {
                // If formatting fails, just use "process"
                @memcpy(name[0..7], "process");
                name_len = 7;
            }
        }

        processes[process_count] = ProcessInfo{
            .pid = pid,
            .name = name,
            .name_len = name_len,
            .resident_size = resident_size,
        };
        process_count += 1;
    }

    return process_count;
}

/// Sort processes by resident size (descending order for top-N)
/// Uses std.sort for O(n log n) performance instead of O(n²) selection sort
pub fn sortProcessesByMemory(processes: []ProcessInfo) void {
    std.sort.block(ProcessInfo, processes, {}, ProcessInfo.greaterThan);
}

/// Sort processes by PID (ascending)
pub fn sortProcessesByPid(processes: []ProcessInfo) void {
    std.sort.block(ProcessInfo, processes, {}, ProcessInfo.lessThanByPid);
}

/// Sort processes by name (alphabetical)
pub fn sortProcessesByName(processes: []ProcessInfo) void {
    std.sort.block(ProcessInfo, processes, {}, ProcessInfo.lessThanByName);
}

test "ProcessInfo greaterThan compares correctly" {
    const proc1 = ProcessInfo{
        .pid = 1,
        .name = undefined,
        .name_len = 0,
        .resident_size = 1000,
    };
    const proc2 = ProcessInfo{
        .pid = 2,
        .name = undefined,
        .name_len = 0,
        .resident_size = 2000,
    };

    try std.testing.expect(ProcessInfo.greaterThan({}, proc2, proc1));
    try std.testing.expect(!ProcessInfo.greaterThan({}, proc1, proc2));
}

test "sortProcessesByMemory sorts correctly" {
    var processes = [_]ProcessInfo{
        .{ .pid = 1, .name = undefined, .name_len = 0, .resident_size = 100 },
        .{ .pid = 2, .name = undefined, .name_len = 0, .resident_size = 300 },
        .{ .pid = 3, .name = undefined, .name_len = 0, .resident_size = 200 },
    };

    sortProcessesByMemory(&processes);

    try std.testing.expectEqual(@as(u64, 300), processes[0].resident_size);
    try std.testing.expectEqual(@as(u64, 200), processes[1].resident_size);
    try std.testing.expectEqual(@as(u64, 100), processes[2].resident_size);
}
