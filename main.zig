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
const pid_t = c_int;
const task_t = mach_port_t;

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

// Task info structure for process memory
const task_basic_info_64_data_t = extern struct {
    suspend_count: natural_t,
    virtual_size: u64,
    resident_size: u64,
    user_time: time_value_t,
    system_time: time_value_t,
    policy: c_int,
};

const time_value_t = extern struct {
    seconds: c_int,
    microseconds: c_int,
};

// Mach API function declarations
extern "c" fn mach_host_self() mach_port_t;
extern "c" fn host_statistics64(
    host_priv: mach_port_t,
    flavor: c_int,
    host_info_out: *vm_statistics64_data_t,
    host_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;
extern "c" fn task_for_pid(
    target_tport: mach_port_t,
    pid: c_int,
    task: *task_t,
) kern_return_t;
extern "c" fn task_info(
    target_task: task_t,
    flavor: c_int,
    task_info_out: *task_basic_info_64_data_t,
    task_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;
extern "c" fn mach_port_deallocate(
    ipc_space: mach_port_t,
    name: mach_port_t,
) kern_return_t;

// Mach constants
const HOST_VM_INFO64: c_int = 4;
const HOST_VM_INFO64_COUNT: mach_msg_type_number_t = @sizeOf(vm_statistics64_data_t) / @sizeOf(natural_t);
const TASK_BASIC_INFO_64: c_int = 5;
const TASK_BASIC_INFO_64_COUNT: mach_msg_type_number_t = @sizeOf(task_basic_info_64_data_t) / @sizeOf(natural_t);
const KERN_SUCCESS: kern_return_t = 0;

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

// Process listing functions
extern "c" fn proc_listpids(
    type: c_int,
    typeinfo: c_uint,
    buffer: ?*anyopaque,
    buffersize: c_int,
) c_int;
extern "c" fn proc_pidpath(
    pid: c_int,
    buffer: *u8,
    buffersize: c_uint,
) c_int;

const PROC_ALL_PIDS: c_int = 1;
const MAXPATHLEN: c_uint = 1024;

// Memory pressure API
extern "c" fn memorystatus_get_level(memory_pressure: *c_uint) c_int;

// Error definitions
const MemoryError = error{
    SysctlFailed,
    MachHostSelfFailed,
    HostStatisticsFailed,
    TaskForPidFailed,
    TaskInfoFailed,
    ProcessListFailed,
    MemoryPressureFailed,
};

// Process information
const ProcessInfo = struct {
    pid: pid_t,
    name: [256]u8,
    name_len: usize,
    resident_size: u64,
};

// Memory statistics structure (expanded)
const MemoryStats = struct {
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
    pressure_level: c_uint,
    page_size: u64,
};

// Command-line options
const Options = struct {
    watch: bool = false,
    watch_interval: u64 = 2,
    compact: bool = false,
    top: ?usize = null,
    color: bool = true,
    breakdown: bool = false,
};

// ANSI color codes
const Color = struct {
    const RESET = "\x1b[0m";
    const RED = "\x1b[31m";
    const GREEN = "\x1b[32m";
    const YELLOW = "\x1b[33m";
    const BLUE = "\x1b[34m";
    const MAGENTA = "\x1b[35m";
    const CYAN = "\x1b[36m";
    const BOLD = "\x1b[1m";
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

/// Get swap total using sysctl
fn getSwapTotal() MemoryError!u64 {
    var size: usize = @sizeOf(u64);
    var swap_total: u64 = 0;
    
    const result = sysctlbyname(
        "vm.swapusage",
        @ptrCast(&swap_total),
        &size,
        null,
        0,
    );
    
    // If this fails, we'll calculate from vm_statistics64
    if (result != 0) {
        return 0; // Will be calculated from swapouts
    }
    
    return swap_total;
}

/// Get memory pressure level
fn getMemoryPressure() MemoryError!c_uint {
    var pressure: c_uint = 0;
    const result = memorystatus_get_level(&pressure);
    if (result != 0) {
        return error.MemoryPressureFailed;
    }
    return pressure;
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
    const free_bytes = vm_info.free_count * page_size_u64;
    const active_bytes = vm_info.active_count * page_size_u64;
    const inactive_bytes = vm_info.inactive_count * page_size_u64;
    const wire_bytes = vm_info.wire_count * page_size_u64;
    const speculative_bytes = vm_info.speculative_count * page_size_u64;
    const compressed_bytes = vm_info.compressor_page_count * page_size_u64;
    
    // Swap: estimate from swapouts (pages swapped out)
    const swap_used_bytes = vm_info.swapouts * page_size_u64;
    const swap_total = getSwapTotal() catch swap_used_bytes;
    
    // Used memory = active + wired (memory actively in use)
    const used = active_bytes + wire_bytes;
    
    // Cached memory = inactive + speculative (can be reclaimed but currently cached)
    const cached = inactive_bytes + speculative_bytes;
    
    // Free memory = completely free pages
    const free = free_bytes;
    
    // Get total memory
    const total = try getTotalMemory();
    
    // Get memory pressure
    const pressure = getMemoryPressure() catch 0;
    
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
        .pressure_level = pressure,
        .page_size = page_size_u64,
    };
}

/// Get process list and their memory usage
fn getProcessList(max_count: usize, processes: []ProcessInfo) MemoryError!usize {
    // First, get all PIDs
    var pid_buffer: [4096]pid_t = undefined;
    const pid_count = proc_listpids(PROC_ALL_PIDS, 0, @ptrCast(&pid_buffer), @intCast(pid_buffer.len * @sizeOf(pid_t)));
    
    if (pid_count <= 0) {
        return error.ProcessListFailed;
    }
    
    const actual_pid_count = @as(usize, @intCast(pid_count)) / @sizeOf(pid_t);
    var process_count: usize = 0;
    
    for (0..@min(actual_pid_count, pid_buffer.len)) |i| {
        if (process_count >= max_count) break;
        
        const pid = pid_buffer[i];
        if (pid <= 0) continue;
        
        var task: task_t = undefined;
        const tfp_result = task_for_pid(mach_task_self(), pid, &task);
        
        if (tfp_result != KERN_SUCCESS) {
            // Skip processes we can't access (need root for some)
            continue;
        }
        
        defer _ = mach_port_deallocate(mach_task_self(), task);
        
        var task_info_data: task_basic_info_64_data_t = undefined;
        var task_info_count: mach_msg_type_number_t = TASK_BASIC_INFO_64_COUNT;
        
        const ti_result = task_info(task, TASK_BASIC_INFO_64, &task_info_data, &task_info_count);
        
        if (ti_result != KERN_SUCCESS) {
            continue;
        }
        
        // Get process name
        var path_buffer: [MAXPATHLEN]u8 = undefined;
        const path_len = proc_pidpath(pid, &path_buffer[0], MAXPATHLEN);
        
        var name: [256]u8 = undefined;
        var name_len: usize = 0;
        
        if (path_len > 0) {
            // Extract basename from path
            var start: usize = 0;
            for (0..@as(usize, @intCast(path_len))) |j| {
                if (path_buffer[j] == '/') {
                    start = j + 1;
                }
            }
            const basename = path_buffer[start..@as(usize, @intCast(path_len))];
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
            .resident_size = task_info_data.resident_size,
        };
        process_count += 1;
    }
    
    return process_count;
}

// Helper to get mach_task_self
extern "c" fn mach_task_self() mach_port_t;

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

/// Format bytes compactly (no space, shorter)
fn formatBytesCompact(bytes: u64, buffer: []u8) ![]const u8 {
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

/// Get color code based on usage percentage
fn getUsageColor(percent: f64, use_color: bool) []const u8 {
    if (!use_color) return "";
    if (percent >= 80.0) return Color.RED;
    if (percent >= 50.0) return Color.YELLOW;
    return Color.GREEN;
}

/// Get memory pressure string
fn getPressureString(level: c_uint) []const u8 {
    return switch (level) {
        0 => "Normal",
        1 => "Warn",
        2 => "Urgent",
        3 => "Critical",
        else => "Unknown",
    };
}

/// Get memory pressure color
fn getPressureColor(level: c_uint, use_color: bool) []const u8 {
    if (!use_color) return "";
    return switch (level) {
        0 => Color.GREEN,
        1 => Color.YELLOW,
        2 => Color.RED,
        3 => Color.RED ++ Color.BOLD,
        else => "",
    };
}

/// Print compact single-line output
fn printCompact(stats: MemoryStats, opts: Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [512]u8 = undefined;
    
    var total_buf: [16]u8 = undefined;
    var used_buf: [16]u8 = undefined;
    var free_buf: [16]u8 = undefined;
    var cached_buf: [16]u8 = undefined;
    
    const total_str = try formatBytesCompact(stats.total, &total_buf);
    const used_str = try formatBytesCompact(stats.used, &used_buf);
    const free_str = try formatBytesCompact(stats.free, &free_buf);
    const cached_str = try formatBytesCompact(stats.cached, &cached_buf);
    
    const usage_percent: f64 = if (stats.total > 0)
        (@as(f64, @floatFromInt(stats.used)) / @as(f64, @floatFromInt(stats.total))) * 100.0
    else
        0.0;
    
    const color = getUsageColor(usage_percent, opts.color);
    const reset = if (opts.color) Color.RESET else "";
    
    const line = try std.fmt.bufPrint(
        &output_buf,
        "{s}{s}{s} total, {s}{s}{s} used ({d:.1}%), {s} free, {s} cached{s}\n",
        .{ color, total_str, reset, color, used_str, reset, usage_percent, free_str, cached_str, reset },
    );
    
    try stdout_file.writeAll(line);
}

/// Print detailed memory breakdown
fn printBreakdown(stats: MemoryStats, opts: Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [256]u8 = undefined;
    
    var active_buf: [32]u8 = undefined;
    var wired_buf: [32]u8 = undefined;
    var inactive_buf: [32]u8 = undefined;
    var speculative_buf: [32]u8 = undefined;
    var compressed_buf: [32]u8 = undefined;
    
    const active_str = try formatBytes(stats.active, &active_buf);
    const wired_str = try formatBytes(stats.wired, &wired_buf);
    const inactive_str = try formatBytes(stats.inactive, &inactive_buf);
    const speculative_str = try formatBytes(stats.speculative, &speculative_buf);
    const compressed_str = try formatBytes(stats.compressed, &compressed_buf);
    
    const reset = if (opts.color) Color.RESET else "";
    const bold = if (opts.color) Color.BOLD else "";
    
    const header = try std.fmt.bufPrint(&output_buf, "{s}Memory Breakdown:{s}\n", .{ bold, reset });
    try stdout_file.writeAll(header);
    
    const line1 = try std.fmt.bufPrint(&output_buf, "  Active:     {s}\n", .{active_str});
    try stdout_file.writeAll(line1);
    
    const line2 = try std.fmt.bufPrint(&output_buf, "  Wired:      {s}\n", .{wired_str});
    try stdout_file.writeAll(line2);
    
    const line3 = try std.fmt.bufPrint(&output_buf, "  Inactive:   {s}\n", .{inactive_str});
    try stdout_file.writeAll(line3);
    
    const line4 = try std.fmt.bufPrint(&output_buf, "  Speculative: {s}\n", .{speculative_str});
    try stdout_file.writeAll(line4);
    
    const line5 = try std.fmt.bufPrint(&output_buf, "  Compressed: {s}\n", .{compressed_str});
    try stdout_file.writeAll(line5);
}

/// Print top processes
fn printTopProcesses(count: usize, opts: Options) !void {
    var processes: [100]ProcessInfo = undefined;
    const actual_count = try getProcessList(count, &processes);
    
    if (actual_count == 0) {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout_file.writeAll("(Unable to access process information - may need root privileges)\n");
        return;
    }
    
    // Sort by resident size (descending)
    for (0..actual_count) |i| {
        var max_idx = i;
        var max_size = processes[i].resident_size;
        for (i + 1..actual_count) |j| {
            if (processes[j].resident_size > max_size) {
                max_idx = j;
                max_size = processes[j].resident_size;
            }
        }
        if (max_idx != i) {
            const temp = processes[i];
            processes[i] = processes[max_idx];
            processes[max_idx] = temp;
        }
    }
    
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [512]u8 = undefined;
    var mem_buf: [32]u8 = undefined;
    
    const reset = if (opts.color) Color.RESET else "";
    const bold = if (opts.color) Color.BOLD else "";
    const cyan = if (opts.color) Color.CYAN else "";
    
    const header = try std.fmt.bufPrint(&output_buf, "{s}Top {d} Processes by Memory:{s}\n", .{ bold, actual_count, reset });
    try stdout_file.writeAll(header);
    
    for (0..actual_count) |i| {
        const proc = processes[i];
        const mem_str = try formatBytes(proc.resident_size, &mem_buf);
        const name = proc.name[0..proc.name_len];
        
        const line = try std.fmt.bufPrint(
            &output_buf,
            "  {s}{d:>6}{s}  {s}{s:<20}{s}  {s}\n",
            .{ cyan, proc.pid, reset, cyan, name, reset, mem_str },
        );
        try stdout_file.writeAll(line);
    }
}

/// Print memory statistics in a formatted table
fn printMemoryStats(stats: MemoryStats, opts: Options) !void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var output_buf: [256]u8 = undefined;
    
    // Format each value
    var total_buf: [32]u8 = undefined;
    var used_buf: [32]u8 = undefined;
    var free_buf: [32]u8 = undefined;
    var cached_buf: [32]u8 = undefined;
    var swap_used_buf: [32]u8 = undefined;
    var swap_total_buf: [32]u8 = undefined;
    
    const total_str = try formatBytes(stats.total, &total_buf);
    const used_str = try formatBytes(stats.used, &used_buf);
    const free_str = try formatBytes(stats.free, &free_buf);
    const cached_str = try formatBytes(stats.cached, &cached_buf);
    const swap_used_str = try formatBytes(stats.swap_used, &swap_used_buf);
    const swap_total_str = try formatBytes(stats.swap_total, &swap_total_buf);
    
    // Calculate usage percentage
    const usage_percent: f64 = if (stats.total > 0)
        (@as(f64, @floatFromInt(stats.used)) / @as(f64, @floatFromInt(stats.total))) * 100.0
    else
        0.0;
    
    const usage_color = getUsageColor(usage_percent, opts.color);
    const reset = if (opts.color) Color.RESET else "";
    const bold = if (opts.color) Color.BOLD else "";
    const pressure_color = getPressureColor(stats.pressure_level, opts.color);
    const pressure_str = getPressureString(stats.pressure_level);
    
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

/// Parse command-line arguments
fn parseArgs(args: [][:0]u8) Options {
    var opts = Options{};
    var i: usize = 1;
    
    while (i < args.len) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
            opts.watch = true;
            // Check for interval
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(u64, args[i + 1], 10)) |interval| {
                    opts.watch_interval = interval;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--compact") or std.mem.eql(u8, arg, "-c")) {
            opts.compact = true;
        } else if (std.mem.eql(u8, arg, "--top")) {
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(usize, args[i + 1], 10)) |count| {
                    opts.top = count;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            opts.color = false;
        } else if (std.mem.eql(u8, arg, "--breakdown") or std.mem.eql(u8, arg, "-b")) {
            opts.breakdown = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
            _ = stdout_file.writeAll(
                \\Usage: ramjet [OPTIONS]
                \\
                \\Options:
                \\  -w, --watch [SECONDS]    Watch mode (update every N seconds, default: 2)
                \\  -c, --compact             Compact single-line output
                \\  --top N                   Show top N processes by memory usage
                \\  -b, --breakdown           Show detailed memory breakdown
                \\  --no-color                Disable colored output
                \\  -h, --help               Show this help message
                \\
            ) catch {};
            std.posix.exit(0);
        }
        
        i += 1;
    }
    
    return opts;
}

/// Clear screen (for watch mode)
fn clearScreen() void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout_file.writeAll("\x1b[2J\x1b[H") catch {};
}

/// Main entry point
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);
    
    const opts = parseArgs(args);
    
    if (opts.watch) {
        // Watch mode
        while (true) {
            clearScreen();
            
            const stats = try getVMStatistics();
            
            if (opts.compact) {
                try printCompact(stats, opts);
            } else {
                try printMemoryStats(stats, opts);
            }
            
            if (opts.breakdown) {
                try printBreakdown(stats, opts);
            }
            
            if (opts.top) |count| {
                try printTopProcesses(count, opts);
            }
            
            // Sleep for interval
            std.Thread.sleep(opts.watch_interval * std.time.ns_per_s);
        }
    } else {
        // Single run
        const stats = try getVMStatistics();
        
        if (opts.compact) {
            try printCompact(stats, opts);
        } else {
            try printMemoryStats(stats, opts);
        }
        
        if (opts.breakdown) {
            try printBreakdown(stats, opts);
        }
        
        if (opts.top) |count| {
            try printTopProcesses(count, opts);
        }
    }
}
