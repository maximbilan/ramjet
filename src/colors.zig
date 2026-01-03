//! ANSI color codes and color-related utilities.
//!
//! This module provides color formatting for terminal output,
//! including usage-based color coding and memory pressure indicators.

const std = @import("std");

/// ANSI color escape codes
pub const Color = struct {
    pub const RESET = "\x1b[0m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
};

/// Memory pressure levels
pub const MemoryPressure = enum(u2) {
    normal = 0,
    warn = 1,
    urgent = 2,
    critical = 3,
    
    /// Convert from raw C uint value
    pub fn fromRaw(value: u2) MemoryPressure {
        return @enumFromInt(@min(value, 3));
    }
    
    /// Get human-readable string
    pub fn toString(self: MemoryPressure) []const u8 {
        return switch (self) {
            .normal => "Normal",
            .warn => "Warn",
            .urgent => "Urgent",
            .critical => "Critical",
        };
    }
};

/// Get color code based on memory usage percentage
/// 
/// - Green: < 50%
/// - Yellow: 50-80%
/// - Red: >= 80%
pub fn getUsageColor(percent: f64, use_color: bool) []const u8 {
    if (!use_color) return "";
    if (percent >= 80.0) return Color.RED;
    if (percent >= 50.0) return Color.YELLOW;
    return Color.GREEN;
}

/// Get color code for memory pressure level
pub fn getPressureColor(pressure: MemoryPressure, use_color: bool) []const u8 {
    if (!use_color) return "";
    return switch (pressure) {
        .normal => Color.GREEN,
        .warn => Color.YELLOW,
        .urgent => Color.RED,
        .critical => Color.RED ++ Color.BOLD,
    };
}

test "getUsageColor returns correct colors" {
    try std.testing.expectEqualStrings("", getUsageColor(30.0, false));
    try std.testing.expectEqualStrings(Color.GREEN, getUsageColor(30.0, true));
    try std.testing.expectEqualStrings(Color.YELLOW, getUsageColor(60.0, true));
    try std.testing.expectEqualStrings(Color.RED, getUsageColor(85.0, true));
}

test "MemoryPressure fromRaw" {
    try std.testing.expectEqual(MemoryPressure.normal, MemoryPressure.fromRaw(0));
    try std.testing.expectEqual(MemoryPressure.warn, MemoryPressure.fromRaw(1));
    try std.testing.expectEqual(MemoryPressure.urgent, MemoryPressure.fromRaw(2));
    try std.testing.expectEqual(MemoryPressure.critical, MemoryPressure.fromRaw(3));
}

test "MemoryPressure toString" {
    try std.testing.expectEqualStrings("Normal", MemoryPressure.normal.toString());
    try std.testing.expectEqualStrings("Warn", MemoryPressure.warn.toString());
    try std.testing.expectEqualStrings("Urgent", MemoryPressure.urgent.toString());
    try std.testing.expectEqualStrings("Critical", MemoryPressure.critical.toString());
}
