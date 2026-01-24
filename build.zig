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

    if (b.option(bool, "examples", "build examples") orelse false) {
        const test_example = b.addExecutable(.{
            .name = "test_example",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,

                .root_source_file = b.path("examples/test.zig"),
                .imports = &.{
                    .{ .name = "zttio", .module = zttio_mod },
                    .{ .name = "zweave", .module = zweave_mod },
                },
            }),
        });
        b.installArtifact(test_example);
    }
}
