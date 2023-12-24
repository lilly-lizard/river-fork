// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 The River Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const mem = std.mem;
const expect = @import("std").testing.expect;

const server = &@import("../main.zig").server;
const util = @import("../util.zig");

const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");

/// todo doc
pub fn incrementMinFocusedTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    return shiftMinFocusedTag(seat, args, out, true);
}

/// todo doc
pub fn decrementMinFocusedTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    return shiftMinFocusedTag(seat, args, out, false);
}

/// todo doc
pub fn incrementMinViewTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    return shiftMinViewTag(seat, args, out, true);
}

/// todo doc
pub fn decrementMinViewTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    return shiftMinViewTag(seat, args, out, false);
}

// ~~ PRIVATE ~~

/// Switch focus to the passed tags.
fn setFocusedTagsInternal(
    seat: *Seat,
    tags: u32,
) void {
    const output = seat.focused_output orelse return;
    if (output.pending.tags != tags) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = tags;
        server.root.applyPending();
    }
}

/// Set the tags of the focused view.
fn setViewTagsInternal(
    seat: *Seat,
    tags: u32,
) void {
    if (seat.focused == .view) {
        const view = seat.focused.view;
        view.pending.tags = tags;
        server.root.applyPending();
    }
}

/// If `increment` is true, the minimum tag is incremented, otherwise it is decremented.
fn shiftMinFocusedTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
    increment: bool,
) Error!void {
    const wrap_index = try parseWrapIndex(args, out);

    // if no tags are currently focused, default to focusing the first tag
    const output = seat.focused_output orelse return;
    if (output.pending.tags == 0) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = 1;
        return;
    }

    const old_tags = output.pending.tags;
    const new_tags = shiftMinTag(wrap_index, old_tags, increment);

    setFocusedTagsInternal(seat, new_tags);
}

/// If `increment` is true, the minimum tag is incremented, otherwise it is decremented.
fn shiftMinViewTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
    increment: bool,
) Error!void {
    const wrap_index = try parseWrapIndex(args, out);

    const output = seat.focused_output orelse return;
    const old_tags = output.pending.tags;
    const new_tags = shiftMinTag(wrap_index, old_tags, increment);

    setViewTagsInternal(seat, new_tags);
}

/// If `increment` is true, the minimum tag is incremented, otherwise it is decremented.
fn shiftMinTag(
    wrap_index: u5,
    old_tags: u32,
    increment: bool,
) u32 {
    const lowest_tag_index = leastSignificantBitIndex(old_tags) catch return old_tags;

    var shifted_tag_index = lowest_tag_index;
    if (increment) {
        shifted_tag_index = shifted_tag_index + 1;
        shifted_tag_index = shifted_tag_index % wrap_index;
    } else {
        if (shifted_tag_index == 0) {
            shifted_tag_index = wrap_index - 1;
        } else {
            shifted_tag_index = shifted_tag_index - 1;
        }
    }

    const one_u32: u32 = 1;
    var new_tags = old_tags ^ (one_u32 << lowest_tag_index); // unset lowest tag
    new_tags = new_tags | (one_u32 << shifted_tag_index); // replace with shifted tag

    return new_tags;
}

fn parseWrapIndex(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!u5 {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    const wrap_index = try std.fmt.parseInt(u5, args[1], 10);

    if (wrap_index == 0) {
        out.* = try std.fmt.allocPrint(util.gpa, "tag index may not be 0", .{});
        return Error.Other;
    }

    return wrap_index;
}

/// Returns the index of the least significant bit set in `in`.
/// Returns `Error.Other` if the there are no bits set in `in`.
fn leastSignificantBitIndex(in: u32) Error!u5 {
    if (in == 0) {
        return Error.Other;
    }

    var smallest_bit_index: u5 = 0;
    var current_bit_index: u5 = 31;
    const one_u32: u32 = 1;

    while (true) {
        const current_bit = in & (one_u32 << current_bit_index);
        if (current_bit != 0) {
            smallest_bit_index = current_bit_index;
        }

        if (current_bit_index == 0) {
            break;
        }
        current_bit_index -= 1;
    }

    return smallest_bit_index;
}

test "leastSignificantBitIndex" {
    const t1 = leastSignificantBitIndex(0);
    try expect(t1 == 0);

    const t2 = leastSignificantBitIndex(0b0010_0000);
    try expect(t2 == 0b0010_0000);

    const t3 = leastSignificantBitIndex(0b1010);
    try expect(t3 == 0b0010);
}
