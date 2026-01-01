const std = @import("std");
const builtin = @import("builtin");

// Only compile on macOS
comptime {
    if (builtin.os.tag != .macos) {
        @compileError("This program only supports macOS");
    }
}

// Mach API types and constants
const mach_port_t = c_uint;
const natural_t = c_uint;
const vm_size_t = c_ulong;
const kern_return_t = c_int;

// Mach message header
const mach_msg_type_number_t = natural_t;

// VM statistics structure (64-bit version)
const vm_statistics64_data_t = extern struct {
    free_count: natural_t,
    active_count: natural_t,
    inactive_count: natural_t,
    wire_count: natural_t,
    zero_fill_count: u64,
    reactivations: u64,
    pageins: u64,
    pageouts: u64,
    faults: u64,
    cow_faults: u64,
    lookups: u64,
    hits: u64,
    purges: u64,
    purges_count: natural_t,
    speculative_count: natural_t,
    decompressions: u64,
    compressions: u64,
    swapins: u64,
    swapouts: u64,
    compressor_page_count: natural_t,
    throttled_count: natural_t,
    external_page_count: natural_t,
    internal_page_count: natural_t,
    total_uncompressed_pages_in_compressor: u64,
};

// Mach API function declarations
extern "c" fn mach_host_self() mach_port_t;
extern "c" fn host_statistics64(
    host_priv: mach_port_t,
    flavor: c_int,
    host_info_out: *vm_statistics64_data_t,
    host_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;

// Mach constants
const HOST_VM_INFO64: c_int = 4;
const HOST_VM_INFO64_COUNT: mach_msg_type_number_t = @sizeOf(vm_statistics64_data_t) / @sizeOf(natural_t);

// System call for sysctl
extern "c" fn sysctlbyname(
    name: [*c]const u8,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) c_int;

// System call for page size
extern "c" fn getpagesize() c_int;

// Error definitions
const MemoryError = error{
    SysctlFailed,
    MachHostSelfFailed,
    HostStatisticsFailed,
};

// Memory statistics structure
const MemoryStats = struct {
    total: u64,
    used: u64,
    free: u64,
    cached: u64,
    page_size: u64,
};

/// Get total physical memory using sysctl
fn getTotalMemory() MemoryError!u64 {
    var size: usize = @sizeOf(u64);
    var memsize: u64 = 0;
    
    const result = sysctlbyname(
        "hw.memsize",
        @ptrCast(&memsize),
        &size,
        null,
        0,
    );
    
    if (result != 0) {
        return error.SysctlFailed;
    }
    
    return memsize;
}

/// Get VM statistics using Mach APIs
fn getVMStatistics() MemoryError!MemoryStats {
    const host = mach_host_self();
    if (host == 0) {
        return error.MachHostSelfFailed;
    }
    
    var vm_info: vm_statistics64_data_t = undefined;
    var count: mach_msg_type_number_t = HOST_VM_INFO64_COUNT;
    
    const result = host_statistics64(
        host,
        HOST_VM_INFO64,
        &vm_info,
        &count,
    );
    
    if (result != 0) {
        return error.HostStatisticsFailed;
    }
    
    // Get system page size using syscall
    const page_size = getpagesize();
    const page_size_u64: u64 = @intCast(page_size);
    
    // Calculate memory values from page counts
    // free_count: pages that are completely free
    // active_count: pages that are currently in use
    // inactive_count: pages that are in the inactive list (can be reclaimed)
    // wire_count: pages that are wired down (cannot be paged out)
    // speculative_count: pages allocated speculatively (treated as cached)
    
    const free_bytes = vm_info.free_count * page_size_u64;
    const active_bytes = vm_info.active_count * page_size_u64;
    const inactive_bytes = vm_info.inactive_count * page_size_u64;
    const wire_bytes = vm_info.wire_count * page_size_u64;
    const speculative_bytes = vm_info.speculative_count * page_size_u64;
    
    // Used memory = active + wired (memory actively in use)
    const used = active_bytes + wire_bytes;
    
    // Cached memory = inactive + speculative (can be reclaimed but currently cached)
    const cached = inactive_bytes + speculative_bytes;
    
    // Free memory = completely free pages
    const free = free_bytes;
    
    // Get total memory
    const total = try getTotalMemory();
    
    return MemoryStats{
        .total = total,
        .used = used,
        .free = free,
        .cached = cached,
        .page_size = page_size_u64,
    };
}

/// Format bytes to human-readable string (MB or GB)
fn formatBytes(bytes: u64, buffer: []u8) ![]const u8 {
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

/// Print memory statistics in a formatted table
fn printMemoryStats(stats: MemoryStats) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    
    // Format each value
    var total_buf: [32]u8 = undefined;
    var used_buf: [32]u8 = undefined;
    var free_buf: [32]u8 = undefined;
    var cached_buf: [32]u8 = undefined;
    var output_buf: [256]u8 = undefined;
    
    const total_str = try formatBytes(stats.total, &total_buf);
    const used_str = try formatBytes(stats.used, &used_buf);
    const free_str = try formatBytes(stats.free, &free_buf);
    const cached_str = try formatBytes(stats.cached, &cached_buf);
    
    // Calculate usage percentage
    const usage_percent: f64 = if (stats.total > 0) 
        (@as(f64, @floatFromInt(stats.used)) / @as(f64, @floatFromInt(stats.total))) * 100.0 
    else 
        0.0;
    
    // Format and print each line
    const line1 = try std.fmt.bufPrint(&output_buf, "Total:    {s}\n", .{total_str});
    try stdout_file.writeAll(line1);
    
    const line2 = try std.fmt.bufPrint(&output_buf, "Used:     {s} ({d:.1}%)\n", .{ used_str, usage_percent });
    try stdout_file.writeAll(line2);
    
    const line3 = try std.fmt.bufPrint(&output_buf, "Free:     {s}\n", .{free_str});
    try stdout_file.writeAll(line3);
    
    const line4 = try std.fmt.bufPrint(&output_buf, "Cached:   {s}\n", .{cached_str});
    try stdout_file.writeAll(line4);
}

/// Main entry point
pub fn main() !void {
    // Perform exactly one system query per run
    const stats = try getVMStatistics();
    
    // Print formatted output
    try printMemoryStats(stats);
}
