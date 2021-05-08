const std = @import("std");
const math = std.math;

const termbox = @import("termbox.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

// tb_shutdown() calls abort() if tb_init() wasn't called, or if tb_shutdown()
// was called twice. Keep track of termbox's state to prevent this.
var is_tb_inited = false;

pub fn init() !void {
    if (is_tb_inited)
        return error.AlreadyInitialized;

    switch (termbox.tb_init()) {
        0 => is_tb_inited = true,
        termbox.TB_EFAILED_TO_OPEN_TTY => return error.TTYOpenFailed,
        termbox.TB_EUNSUPPORTED_TERMINAL => return error.UnsupportedTerminal,
        termbox.TB_EPIPE_TRAP_ERROR => return error.PipeTrapFailed,
        else => unreachable,
    }

    _ = termbox.tb_select_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
    _ = termbox.tb_set_clear_attributes(termbox.TB_WHITE, termbox.TB_BLACK);
    _ = termbox.tb_clear();
}

pub fn deinit() !void {
    if (!is_tb_inited)
        return error.AlreadyDeinitialized;
    termbox.tb_shutdown();
    is_tb_inited = false;
}

fn _draw_string(_x: isize, _y: isize, bg: u32, fg: u32, str: []const u8) !isize {
    var x = _x;
    var y = _y;

    var utf8 = (try std.unicode.Utf8View.init(str)).iterator();
    while (utf8.nextCodepointSlice()) |encoded_codepoint| {
        const codepoint = try std.unicode.utf8Decode(encoded_codepoint);

        if (codepoint == '\n') {
            x = _x;
            y += 1;
            continue;
        }

        termbox.tb_change_cell(x, y, codepoint, bg, fg);
        x += 1;
    }

    return y + 1;
}

fn _draw_infopanel(player: *Mob, moblist: *const std.ArrayList(*Mob), startx: isize, starty: isize, endx: isize, endy: isize) void {
    var y = starty;

    y = _draw_string(startx, y, 0xffffff, 0, "@: You") catch unreachable;

    _ = _draw_string(startx, y, 0xffffff, 0, "HP") catch unreachable;
    {
        var x = startx + 3;
        const HP_percent = (player.HP * 100) / player.max_HP;
        const HP_bar = @divTrunc((endx - x - 1) * 100, @intCast(isize, HP_percent));
        const HP_bar_end = x + HP_bar;

        while (x < HP_bar_end) : (x += 1) {
            termbox.tb_change_cell(x, y, ' ', 0, 0xffffff);
        }
    }
    y += 1;
}

fn _mobs_can_see(moblist: *const std.ArrayList(*Mob), coord: Coord) bool {
    for (moblist.items) |mob| {
        if (mob.is_dead) continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

pub fn draw() void {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const playery = @intCast(isize, state.player.y);
    const playerx = @intCast(isize, state.player.x);
    var player = state.dungeon[state.player.y][state.player.x].mob orelse unreachable;

    const maxy: isize = termbox.tb_height() - 8;
    const maxx: isize = termbox.tb_width() - 30;
    const minx: isize = 0;
    const miny: isize = 0;

    const starty = playery - @divFloor(maxy, 2);
    const endy = playery + @divFloor(maxy, 2);
    const startx = playerx - @divFloor(maxx, 2);
    const endx = playerx + @divFloor(maxx, 2);

    var cursory: isize = 0;
    var cursorx: isize = 0;

    // Create a list of all mobs on the map so that we can calculate what tiles
    // are in the FOV of any mob. Use all mobs on the map, not just the ones
    // that will be displayed.
    var moblist = std.ArrayList(*Mob).init(&fba.allocator);
    {
        var iy = starty;
        while (iy < endy) : (iy += 1) {
            var ix: isize = startx;
            while (ix < endx) : (ix += 1) {
                if (iy < 0 or ix < 0 or iy >= state.HEIGHT or ix >= state.WIDTH) {
                    continue;
                }

                const u_x: usize = @intCast(usize, ix);
                const u_y: usize = @intCast(usize, iy);
                const coord = Coord.new(u_x, u_y);

                if (coord.eq(state.player))
                    continue;

                if (state.dungeon[u_y][u_x].mob) |*mob| {
                    if (!player.cansee(coord))
                        continue;

                    moblist.append(mob) catch unreachable;
                }
            }
        }
    }

    var y = starty;
    while (y < endy and cursory < @intCast(usize, maxy)) : ({
        y += 1;
        cursory += 1;
        cursorx = 0;
    }) {
        var x: isize = startx;
        while (x < endx and cursorx < maxx) : ({
            x += 1;
            cursorx += 1;
        }) {
            // if out of bounds on the map, draw a black tile
            if (y < 0 or x < 0 or y >= state.HEIGHT or x >= state.WIDTH) {
                termbox.tb_change_cell(cursorx, cursory, ' ', 0, 0);
                continue;
            }

            const u_x: usize = @intCast(usize, x);
            const u_y: usize = @intCast(usize, y);
            const coord = Coord.new(u_x, u_y);

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!player.cansee(coord)) {
                if (player.memory.contains(coord)) {
                    const tile = @as(u32, player.memory.get(coord) orelse unreachable);
                    termbox.tb_change_cell(cursorx, cursory, tile, 0x3f3f3f, 0x101010);
                } else {
                    termbox.tb_change_cell(cursorx, cursory, ' ', 0xffffff, 0);
                }
                continue;
            }

            switch (state.dungeon[u_y][u_x].type) {
                .Wall => termbox.tb_change_cell(cursorx, cursory, '#', 0x505050, 0x9e9e9e),
                .Floor => if (state.dungeon[u_y][u_x].mob) |mob| {
                    var color: u32 = 0x1e1e1e;

                    if (mob.current_pain() > 0.0) {
                        var red = @floatToInt(u32, mob.current_pain() * 0x7ff);
                        color = math.clamp(red, 0x00, 0xee) << 16;
                    }

                    if (mob.is_dead) {
                        color = 0xdc143c;
                    }

                    termbox.tb_change_cell(cursorx, cursory, mob.tile, 0xffffff, color);
                } else {
                    const tile: u32 = if (_mobs_can_see(&moblist, coord)) '·' else ' ';
                    var color: u32 = if (state.dungeon[u_y][u_x].marked)
                        0x454545
                    else
                        0x1e1e1e;
                    termbox.tb_change_cell(cursorx, cursory, tile, 0xffffff, color);
                },
            }

            if (u_y == playery and u_x == playerx)
                termbox.tb_change_cell(cursorx, cursory, '@', 0x0, 0xffffff);
        }
    }

    _draw_infopanel(&player, &moblist, maxx, 1, termbox.tb_width(), maxy);

    termbox.tb_present();
    state.reset_marks();
}
