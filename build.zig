const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zttio_mod = b.dependency("zttio", .{
        .target = target,
        .optimize = optimize,
    }).module("zttio");

    const uucode_mod = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{ "east_asian_width", "grapheme_break", "general_category", "is_emoji_presentation", "uppercase_mapping" }),
    }).module("uucode");

    const zweave_mod = b.addModule("zweave", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "zttio", .module = zttio_mod },
            .{ .name = "uucode", .module = uucode_mod },
        },
    });

    const zweave_mod_tests = b.addTest(.{
        .root_module = zweave_mod,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(zweave_mod_tests).step);

    const tracy_enabled = b.option(
        bool,
        "tracy",
        "Build with Tracy support.",
    ) orelse false;

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    importTracy(tracy_enabled, tracy, zweave_mod);

    const example_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("example.zig"),
        .imports = &.{
            .{ .name = "zttio", .module = zttio_mod },
            .{ .name = "zweave", .module = zweave_mod },
        },
    });
    importTracy(tracy_enabled, tracy, example_mod);

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = example_mod,
    });
    const example_run = b.step("run-example", "run example");
    const example_cmd = b.addRunArtifact(example);
    example_run.dependOn(&example_cmd.step);
    example_cmd.step.dependOn(&example.step);
    if (b.args) |args| {
        example_cmd.addArgs(args);
    }
}

fn importTracy(enabled: bool, tracy: *std.Build.Dependency, module: *std.Build.Module) void {
    module.addImport("tracy", tracy.module("tracy"));
    if (enabled) {
        module.addImport("tracy_impl", tracy.module("tracy_impl_enabled"));
    } else {
        module.addImport("tracy_impl", tracy.module("tracy_impl_disabled"));
    }
}
