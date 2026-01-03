//! Mach API bindings and system calls for macOS.
//!
//! This module provides low-level bindings to Mach APIs and system calls
//! needed for querying memory statistics and process information.

const std = @import("std");
const builtin = @import("builtin");

// Only compile on macOS
comptime {
    if (builtin.os.tag != .macos) {
        @compileError("This module only supports macOS");
    }
}

// Mach API types
pub const mach_port_t = c_uint;
pub const natural_t = c_uint;
pub const vm_size_t = c_ulong;
pub const kern_return_t = c_int;
pub const pid_t = c_int;
pub const task_t = mach_port_t;
pub const mach_msg_type_number_t = natural_t;

// VM statistics structure (64-bit version)
pub const vm_statistics64_data_t = extern struct {
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

// Task info structure for process memory (using proc_pidinfo)
// Must match sys/proc_info.h exactly
pub const proc_taskinfo = extern struct {
    pti_virtual_size: u64,
    pti_resident_size: u64,
    pti_total_user: u64,
    pti_total_system: u64,
    pti_threads_user: u64,
    pti_threads_system: u64,
    pti_policy: i32,
    pti_faults: i32,
    pti_pageins: i32,
    pti_cow_faults: i32,
    pti_messages_sent: i32,
    pti_messages_received: i32,
    pti_syscalls_mach: i32,
    pti_syscalls_unix: i32,
    pti_csw: i32,
    pti_threadnum: i32,
    pti_numrunning: i32,
    pti_priority: i32,
};

// Mach API function declarations
extern "c" fn mach_host_self() mach_port_t;
extern "c" fn host_statistics64(
    host_priv: mach_port_t,
    flavor: c_int,
    host_info_out: *vm_statistics64_data_t,
    host_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;

// proc_pidinfo function (doesn't require special privileges)
extern "c" fn proc_pidinfo(
    pid: c_int,
    flavor: c_int,
    arg: u64,
    buffer: ?*anyopaque,
    buffersize: c_int,
) c_int;

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

// Mach constants
pub const HOST_VM_INFO64: c_int = 4;
pub const HOST_VM_INFO64_COUNT: mach_msg_type_number_t = @sizeOf(vm_statistics64_data_t) / @sizeOf(natural_t);
pub const PROC_PIDTASKINFO: c_int = 4;
pub const KERN_SUCCESS: kern_return_t = 0;

// Process listing constants
pub const PROC_ALL_PIDS: c_int = 1;
pub const MAXPATHLEN: c_uint = 1024;

// Error definitions
pub const MachError = error{
    SysctlFailed,
    MachHostSelfFailed,
    HostStatisticsFailed,
    ProcessListFailed,
    MemoryPressureFailed,
};

/// Get system page size
pub fn getPageSize() c_int {
    return getpagesize();
}

/// Get total physical memory using sysctl
pub fn getTotalMemory() MachError!u64 {
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

/// Get swap total using sysctl.
/// Returns 0 if sysctl fails (will be estimated from swapouts in that case).
pub fn getSwapTotal() u64 {
    var size: usize = @sizeOf(u64);
    var swap_total: u64 = 0;

    const result = sysctlbyname(
        "vm.swapusage",
        @ptrCast(&swap_total),
        &size,
        null,
        0,
    );

    // If this fails, return 0 - will be estimated from vm_statistics64 swapouts
    if (result != 0) {
        return 0;
    }

    return swap_total;
}

/// Get memory pressure level using sysctl
pub fn getMemoryPressure() MachError!c_uint {
    var size: usize = @sizeOf(c_uint);
    var pressure: c_uint = 0;

    const result = sysctlbyname(
        "vm.memory_pressure",
        @ptrCast(&pressure),
        &size,
        null,
        0,
    );

    if (result != 0) {
        return error.MemoryPressureFailed;
    }

    return pressure;
}

/// Get VM statistics using Mach APIs
pub fn getVMStatistics64() MachError!vm_statistics64_data_t {
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

    if (result != KERN_SUCCESS) {
        return error.HostStatisticsFailed;
    }

    return vm_info;
}

/// Get process task info for a specific PID
pub fn getProcessTaskInfo(pid: pid_t) ?proc_taskinfo {
    var task_info_data: proc_taskinfo = undefined;
    const info_size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, @ptrCast(&task_info_data), @intCast(@sizeOf(proc_taskinfo)));

    // Check if we got valid data - must return exactly the struct size
    if (info_size != @sizeOf(proc_taskinfo)) {
        return null; // Process not accessible
    }

    return task_info_data;
}

/// Get process path for a specific PID
pub fn getProcessPath(pid: pid_t) ?[]const u8 {
    var path_buffer: [MAXPATHLEN]u8 = undefined;
    const path_len = proc_pidpath(pid, &path_buffer[0], MAXPATHLEN);

    if (path_len > 0) {
        return path_buffer[0..@as(usize, @intCast(path_len))];
    }

    return null;
}

/// Get list of all PIDs
pub fn getAllPids(buffer: []pid_t) MachError!usize {
    const pid_count = proc_listpids(PROC_ALL_PIDS, 0, @ptrCast(buffer.ptr), @intCast(buffer.len * @sizeOf(pid_t)));

    if (pid_count <= 0) {
        return error.ProcessListFailed;
    }

    const actual_pid_count = @as(usize, @intCast(pid_count)) / @sizeOf(pid_t);
    return @min(actual_pid_count, buffer.len);
}

// Tests
test "getPageSize returns positive value" {
    const page_size = getPageSize();
    try std.testing.expect(page_size > 0);
}

test "getTotalMemory returns valid value" {
    const total = try getTotalMemory();
    try std.testing.expect(total > 0);
}

test "getVMStatistics64 returns valid statistics" {
    const vm_info = try getVMStatistics64();
    // Just verify we got a struct back - values depend on system state
    _ = vm_info;
}
