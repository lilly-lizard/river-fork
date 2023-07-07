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

/// Switch focus to the passed tags.
pub fn setFocusedTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(args, out);
    const output = seat.focused_output orelse return;
    if (output.pending.tags != tags) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = tags;
        server.root.applyPending();
    }
}

/// todo
pub fn incrementFocusedTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    // if no tags are currently focused, default to focusing the first tag
    if (seat.focused_output.pending.tags == 0) {
        seat.focused_output.previous_tags = seat.focused_output.pending.tags;
        seat.focused_output.pending = 1;
        return;
    }

    const wrap_index_u32 = try std.fmt.parseInt(u32, args[1], 10);
    _ = wrap_index_u32;

    const lowest_tag_index = leastSignificantBitIndex(seat.focused_output.pending.tags);
    _ = lowest_tag_index;

    _ = out;
}

/// todo
pub fn decrementFocusedTag(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    _ = out;
    _ = args;
    _ = seat;
}

pub fn spawnTagmask(
    _: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(args, out);
    server.config.spawn_tagmask = tags;
}

/// Set the tags of the focused view.
pub fn setViewTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(args, out);
    if (seat.focused == .view) {
        const view = seat.focused.view;
        view.pending.tags = tags;
        server.root.applyPending();
    }
}

/// Toggle focus of the passsed tags.
pub fn toggleFocusedTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(args, out);
    const output = seat.focused_output orelse return;
    const new_focused_tags = output.pending.tags ^ tags;
    if (new_focused_tags != 0) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = new_focused_tags;
        server.root.applyPending();
    }
}

/// Toggle the passed tags of the focused view
pub fn toggleViewTags(
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(args, out);
    if (seat.focused == .view) {
        const new_tags = seat.focused.view.pending.tags ^ tags;
        if (new_tags != 0) {
            const view = seat.focused.view;
            view.pending.tags = new_tags;
            server.root.applyPending();
        }
    }
}

/// Switch focus to tags that were selected previously
pub fn focusPreviousTags(
    seat: *Seat,
    args: []const []const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len > 1) return error.TooManyArguments;
    const output = seat.focused_output orelse return;
    const previous_tags = output.previous_tags;
    if (output.pending.tags != previous_tags) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = previous_tags;
        server.root.applyPending();
    }
}

/// Set the tags of the focused view to the tags that were selected previously
pub fn sendToPreviousTags(
    seat: *Seat,
    args: []const []const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len > 1) return error.TooManyArguments;

    const output = seat.focused_output orelse return;
    if (seat.focused == .view) {
        const view = seat.focused.view;
        view.pending.tags = output.previous_tags;
        server.root.applyPending();
    }
}

fn parseTags(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!u32 {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    const tags = try std.fmt.parseInt(u32, args[1], 10);

    if (tags == 0) {
        out.* = try std.fmt.allocPrint(util.gpa, "tags may not be 0", .{});
        return Error.Other;
    }

    return tags;
}

fn parseWrapIndex(
    args: []const [:0]const u8,
) Error!u32 {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    const wrap_index_u32 = try std.fmt.parseInt(u32, args[1], 10);

    return wrap_index_u32;
}

/// Returns the index of the least significant bit set in `in`.
/// Returns `Error.Other` if the there are no bits set in `in`.
fn leastSignificantBitIndex(in: u32) Error!u32 {
    if (in == 0) {
        return Error.Other;
    }

    var smallest_bit_index: u5 = 0;
    var current_bit_index: u5 = 31;
    const one: u32 = 1;

    while (true) {
        const current_bit = in & (one << current_bit_index);
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
