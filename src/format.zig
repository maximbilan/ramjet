//! Formatting utilities for memory values and output.
//!
//! This module provides functions to format bytes into human-readable
//! strings (MB/GB) and format output tables.

const std = @import("std");

/// Format bytes to human-readable string (MB or GB)
/// 
/// Example:
/// ```zig
/// var buf: [32]u8 = undefined;
/// const formatted = try formatBytes(1_073_741_824, &buf);
/// // formatted == "1.0 GB"
/// ```
pub fn formatBytes(bytes: u64, buffer: []u8) ![]const u8 {
    const gb: f64 = 1024.0 * 1024.0 * 1024.0;
    const mb: f64 = 1024.0 * 1024.0;
    
    const bytes_f64: f64 = @floatFromInt(bytes);
    
    if (bytes_f64 >= gb) {
        const gb_value = bytes_f64 / gb;
        return try std.fmt.bufPrint(buffer, "{d:.1} GB", .{gb_value});
    } else {
        const mb_value = bytes_f64 / mb;
        return try std.fmt.bufPrint(buffer, "{d:.1} MB", .{mb_value});
    }
}

/// Format bytes compactly (no space, shorter units)
/// 
/// Example:
/// ```zig
/// var buf: [32]u8 = undefined;
/// const formatted = try formatBytesCompact(1_073_741_824, &buf);
/// // formatted == "1.0G"
/// ```
pub fn formatBytesCompact(bytes: u64, buffer: []u8) ![]const u8 {
    const gb: f64 = 1024.0 * 1024.0 * 1024.0;
    const mb: f64 = 1024.0 * 1024.0;
    const kb: f64 = 1024.0;
    
    const bytes_f64: f64 = @floatFromInt(bytes);
    
    if (bytes_f64 >= gb) {
        const gb_value = bytes_f64 / gb;
        return try std.fmt.bufPrint(buffer, "{d:.1}G", .{gb_value});
    } else if (bytes_f64 >= mb) {
        const mb_value = bytes_f64 / mb;
        return try std.fmt.bufPrint(buffer, "{d:.1}M", .{mb_value});
    } else {
        const kb_value = bytes_f64 / kb;
        return try std.fmt.bufPrint(buffer, "{d:.1}K", .{kb_value});
    }
}

/// Right-pad a string to a given width (adds spaces on the right)
pub fn padRight(str: []const u8, width: usize, buffer: []u8) []const u8 {
    if (str.len >= width) return str;
    @memcpy(buffer[0..str.len], str);
    @memset(buffer[str.len..width], ' ');
    return buffer[0..width];
}

/// Left-pad a string to a given width (adds spaces on the left)
pub fn padLeft(str: []const u8, width: usize, buffer: []u8) []const u8 {
    if (str.len >= width) return str;
    const pad_len = width - str.len;
    @memset(buffer[0..pad_len], ' ');
    @memcpy(buffer[pad_len..width], str);
    return buffer[0..width];
}

test "formatBytes formats GB correctly" {
    var buf: [32]u8 = undefined;
    const result = try formatBytes(2_147_483_648, &buf); // 2GB
    try std.testing.expectEqualStrings("2.0 GB", result);
}

test "formatBytes formats MB correctly" {
    var buf: [32]u8 = undefined;
    const result = try formatBytes(5_242_880, &buf); // 5MB
    try std.testing.expectEqualStrings("5.0 MB", result);
}

test "formatBytesCompact formats correctly" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("2.0G", try formatBytesCompact(2_147_483_648, &buf));
    try std.testing.expectEqualStrings("5.0M", try formatBytesCompact(5_242_880, &buf));
    try std.testing.expectEqualStrings("1.5K", try formatBytesCompact(1536, &buf));
}

test "padRight pads correctly" {
    var buf: [64]u8 = undefined;
    const padded = padRight("test", 10, &buf);
    try std.testing.expectEqualStrings("test      ", padded);
    try std.testing.expectEqual(@as(usize, 10), padded.len);
}

test "padLeft pads correctly" {
    var buf: [64]u8 = undefined;
    const padded = padLeft("test", 10, &buf);
    try std.testing.expectEqualStrings("      test", padded);
    try std.testing.expectEqual(@as(usize, 10), padded.len);
}
