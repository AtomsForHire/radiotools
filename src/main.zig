const std = @import("std");
const check_amps = @import("check_amps.zig");

pub fn main() !void {

    // Get allocator, should chose more appropriate allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Get args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: radio <subcommand> [args...]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[1];

    // Subcommand dispatch
    if (std.mem.eql(u8, subcommand, "checkamps")) {
        try std.fs.File.stdout().writeAll("Running checkamps\n");

        check_amps.cmdCheckAmps(args[1..], allocator) catch {
            std.process.exit(1);
        };
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
    }
}
