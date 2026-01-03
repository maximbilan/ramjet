const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    const exe = b.addExecutable(.{
        .name = "ramjet",
        .root_module = b.addModule("ramjet", .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link against system frameworks required for Mach APIs
    exe.linkFramework("Foundation");
    exe.linkFramework("IOKit");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step - run tests for all modules
    const test_step = b.step("test", "Run all tests");
    
    // Test each module
    const mach_tests = b.addTest(.{
        .root_module = b.addModule("mach", .{
            .root_source_file = b.path("src/mach.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    mach_tests.linkFramework("Foundation");
    mach_tests.linkFramework("IOKit");
    mach_tests.linkLibC();
    
    const colors_tests = b.addTest(.{
        .root_module = b.addModule("colors", .{
            .root_source_file = b.path("src/colors.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const format_tests = b.addTest(.{
        .root_module = b.addModule("format", .{
            .root_source_file = b.path("src/format.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const memory_tests = b.addTest(.{
        .root_module = b.addModule("memory", .{
            .root_source_file = b.path("src/memory.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    memory_tests.linkFramework("Foundation");
    memory_tests.linkFramework("IOKit");
    memory_tests.linkLibC();
    
    const process_tests = b.addTest(.{
        .root_module = b.addModule("process", .{
            .root_source_file = b.path("src/process.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    process_tests.linkFramework("Foundation");
    process_tests.linkFramework("IOKit");
    process_tests.linkLibC();
    
    const cli_tests = b.addTest(.{
        .root_module = b.addModule("cli", .{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_mach_tests = b.addRunArtifact(mach_tests);
    const run_colors_tests = b.addRunArtifact(colors_tests);
    const run_format_tests = b.addRunArtifact(format_tests);
    const run_memory_tests = b.addRunArtifact(memory_tests);
    const run_process_tests = b.addRunArtifact(process_tests);
    const run_cli_tests = b.addRunArtifact(cli_tests);
    
    test_step.dependOn(&run_mach_tests.step);
    test_step.dependOn(&run_colors_tests.step);
    test_step.dependOn(&run_format_tests.step);
    test_step.dependOn(&run_memory_tests.step);
    test_step.dependOn(&run_process_tests.step);
    test_step.dependOn(&run_cli_tests.step);
}
