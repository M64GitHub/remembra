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
        }),
    });

    tests.root_module.linkSystemLibrary("sqlite3", .{});

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const http_test = b.addExecutable(.{
        .name = "http_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/http_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const http_test_run = b.addRunArtifact(http_test);
    const http_test_step = b.step("run-http-test", "Test HTTP client with Ollama");
    http_test_step.dependOn(&http_test_run.step);
}
