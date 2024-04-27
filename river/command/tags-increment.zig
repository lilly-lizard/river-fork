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
const math = @import("std").math;

const server = &@import("../main.zig").server;
const util = @import("../util.zig");

const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");

/// Increments the minimum focused tag. Requires an integer parameter
/// specifying the a tag number to wrap around. Examples (wrap_index = 8):
/// - 0010_0000 -> 0001_0000: tag incremented
/// - 0100_0010 -> 0010_0010: only minimum tag gets incremented
/// - 0000_0001 -> 1000_0000: increment and wrap around
pub fn incrementFocusedTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    _ = out;
    return shiftFocusedTags(seat, args, true);
}

/// Decrements the minimum focused tag. Requires an integer parameter
/// specifying the a tag number to wrap around. Examples (wrap_index = 8):
/// - 0010_0000 -> 0100_0000: tag decremented
/// - 0100_0010 -> 1000_0010: only minimum tag gets decremented
/// - 1000_0000 -> 0000_0001: decrement and wrap around
pub fn decrementFocusedTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    _ = out;
    return shiftFocusedTags(seat, args, false);
}

/// Increments the minimum view tag. Requires an integer parameter
/// specifying the a tag number to wrap around. Examples (wrap_index = 8):
/// - 0010_0000 -> 0001_0000: tag incremented
/// - 0100_0010 -> 0010_0010: only minimum tag gets incremented
/// - 0000_0001 -> 1000_0000: increment and wrap around
pub fn incrementViewTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    _ = out;
    return shiftViewTags(seat, args, true);
}

/// Decrements the minimum view tag. Requires an integer parameter
/// specifying the a tag number to wrap around. Examples (wrap_index = 8):
/// - 0010_0000 -> 0100_0000: tag decremented
/// - 0100_0010 -> 1000_0010: only minimum tag gets decremented
/// - 1000_0000 -> 0000_0001: decrement and wrap around
pub fn decrementViewTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    _ = out;
    return shiftViewTags(seat, args, false);
}

// Private functions

/// If `increment` is true, the minimum tag is incremented, otherwise it
/// is decremented.
fn shiftFocusedTags(
    seat: *Seat,
    args: []const [:0]const u8,
    increment: bool,
) Error!void {
    const output = seat.focused_output orelse return;
    const old_tags = output.pending.tags;
    const new_tags = try shiftTags(args, old_tags, increment);

    if (new_tags != 0) {
        output.previous_tags = old_tags;
        output.pending.tags = new_tags;
        server.root.applyPending();
    }
}

/// If `increment` is true, the minimum tag is incremented, otherwise it
/// is decremented.
fn shiftViewTags(
    seat: *Seat,
    args: []const [:0]const u8,
    increment: bool,
) Error!void {
    if (seat.focused != .view) {
        return;
    }
    const view = seat.focused.view;
    const old_tags = view.pending.tags;
    const new_tags = try shiftTags(args, old_tags, increment);

    if (new_tags != 0) {
        view.pending.tags = new_tags;
        server.root.applyPending();
    }
}

/// If `increment` is true, the minimum tag is incremented, otherwise it
/// is decremented.
/// Returns new shifted tags.
fn shiftTags(
    args: []const [:0]const u8,
    old_tags: u32,
    increment: bool,
) Error!u32 {
    const wrap_index: u5 = try parseWrapIndex(args);

    var new_tags = old_tags;
    if (increment) {
        new_tags = new_tags << 1;
        if (wrap_index != 0) {
            const wrapped_tag = (old_tags >> (wrap_index - 1)) & 1;
            const unwrapped_tag = @as(u32, 1) << wrap_index;
            new_tags |= wrapped_tag;
            new_tags &= ~unwrapped_tag;
        }
    } else { // decrement
        new_tags = new_tags >> 1;
        if (wrap_index != 0) {
            const wrapped_tag = (old_tags & 1) << (wrap_index - 1);
            new_tags |= wrapped_tag;
        }
    }

    return new_tags;
}

/// Returning a value of 0 indicates that no wrapping should happen.
/// If the argument is >= 32, an int parsing error is returned because
/// the tags we are shifting are represented as u32.
fn parseWrapIndex(
    args: []const [:0]const u8,
) Error!u5 {
    if (args.len > 2) return Error.TooManyArguments;
    // this argument is optional. 0 indicates no wrapping should happen.
    if (args.len < 2) return 0;
    return try std.fmt.parseInt(u5, args[1], 10);
}
