//! Memory statistics types and collection functions.
//!
//! This module provides types and functions for collecting and working with
//! system memory statistics from Mach APIs.

const std = @import("std");
const mach = @import("mach.zig");
const colors = @import("colors.zig");

/// Memory statistics structure
pub const MemoryStats = struct {
    total: u64,
    used: u64,
    free: u64,
    cached: u64,
    // Detailed breakdown
    active: u64,
    wired: u64,
    inactive: u64,
    speculative: u64,
    compressed: u64,
    // Swap
    swap_used: u64,
    swap_total: u64,
    // Pressure
    pressure: colors.MemoryPressure,
    page_size: u64,
    
    /// Calculate usage percentage
    pub fn usagePercent(self: MemoryStats) f64 {
        if (self.total == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.used)) / @as(f64, @floatFromInt(self.total))) * 100.0;
    }
};

/// Get VM statistics using Mach APIs and convert to MemoryStats
pub fn getVMStatistics() mach.MachError!MemoryStats {
    const vm_info = try mach.getVMStatistics64();
    
    // Get system page size
    const page_size = mach.getPageSize();
    const page_size_u64: u64 = @intCast(page_size);
    
    // Calculate memory values from page counts
    const free_bytes = vm_info.free_count * page_size_u64;
    const active_bytes = vm_info.active_count * page_size_u64;
    const inactive_bytes = vm_info.inactive_count * page_size_u64;
    const wire_bytes = vm_info.wire_count * page_size_u64;
    const speculative_bytes = vm_info.speculative_count * page_size_u64;
    const compressed_bytes = vm_info.compressor_page_count * page_size_u64;
    
    // Swap: estimate from swapouts (pages swapped out)
    const swap_used_bytes = vm_info.swapouts * page_size_u64;
    const swap_total = if (mach.getSwapTotal() > 0) mach.getSwapTotal() else swap_used_bytes;
    
    // Used memory = active + wired (memory actively in use)
    const used = active_bytes + wire_bytes;
    
    // Cached memory = inactive + speculative (can be reclaimed but currently cached)
    const cached = inactive_bytes + speculative_bytes;
    
    // Free memory = completely free pages
    const free = free_bytes;
    
    // Get total memory
    const total = try mach.getTotalMemory();
    
    // Get memory pressure
    const pressure_raw = mach.getMemoryPressure() catch 0;
    const pressure = colors.MemoryPressure.fromRaw(@intCast(@min(pressure_raw, 3)));
    
    return MemoryStats{
        .total = total,
        .used = used,
        .free = free,
        .cached = cached,
        .active = active_bytes,
        .wired = wire_bytes,
        .inactive = inactive_bytes,
        .speculative = speculative_bytes,
        .compressed = compressed_bytes,
        .swap_used = swap_used_bytes,
        .swap_total = swap_total,
        .pressure = pressure,
        .page_size = page_size_u64,
    };
}

test "MemoryStats usagePercent calculates correctly" {
    const stats = MemoryStats{
        .total = 8_589_934_592, // 8GB
        .used = 4_294_967_296,  // 4GB
        .free = 2_147_483_648,  // 2GB
        .cached = 2_147_483_648, // 2GB
        .active = 2_147_483_648,
        .wired = 2_147_483_648,
        .inactive = 1_073_741_824,
        .speculative = 1_073_741_824,
        .compressed = 0,
        .swap_used = 0,
        .swap_total = 0,
        .pressure = .normal,
        .page_size = 4096,
    };
    
    const percent = stats.usagePercent();
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), percent, 0.1);
}

test "getVMStatistics returns valid stats" {
    const stats = try getVMStatistics();
    try std.testing.expect(stats.total > 0);
    try std.testing.expect(stats.page_size > 0);
    // Verify calculations are consistent
    try std.testing.expect(stats.used == stats.active + stats.wired);
    try std.testing.expect(stats.cached == stats.inactive + stats.speculative);
}
