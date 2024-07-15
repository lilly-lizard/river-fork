// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 - 2023 The River Developers
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
const assert = std.debug.assert;
const wlr = @import("wlroots");
const flags = @import("flags");

const log = std.log;
const server = &@import("../main.zig").server;

const Direction = @import("../command.zig").Direction;
const Error = @import("../command.zig").Error;
const Output = @import("../Output.zig");
const Seat = @import("../Seat.zig");
const View = @import("../View.zig");
const Vector = @import("../Vector.zig");

const getOutput = @import("output.zig").getOutput;

/// Focus either the next or the previous visible view, depending on the enum
/// passed. Does nothing if there are 1 or 0 views in the stack.
pub fn focusView(
    seat: *Seat,
    args: []const [:0]const u8,
    _: *?[]const u8,
) Error!void {
    const result = flags.parser([:0]const u8, &.{
        .{ .name = "skip-floating", .kind = .boolean },
    }).parse(args[1..]) catch {
        return error.InvalidValue;
    };
    if (result.args.len < 1) return Error.NotEnoughArguments;
    if (result.args.len > 1) return Error.TooManyArguments;

    if (try getTarget(
        seat,
        result.args[0],
        if (result.flags.@"skip-floating") .skip_float else .all,
    )) |target| {
        seat.focus(target);
        if (target.pending.output != seat.focused_output) {
            seat.focusOutput(target.pending.output);
        }
        server.root.applyPending();
    }
}

/// Swap the currently focused view with either the view higher or lower in the visible stack
pub fn swap(
    seat: *Seat,
    args: []const [:0]const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    if (try getTarget(seat, args[1], .skip_float)) |target| {
        assert(!target.pending.float);
        seat.focused.view.pending_wm_stack_link.swapWith(&target.pending_wm_stack_link);
        seat.cursor.may_need_warp = true;
        server.root.applyPending();
    }
}

const TargetMode = enum { all, skip_float };
fn getTarget(seat: *Seat, direction_str: []const u8, target_mode: TargetMode) !?*View {
    if (seat.focused != .view) return null;
    if (target_mode == .skip_float and seat.focused.view.pending.float) return null;
    const focused_output = seat.focused_output orelse return null;

    // If no currently view is focused, focus the first in the stack.
    if (seat.focused != .view) {
        var it = focused_output.pending.wm_stack.iterator(.forward);
        return it.next();
    }

    // Logical direction, based on the view stack.
    if (std.meta.stringToEnum(Direction, direction_str)) |direction| {
        switch (direction) {
            inline else => |dir| {
                const it_dir = comptime switch (dir) {
                    .next => .forward,
                    .previous => .reverse,
                };
                var it = focused_output.pending.wm_stack.iterator(it_dir);
                while (it.next()) |view| {
                    if (view == seat.focused.view) break;
                } else {
                    unreachable;
                }

                // Return the next view in the stack matching the tags if any.
                while (it.next()) |view| {
                    if (target_mode == .skip_float and view.pending.float) continue;
                    if (focused_output.pending.tags & view.pending.tags != 0) return view;
                }

                // Wrap and return the first view in the stack matching the tags if
                // any is found before completing the loop back to the focused view.
                while (it.next()) |view| {
                    if (view == seat.focused.view) return null;
                    if (target_mode == .skip_float and view.pending.float) continue;
                    if (focused_output.pending.tags & view.pending.tags != 0) return view;
                }

                unreachable;
            },
        }
    }

    // Spatial direction, based on view position.
    if (std.meta.stringToEnum(wlr.OutputLayout.Direction, direction_str)) |direction| {
        const focus_position = Vector.positionOfBox(seat.focused.view.current.box);
        var target: ?*View = null;
        var target_distance: usize = std.math.maxInt(usize);

        var x = focused_output.scene_output.x;
        var y = focused_output.scene_output.y;
        log.info(">>> focused output x = {x}, y = {x}", .{ x, y });

        var it = focused_output.pending.wm_stack.iterator(.forward);
        while (it.next()) |view| {
            if (focused_output.pending.tags & view.pending.tags == 0) continue;
            if (target_mode == .skip_float and view.pending.float) continue;
            if (view == seat.focused.view) continue;
            const view_position = Vector.positionOfBox(view.current.box);
            const position_diff = focus_position.diff(view_position);
            if ((position_diff.direction() orelse continue) != direction) continue;
            const distance = position_diff.length();
            if (distance < target_distance) {
                target = view;
                target_distance = distance;
            }
        }

        if (target != null) {
            log.info(">> local target found", .{});
            // prefer a target from current output
            return target;
        } else {
            log.info(">> local target not found", .{});
        }
        // check adjacent output
        const next_output: *Output = (try getOutput(seat, direction_str)) orelse return target;
        log.info(">> adjacent output found", .{});

        x = next_output.scene_output.x;
        y = next_output.scene_output.y;
        log.info(">>> adjacent output x = {x}, y = {x}", .{ x, y });

        it = next_output.pending.wm_stack.iterator(.forward);
        while (it.next()) |view| {
            if (next_output.pending.tags & view.pending.tags == 0) continue;
            if (target_mode == .skip_float and view.pending.float) continue;
            if (view == seat.focused.view) continue;
            const view_position = Vector.positionOfBox(view.current.box);
            log.info(">>>> potential view x = {x}, y = {x}", .{ view_position.x, view_position.y });
            const position_diff = focus_position.diff(view_position);
            log.info(">>>> potential view diff x = {x}, y = {x}", .{ position_diff.x, position_diff.y });
            const distance = position_diff.length();
            if (distance < target_distance) {
                target = view;
                target_distance = distance;
            }
        }

        if (target != null) {
            log.info(">> adjacent target found", .{});
        } else {
            log.info(">> adjacent target not found", .{});
        }
        return target;
    }

    return Error.InvalidDirection;
}

fn getTargetFromOutput(seat: *Seat, output: *Output, target_mode: TargetMode, focus_position: Vector, direction: wlr.OutputLayout.Direction, target: *?*View, target_distance: *usize) void {
    var it = output.pending.wm_stack.iterator(.forward);
    while (it.next()) |view| {
        if (output.pending.tags & view.pending.tags == 0) continue;
        if (target_mode == .skip_float and view.pending.float) continue;
        if (view == seat.focused.view) continue;
        const view_position = Vector.positionOfBox(view.current.box);
        const position_diff = focus_position.diff(view_position);
        if ((position_diff.direction() orelse continue) != direction) continue;
        const distance = position_diff.length();
        if (distance < target_distance.*) {
            target.* = view;
            target_distance.* = distance;
        }
    }
}
