const std = @import("std");
const c = @cImport({
    @cInclude("fitsio.h");
});

// Helper to calculate complex magnitude from a flat buffer
// Corresponds to: cabs(slice[f][pol]) in your C code
// We assume the buffer is: [Real, Imag, Real, Imag, ...]
fn getAmp(buffer: []f64, index: usize) f64 {
    const re = buffer[index];
    const im = buffer[index + 1];
    return std.math.sqrt(re * re + im * im);
}

fn findMaxAmpForAnt(pol_idx: usize, n_freqs: i64, n_pols: i64, ant_data: []f64) f64 {
    var max_val: f64 = -1.0;

    // Stride calculation:
    // In C: cube[t][a][f][p]
    // Here 'ant_data' is already offset to the start of [f][p]
    // Each complex number is 2 doubles (Real, Imag)
    // The "Pol" dimension is the fastest moving (after Real/Imag)
    // The "Freq" dimension is outside that.

    var f: usize = 0;
    while (f < n_freqs) : (f += 1) {
        // Index Logic:
        // f * (stride of one frequency block) + p * (stride of one complex number)
        // stride of freq block = n_pols * 2 doubles
        // stride of complex = 2 doubles
        const idx = (f * @as(usize, @intCast(n_pols)) * 2) + (pol_idx * 2);

        const amp = getAmp(ant_data, idx);
        if (amp > max_val) max_val = amp;
    }
    return max_val;
}

fn checkAmps(n_time: i64, n_ants: i64, n_freqs: i64, n_pols: i64, buffer: []f64) !void {
    var t: usize = 0;

    // Pre-calculate strides for performance (and sanity)
    // One "Time" step contains: n_ants * n_freqs * n_pols * 2(complex) doubles
    const ant_stride = @as(usize, @intCast(n_freqs * n_pols * 2));
    const time_stride = @as(usize, @intCast(n_ants)) * ant_stride;

    while (t < n_time) : (t += 1) {
        var a: usize = 0;
        while (a < n_ants) : (a += 1) {

            // Calculate where this specific antenna's data starts in the big buffer
            const offset = (t * time_stride) + (a * ant_stride);
            const ant_slice = buffer[offset .. offset + ant_stride];

            // C code: find_max_amp_for_ant(0, ...) -> XX
            // C code: find_max_amp_for_ant(3, ...) -> YY
            const temp_xx = findMaxAmpForAnt(0, n_freqs, n_pols, ant_slice);
            const temp_yy = findMaxAmpForAnt(3, n_freqs, n_pols, ant_slice);

            std.debug.print("T: {d:3}, ant: {d:3}, XX: {d:7.5}, YY: {d:7.5}\n", .{ t, a, temp_xx, temp_yy });
        }
    }
}

pub fn cmdCheckAmps(args: [][:0]u8, allocator: std.mem.Allocator) !void {
    if (args.len != 2) {
        std.debug.print("Usage: radio checkamps [filename]\n", .{});
        return error.InvalidArgs;
    }

    const filename = args[1];
    var status: c_int = 0;
    var fptr: ?*c.fitsfile = null;

    // Open file
    _ = c.fits_open_file(&fptr, filename.ptr, c.READONLY, &status);

    // Defer the closing of file
    defer {
        _ = c.fits_close_file(fptr, &status);
    }

    // Move to SOLUTIONS HDU
    _ = c.fits_movnam_hdu(fptr, c.IMAGE_HDU, @constCast("SOLUTIONS"), 0, &status);

    if (status != 0) {
        _ = c.fits_report_error(c.stderr(), status);
        return error.FitsError;
    }

    // Get dimensions
    var naxis: c_int = 0;
    _ = c.fits_get_img_dim(fptr, &naxis, &status);

    var naxes = [_]c_long{ 1, 1, 1, 1 };
    _ = c.fits_get_img_size(fptr, 4, &naxes, &status);

    std.debug.print("Shape: ({d}, {d}, {d}, {d})\n", .{ naxes[0], naxes[1], naxes[2], naxes[3] });

    const total_pix: usize = @intCast(naxes[0] * naxes[1] * naxes[2] * naxes[3]);

    // Allocate buffer
    const buffer = try allocator.alloc(f64, total_pix);
    defer allocator.free(buffer);

    var fpixel = [_]c_long{ 1, 1, 1, 1 };
    _ = c.fits_read_pix(fptr, c.TDOUBLE, &fpixel, @intCast(total_pix), null, buffer.ptr, // Pass the raw pointer to C
        null, &status);

    if (status != 0) {
        c.fits_report_error(c.stderr(), status);
        return error.FitsError;
    }

    // Calculate dimensions
    const n_pols = @divExact(naxes[0], 2); // 2 doubles per complex
    const n_freqs = naxes[1];
    const n_ants = naxes[2];
    const n_time = naxes[3];

    try checkAmps(n_time, n_ants, n_freqs, n_pols, buffer);
}

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

        cmdCheckAmps(args[1..], allocator) catch {
            std.process.exit(1);
        };
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
    }
}
