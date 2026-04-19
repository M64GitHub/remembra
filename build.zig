const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "remembra",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/remembra.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.linkSystemLibrary("sqlite3", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run REMEMBRA");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/remembra.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    tests.root_module.linkSystemLibrary("sqlite3", .{});

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const spike_or = b.addExecutable(.{
        .name = "spike_openrouter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/spike_openrouter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const spike_or_run = b.addRunArtifact(spike_or);
    const spike_or_step = b.step(
        "spike-openrouter",
        "Probe OpenRouter HTTPS streaming",
    );
    spike_or_step.dependOn(&spike_or_run.step);

    const server_exe = b.addExecutable(.{
        .name = "remembra-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/remembra_server.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    server_exe.root_module.linkSystemLibrary("sqlite3", .{});
    b.installArtifact(server_exe);

    const server_run = b.addRunArtifact(server_exe);
    const server_step = b.step("serve", "Run REMEMBRA HTTP server");
    server_step.dependOn(&server_run.step);
}
