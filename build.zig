const std = @import("std");

const warn_flags = [_][]const u8{
    "-std=c23",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-Wshadow",
    "-Wcast-qual",
    "-Wcast-align",
    "-Wpointer-arith",
    "-Wmissing-prototypes",
    "-Wwrite-strings",
    "-Wvla",
    "-Wfloat-equal",
    "-Wundef",
    "-Wformat=2",
    "-Wnull-dereference",
    "-Wimplicit-fallthrough",
    "-Wno-unused-parameter",
};

const release_flags = [_][]const u8{
    "-fstack-protector-strong",
    "-ftrivial-auto-var-init=zero",
    "-fno-delete-null-pointer-checks",
};

const linux_flags = [_][]const u8{
    "-D_GNU_SOURCE",
};

const linux_release_flags = [_][]const u8{
    "-D_FORTIFY_SOURCE=3",
};

const linux_x86_64_flags = [_][]const u8{
    "-fstack-clash-protection",
};

const platform_flags = [_][]const u8{
    "-D_POSIX_C_SOURCE=200809L",
    "-D_DARWIN_C_SOURCE",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Version string from git tag") orelse "dev";

    var cflags: std.ArrayList([]const u8) = .empty;
    try cflags.appendSlice(b.allocator, &warn_flags);
    try cflags.appendSlice(b.allocator, &platform_flags);
    if (optimize != .Debug) {
        try cflags.appendSlice(b.allocator, &release_flags);
    }
    if (target.result.os.tag == .linux) {
        try cflags.appendSlice(b.allocator, &linux_flags);
        if (optimize != .Debug) {
            try cflags.appendSlice(b.allocator, &linux_release_flags);
        }
        if (target.result.cpu.arch == .x86_64) {
            try cflags.appendSlice(b.allocator, &linux_x86_64_flags);
        }
    }
    const flags = cflags.items;

    const exe = b.addExecutable(.{
        .name = "ctype",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = if (optimize == .Debug) .full else .trap,
        }),
    });

    exe.root_module.addCMacro("CTYPE_VERSION", b.fmt("\"{s}\"", .{version}));

    exe.root_module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &.{
            "src/term.c",
            "src/words.c",
            "src/stats.c",
            "src/render.c",
            "src/input.c",
            "src/main.c",
        },
        .flags = flags,
    });

    b.installArtifact(exe);

    const install_words = b.addInstallFile(
        b.path("assets/words_en.txt"),
        "share/ctype/words.txt",
    );
    b.getInstallStep().dependOn(&install_words.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run ctype");
    run_step.dependOn(&run_cmd.step);

    const test_exe = b.addExecutable(.{
        .name = "ctype_test",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = if (optimize == .Debug) .full else .trap,
        }),
    });

    test_exe.root_module.addCMacro("CTYPE_VERSION", b.fmt("\"{s}\"", .{version}));

    test_exe.root_module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &.{
            "src/term.c",
            "src/words.c",
            "src/stats.c",
            "src/input.c",
            "src/test_main.c",
        },
        .flags = flags,
    });

    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
