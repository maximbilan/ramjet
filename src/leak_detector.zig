//! Memory leak detection functionality.
//!
//! This module tracks process memory usage over time to detect potential memory leaks.

const std = @import("std");
const process = @import("process.zig");
const mach = @import("mach.zig");

/// Maximum number of history snapshots to keep
pub const MAX_HISTORY: usize = 10;

/// Process memory snapshot entry
const ProcessSnapshotEntry = struct {
    pid: mach.pid_t,
    resident_size: u64,
};

/// Memory leak detector state
pub const LeakDetector = struct {
    history: [MAX_HISTORY][process.MAX_PROCESS_BUFFER]ProcessSnapshotEntry,
    history_counts: [MAX_HISTORY]usize,
    timestamps: [MAX_HISTORY]i64,
    history_count: usize,
    current_index: usize,

    /// Initialize leak detector
    pub fn init() LeakDetector {
        var detector = LeakDetector{
            .history = undefined,
            .history_counts = undefined,
            .timestamps = undefined,
            .history_count = 0,
            .current_index = 0,
        };
        // Initialize arrays to zero for safety
        @memset(&detector.history_counts, 0);
        @memset(&detector.timestamps, 0);
        // Note: history array elements are initialized when snapshots are added
        return detector;
    }

    /// Add a snapshot of current processes
    pub fn addSnapshot(self: *LeakDetector, processes: []const process.ProcessInfo, count: usize) void {
        const idx = if (self.history_count < MAX_HISTORY) self.history_count else self.current_index;
        const actual_count = @min(count, self.history[idx].len);

        // Copy process data
        for (0..actual_count) |i| {
            self.history[idx][i] = ProcessSnapshotEntry{
                .pid = processes[i].pid,
                .resident_size = processes[i].resident_size,
            };
        }

        self.history_counts[idx] = actual_count;
        self.timestamps[idx] = std.time.timestamp();

        if (self.history_count < MAX_HISTORY) {
            self.history_count += 1;
        } else {
            // Circular buffer - overwrite oldest
            self.current_index = (self.current_index + 1) % MAX_HISTORY;
        }
    }

    /// Detect potential memory leaks
    /// Returns array of PIDs with significant memory growth
    pub fn detectLeaks(self: *LeakDetector, leaks: []LeakInfo, process_names: []const process.ProcessInfo) usize {
        if (self.history_count < 2) {
            return 0; // Need at least 2 snapshots
        }

        var leak_count: usize = 0;
        const oldest_idx = if (self.history_count < MAX_HISTORY) 0 else self.current_index;
        const newest_idx = if (self.history_count < MAX_HISTORY) self.history_count - 1 else (self.current_index + MAX_HISTORY - 1) % MAX_HISTORY;

        const oldest = self.history[oldest_idx][0..self.history_counts[oldest_idx]];
        const newest = self.history[newest_idx][0..self.history_counts[newest_idx]];
        const time_diff = self.timestamps[newest_idx] - self.timestamps[oldest_idx];

        if (time_diff <= 0) return 0;

        // Create a map of newest processes by PID
        var newest_map: [process.MAX_PROCESS_BUFFER]struct { pid: mach.pid_t, size: u64 } = undefined;
        var newest_map_count: usize = 0;
        for (newest) |entry| {
            newest_map[newest_map_count] = .{ .pid = entry.pid, .size = entry.resident_size };
            newest_map_count += 1;
        }

        // Check each process in oldest snapshot
        for (oldest) |old_entry| {
            // Find matching process in newest
            var found = false;
            var new_size: u64 = 0;
            for (newest_map[0..newest_map_count]) |new_entry| {
                if (new_entry.pid == old_entry.pid) {
                    found = true;
                    new_size = new_entry.size;
                    break;
                }
            }

            if (!found) continue; // Process no longer exists

            const growth = if (new_size > old_entry.resident_size) new_size - old_entry.resident_size else 0;
            const growth_mb = @as(f64, @floatFromInt(growth)) / (1024.0 * 1024.0);

            // Consider it a leak if:
            // 1. Growth > 50MB
            // 2. Growth > 20% of original size
            const growth_percent = if (old_entry.resident_size > 0)
                (@as(f64, @floatFromInt(growth)) / @as(f64, @floatFromInt(old_entry.resident_size))) * 100.0
            else
                0.0;

            if (growth_mb > 50.0 or growth_percent > 20.0) {
                if (leak_count < leaks.len) {
                    // Find process name from current process list
                    var proc_name: [256]u8 = undefined;
                    var name_len: usize = 0;
                    @memset(&proc_name, 0);

                    for (process_names) |proc| {
                        if (proc.pid == old_entry.pid) {
                            name_len = proc.name_len;
                            @memcpy(proc_name[0..name_len], proc.name[0..name_len]);
                            break;
                        }
                    }

                    if (name_len == 0) {
                        // Fallback to PID
                        if (std.fmt.bufPrint(&proc_name, "pid-{}", .{old_entry.pid})) |pid_str| {
                            name_len = pid_str.len;
                        } else |_| {
                            @memcpy(proc_name[0..7], "process");
                            name_len = 7;
                        }
                    }

                    leaks[leak_count] = LeakInfo{
                        .pid = old_entry.pid,
                        .name = proc_name,
                        .name_len = name_len,
                        .old_size = old_entry.resident_size,
                        .new_size = new_size,
                        .growth = growth,
                        .time_span = @as(u64, @intCast(time_diff)),
                    };
                    leak_count += 1;
                }
            }
        }

        return leak_count;
    }
};

/// Information about a detected memory leak
pub const LeakInfo = struct {
    pid: mach.pid_t,
    name: [256]u8,
    name_len: usize,
    old_size: u64,
    new_size: u64,
    growth: u64,
    time_span: u64, // seconds
};

test "LeakDetector init creates empty detector" {
    const detector = LeakDetector.init();
    try std.testing.expectEqual(@as(usize, 0), detector.history_count);
    try std.testing.expectEqual(@as(usize, 0), detector.current_index);
}

test "LeakDetector addSnapshot stores process data" {
    var detector = LeakDetector.init();
    var processes = [_]process.ProcessInfo{
        .{ .pid = 100, .name = undefined, .name_len = 0, .resident_size = 1000 },
        .{ .pid = 200, .name = undefined, .name_len = 0, .resident_size = 2000 },
    };

    detector.addSnapshot(&processes, 2);

    try std.testing.expectEqual(@as(usize, 1), detector.history_count);
    try std.testing.expectEqual(@as(usize, 2), detector.history_counts[0]);
    try std.testing.expectEqual(@as(mach.pid_t, 100), detector.history[0][0].pid);
    try std.testing.expectEqual(@as(u64, 1000), detector.history[0][0].resident_size);
    try std.testing.expectEqual(@as(mach.pid_t, 200), detector.history[0][1].pid);
    try std.testing.expectEqual(@as(u64, 2000), detector.history[0][1].resident_size);
}

test "LeakDetector detectLeaks requires at least 2 snapshots" {
    var detector = LeakDetector.init();
    var processes = [_]process.ProcessInfo{
        .{ .pid = 100, .name = undefined, .name_len = 0, .resident_size = 1000 },
    };
    var leaks: [10]LeakInfo = undefined;

    // No snapshots
    try std.testing.expectEqual(@as(usize, 0), detector.detectLeaks(&leaks, &processes));

    // One snapshot
    detector.addSnapshot(&processes, 1);
    try std.testing.expectEqual(@as(usize, 0), detector.detectLeaks(&leaks, &processes));
}

test "LeakDetector detectLeaks detects large growth" {
    var detector = LeakDetector.init();
    var leaks: [10]LeakInfo = undefined;

    // First snapshot - process with 100MB
    var processes1 = [_]process.ProcessInfo{
        .{ .pid = 100, .name = "test", .name_len = 4, .resident_size = 100 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes1, 1);

    // Wait a bit (simulate time passing)
    std.Thread.sleep(100_000_000); // 100ms

    // Second snapshot - process grew to 200MB (100MB growth > 50MB threshold)
    var processes2 = [_]process.ProcessInfo{
        .{ .pid = 100, .name = "test", .name_len = 4, .resident_size = 200 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes2, 1);

    const leak_count = detector.detectLeaks(&leaks, &processes2);
    try std.testing.expectEqual(@as(usize, 1), leak_count);
    try std.testing.expectEqual(@as(mach.pid_t, 100), leaks[0].pid);
    try std.testing.expectEqual(@as(u64, 100 * 1024 * 1024), leaks[0].old_size);
    try std.testing.expectEqual(@as(u64, 200 * 1024 * 1024), leaks[0].new_size);
    try std.testing.expectEqual(@as(u64, 100 * 1024 * 1024), leaks[0].growth);
}

test "LeakDetector detectLeaks detects percentage-based growth" {
    var detector = LeakDetector.init();
    var leaks: [10]LeakInfo = undefined;

    // First snapshot - process with 100MB
    var processes1 = [_]process.ProcessInfo{
        .{ .pid = 200, .name = "app", .name_len = 3, .resident_size = 100 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes1, 1);

    std.Thread.sleep(100_000_000);

    // Second snapshot - process grew to 130MB (30MB growth, but 30% > 20% threshold)
    var processes2 = [_]process.ProcessInfo{
        .{ .pid = 200, .name = "app", .name_len = 3, .resident_size = 130 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes2, 1);

    const leak_count = detector.detectLeaks(&leaks, &processes2);
    try std.testing.expectEqual(@as(usize, 1), leak_count);
    try std.testing.expectEqual(@as(mach.pid_t, 200), leaks[0].pid);
}

test "LeakDetector detectLeaks ignores small growth" {
    var detector = LeakDetector.init();
    var leaks: [10]LeakInfo = undefined;

    // First snapshot
    var processes1 = [_]process.ProcessInfo{
        .{ .pid = 300, .name = "small", .name_len = 5, .resident_size = 100 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes1, 1);

    std.Thread.sleep(100_000_000);

    // Second snapshot - small growth (10MB < 50MB, and 10% < 20%)
    var processes2 = [_]process.ProcessInfo{
        .{ .pid = 300, .name = "small", .name_len = 5, .resident_size = 110 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes2, 1);

    const leak_count = detector.detectLeaks(&leaks, &processes2);
    try std.testing.expectEqual(@as(usize, 0), leak_count);
}

test "LeakDetector detectLeaks handles circular buffer" {
    var detector = LeakDetector.init();

    // Fill up the history buffer (MAX_HISTORY snapshots)
    var i: usize = 0;
    while (i < MAX_HISTORY) : (i += 1) {
        var processes = [_]process.ProcessInfo{
            .{ .pid = 100, .name = "test", .name_len = 4, .resident_size = 100 * 1024 * 1024 },
        };
        detector.addSnapshot(&processes, 1);
        std.Thread.sleep(10_000_000); // 10ms between snapshots
    }

    // Add one more to trigger circular buffer
    var processes_new = [_]process.ProcessInfo{
        .{ .pid = 100, .name = "test", .name_len = 4, .resident_size = 200 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes_new, 1);

    // Should still have MAX_HISTORY snapshots
    try std.testing.expectEqual(MAX_HISTORY, detector.history_count);
}

test "LeakDetector detectLeaks ignores processes that no longer exist" {
    var detector = LeakDetector.init();
    var leaks: [10]LeakInfo = undefined;

    // First snapshot - two processes
    var processes1 = [_]process.ProcessInfo{
        .{ .pid = 100, .name = "proc1", .name_len = 5, .resident_size = 100 * 1024 * 1024 },
        .{ .pid = 200, .name = "proc2", .name_len = 5, .resident_size = 200 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes1, 2);

    std.Thread.sleep(100_000_000);

    // Second snapshot - only one process (other exited)
    var processes2 = [_]process.ProcessInfo{
        .{ .pid = 100, .name = "proc1", .name_len = 5, .resident_size = 200 * 1024 * 1024 },
    };
    detector.addSnapshot(&processes2, 1);

    const leak_count = detector.detectLeaks(&leaks, &processes2);
    // Should detect leak for process 100, but not for 200 (which no longer exists)
    try std.testing.expectEqual(@as(usize, 1), leak_count);
    try std.testing.expectEqual(@as(mach.pid_t, 100), leaks[0].pid);
}
