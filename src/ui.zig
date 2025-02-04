// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;
const io = std.io;
const assert = std.debug.assert;
const mem = std.mem;
const enums = std.enums;

const RexMap = @import("rexpaint").RexMap;

const display = @import("display.zig");
const colors = @import("colors.zig");
const player = @import("player.zig");
const spells = @import("spells.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const gas = @import("gas.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const termbox = @import("termbox.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");
const rng = @import("rng.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;
const StringBuf64 = @import("buffer.zig").StringBuf64;

const Mob = types.Mob;
const StatusDataInfo = types.StatusDataInfo;
const SurfaceItem = types.SurfaceItem;
const Stat = types.Stat;
const Resistance = types.Resistance;
const Coord = types.Coord;
const Direction = types.Direction;
const Tile = types.Tile;
const Status = types.Status;
const Item = types.Item;
const CoordArrayList = types.CoordArrayList;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// -----------------------------------------------------------------------------

pub const LEFT_INFO_WIDTH: usize = 35;
//pub const RIGHT_INFO_WIDTH: usize = 24;
pub const LOG_HEIGHT: usize = 8;

pub const MIN_HEIGHT = HEIGHT + LOG_HEIGHT + 2;
//const min_width = WIDTH + LEFT_INFO_WIDTH + RIGHT_INFO_WIDTH + 2;
pub const MIN_WIDTH = WIDTH + LEFT_INFO_WIDTH + 2 + 1;

pub fn init() !void {
    try display.init(MIN_WIDTH, MIN_HEIGHT);
    clearScreen();
}

// Check that the window is the minimum size.
//
// Return true if the user resized the window, false if the user press Ctrl+C.
pub fn checkWindowSize() bool {
    while (true) {
        const cur_w = display.width();
        const cur_h = display.height();

        if (cur_w >= MIN_WIDTH and cur_h >= MIN_HEIGHT) {
            // All's well
            clearScreen();
            return true;
        }

        _ = _drawStr(1, 1, cur_w, "Your terminal is too small.", .{});
        _ = _drawStrf(1, 3, cur_w, "Minimum: {}x{}.", .{ MIN_WIDTH, MIN_HEIGHT }, .{});
        _ = _drawStrf(1, 4, cur_w, "Current size: {}x{}.", .{ cur_w, cur_h }, .{});

        display.present();

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return false,
                else => {},
            },
            .Char => |c| switch (c) {
                'q' => return false,
                else => {},
            },
            else => {},
        }
    }
}

pub fn deinit() !void {
    try display.deinit();
}

pub const DisplayWindow = enum { Whole, PlayerInfo, Main, Log };
pub const Dimension = struct {
    startx: usize,
    endx: usize,
    starty: usize,
    endy: usize,

    pub fn width(self: @This()) usize {
        return self.endx - self.startx;
    }

    pub fn height(self: @This()) usize {
        return self.endy - self.starty;
    }
};

pub fn dimensions(w: DisplayWindow) Dimension {
    const height = display.height();
    //const width = display.width();

    const playerinfo_width = LEFT_INFO_WIDTH;
    //const playerinfo_width = width - WIDTH - 2;
    //const enemyinfo_width = RIGHT_INFO_WIDTH;

    const main_start = 1;
    const main_width = WIDTH;
    const main_height = HEIGHT;
    const playerinfo_start = main_start + main_width + 1;
    const log_start = main_start;
    //const enemyinfo_start = main_start + main_width + 1;

    return switch (w) {
        .Whole => .{
            .startx = 1,
            .endx = playerinfo_start + playerinfo_width,
            .starty = 1,
            .endy = height - 1,
        },
        .PlayerInfo => .{
            .startx = playerinfo_start,
            .endx = playerinfo_start + playerinfo_width,
            .starty = 1,
            .endy = height - 1,
            //.width = playerinfo_width,
            //.height = height - 1,
        },
        .Main => .{
            .startx = main_start,
            .endx = main_start + main_width,
            .starty = 1,
            .endy = main_height + 2,
            //.width = main_width,
            //.height = main_height,
        },
        .Log => .{
            .startx = log_start,
            .endx = log_start + main_width,
            .starty = 2 + main_height,
            .endy = height - 1,
            //.width = main_width,
            //.height = math.max(LOG_HEIGHT, height - (2 + main_height) - 1),
        },
    };
}

// Formatting descriptions for stuff. {{{

// XXX: Uses a static internal buffer. Buffer must be consumed before next call,
// not thread safe, etc.
fn _formatBool(val: bool) []const u8 {
    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();

    const color: u21 = if (val) 'b' else 'r';
    const string = if (val) @as([]const u8, "yes") else "no";
    _writerWrite(w, "${u}{s}$.", .{ color, string });

    return fbs.getWritten();
}

// XXX: Uses a static internal buffer. Buffer must be consumed before next call,
// not thread safe, etc.
fn _formatStatusInfo(statusinfo: *const StatusDataInfo) []const u8 {
    const S = struct {
        var buf: [65535]u8 = undefined;
    };

    var fbs = std.io.fixedBufferStream(&S.buf);
    var w = fbs.writer();

    const sname = statusinfo.status.string(state.player);
    switch (statusinfo.duration) {
        .Prm => _writerWrite(w, "$bPrm$. {s}\n", .{sname}),
        .Equ => _writerWrite(w, "$bEqu$. {s}\n", .{sname}),
        .Tmp => _writerWrite(w, "$bTmp$. {s} $g({})$.\n", .{ sname, statusinfo.duration.Tmp }),
        .Ctx => _writerWrite(w, "$bCtx$. {s}\n", .{sname}),
    }

    return fbs.getWritten();
}

fn _writerWrite(writer: io.FixedBufferStream([]u8).Writer, comptime fmt: []const u8, args: anytype) void {
    writer.print(fmt, args) catch err.wat();
}

fn _writerHeader(writer: io.FixedBufferStream([]u8).Writer, linewidth: usize, comptime fmt: []const u8, args: anytype) void {
    writer.writeAll("─($c ") catch err.wat();

    const prev_pos = @intCast(usize, writer.context.getPos() catch err.wat());
    writer.print(fmt, args) catch err.wat();
    const new_pos = @intCast(usize, writer.context.getPos() catch err.wat());

    writer.writeAll(" $.)─") catch err.wat();

    var i: usize = linewidth - (new_pos - prev_pos) - 3 - 3 - 1;
    while (i > 0) : (i -= 1)
        writer.writeAll("─") catch err.wat();

    writer.writeAll("\n\n") catch err.wat();
}

fn _writerHLine(writer: io.FixedBufferStream([]u8).Writer, linewidth: usize) void {
    var i: usize = 0;
    while (i < linewidth) : (i += 1)
        writer.writeAll("─") catch err.wat();
    writer.writeAll("\n") catch err.wat();
}

fn _writerMonsHostility(w: io.FixedBufferStream([]u8).Writer, mob: *Mob) void {
    if (mob.isHostileTo(state.player)) {
        if (mob.ai.is_combative) {
            _writerWrite(w, "$rhostile$.\n", .{});
        } else {
            _writerWrite(w, "$gnon-combatant$.\n", .{});
        }
    } else {
        _writerWrite(w, "$bneutral$.\n", .{});
    }
}

fn _writerMobStats(
    w: io.FixedBufferStream([]u8).Writer,
    mob: *Mob,
) void {
    // TODO: don't manually tabulate this?
    _writerWrite(w, "$cstat       value$.\n", .{});
    inline for (@typeInfo(Stat).Enum.fields) |statv| {
        const stat = @intToEnum(Stat, statv.value);
        const stat_val_raw = mob.stat(stat);
        const stat_val = utils.SignedFormatter{ .v = stat_val_raw };

        if (stat == .Sneak) continue;
        _writerWrite(w, "$c{s: <8}$.   {: >5}\n", .{ stat.string(), stat_val });
    }
    inline for (@typeInfo(Resistance).Enum.fields) |resistancev| {
        const resist = @intToEnum(Resistance, resistancev.value);
        const resist_val = utils.SignedFormatter{ .v = mob.resistance(resist) };
        if (resist_val.v != 0) {
            _writerWrite(w, "$c{s: <8}$.   {: >5}%\n", .{ resist.string(), resist_val });
        }
    }
    _writerWrite(w, "\n", .{});
}

fn _writerStats(
    w: io.FixedBufferStream([]u8).Writer,
    p_stats: ?enums.EnumFieldStruct(Stat, isize, 0),
    p_resists: ?enums.EnumFieldStruct(Resistance, isize, 0),
) void {
    // TODO: don't manually tabulate this?
    _writerWrite(w, "$cstat       value$.\n", .{});
    if (p_stats) |stats| {
        inline for (@typeInfo(Stat).Enum.fields) |statv| {
            const stat = @intToEnum(Stat, statv.value);

            const x_stat_val = utils.getFieldByEnum(Stat, stats, stat);
            // var base_stat_val = @intCast(isize, switch (stat) {
            //     .Missile => combat.chanceOfMissileLanding(state.player),
            //     .Melee => combat.chanceOfMeleeLanding(state.player, null),
            //     .Evade => combat.chanceOfAttackEvaded(state.player, null),
            //     else => state.player.stat(stat),
            // });
            // if (state.dungeon.terrainAt(state.player.coord) == terrain) {
            //     base_stat_val -= terrain_stat_val;
            // }
            // const new_stat_val = base_stat_val + terrain_stat_val;

            if (x_stat_val != 0) {
                // // TODO: use $r for negative '->' values, I tried to do this with
                // // Zig v9.1 but ran into a compiler bug where the `color` variable
                // // was replaced with random garbage.
                // _writerWrite(w, "{s: <8} $a{: >5}$. $b{: >5}$. $a{: >5}$.\n", .{
                //     stat.string(), base_stat_val, terrain_stat_val, new_stat_val,
                // });
                const fmt_val = utils.SignedFormatter{ .v = x_stat_val };
                _writerWrite(w, "{s: <8} $a{: >5}$.\n", .{ stat.string(), fmt_val });
            }
        }
    }
    if (p_resists) |resists| {
        inline for (@typeInfo(Resistance).Enum.fields) |resistancev| {
            const resist = @intToEnum(Resistance, resistancev.value);

            const x_resist_val = utils.getFieldByEnum(Resistance, resists, resist);
            // var base_resist_val = @intCast(isize, state.player.resistance(resist));
            // if (state.dungeon.terrainAt(state.player.coord) == terrain) {
            //     base_resist_val -= terrain_resist_val;
            // }
            // const new_resist_val = base_resist_val + terrain_resist_val;

            if (x_resist_val != 0) {
                // // TODO: use $r for negative '->' values, I tried to do this with
                // // Zig v9.1 but ran into a compiler bug where the `color` variable
                // // was replaced with random garbage.
                // _writerWrite(w, "{s: <8} $a{: >5}$. $b{: >5}$. $a{: >5}$.\n", .{
                //     resist.string(), base_resist_val, terrain_resist_val, new_resist_val,
                // });
                const fmt_val = utils.SignedFormatter{ .v = x_resist_val };
                _writerWrite(w, "{s: <8} $a{: >5}$.\n", .{ resist.string(), fmt_val });
            }
        }
    }
    _writerWrite(w, "\n", .{});
}

fn _getTerrDescription(w: io.FixedBufferStream([]u8).Writer, terrain: *const surfaces.Terrain, linewidth: usize) void {
    _writerWrite(w, "$c{s}$.\n", .{terrain.name});
    _writerWrite(w, "terrain\n", .{});
    _writerWrite(w, "\n", .{});

    if (terrain.fire_retardant) {
        _writerWrite(w, "It will put out fires.\n", .{});
        _writerWrite(w, "\n", .{});
    } else if (terrain.flammability > 0) {
        _writerWrite(w, "It is flammable.\n", .{});
        _writerWrite(w, "\n", .{});
    }

    _writerStats(w, terrain.stats, terrain.resists);
    _writerWrite(w, "\n", .{});

    if (terrain.effects.len > 0) {
        _writerHeader(w, linewidth, "effects", .{});
        for (terrain.effects) |effect| {
            _writerWrite(w, "{s}\n", .{_formatStatusInfo(&effect)});
        }
    }
}

fn _getSurfDescription(w: io.FixedBufferStream([]u8).Writer, surface: SurfaceItem, linewidth: usize) void {
    switch (surface) {
        .Machine => |m| {
            _writerWrite(w, "$c{s}$.\n", .{m.name});
            _writerWrite(w, "feature\n", .{});
            _writerWrite(w, "\n", .{});

            if (m.player_interact) |interaction| {
                const remaining = interaction.max_use - interaction.used;
                const plural: []const u8 = if (remaining == 1) "" else "s";
                _writerWrite(w, "$cInteraction:$. {s}.\n\n", .{interaction.name});
                _writerWrite(w, "You used this machine $b{}$. times.\n", .{interaction.used});
                _writerWrite(w, "It can be used $b{}$. more time{s}.\n", .{ remaining, plural });
                _writerWrite(w, "\n", .{});
            }

            _writerWrite(w, "\n", .{});
        },
        .Prop => |p| _writerWrite(w, "$c{s}$.\nobject\n\n$gNothing to see here.$.\n", .{p.name}),
        .Container => |c| {
            _writerWrite(w, "$cA {s}$.\nContainer\n\n", .{c.name});
            if (c.items.len == 0) {
                _writerWrite(w, "It appears to be empty...\n", .{});
            } else if (!c.isLootable()) {
                _writerWrite(w, "You don't expect to find anything useful inside.\n", .{});
            } else {
                _writerWrite(w, "Who knows what goodies lie within?\n\n", .{});
                _writerWrite(w, "$gBump into it to search for loot.\n", .{});
            }
        },
        .Poster => |p| {
            _writerWrite(w, "$cPoster$.\n\n", .{});
            _writerWrite(w, "Some writing on a board:\n", .{});
            _writerHLine(w, linewidth);
            _writerWrite(w, "$g{s}$.\n", .{p.text});
            _writerHLine(w, linewidth);
        },
        .Stair => |s| {
            if (s == null) {
                _writerWrite(w, "$cDownward Stairs$.\n\n", .{});
                _writerWrite(w, "$gGoing back down would sure be dumb.$.\n", .{});
            } else {
                _writerWrite(w, "$cUpward Stairs$.\n\nStairs to {s}.\n", .{
                    state.levelinfo[s.?.z].name,
                });
            }
            if (state.levelinfo[s.?.z].optional) {
                _writerWrite(w, "\nThese stairs are $coptional$. and lead to more difficult floors.\n", .{});
            }
        },
        .Corpse => |c| {
            // Since the mob object was deinit'd, we can't rely on
            // mob.displayName() working
            const name = c.ai.profession_name orelse c.species.name;
            _writerWrite(w, "$c{s} remains$.\n", .{name});
            _writerWrite(w, "corpse\n\n", .{});
            _writerWrite(w, "This corpse is just begging for a necromancer to raise it.", .{});
        },
    }
}

const MobInfoLine = struct {
    char: u21,
    color: u21 = '.',
    string: std.ArrayList(u8) = std.ArrayList(u8).init(state.GPA.allocator()),

    pub const ArrayList = std.ArrayList(@This());

    pub fn deinitList(list: ArrayList) void {
        for (list.items) |item| item.string.deinit();
        list.deinit();
    }
};

fn _getMonsInfoSet(mob: *Mob) MobInfoLine.ArrayList {
    var list = MobInfoLine.ArrayList.init(state.GPA.allocator());

    {
        var i = MobInfoLine{ .char = '*' };
        i.color = if (mob.HP <= (mob.max_HP / 5)) @as(u21, 'r') else '.';
        i.string.writer().print("{}/{} HP, {} MP", .{ mob.HP, mob.max_HP, mob.MP }) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.prisoner_status) |ps| {
        var i = MobInfoLine{ .char = 'p' };
        const str = if (ps.held_by) |_| "chained" else "prisoner";
        i.string.writer().print("{s}", .{str}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.resistance(.rFume) == 0) {
        var i = MobInfoLine{ .char = 'u' };
        i.string.writer().print("unbreathing $g(100% rFume)$.", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.immobile) {
        var i = MobInfoLine{ .char = 'i' };
        i.string.writer().print("immobile", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.isUnderStatus(.CopperWeapon) != null and mob.hasWeaponOfEgo(.Copper)) {
        var i = MobInfoLine{ .char = 'C', .color = 'r' };
        i.string.writer().print("has copper weapon", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    const mobspeed = mob.stat(.Speed);
    const youspeed = state.player.stat(.Speed);
    if (mobspeed != youspeed) {
        var i = MobInfoLine{ .char = if (mobspeed < youspeed) @as(u21, 'f') else 's' };
        i.color = if (mobspeed < youspeed) @as(u21, 'p') else 'b';
        const str = if (mobspeed < youspeed) "faster than you" else "slower than you";
        i.string.writer().print("{s}", .{str}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.ai.phase == .Investigate) {
        assert(mob.sustiles.items.len > 0);

        var i = MobInfoLine{ .char = '?' };
        var you_str: []const u8 = "";
        {
            const cur_sustile = mob.sustiles.items[mob.sustiles.items.len - 1].coord;
            if (state.dungeon.soundAt(cur_sustile).mob_source) |soundsource| {
                if (soundsource == state.player) {
                    you_str = "your noise";
                }
            }
        }
        i.string.writer().print("investigating {s}", .{you_str}) catch err.wat();

        list.append(i) catch err.wat();
    } else if (mob.ai.phase == .Flee) {
        var i = MobInfoLine{ .char = '!' };
        i.string.writer().print("fleeing", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    {
        var i = MobInfoLine{ .char = '@' };

        if (mob.isHostileTo(state.player) and mob.ai.is_combative) {
            const Awareness = union(enum) { Seeing, Remember: usize, None };
            const awareness: Awareness = for (mob.enemyList().items) |enemyrec| {
                if (enemyrec.mob == state.player) {
                    // Zig, why the fuck do I need to cast the below as Awareness?
                    // Wouldn't I like to fucking chop your fucking type checker into
                    // tiny shreds with a +9 halberd of flaming.
                    break if (enemyrec.last_seen != null and enemyrec.last_seen.?.eq(state.player.coord))
                        @as(Awareness, .Seeing)
                    else
                        Awareness{ .Remember = enemyrec.counter };
                }
            } else .None;

            switch (awareness) {
                .Seeing => {
                    i.color = 'r';
                    i.string.writer().print("sees you", .{}) catch err.wat();
                },
                .Remember => |turns_left| {
                    i.color = 'p';
                    i.string.writer().print("remembers you (~$b{}$. turns left)", .{turns_left}) catch err.wat();
                },
                .None => {
                    i.color = 'b';
                    i.string.writer().print("unaware of you", .{}) catch err.wat();
                },
            }
        } else {
            i.string.writer().print("doesn't care", .{}) catch err.wat();
        }

        list.append(i) catch err.wat();
    }

    if (mob.isUnderStatus(.Sleeping) != null) {
        var i = MobInfoLine{ .char = 'Z' };
        i.string.writer().print("{s}", .{Status.string(.Sleeping, mob)}) catch err.wat();
        list.append(i) catch err.wat();
    }

    return list;
}

fn _getMonsStatsDescription(w: io.FixedBufferStream([]u8).Writer, mob: *Mob, linewidth: usize) void {
    _ = linewidth;

    _writerWrite(w, "$c{s}$.\n", .{mob.displayName()});
    _writerMonsHostility(w, mob);
    _writerWrite(w, "\n", .{});

    _writerMobStats(w, mob);
}

fn _getMonsSpellsDescription(w: io.FixedBufferStream([]u8).Writer, mob: *Mob, linewidth: usize) void {
    _ = linewidth;

    _writerWrite(w, "$c{s}$.\n", .{mob.displayName()});
    _writerMonsHostility(w, mob);
    _writerWrite(w, "\n", .{});

    if (mob.spells.len == 0) {
        _writerWrite(w, "$gThis monster has no spells, and is thus (relatively) safe to underestimate.$.\n", .{});
        _writerWrite(w, "\n", .{});
    } else {
        const chance = spells.appxChanceOfWillOverpowered(mob, state.player);
        const colorset = [_]u21{ 'g', 'b', 'b', 'p', 'p', 'r', 'r', 'r', 'r', 'r' };
        _writerWrite(w, "$cChance to overpower your will$.: ${u}{}%$.\n", .{
            colorset[chance / 10], chance,
        });
        _writerWrite(w, "\n", .{});

        for (mob.spells) |spellcfg| {
            _writerWrite(w, "$c{s}$. $g($b{}$. $gmp)$.\n", .{
                spellcfg.spell.name, spellcfg.MP_cost,
            });

            if (spellcfg.spell.cast_type == .Smite) {
                const target = @as([]const u8, switch (spellcfg.spell.smite_target_type) {
                    .Self => "$bself$.",
                    .SpecificMob => |id| b: {
                        const t = mobs.findMobById(id).?;
                        break :b t.mob.ai.profession_name orelse t.mob.species.name;
                    },
                    .UndeadAlly => "undead ally",
                    .Mob => "you",
                    .Corpse => "corpse",
                });
                _writerWrite(w, "· $ctarget$.: {s}\n", .{target});
            } else if (spellcfg.spell.cast_type == .Bolt) {
                const dodgeable = spellcfg.spell.bolt_dodgeable;
                _writerWrite(w, "· $cdodgeable$.: {s}\n", .{_formatBool(dodgeable)});
            }

            if (!(spellcfg.spell.cast_type == .Smite and
                spellcfg.spell.smite_target_type == .Self))
            {
                const targeting = @as([]const u8, switch (spellcfg.spell.cast_type) {
                    .Ray => @panic("TODO"),
                    .Smite => "smite-targeted",
                    .Bolt => "bolt",
                });
                _writerWrite(w, "· $ctype$.: {s}\n", .{targeting});
            }

            if (spellcfg.spell.checks_will) {
                _writerWrite(w, "· $cwill-checked$.: $byes$.\n", .{});
            } else {
                _writerWrite(w, "· $cwill-checked$.: $rno$.\n", .{});
            }

            switch (spellcfg.spell.effect_type) {
                .Status => |s| _writerWrite(w, "· $gTmp$. {s} ({})\n", .{
                    s.string(state.player), spellcfg.duration,
                }),
                .Heal => _writerWrite(w, "· $gIns$. Heal <{}>\n", .{spellcfg.power}),
                .Custom => {},
            }

            _writerWrite(w, "\n", .{});
        }
    }
}

fn _getMonsDescription(w: io.FixedBufferStream([]u8).Writer, mob: *Mob, linewidth: usize) void {
    _ = linewidth;

    if (mob == state.player) {
        _writerWrite(w, "$cYou.$.\n", .{});
        _writerWrite(w, "\n", .{});

        var statuses = state.player.statuses.iterator();
        while (statuses.next()) |entry| {
            if (state.player.isUnderStatus(entry.key) == null)
                continue;
            _writerWrite(w, "{s}", .{_formatStatusInfo(entry.value)});
        }
        _writerWrite(w, "\n", .{});

        _writerMobStats(w, state.player);
        _writerWrite(w, "\n", .{});

        _writerHeader(w, linewidth, "collected runes", .{});
        var runes_iter = state.collected_runes.iterator();
        while (runes_iter.next()) |rune| if (rune.value.*) {
            _writerWrite(w, "· $b{s}$. Rune", .{rune.key.name()});
        };

        return;
    }

    _writerWrite(w, "$c{s}$.\n", .{mob.displayName()});
    _writerMonsHostility(w, mob);
    _writerWrite(w, "\n", .{});

    const infoset = _getMonsInfoSet(mob);
    defer MobInfoLine.deinitList(infoset);
    for (infoset.items) |info| {
        _writerWrite(w, "${u}{u}$. {s}\n", .{ info.color, info.char, info.string.items });
    }

    _writerWrite(w, "\n", .{});

    const you_melee = combat.chanceOfMeleeLanding(state.player, mob);
    const you_evade = combat.chanceOfAttackEvaded(state.player, null);
    const mob_melee = combat.chanceOfMeleeLanding(mob, state.player);
    const mob_evade = combat.chanceOfAttackEvaded(mob, null);

    const c_melee_you = mob_melee * (100 - you_evade) / 100;
    const c_evade_you = 100 - (you_melee * (100 - mob_evade) / 100);

    const m_colorsets = [_]u21{ 'g', 'g', 'g', 'g', 'b', 'b', 'b', 'b', 'r', 'r', 'r' };
    const e_colorsets = [_]u21{ 'g', 'b', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r' };
    const c_melee_you_color = m_colorsets[c_melee_you / 10];
    const c_evade_you_color = e_colorsets[c_evade_you / 10];

    _writerWrite(w, "${u}{}%$. to hit you.\n", .{ c_melee_you_color, c_melee_you });
    _writerWrite(w, "${u}{}%$. to evade you.\n", .{ c_evade_you_color, c_evade_you });
    _writerWrite(w, "\n", .{});

    _writerWrite(w, "Hits for ~$r{}$. damage.\n", .{mob.totalMeleeOutput(state.player)});
    _writerWrite(w, "\n", .{});

    var statuses = mob.statuses.iterator();
    while (statuses.next()) |entry| {
        if (mob.isUnderStatus(entry.key) == null)
            continue;
        _writerWrite(w, "{s}", .{_formatStatusInfo(entry.value)});
    }
    _writerWrite(w, "\n", .{});

    _writerHeader(w, linewidth, "info", .{});
    if (mob.life_type == .Construct)
        _writerWrite(w, "· is non-living ($bconstruct$.)\n", .{})
    else if (mob.life_type == .Undead)
        _writerWrite(w, "· is non-living ($bundead$.)\n", .{});
    if (mob.ai.is_curious and !mob.deaf)
        _writerWrite(w, "· investigates noises\n", .{})
    else
        _writerWrite(w, "· won't investigate noises\n", .{});
    if (mob.ai.flag(.SocialFighter))
        _writerWrite(w, "· won't attack alone\n", .{});
    if (mob.ai.flag(.MovesDiagonally))
        _writerWrite(w, "· (usually) moves diagonally\n", .{});
    if (mob.ai.flag(.DetectWithHeat))
        _writerWrite(w, "· detected w/ $bDetect Heat$.\n", .{});
    if (mob.ai.flag(.DetectWithElec))
        _writerWrite(w, "· detected w/ $bDetect Electricity$.\n", .{});
    _writerWrite(w, "\n", .{});

    if (mob.ai.flee_effect) |effect| {
        _writerHeader(w, linewidth, "flee behaviour", .{});
        _writerWrite(w, "· {s}", .{_formatStatusInfo(&effect)});
        _writerWrite(w, "\n", .{});
    }
}

fn _getItemDescription(w: io.FixedBufferStream([]u8).Writer, item: Item, linewidth: usize) void {
    _ = linewidth;

    const shortname = (item.shortName() catch err.wat()).constSlice();

    //S.appendChar(w, ' ', (linewidth / 2) -| (shortname.len / 2));
    _writerWrite(w, "$c{s}$.\n", .{shortname});

    const itemtype: []const u8 = switch (item) {
        .Rune => err.wat(),
        .Ring => "ring",
        .Consumable => |c| if (c.is_potion) "potion" else "consumable",
        .Vial => "vial",
        .Projectile => "projectile",
        .Armor => "armor",
        .Cloak => "cloak",
        .Aux => "auxiliary item",
        .Weapon => |wp| if (wp.martial) "martial weapon" else "weapon",
        .Boulder => "boulder",
        .Prop => "prop",
        .Evocable => "evocable",
    };
    _writerWrite(w, "{s}\n", .{itemtype});

    _writerWrite(w, "\n", .{});

    switch (item) {
        .Rune => err.wat(),
        .Ring => _writerWrite(w, "TODO: ring descriptions.", .{}),
        .Consumable => |p| {
            _writerHeader(w, linewidth, "effects", .{});
            for (p.effects) |effect| switch (effect) {
                .Kit => |m| _writerWrite(w, "· $gMachine$. {s}\n", .{m.name}),
                .Damage => |d| _writerWrite(w, "· $gIns$. {s} <$b{}$.>\n", .{ d.kind.string(), d.amount }),
                .Heal => |h| _writerWrite(w, "· $gIns$. heal <$b{}$.>\n", .{h}),
                .Resist => |r| _writerWrite(w, "· $gPrm$. {s: <7} $b{:>4}$.\n", .{ r.r.string(), r.change }),
                .Stat => |s| _writerWrite(w, "· $gPrm$. {s: <7} $b{:>4}$.\n", .{ s.s.string(), s.change }),
                .Gas => |g| _writerWrite(w, "· $gGas$. {s}\n", .{gas.Gases[g].name}),
                .Status => |s| _writerWrite(w, "· $gTmp$. {s}\n", .{s.string(state.player)}),
                .Custom => _writerWrite(w, "· $G(See description)$.\n", .{}),
            };
            _writerWrite(w, "\n", .{});

            if (p.dip_effect) |effect| {
                _writerHeader(w, linewidth, "dip effects", .{});
                _writerWrite(w, "{s}", .{_formatStatusInfo(&effect)});
            }
        },
        .Projectile => |p| {
            const dmg = p.damage orelse @as(usize, 0);
            _writerWrite(w, "$cdamage$.: {}\n", .{dmg});
            switch (p.effect) {
                .Status => |sinfo| {
                    _writerHeader(w, linewidth, "effects", .{});
                    _writerWrite(w, "{s}", .{_formatStatusInfo(&sinfo)});
                },
            }
        },
        .Cloak => |c| _writerStats(w, c.stats, c.resists),
        .Aux => |x| {
            _writerStats(w, x.stats, x.resists);

            if (x.equip_effects.len > 0) {
                _writerHeader(w, linewidth, "on equip", .{});
                for (x.equip_effects) |effect|
                    _writerWrite(w, "· {s}", .{_formatStatusInfo(&effect)});
                _writerWrite(w, "\n", .{});
            }
        },
        .Armor => |a| _writerStats(w, a.stats, a.resists),
        .Weapon => |p| {
            if (p.reach != 1) _writerWrite(w, "$creach:$. {}\n", .{p.reach});
            if (p.delay != 100) {
                const col: u21 = if (p.delay > 100) 'r' else 'a';
                _writerWrite(w, "$cdelay:$. ${u}{}%$.\n", .{ col, p.delay });
            }
            if (p.knockback != 0) _writerWrite(w, "$cknockback:$. {}\n", .{p.knockback});
            _writerWrite(w, "\n", .{});

            if (p.is_dippable) {
                _writerWrite(w, "$aCan be dipped.$.\n", .{});
            } else {
                _writerWrite(w, "$rCan't be dipped.$.\n", .{});
            }
            _writerWrite(w, "\n", .{});

            if (p.dip_effect) |potion| {
                assert(p.dip_counter > 0);
                _writerWrite(w, "$cCurrent dip effect:$.\n", .{});
                _writerWrite(w, "· {s}", .{_formatStatusInfo(&potion.dip_effect.?)});
                _writerWrite(w, "· {} attacks left\n", .{p.dip_counter});
            }
            _writerWrite(w, "\n", .{});

            _writerStats(w, p.stats, null);

            if (p.equip_effects.len > 0) {
                _writerHeader(w, linewidth, "on equip", .{});
                for (p.equip_effects) |effect|
                    _writerWrite(w, "· {s}", .{_formatStatusInfo(&effect)});
                _writerWrite(w, "\n", .{});
            }

            _writerHeader(w, linewidth, "on attack", .{});
            _writerWrite(w, "· $gIns$. damage <{}>\n", .{p.damage});
            for (p.effects) |effect|
                _writerWrite(w, "· {s}", .{_formatStatusInfo(&effect)});
            _writerWrite(w, "\n", .{});
        },
        .Evocable => |e| {
            _writerWrite(w, "$b{}$./$b{}$. charges.\n", .{ e.charges, e.max_charges });
            _writerWrite(w, "$crechargable:$. {s}\n", .{_formatBool(e.rechargable)});
            _writerWrite(w, "\n", .{});

            if (e.delete_when_inert) {
                _writerWrite(w, "$bThis item is destroyed on use.$.", .{});
                _writerWrite(w, "\n", .{});
            }
        },
        .Boulder, .Prop, .Vial => _writerWrite(w, "$G(This item is useless.)$.", .{}),
    }

    _writerWrite(w, "\n", .{});
}

// }}}

fn _clearLineWith(from: usize, to: usize, y: usize, ch: u32, fg: u32, bg: u32) void {
    var x = from;
    while (x <= to) : (x += 1)
        display.setCell(x, y, .{ .ch = ch, .fg = fg, .bg = bg });
}

pub fn clearScreen() void {
    const height = display.height();
    const width = display.width();

    var y: usize = 0;
    while (y < height) : (y += 1)
        _clearLineWith(0, width, y, ' ', 0, colors.BG);
}

fn _clear_line(from: usize, to: usize, y: usize) void {
    _clearLineWith(from, to, y, ' ', 0, colors.BG);
}

pub fn _drawBorder(color: u32, d: Dimension) void {
    var y = d.starty;
    while (y <= d.endy) : (y += 1) {
        var x = d.startx;
        while (x <= d.endx) : (x += 1) {
            if (y != d.starty and y != d.endy and x != d.startx and x != d.endx) {
                continue;
            }

            const char: u21 = if (y == d.starty or y == d.endy) '─' else '│';
            display.setCell(x, y, .{ .ch = char, .fg = color, .bg = colors.BG });
        }
    }

    // Fix corners
    display.setCell(d.startx, d.starty, .{ .ch = '╭', .fg = color, .bg = colors.BG });
    display.setCell(d.endx, d.starty, .{ .ch = '╮', .fg = color, .bg = colors.BG });
    display.setCell(d.startx, d.endy, .{ .ch = '╰', .fg = color, .bg = colors.BG });
    display.setCell(d.endx, d.endy, .{ .ch = '╯', .fg = color, .bg = colors.BG });

    display.present();
}

const DrawStrOpts = struct {
    bg: ?u32 = colors.BG,
    fg: u32 = colors.OFF_WHITE,
    endy: ?usize = null,
    fold: bool = true,
    // When folding text, skip the first X lines. Used to implement scrolling.
    skip_lines: usize = 0,
};

fn _drawStrf(_x: usize, _y: usize, endx: usize, comptime format: []const u8, args: anytype, opts: DrawStrOpts) usize {
    const str = std.fmt.allocPrint(state.GPA.allocator(), format, args) catch err.oom();
    defer state.GPA.allocator().free(str);
    return _drawStr(_x, _y, endx, str, opts);
}

// Escape characters:
//     $g       fg = GREY
//     $G       fg = DARK_GREY
//     $C       fg = CONCRETE
//     $c       fg = LIGHT_CONCRETE
//     $a       fg = AQUAMARINE
//     $p       fg = PINK
//     $b       fg = LIGHT_STEEL_BLUE
//     $r       fg = PALE_VIOLET_RED
//     $o       fg = GOLD
//     $.       reset fg and bg to defaults
//     $~       inverg fg/bg
fn _drawStr(_x: usize, _y: usize, endx: usize, str: []const u8, opts: DrawStrOpts) usize {
    // const width = display.width();
    const height = display.height();

    var x = _x;
    var y = _y;
    var skipped: usize = 0;

    var fg = opts.fg;
    var bg: ?u32 = opts.bg;

    const linewidth = if (opts.fold) @intCast(usize, endx - x + 1) else str.len;

    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, linewidth);
    while (fold_iter.next(&fibuf)) |line| : ({
        y += 1;
        x = _x;
    }) {
        if (skipped < opts.skip_lines) {
            skipped += 1;
            y -= 1; // Stay on the same line
            continue;
        }

        if (y >= height or (opts.endy != null and y >= opts.endy.?)) {
            break;
        }

        var utf8 = (std.unicode.Utf8View.init(line) catch err.bug("bad utf8", .{})).iterator();
        while (utf8.nextCodepointSlice()) |encoded_codepoint| {
            const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch err.bug("bad utf8", .{});
            const def_bg = display.getCell(x, y).bg;

            switch (codepoint) {
                '\n' => {
                    y += 1;
                    x = _x;
                    continue;
                },
                '\r' => err.bug("Bad character found in string.", .{}),
                '$' => {
                    const next_encoded_codepoint = utf8.nextCodepointSlice() orelse
                        err.bug("Found incomplete escape sequence", .{});
                    const next_codepoint = std.unicode.utf8Decode(next_encoded_codepoint) catch err.bug("bad utf8", .{});
                    switch (next_codepoint) {
                        '.' => {
                            fg = opts.fg;
                            bg = opts.bg;
                        },
                        '~' => {
                            const t = fg;
                            fg = bg orelse def_bg;
                            bg = t;
                        },
                        'g' => fg = colors.GREY,
                        'G' => fg = colors.DARK_GREY,
                        'C' => fg = colors.CONCRETE,
                        'c' => fg = colors.LIGHT_CONCRETE,
                        'p' => fg = colors.PINK,
                        'b' => fg = colors.LIGHT_STEEL_BLUE,
                        'r' => fg = colors.PALE_VIOLET_RED,
                        'a' => fg = colors.AQUAMARINE,
                        'o' => fg = colors.GOLD,
                        else => err.bug("Found unknown escape sequence '${u}' (line: '{s}')", .{ next_codepoint, line }),
                    }
                    continue;
                },
                else => {
                    display.setCell(x, y, .{ .ch = codepoint, .fg = fg, .bg = bg orelse def_bg });
                    x += 1;
                },
            }

            if (!opts.fold and x == endx) {
                x -= 1;
            }
        }
    }

    return y;
}

fn _drawBar(
    y: usize,
    startx: usize,
    endx: usize,
    current: usize,
    max: usize,
    description: []const u8,
    bg: u32,
    fg: u32,
    opts: struct { detail: bool = true },
) void {
    assert(current <= max);

    const depleted_bg = colors.percentageOf(bg, 40);
    const percent = if (max == 0) 100 else (current * 100) / max;
    const bar = @divTrunc((endx - startx - 1) * percent, 100);
    const bar_end = startx + bar;

    _clearLineWith(startx, endx - 1, y, ' ', fg, depleted_bg);
    if (percent != 0)
        _clearLineWith(startx, bar_end, y, ' ', fg, bg);

    _ = _drawStr(startx + 1, y, endx, description, .{ .fg = fg, .bg = null });

    if (opts.detail) {
        // Find out the width of "<current>/<max>" so we can right-align it
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        @call(.{ .modifier = .always_inline }, std.fmt.format, .{ fbs.writer(), "{} / {}", .{ current, max } }) catch err.bug("format error", .{});
        const info_width = fbs.getWritten().len;

        _ = _drawStrf(endx - info_width - 1, y, endx, "{} / {}", .{ current, max }, .{ .fg = fg, .bg = null });
    }
}

fn drawInfo(moblist: []const *Mob, startx: usize, starty: usize, endx: usize, endy: usize) void {
    // const last_action_cost = if (state.player.activities.current()) |lastaction| b: {
    //     const spd = @intToFloat(f64, state.player.speed());
    //     break :b (spd * @intToFloat(f64, lastaction.cost())) / 100.0 / 10.0;
    // } else 0.0;

    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    const lvlstr = state.levelinfo[state.player.coord.z].name;
    //_clearLineWith(startx, endx - 1, y, '─', colors.DARK_GREY, colors.BG);
    //const lvlstrx = startx + @divTrunc(endx - startx - 1, 2) - @intCast(isize, (lvlstr.len + 4) / 2);
    //y = _drawStrf(lvlstrx, y, endx, "$G┤$. $c{s}$. $G├$.", .{lvlstr}, .{});
    //y += 1;
    _ = _drawStrf(startx, y, endx, "$cturns:$. {}", .{state.player_turns}, .{});
    y = _drawStrf(endx - lvlstr.len, y, endx, "$c{s}$.", .{lvlstr}, .{});
    y += 1;

    // zig fmt: off
    const stats = [_]struct { b: []const u8, a: []const u8, v: isize }{
        .{ .b = "martial: ", .a = "",  .v = state.player.stat(.Martial) },
        .{ .b = "vision:  ", .a = "",  .v = state.player.stat(.Vision) },
        .{ .b = "rFire:  ",  .a = "%", .v = state.player.resistance(.rFire) },
        .{ .b = "rElec:  ",  .a = "%", .v = state.player.resistance(.rElec) },
    };
    // zig fmt: on

    for (stats) |stat, i| {
        const v = utils.SignedFormatter{ .v = stat.v };
        const x = switch (i % 2) {
            0 => startx,
            1 => endx - std.fmt.count("{s} {: >3}{s}", .{ stat.b, v, stat.a }),
            //2 => startx + (@divTrunc(endx - startx, 3) * 2) + 1,
            else => unreachable,
        };
        const c: u21 = if (stat.v < 0) 'p' else '.';
        _ = _drawStrf(x, y, endx, "$c{s}$. ${u}{: >3}{s}$.", .{ stat.b, c, v, stat.a }, .{});
        if (i % 2 == 1 or i == stats.len - 1)
            y += 1;
    }

    y += 1;

    const bar_endx = endx - 9;

    // Use red if below 40% health
    const color: [2]u32 = if (state.player.HP < (state.player.max_HP / 5) * 2)
        [_]u32{ colors.percentageOf(colors.PALE_VIOLET_RED, 25), colors.LIGHT_PALE_VIOLET_RED }
    else
        [_]u32{ colors.percentageOf(colors.DOBALENE_BLUE, 25), colors.DOBALENE_BLUE };
    _drawBar(y, startx, bar_endx, state.player.HP, state.player.max_HP, "health", color[0], color[1], .{});
    const hit = combat.chanceOfMeleeLanding(state.player, null);
    _ = _drawStrf(bar_endx + 1, y, endx, "$.hit {: >3}%$.", .{hit}, .{});
    y += 1;

    _drawBar(y, startx, bar_endx, state.player.MP, state.player.max_MP, "magic", colors.percentageOf(colors.GOLD, 25), colors.LIGHT_GOLD, .{});
    const ev = utils.SignedFormatter{ .v = state.player.stat(.Evade) };
    _ = _drawStrf(bar_endx + 1, y, endx, "$pev  {: >3}%$.", .{ev}, .{});
    y += 1;

    const sneak = @intCast(usize, state.player.stat(.Sneak));
    const is_walking = state.player.turnsSpentMoving() >= sneak;
    _drawBar(y, startx, bar_endx, math.min(sneak, state.player.turnsSpentMoving()), sneak, if (is_walking) "walking" else "sneaking", if (is_walking) 0x25570e else 0x154705, 0xa5d78e, .{});
    const arm = utils.SignedFormatter{ .v = state.player.resistance(.Armor) };
    _ = _drawStrf(bar_endx + 1, y, endx, "$barm {: >3}%$.", .{arm}, .{});
    y += 2;

    {
        var status_drawn = false;
        var statuses = state.player.statuses.iterator();
        while (statuses.next()) |entry| {
            if (state.player.isUnderStatus(entry.key) == null)
                continue;

            const statusinfo = state.player.isUnderStatus(entry.key).?;
            const sname = statusinfo.status.string(state.player);

            if (statusinfo.duration == .Tmp) {
                _drawBar(y, startx, endx, statusinfo.duration.Tmp, Status.MAX_DURATION, sname, 0x30055c, 0xd069fc, .{});
            } else {
                _drawBar(y, startx, endx, Status.MAX_DURATION, Status.MAX_DURATION, sname, 0x054c20, 0x69fcd0, .{ .detail = false });
            }

            //y = _drawStrf(startx, y, endx, "{s} ({} turns)", .{ sname, duration }, .{ .fg = 0x8019ac, .bg = null });
            y += 1;
            status_drawn = true;
        }
        if (status_drawn) y += 1;
    }

    const light = state.dungeon.lightAt(state.player.coord).*;
    const spotted = player.isPlayerSpotted();

    if (light or spotted) {
        const lit_str = if (light) "$C$~ Lit $. " else "";
        const spotted_str = if (spotted) "$bSpotted$. " else "";

        y = _drawStrf(startx, y, endx, "{s}{s}", .{
            lit_str, spotted_str,
        }, .{});
        y += 1;
    }

    var ring_i: usize = 0;
    while (ring_i <= 9) : (ring_i += 1)
        if (player.getRingByIndex(ring_i)) |ring| {
            if (ring.activated) {
                const bg = colors.percentageOf(colors.CONCRETE, 10);
                _clearLineWith(startx, endx, y, ' ', bg, bg);
                y = _drawStrf(startx, y, endx, "$c· {s}$.", .{ring.name}, .{ .bg = bg });
            } else {
                y = _drawStrf(startx, y, endx, "$b{}$. $c{s}$.", .{ ring_i, ring.name }, .{});
            }
        };
    y += 1;

    // ------------------------------------------------------------------------

    {
        const FeatureInfo = struct {
            name: StringBuf64,
            tile: display.Cell,
            priority: usize,
            player: bool,
        };

        var features = std.ArrayList(FeatureInfo).init(state.GPA.allocator());
        defer features.deinit();

        for (state.player.fov) |row, iy| for (row) |_, ix| {
            const coord = Coord.new2(state.player.coord.z, ix, iy);

            if (state.player.fov[iy][ix] > 0) {
                var name = StringBuf64.init(null);
                var priority: usize = 0;

                if (state.dungeon.itemsAt(coord).len > 0) {
                    const item = state.dungeon.itemsAt(coord).last().?;
                    if (item != .Vial and item != .Prop and item != .Boulder) {
                        name.appendSlice((item.shortName() catch err.wat()).constSlice()) catch err.wat();
                    }
                    priority = 3;
                } else if (state.dungeon.at(coord).surface) |surf| {
                    priority = 2;
                    name.appendSlice(switch (surf) {
                        .Machine => |m| if (m.player_interact != null) m.name else "",
                        .Prop => "",
                        .Corpse => "corpse",
                        .Container => |c| c.name,
                        .Poster => "poster",
                        .Stair => |s| if (s != null) "upward stairs" else "",
                    }) catch err.wat();
                } else if (!mem.eql(u8, state.dungeon.terrainAt(coord).id, "t_default")) {
                    priority = 1;
                    name.appendSlice(state.dungeon.terrainAt(coord).name) catch err.wat();
                } else if (state.dungeon.at(coord).type != .Wall) {
                    const material = state.dungeon.at(coord).material;
                    switch (state.dungeon.at(coord).type) {
                        .Wall => name.fmt("{s} wall", .{material.name}),
                        .Floor => name.fmt("{s} floor", .{material.name}),
                        .Lava => name.appendSlice("lava") catch err.wat(),
                        .Water => name.appendSlice("water") catch err.wat(),
                    }
                }

                if (name.len > 0) {
                    const existing = utils.findFirstNeedlePtr(features.items, name, struct {
                        pub fn func(f: *const FeatureInfo, n: StringBuf64) bool {
                            return mem.eql(u8, n.constSlice(), f.name.constSlice());
                        }
                    }.func);
                    if (existing == null) {
                        features.append(FeatureInfo{
                            .name = name,
                            .tile = Tile.displayAs(coord, true, true),
                            .player = state.player.coord.eq(coord),
                            .priority = priority,
                        }) catch err.wat();
                    } else {
                        if (state.player.coord.eq(coord))
                            existing.?.player = true;
                    }
                }
            }
        };

        std.sort.sort(FeatureInfo, features.items, {}, struct {
            pub fn f(_: void, a: FeatureInfo, b: FeatureInfo) bool {
                return a.priority < b.priority;
            }
        }.f);

        for (features.items) |feature| {
            display.setCell(startx, y, feature.tile);

            _ = _drawStrf(startx + 2, y, endx, "$c{s}$.", .{feature.name.constSlice()}, .{});
            if (feature.player) {
                _ = _drawStrf(endx - 1, y, endx, "@", .{}, .{});
            }

            y += 1;
        }
    }
    y += 1;

    // ------------------------------------------------------------------------

    for (moblist) |mob| {
        if (mob.is_dead) continue;

        _clear_line(startx, endx, y);
        _clear_line(startx, endx, y + 1);

        display.setCell(startx, y, Tile.displayAs(mob.coord, true, false));

        const name = mob.displayName();
        _ = _drawStrf(startx + 2, y, endx, "$c{s}$.", .{name}, .{ .bg = null });

        const infoset = _getMonsInfoSet(mob);
        defer MobInfoLine.deinitList(infoset);
        //var info_x: isize = startx + 2 + @intCast(isize, name.len) + 2;
        var info_x: usize = endx - infoset.items.len;
        for (infoset.items) |info| {
            _ = _drawStrf(info_x, y, endx, "${u}{u}$.", .{ info.color, info.char }, .{ .bg = null });
            info_x += 1;
        }
        y += 1;

        //_drawBar(y, startx, endx, @floatToInt(usize, mob.HP), @floatToInt(usize, mob.max_HP), "health", 0x232faa, 0xffffff, .{});
        //y += 1;

        {
            var status_drawn = false;
            var statuses = mob.statuses.iterator();
            while (statuses.next()) |entry| {
                if (mob.isUnderStatus(entry.key) == null or entry.value.duration != .Tmp)
                    continue;

                const statusinfo = mob.isUnderStatus(entry.key).?;
                const duration = statusinfo.duration.Tmp;
                const sname = statusinfo.status.string(state.player);

                _drawBar(y, startx, endx, duration, Status.MAX_DURATION, sname, 0x30055c, 0xd069fc, .{});
                //y = _drawStrf(startx, y, endx, "{s}", .{_formatStatusInfo(entry.value)}, .{ .bg = null });
                y += 1;
                status_drawn = true;
            }
            if (status_drawn) y += 1;
        }

        //const activity = if (mob.prisoner_status != null) if (mob.prisoner_status.?.held_by != null) "(chained)" else "(prisoner)" else mob.activity_description();
        //y = _drawStrf(endx - @divTrunc(endx - startx, 2) - @intCast(isize, activity.len / 2), y, endx, "{s}", .{activity}, .{ .fg = 0x9a9a9a });

        //y += 2;
    }
}

fn drawLog(startx: usize, endx: usize, alloc: mem.Allocator) Console {
    const linewidth = @intCast(usize, endx - startx - 1);

    var parent_console = Console.init(alloc, linewidth, 512); // TODO: alloc on demand

    if (state.messages.items.len == 0)
        return parent_console;

    const messages_len = state.messages.items.len - 1;

    var total_height: usize = 0;
    for (state.messages.items) |message, i| {
        var console = Console.init(alloc, linewidth, 7);

        const col = if (message.turn >= state.player_turns or i == messages_len)
            message.type.color()
        else
            colors.darken(message.type.color(), 2);

        const line = if (i > 0 and i < messages_len and (message.turn != state.messages.items[i - 1].turn and message.turn != state.messages.items[i + 1].turn))
            @as(u21, ' ')
        else if (i == 0 or message.turn > state.messages.items[i - 1].turn)
            @as(u21, '╭')
        else if (i == messages_len or message.turn < state.messages.items[i + 1].turn)
            @as(u21, '╰')
        else
            @as(u21, '│');

        const noisetext: []const u8 = if (message.noise) "$c─$a♫$. " else "$c─$.  ";

        var lines: usize = undefined;
        if (message.dups == 0) {
            lines = console.drawTextAtf(0, 0, "$G{u}$.{s}{s}", .{ line, noisetext, utils.used(message.msg) }, .{ .fg = col });
        } else {
            lines = console.drawTextAtf(0, 0, "$G{u}$.{s}{s} (×{})", .{ line, noisetext, utils.used(message.msg), message.dups + 1 }, .{ .fg = col });
        }

        total_height += lines;
        console.changeHeight(lines);
        parent_console.addSubconsole(console, null, null);
    }

    parent_console.changeHeight(total_height);

    return parent_console;
}

fn _mobs_can_see(moblist: []const *Mob, coord: Coord) bool {
    for (moblist) |mob| {
        if (mob.is_dead or mob.no_show_fov or
            !mob.ai.is_combative or !mob.isHostileTo(state.player))
            continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

fn modifyTile(moblist: []const *Mob, coord: Coord, p_tile: display.Cell) display.Cell {
    var tile = p_tile;

    // Draw noise and indicate if that tile is visible by another mob
    switch (state.dungeon.at(coord).type) {
        .Floor => {
            const has_stuff = state.dungeon.at(coord).surface != null or
                state.dungeon.at(coord).mob != null or
                state.dungeon.itemsAt(coord).len > 0;

            const light = state.dungeon.lightAt(state.player.coord).*;
            if (state.player.coord.eq(coord)) {
                tile.fg = if (light) colors.LIGHT_CONCRETE else colors.LIGHT_STEEL_BLUE;
            }

            if (_mobs_can_see(moblist, coord)) {
                // Treat this cell specially if it's the player and the player is
                // being watched.
                if (state.player.coord.eq(coord) and _mobs_can_see(moblist, coord)) {
                    return .{ .bg = colors.LIGHT_CONCRETE, .fg = colors.BG, .ch = '@' };
                }

                if (has_stuff) {
                    if (state.is_walkable(coord, .{ .right_now = true })) {
                        // Swap.
                        tile.fg ^= tile.bg;
                        tile.bg ^= tile.fg;
                        tile.fg ^= tile.bg;
                    }
                } else {
                    //tile.ch = '⬞';
                    //tile.ch = '÷';
                    //tile.fg = 0xffffff;
                    tile.fg = 0xff6666;
                }
            }
        },
        else => {},
    }

    return tile;
}

pub fn drawMap(moblist: []const *Mob, startx: usize, endx: usize, starty: usize, endy: usize) void {
    //const playery = @intCast(isize, state.player.coord.y);
    //const playerx = @intCast(isize, state.player.coord.x);
    const level = state.player.coord.z;

    var cursory = starty;
    var cursorx = startx;

    //const height = @intCast(usize, endy - starty);
    //const width = @intCast(usize, endx - startx);
    //const map_starty = playery - @intCast(isize, height / 2);
    //const map_endy = playery + @intCast(isize, height / 2);
    //const map_startx = playerx - @intCast(isize, width / 2);
    //const map_endx = playerx + @intCast(isize, width / 2);

    const map_starty: usize = 0;
    const map_endy: usize = HEIGHT;
    const map_startx: usize = 0;
    const map_endx: usize = WIDTH;

    var y = map_starty;
    while (y < map_endy and cursory < endy) : ({
        y += 1;
        cursory += 1;
        cursorx = startx;
    }) {
        var x: usize = map_startx;
        while (x < map_endx and cursorx < endx) : ({
            x += 1;
            cursorx += 1;
        }) {
            // if out of bounds on the map, draw a black tile
            if (y < 0 or x < 0 or y >= HEIGHT or x >= WIDTH) {
                display.setCell(cursorx, cursory, .{ .bg = colors.BG });
                continue;
            }

            const u_x: usize = @intCast(usize, x);
            const u_y: usize = @intCast(usize, y);
            const coord = Coord.new2(level, u_x, u_y);

            var tile: display.Cell = undefined;

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!state.player.cansee(coord)) {
                tile = .{ .fg = 0, .bg = colors.BG, .ch = ' ' };

                if (state.memory.contains(coord)) {
                    tile = (state.memory.get(coord) orelse unreachable).tile;

                    const old_sbg = tile.sbg;

                    tile.bg = colors.darken(colors.filterGrayscale(tile.bg), 4);
                    tile.fg = colors.darken(colors.filterGrayscale(tile.fg), 4);
                    tile.sbg = colors.darken(colors.filterGrayscale(tile.sbg), 4);
                    tile.sfg = colors.darken(colors.filterGrayscale(tile.sfg), 4);

                    if (tile.bg < colors.BG) tile.bg = colors.BG;

                    // Don't lighten the sbg if it was originally 0 (because
                    // then we have to fallback to the bg)
                    if (tile.sbg < colors.BG and old_sbg != 0) tile.sbg = colors.BG;
                }

                // Can we hear anything
                if (state.player.canHear(coord)) |noise| if (noise.state == .New) {
                    tile.fg = 0x00d610;
                    tile.ch = if (noise.intensity.radiusHeard() > 6) '♫' else '♩';
                    tile.sch = null;
                };
            } else {
                tile = modifyTile(moblist, coord, Tile.displayAs(coord, false, false));
            }

            display.setCell(cursorx, cursory, tile);
        }
    }
}

pub fn drawNoPresent() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const moblist = state.createMobList(false, true, state.player.coord.z, alloc);

    const pinfo_win = dimensions(.PlayerInfo);
    const main_win = dimensions(.Main);
    const log_window = dimensions(.Log);

    drawInfo(moblist.items, pinfo_win.startx, pinfo_win.starty, pinfo_win.endx, pinfo_win.endy);
    drawMap(moblist.items, main_win.startx, main_win.endx, main_win.starty, main_win.endy);

    const log_console = drawLog(log_window.startx, log_window.endx, alloc);
    log_console.renderAreaAt(
        @intCast(usize, log_window.startx),
        @intCast(usize, log_window.starty),
        0,
        log_console.height -| @intCast(usize, log_window.endy - log_window.starty),
        log_console.width,
        log_console.height,
    );
    log_console.deinit();
}

pub fn draw() void {
    drawNoPresent();
    display.present();
}

pub const ChooseCellOpts = struct {
    require_seen: bool = true,
    max_distance: ?usize = null,
    show_trajectory: bool = false,
    require_lof: bool = false,
};

pub fn chooseCell(opts: ChooseCellOpts) ?Coord {
    const mainw = dimensions(.Main);

    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

    var coord: Coord = state.player.coord;

    while (true) {
        drawMap(moblist.items, mainw.startx, mainw.endx, mainw.starty, mainw.endy);

        if (opts.show_trajectory) {
            const trajectory = state.player.coord.drawLine(coord, state.mapgeometry, 0);
            const fg = if (utils.hasClearLOF(state.player.coord, coord))
                colors.CONCRETE
            else
                colors.PALE_VIOLET_RED;

            for (trajectory.constSlice()) |traj_c| {
                const d_traj_c_y = mainw.starty + traj_c.y;
                const d_traj_c_x = mainw.startx + traj_c.x;

                if (state.player.coord.eq(traj_c)) continue;
                if (coord.eq(traj_c)) break;

                if (!state.is_walkable(traj_c, .{
                    .right_now = true,
                    .only_if_breaks_lof = true,
                }))
                    break;

                display.setCell(d_traj_c_x, d_traj_c_y, .{ .ch = 'x', .fg = fg, .bg = colors.BG });
            }
        }

        const display_x = mainw.startx + coord.x;
        const display_y = mainw.starty + coord.y;
        display.setCell(display_x - 1, display_y - 1, .{ .ch = '╭', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 0, display_y - 1, .{ .ch = '─', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y - 1, .{ .ch = '╮', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 0, .{ .ch = '│', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 0, .{ .ch = '│', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 1, .{ .ch = '╰', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 0, display_y + 1, .{ .ch = '─', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 1, .{ .ch = '╯', .fg = colors.CONCRETE, .bg = colors.BG });

        display.present();

        // This is a bit of a hack, erase the bordering but don't present the
        // changes, so that if the user moves to the edge of the map and then moves
        // away, there won't be bordering left as an artifact (as the map drawing
        // routines won't erase it, since it's outside its window).
        display.setCell(display_x - 1, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x + 0, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 0, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 0, .{ .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 1, .{ .bg = colors.BG });
        display.setCell(display_x + 0, display_y + 1, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 1, .{ .bg = colors.BG });

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .Esc, .CtrlC, .CtrlG => return null,
                .Enter => {
                    if (opts.require_seen and !state.player.cansee(coord) and
                        !state.memory.contains(coord))
                    {
                        drawAlert("You haven't seen that place!", .{});
                    } else if (opts.max_distance != null and
                        coord.distance(state.player.coord) > opts.max_distance.?)
                    {
                        drawAlert("Out of range!", .{});
                    } else if (opts.require_lof and
                        !utils.hasClearLOF(state.player.coord, coord))
                    {
                        drawAlert("There's something in the way.", .{});
                    } else {
                        return coord;
                    }
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'a', 'h' => coord = coord.move(.West, state.mapgeometry) orelse coord,
                'x', 'j' => coord = coord.move(.South, state.mapgeometry) orelse coord,
                'w', 'k' => coord = coord.move(.North, state.mapgeometry) orelse coord,
                'd', 'l' => coord = coord.move(.East, state.mapgeometry) orelse coord,
                'q', 'y' => coord = coord.move(.NorthWest, state.mapgeometry) orelse coord,
                'e', 'u' => coord = coord.move(.NorthEast, state.mapgeometry) orelse coord,
                'z', 'b' => coord = coord.move(.SouthWest, state.mapgeometry) orelse coord,
                'c', 'n' => coord = coord.move(.SouthEast, state.mapgeometry) orelse coord,
                else => {},
            },
            else => {},
        }
    }
}

pub fn chooseDirection() ?Direction {
    const mainw = dimensions(.Main);

    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

    var direction: Direction = .North;

    while (true) {
        drawMap(moblist.items, mainw.startx, mainw.endx, mainw.starty, mainw.endy);

        const maybe_coord = state.player.coord.move(direction, state.mapgeometry);

        if (maybe_coord) |coord| {
            const display_x = mainw.startx + coord.x;
            const display_y = mainw.starty + coord.y;
            const char: u21 = switch (direction) {
                .North => '↑',
                .South => '↓',
                .East => '→',
                .West => '←',
                .NorthEast => '↗',
                .NorthWest => '↖',
                .SouthEast => '↘',
                .SouthWest => '↙',
            };
            display.setCell(display_x, display_y, .{ .ch = char, .fg = colors.LIGHT_CONCRETE, .bg = colors.BG });
        }

        display.present();

        drawModalText(colors.CONCRETE, "direction: {}", .{direction});

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return null,
                .Enter => {
                    if (maybe_coord == null) {
                        //drawAlert("Invalid coord!", .{});
                        drawModalText(0xffaaaa, "Invalid direction!", .{});
                    } else {
                        return direction;
                    }
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'a', 'h' => direction = .West,
                'x', 'j' => direction = .South,
                'w', 'k' => direction = .North,
                'd', 'l' => direction = .East,
                'q', 'y' => direction = .NorthWest,
                'e', 'u' => direction = .NorthEast,
                'z', 'b' => direction = .SouthWest,
                'c', 'n' => direction = .SouthEast,
                else => {},
            },
            else => {},
        }
    }
}

pub const LoadingScreen = struct {
    main_con: Console,
    logo_con: Console,
    text_con: Console,

    pub const TEXT_CON_HEIGHT = 2;
    pub const TEXT_CON_WIDTH = 28;

    pub fn deinit(self: @This()) void {
        self.main_con.deinit();

        // Deinit'ing main_con automatically frees subconsoles
        //self.logo_con.deinit();
        //self.text_con.deinit();
    }
};

pub fn initLoadingScreen() LoadingScreen {
    const win = dimensions(.Whole);
    var win_c: LoadingScreen = undefined;

    const map = RexMap.initFromFile(state.GPA.allocator(), "data/logo.xp") catch err.wat();
    defer map.deinit();

    win_c.main_con = Console.init(state.GPA.allocator(), win.width(), win.height());
    win_c.logo_con = Console.init(state.GPA.allocator(), map.width, map.height + 1); // +1 padding
    win_c.text_con = Console.init(state.GPA.allocator(), LoadingScreen.TEXT_CON_WIDTH, LoadingScreen.TEXT_CON_HEIGHT);

    const starty = (win.height() / 2) - ((map.height + LoadingScreen.TEXT_CON_HEIGHT + 1) / 2);

    win_c.logo_con.drawXP(&map);
    win_c.main_con.addSubconsole(win_c.logo_con, win_c.main_con.centerX(map.width), starty);

    win_c.main_con.addSubconsole(win_c.text_con, win_c.main_con.centerX(LoadingScreen.TEXT_CON_WIDTH), null);

    return win_c;
}

pub fn drawLoadingScreen(loading_win: *LoadingScreen, text_context: []const u8, text: []const u8, percent_done: usize) !void {
    const win = dimensions(.Whole);

    loading_win.text_con.clear();

    var y: usize = 0;
    y += loading_win.text_con.drawTextAt(0, y, text, .{});
    y += loading_win.text_con.drawBarAt(
        0,
        LoadingScreen.TEXT_CON_WIDTH,
        y,
        percent_done,
        100,
        text_context,
        colors.percentageOf(colors.DOBALENE_BLUE, 25),
        colors.DOBALENE_BLUE,
        .{ .detail_type = .Percent },
    );

    loading_win.main_con.renderFully(@intCast(usize, win.startx), @intCast(usize, win.starty));

    display.present();
    clearScreen();

    if (display.waitForEvent(20)) |ev| switch (ev) {
        .Quit => {
            state.state = .Quit;
            return error.Canceled;
        },
        .Key => |k| switch (k) {
            .CtrlC, .Esc, .Enter => return error.Canceled,
            else => {},
        },
        else => {},
    } else |e| if (e != error.NoInput) err.wat();
}

pub fn drawLoadingScreenFinish(loading_win: *LoadingScreen) bool {
    const win = dimensions(.Whole);

    loading_win.text_con.clear();

    const text = switch (rng.range(usize, 0, 99)) {
        0...97 => "-- Press any key to begin --",
        98...99 => "-- Press any key to inevitably die --",
        else => err.wat(),
    };

    _ = loading_win.text_con.drawTextAtf(0, 0, "$b{s}$.", .{text}, .{});

    loading_win.main_con.renderFully(@intCast(usize, win.startx), @intCast(usize, win.starty));

    display.present();
    clearScreen();

    _ = waitForInput(' ') orelse return false;
    return true;
}

pub fn drawTextScreen(comptime fmt: []const u8, args: anytype) void {
    const mainw = dimensions(.Main);

    const text = std.fmt.allocPrint(state.GPA.allocator(), fmt, args) catch err.wat();
    defer state.GPA.allocator().free(text);

    var con = Console.init(state.GPA.allocator(), mainw.width(), mainw.height());
    defer con.deinit();

    var y: usize = 0;
    y += con.drawTextAt(0, y, text, .{});

    con.renderFully(@intCast(usize, mainw.startx), @intCast(usize, mainw.starty));

    display.present();
    clearScreen();

    while (true) {
        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .Enter => return,
                else => {},
            },
            .Char => |c| switch (c) {
                ' ' => return,
                else => {},
            },
            else => {},
        }
    }
}

pub fn drawMessagesScreen() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const mainw = dimensions(.Main);
    const logw = dimensions(.Log);

    assert(logw.starty > mainw.starty);
    assert(logw.endx == mainw.endx);

    var starty = logw.starty;
    const endy = logw.endy;

    const console = drawLog(mainw.startx, mainw.endx, arena.allocator());
    defer console.deinit();

    var scroll: usize = 0;

    while (true) {
        if (starty > mainw.starty) {
            starty = math.max(mainw.starty, starty -| 3);
        }

        // Clear window.
        {
            var y = starty;
            while (y <= endy) : (y += 1)
                _clear_line(mainw.startx, mainw.endx, y);
        }

        const window_height = @intCast(usize, endy - starty - 1);

        scroll = math.min(scroll, console.height -| window_height);

        const first_line = console.height -| window_height -| scroll;
        const last_line = math.min(first_line + window_height, console.height);
        console.renderAreaAt(@intCast(usize, mainw.startx), @intCast(usize, starty), 0, first_line, console.width, last_line);

        display.present();

        if (display.waitForEvent(50)) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .Enter => return,
                else => {},
            },
            .Char => |c| switch (c) {
                'x', 'j' => scroll -|= 1,
                'w', 'k' => scroll += 1,
                'M' => return,
                else => {},
            },
            else => {},
        } else |e| if (e != error.NoInput) break;
    }
}

// Examine mode {{{
pub const ExamineTileFocus = enum { Item, Surface, Mob };

pub fn drawExamineScreen(starting_focus: ?ExamineTileFocus) bool {
    const mainw = dimensions(.Main);
    const logw = dimensions(.Log);
    const infow = dimensions(.PlayerInfo);

    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

    const MobTileFocus = enum { Main, Stats, Spells };

    var coord: Coord = state.player.coord;
    var tile_focus = starting_focus orelse .Mob;
    var mob_tile_focus: MobTileFocus = .Main;
    var desc_scroll: usize = 0;

    var kbd_s = false;
    var kbd_a = false;

    while (true) {
        const has_item = state.dungeon.itemsAt(coord).len > 0;
        const has_mons = state.dungeon.at(coord).mob != null;
        const has_surf = state.dungeon.at(coord).surface != null or !mem.eql(u8, state.dungeon.terrainAt(coord).id, "t_default");

        // Draw side info pane.
        if (state.player.cansee(coord) and has_mons or has_surf or has_item) {
            const linewidth = @intCast(usize, infow.endx - infow.startx);

            var textbuf: [4096]u8 = undefined;
            var text = io.fixedBufferStream(&textbuf);
            var writer = text.writer();

            const mons_tab = if (tile_focus == .Mob) "$cMob$." else "$gMob$.";
            const surf_tab = if (tile_focus == .Surface) "$cSurface$." else "$gSurface$.";
            const item_tab = if (tile_focus == .Item) "$cItem$." else "$gItem$.";
            _writerWrite(writer, "{s} · {s} · {s}$.\n", .{ mons_tab, surf_tab, item_tab });

            _writerWrite(writer, "Press $b<>$. to switch tabs.\n", .{});
            _writerWrite(writer, "\n", .{});

            if (tile_focus == .Mob and has_mons) {
                const mob = state.dungeon.at(coord).mob.?;

                // Sanitize mob_tile_focus
                if (mob == state.player) {
                    mob_tile_focus = .Main;
                }

                switch (mob_tile_focus) {
                    .Main => _getMonsDescription(writer, mob, linewidth),
                    .Spells => _getMonsSpellsDescription(writer, mob, linewidth),
                    .Stats => _getMonsStatsDescription(writer, mob, linewidth),
                }
            } else if (tile_focus == .Surface and has_surf) {
                if (state.dungeon.at(coord).surface) |surf| {
                    _getSurfDescription(writer, surf, linewidth);
                } else {
                    _getTerrDescription(writer, state.dungeon.terrainAt(coord), linewidth);
                }
            } else if (tile_focus == .Item and has_item) {
                _getItemDescription(writer, state.dungeon.itemsAt(coord).last().?, linewidth);
            }

            // Add keybinding descriptions
            if (tile_focus == .Mob and has_mons) {
                const mob = state.dungeon.at(coord).mob.?;
                if (mob != state.player) {
                    kbd_s = true;
                    switch (mob_tile_focus) {
                        .Main => _writerWrite(writer, "Press $bs$. to see stats.\n", .{}),
                        .Stats => _writerWrite(writer, "Press $bs$. to see spells.\n", .{}),
                        .Spells => _writerWrite(writer, "Press $bs$. to see mob.\n", .{}),
                    }
                }

                if (mob != state.player and state.player.canMelee(mob)) {
                    kbd_a = true;
                    _writerWrite(writer, "Press $bA$. to attack.\n", .{});
                }
            } else if (tile_focus == .Surface and has_surf) {
                // nothing
            }

            var y = infow.starty;

            while (y < infow.endy) : (y += 1)
                _clear_line(infow.startx, infow.endx, y);
            y = infow.starty;

            y = _drawStr(infow.startx, y, infow.endx, text.getWritten(), .{});
        } else {
            var y = infow.starty;
            while (y < infow.endy) : (y += 1)
                _clear_line(infow.startx, infow.endx, y);
        }

        // Draw description pane.
        if (state.player.cansee(coord)) {
            const log_startx = logw.startx;
            const log_endx = logw.endx;
            const log_starty = logw.starty;
            const log_endy = logw.endy;

            var descbuf: [4096]u8 = undefined;
            var descbuf_stream = io.fixedBufferStream(&descbuf);
            var writer = descbuf_stream.writer();

            if (tile_focus == .Mob and state.dungeon.at(coord).mob != null) {
                const mob = state.dungeon.at(coord).mob.?;
                if (mob_tile_focus == .Spells) {
                    for (mob.spells) |spell| {
                        if (state.descriptions.get(spell.spell.id)) |spelldesc| {
                            _writerWrite(writer, "$c{s}$.: {s}", .{
                                spell.spell.name, spelldesc,
                            });
                            _writerWrite(writer, "\n\n", .{});
                        }
                    }
                } else {
                    if (state.descriptions.get(mob.id)) |mobdesc| {
                        _writerWrite(writer, "{s}", .{mobdesc});
                        _writerWrite(writer, "\n\n", .{});
                    }
                }
            }

            if (tile_focus == .Surface) {
                if (state.dungeon.at(coord).surface != null) {
                    const id = state.dungeon.at(coord).surface.?.id();
                    if (state.descriptions.get(id)) |surfdesc| {
                        _writerWrite(writer, "{s}", .{surfdesc});
                        _writerWrite(writer, "\n\n", .{});
                    }
                } else {
                    const id = state.dungeon.terrainAt(coord).id;
                    if (state.descriptions.get(id)) |terraindesc| {
                        _writerWrite(writer, "{s}", .{terraindesc});
                        _writerWrite(writer, "\n\n", .{});
                    }
                }
            }

            if (tile_focus == .Item and state.dungeon.itemsAt(coord).len > 0) {
                if (state.dungeon.itemsAt(coord).data[0].id()) |id|
                    if (state.descriptions.get(id)) |itemdesc| {
                        _writerWrite(writer, "{s}", .{itemdesc});
                        _writerWrite(writer, "\n\n", .{});
                    };
            }

            var y = log_starty;
            while (y < log_endy) : (y += 1) _clear_line(log_startx, log_endx, y);

            const lasty = _drawStr(log_startx, log_starty, log_endx, descbuf_stream.getWritten(), .{
                .skip_lines = desc_scroll,
                .endy = log_endy,
            });

            if (desc_scroll > 0) {
                _ = _drawStr(log_endx - 14, log_starty, log_endx, " $p-- PgUp --$.", .{});
            }
            if (lasty == log_endy) {
                _ = _drawStr(log_endx - 14, log_endy - 1, log_endx, " $p-- PgDn --$.", .{});
            }
        }

        drawMap(moblist.items, mainw.startx, mainw.endx, mainw.starty, mainw.endy);

        const display_x = mainw.startx + coord.x;
        const display_y = mainw.starty + coord.y;
        display.setCell(display_x - 1, display_y - 1, .{ .ch = '╭', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 0, display_y - 1, .{ .ch = '─', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y - 1, .{ .ch = '╮', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 0, .{ .ch = '│', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 0, .{ .ch = '│', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 1, .{ .ch = '╰', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 0, display_y + 1, .{ .ch = '─', .fg = colors.CONCRETE, .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 1, .{ .ch = '╯', .fg = colors.CONCRETE, .bg = colors.BG });

        display.present();

        // This is a bit of a hack, erase the bordering but don't present the
        // changes, so that if the user moves to the edge of the map and then moves
        // away, there won't be bordering left as an artifact (as the map drawing
        // routines won't erase it, since it's outside its window).
        display.setCell(display_x - 1, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x + 0, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y - 1, .{ .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 0, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 0, .{ .bg = colors.BG });
        display.setCell(display_x - 1, display_y + 1, .{ .bg = colors.BG });
        display.setCell(display_x + 0, display_y + 1, .{ .bg = colors.BG });
        display.setCell(display_x + 1, display_y + 1, .{ .bg = colors.BG });

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Key => |k| switch (k) {
                .CtrlC, .CtrlG, .Esc => return false,
                .PgUp => desc_scroll -|= 1,
                .PgDn => desc_scroll += 1,
                else => {},
            },
            .Char => |c| switch (c) {
                'a', 'h' => coord = coord.move(.West, state.mapgeometry) orelse coord,
                'x', 'j' => coord = coord.move(.South, state.mapgeometry) orelse coord,
                'w', 'k' => coord = coord.move(.North, state.mapgeometry) orelse coord,
                'd', 'l' => coord = coord.move(.East, state.mapgeometry) orelse coord,
                'q', 'y' => coord = coord.move(.NorthWest, state.mapgeometry) orelse coord,
                'e', 'u' => coord = coord.move(.NorthEast, state.mapgeometry) orelse coord,
                'z', 'b' => coord = coord.move(.SouthWest, state.mapgeometry) orelse coord,
                'c', 'n' => coord = coord.move(.SouthEast, state.mapgeometry) orelse coord,
                'A' => if (kbd_a) {
                    state.player.fight(state.dungeon.at(coord).mob.?, .{});
                    return true;
                },
                's' => if (kbd_s) {
                    mob_tile_focus = switch (mob_tile_focus) {
                        .Main => .Stats,
                        .Stats => .Spells,
                        .Spells => .Main,
                    };
                },
                '>' => {
                    tile_focus = switch (tile_focus) {
                        .Mob => .Surface,
                        .Surface => .Item,
                        .Item => .Mob,
                    };
                    if (tile_focus == .Mob) mob_tile_focus = .Main;
                },
                '<' => {
                    tile_focus = switch (tile_focus) {
                        .Mob => .Item,
                        .Surface => .Mob,
                        .Item => .Surface,
                    };
                    if (tile_focus == .Mob) mob_tile_focus = .Main;
                },
                else => {},
            },
            else => {},
        }
    }

    return false;
}
// }}}

// Wait for input. Return null if Ctrl+c or escape was pressed, default_input
// if <enter> is pressed ,otherwise the key pressed. Will continue waiting if a
// mouse event or resize event was recieved.
pub fn waitForInput(default_input: ?u8) ?u32 {
    while (true) {
        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return null,
                .Enter => if (default_input) |def| return def else continue,
                else => {},
            },
            .Char => |c| return c,
            else => {},
        }
    }
}

pub fn drawInventoryScreen() bool {
    const main_window = dimensions(.Main);
    const iteminfo_window = dimensions(.PlayerInfo);
    const log_window = dimensions(.Log);

    const ItemListType = enum { Pack, Equip };

    var desc_scroll: usize = 0;
    var chosen: usize = 0;
    var chosen_itemlist: ItemListType = if (state.player.inventory.pack.len == 0) .Equip else .Pack;
    var y: usize = 0;

    while (true) {
        clearScreen();

        const starty = main_window.starty;
        const x = main_window.startx;
        const endx = main_window.endx;

        const itemlist_len = if (chosen_itemlist == .Pack) state.player.inventory.pack.len else state.player.inventory.equ_slots.len;
        const chosen_item: ?Item = if (chosen_itemlist == .Pack) state.player.inventory.pack.data[chosen] else state.player.inventory.equ_slots[chosen];

        // Draw list of items
        {
            y = starty;
            y = _drawStr(x, y, endx, "$cInventory:$.", .{});
            for (state.player.inventory.pack.constSlice()) |item, i| {
                const startx = x;

                const name = (item.longName() catch err.wat()).constSlice();
                const color = if (i == chosen and chosen_itemlist == .Pack) colors.LIGHT_CONCRETE else colors.GREY;
                const arrow = if (i == chosen and chosen_itemlist == .Pack) ">" else " ";
                _clear_line(startx, endx, y);
                y = _drawStrf(startx, y, endx, "{s} {s}", .{ arrow, name }, .{ .fg = color });
            }

            y = starty;
            const startx = endx - @divTrunc(endx - x, 2);
            y = _drawStr(startx, y, endx, "$cEquipment:$.", .{});
            inline for (@typeInfo(Mob.Inventory.EquSlot).Enum.fields) |slots_f, i| {
                const slot = @intToEnum(Mob.Inventory.EquSlot, slots_f.value);
                const arrow = if (i == chosen and chosen_itemlist == .Equip) ">" else "·";
                const color = if (i == chosen and chosen_itemlist == .Equip) colors.LIGHT_CONCRETE else colors.GREY;

                _clear_line(startx, endx, y);

                if (state.player.inventory.equipment(slot).*) |item| {
                    const name = (item.longName() catch unreachable).constSlice();
                    y = _drawStrf(startx, y, endx, "{s} {s: >6}: {s}", .{ arrow, slot.name(), name }, .{ .fg = color });
                } else {
                    y = _drawStrf(startx, y, endx, "{s} {s: >6}:", .{ arrow, slot.name() }, .{ .fg = color });
                }
            }
        }

        var dippable = false;
        var usable = false;
        var throwable = false;

        if (chosen_item != null and itemlist_len > 0) switch (chosen_item.?) {
            .Consumable => |p| {
                usable = true;
                dippable = p.dip_effect != null;
                throwable = p.throwable;
            },
            .Evocable => usable = true,
            .Projectile => throwable = true,
            else => {},
        };

        // Draw item info
        if (chosen_item != null and itemlist_len > 0) {
            const ii_startx = iteminfo_window.startx;
            const ii_endx = iteminfo_window.endx;
            const ii_starty = iteminfo_window.starty;
            const ii_endy = iteminfo_window.endy;

            var ii_y = ii_starty;
            while (ii_y < ii_endy) : (ii_y += 1)
                _clear_line(ii_startx, ii_endx, ii_y);

            var descbuf: [4096]u8 = undefined;
            var descbuf_stream = io.fixedBufferStream(&descbuf);
            var writer = descbuf_stream.writer();
            _getItemDescription(
                descbuf_stream.writer(),
                chosen_item.?,
                LEFT_INFO_WIDTH - 1,
            );

            if (usable) writer.print("$cENTER$. to use.\n", .{}) catch err.wat();
            if (dippable) writer.print("$cD$. to dip your weapon.\n", .{}) catch err.wat();
            if (throwable) writer.print("$ct$. to throw.\n", .{}) catch err.wat();

            _ = _drawStr(ii_startx, ii_starty, ii_endx, descbuf_stream.getWritten(), .{});
        }

        // Draw item description
        if (chosen_item != null) {
            const log_startx = log_window.startx;
            const log_endx = log_window.endx;
            const log_starty = log_window.starty;
            const log_endy = log_window.endy;

            if (itemlist_len > 0) {
                const id = chosen_item.?.id();
                const default_desc = "(Missing description)";
                const desc: []const u8 = if (id) |i_id| state.descriptions.get(i_id) orelse default_desc else default_desc;

                const ending_y = _drawStr(log_startx, log_starty, log_endx, desc, .{
                    .skip_lines = desc_scroll,
                    .endy = log_endy,
                });

                if (desc_scroll > 0) {
                    _ = _drawStr(log_endx - 14, log_starty, log_endx, " $p-- PgUp --$.", .{});
                }
                if (ending_y == log_endy) {
                    _ = _drawStr(log_endx - 14, log_endy - 1, log_endx, " $p-- PgDn --$.", .{});
                }
            } else {
                _ = _drawStr(log_startx, log_starty, log_endx, "Your inventory is empty.", .{});
            }
        }

        display.present();

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Key => |k| switch (k) {
                .ArrowRight => {
                    chosen_itemlist = .Equip;
                    chosen = 0;
                },
                .ArrowLeft => {
                    chosen_itemlist = .Pack;
                    chosen = 0;
                },
                .ArrowDown => if (chosen < itemlist_len - 1) {
                    chosen += 1;
                },
                .ArrowUp => chosen -|= 1,
                .PgUp => desc_scroll -|= 1,
                .PgDn => desc_scroll += 1,
                .CtrlC, .Esc => return false,
                .Enter => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        return player.useItem(chosen);
                } else if (chosen_item) |item| {
                    switch (item) {
                        .Weapon => drawAlert("Bump into enemies to attack.", .{}),
                        .Ring => drawAlert("Follow the ring's pattern to use it.", .{}),
                        else => drawAlert("You can't use that!", .{}),
                    }
                } else {
                    drawAlert("You can't use that!", .{});
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'd' => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        if (player.dropItem(chosen)) return true;
                } else {
                    drawAlert("You can't drop that!", .{});
                },
                'D' => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        if (player.dipWeapon(chosen)) return true;
                } else {
                    drawAlert("Select a potion and press $bD$. to dip something in it.", .{});
                },
                't' => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        if (player.throwItem(chosen)) return true;
                } else {
                    drawAlert("You can't throw that!", .{});
                },
                'l' => {
                    chosen_itemlist = .Equip;
                    chosen = 0;
                },
                'h' => {
                    chosen_itemlist = .Pack;
                    chosen = 0;
                },
                'j' => if (itemlist_len > 0 and chosen < itemlist_len - 1) {
                    chosen += 1;
                },
                'k' => if (itemlist_len > 0 and chosen > 0) {
                    chosen -= 1;
                },
                else => {},
            },
            else => {},
        }
    }
}

pub fn drawModalText(color: u32, comptime fmt: []const u8, args: anytype) void {
    const wind = dimensions(.Main);

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.bug("format error!", .{});
    const str = fbs.getWritten();

    assert(str.len < WIDTH - 4);

    const y = if (state.player.coord.y > (HEIGHT / 2) * 2) wind.starty + 2 else wind.endy - 2;
    const x = 1;

    display.setCell(x, y, .{ .ch = '█', .fg = color, .bg = colors.BG });
    _ = _drawStrf(x + 1, y, wind.endx, " {s} ", .{str}, .{ .bg = colors.percentageOf(color, 30) });
    display.setCell(x + str.len + 3, y, .{ .ch = '█', .fg = color, .bg = colors.BG });

    display.present();
}

pub fn drawAlert(comptime fmt: []const u8, args: anytype) void {
    const wind = dimensions(.Log);

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.bug("format error!", .{});
    const str = fbs.getWritten();

    // Get height of folded text, so that we can center it vertically
    const linewidth = @intCast(usize, (wind.endx - wind.startx) - 4);
    var text_height: usize = 0;
    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, linewidth);
    while (fold_iter.next(&fibuf)) |_| text_height += 1;

    // Clear log window
    var y = wind.starty;
    while (y < wind.endy) : (y += 1) _clear_line(wind.startx, wind.endx, y);

    const txt_starty = wind.endy -
        @divTrunc(wind.endy - wind.starty, 2) -
        text_height + 1 / 2;
    y = txt_starty;

    _ = _drawStr(wind.startx + 2, txt_starty, wind.endx, str, .{});

    display.present();

    _drawBorder(colors.CONCRETE, wind);
    std.time.sleep(150_000_000);
    _drawBorder(colors.BG, wind);
    std.time.sleep(150_000_000);
    _drawBorder(colors.CONCRETE, wind);
    std.time.sleep(150_000_000);
    _drawBorder(colors.BG, wind);
    std.time.sleep(150_000_000);
    _drawBorder(colors.CONCRETE, wind);
    std.time.sleep(500_000_000);
}

pub fn drawAlertThenLog(comptime fmt: []const u8, args: anytype) void {
    const log_window = dimensions(.Log);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    drawAlert(fmt, args);

    const log_console = drawLog(log_window.startx, log_window.endx, arena.allocator());
    log_console.renderAreaAt(
        @intCast(usize, log_window.startx),
        @intCast(usize, log_window.starty),
        0,
        log_console.height -| @intCast(usize, log_window.endy - log_window.starty),
        log_console.width,
        log_console.height,
    );
    log_console.deinit();
}

pub fn drawChoicePrompt(comptime fmt: []const u8, args: anytype, options: []const []const u8) ?usize {
    assert(options.len > 0);

    const wind = dimensions(.Log);

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    @call(.{ .modifier = .always_inline }, std.fmt.format, .{ fbs.writer(), fmt, args }) catch err.bug("format error", .{});
    const str = fbs.getWritten();

    // Clear log window
    var y: usize = wind.starty;
    while (y < wind.endy) : (y += 1) _clear_line(wind.startx, wind.endx, y);
    y = wind.starty;

    var chosen: usize = 0;
    var cancelled = false;

    while (true) {
        y = wind.starty;
        y = _drawStrf(wind.startx, y, wind.endx, "$c{s}$.", .{str}, .{});

        for (options) |option, i| {
            const ind = if (chosen == i) ">" else "-";
            const color = if (chosen == i) colors.LIGHT_CONCRETE else colors.GREY;
            y = _drawStrf(wind.startx, y, wind.endx, "{s} {s}", .{ ind, option }, .{ .fg = color });
        }

        display.present();

        switch (display.waitForEvent(null) catch err.wat()) {
            .Quit => {
                state.state = .Quit;
                cancelled = true;
                break;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .CtrlG => {
                    cancelled = true;
                    break;
                },
                .Enter => break,
                .ArrowDown, .ArrowLeft => if (chosen < options.len - 1) {
                    chosen += 1;
                },
                .ArrowUp, .ArrowRight => if (chosen > 0) {
                    chosen -= 1;
                },
                else => {},
            },
            .Char => |c| switch (c) {
                ' ' => break,
                'q' => {
                    cancelled = true;
                    break;
                },
                'j', 'h' => if (chosen < options.len - 1) {
                    chosen += 1;
                },
                'k', 'l' => if (chosen > 0) {
                    chosen -= 1;
                },
                '0'...'9' => {
                    const num: usize = c - '0';
                    if (num < options.len) {
                        chosen = num;
                    }
                },
                else => {},
            },
            else => {},
        }
    }

    return if (cancelled) null else chosen;
}

pub fn drawYesNoPrompt(comptime fmt: []const u8, args: anytype) bool {
    Animation.apply(.{ .PopChar = .{ .coord = state.player.coord, .char = '?', .delay = 120 } });

    const r = (drawChoicePrompt(fmt, args, &[_][]const u8{ "No", "Yes" }) orelse 0) == 1;
    if (!r) state.message(.Unimportant, "Cancelled.", .{});
    return r;
}

pub fn drawContinuePrompt(comptime fmt: []const u8, args: anytype) void {
    state.message(.Info, fmt, args);
    _ = drawChoicePrompt(fmt, args, &[_][]const u8{"Press $b<Enter>$. to continue."});
}

pub fn drawItemChoicePrompt(comptime fmt: []const u8, args: anytype, items: []const Item) ?usize {
    assert(items.len > 0); // This should have been handled previously.

    // A bit messy.
    var namebuf = std.ArrayList([]const u8).init(state.GPA.allocator());
    defer {
        for (namebuf.items) |str| state.GPA.allocator().free(str);
        namebuf.deinit();
    }

    for (items) |item| {
        const itemname = item.longName() catch err.wat();
        const string = state.GPA.allocator().alloc(u8, itemname.len) catch err.wat();
        std.mem.copy(u8, string, itemname.constSlice());
        namebuf.append(string) catch err.wat();
    }

    return drawChoicePrompt(fmt, args, namebuf.items);
}

pub const Console = struct {
    alloc: mem.Allocator,
    grid: []display.Cell,
    width: usize,
    height: usize,
    subconsoles: Subconsole.AList,

    pub const Self = @This();
    pub const AList = std.ArrayList(Self);

    pub const Subconsole = struct {
        console: Console,
        x: ?usize = null, // Defaults to 0.
        y: ?usize = null, // Defaults to last_subconsole.y orelse 0.

        pub const AList = std.ArrayList(@This());
    };

    pub fn init(alloc: mem.Allocator, width: usize, height: usize) Self {
        const self = .{
            .alloc = alloc,
            .grid = alloc.alloc(display.Cell, width * height) catch err.wat(),
            .width = width,
            .height = height,
            .subconsoles = Subconsole.AList.init(alloc),
        };
        mem.set(display.Cell, self.grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });
        return self;
    }

    pub fn deinit(self: *const Self) void {
        self.alloc.free(self.grid);
        for (self.subconsoles.items) |subconsole|
            subconsole.console.deinit();
        self.subconsoles.deinit();
    }

    pub fn addSubconsole(self: *Self, subconsole: Console, x: ?usize, y: ?usize) void {
        self.subconsoles.append(.{ .console = subconsole, .x = x, .y = y }) catch err.wat();
    }

    // Utility function for centering subconsoles
    pub fn centerX(self: *const Self, subwidth: usize) usize {
        return (self.width / 2) - (subwidth / 2);
    }

    pub fn changeHeight(self: *Self, new_height: usize) void {
        const new_grid = self.alloc.alloc(display.Cell, self.width * new_height) catch err.wat();
        mem.set(display.Cell, new_grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });

        // Copy old grid to new grid
        var y: usize = 0;
        while (y < new_height and y < self.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                new_grid[self.width * y + x] = self.grid[self.width * y + x];
            }
        }

        self.alloc.free(self.grid);

        self.height = new_height;
        self.grid = new_grid;
    }

    pub fn clearTo(self: *const Self, to: display.Cell) void {
        mem.set(display.Cell, self.grid, to);
    }

    fn clearLineTo(self: *const Self, startx: usize, endx: usize, y: usize, cell: display.Cell) void {
        var x = startx;
        while (x <= endx) : (x += 1)
            self.grid[y * self.width + x] = cell;
    }

    fn clearLine(self: *const Self, startx: usize, endx: usize, y: usize) void {
        self.clearLineTo(startx, endx, y, .{ .ch = ' ', .fg = 0, .bg = colors.BG });
    }

    pub fn clear(self: *const Self) void {
        self.clearTo(.{ .ch = ' ', .fg = 0, .bg = colors.BG });
    }

    pub fn renderAreaAt(self: *const Self, offset_x: usize, offset_y: usize, begin_x: usize, begin_y: usize, end_x: usize, end_y: usize) void {
        var dy: usize = offset_y;
        var y: usize = begin_y;
        while (y < end_y) : (y += 1) {
            _clear_line(offset_x, offset_x + (end_x - begin_x), dy);

            var dx: usize = offset_x;
            var x: usize = begin_x;
            while (x < end_x) : (x += 1) {
                display.setCell(dx, dy, self.grid[self.width * y + x]);
                dx += 1;
            }
            dy += 1;
        }

        // FIXME: subconsoles with non-null y coords are broken

        var last_sub_y: usize = 0;
        var sdy: usize = offset_y;
        for (self.subconsoles.items) |subconsole| {
            var i: usize = 0;
            while (i < subconsole.console.height) : (i += 1) {
                const sy = subconsole.y orelse last_sub_y;
                const sx = subconsole.x orelse 0;
                last_sub_y += 1;
                if (sy < begin_y or sy > end_y or sx < begin_x or sx > end_x)
                    continue;
                const sdx = offset_x + sx;
                subconsole.console.renderAreaAt(sdx, sdy, 0, i, subconsole.console.width, i + 1);
                sdy += 1;
            }
        }
    }

    pub fn renderFully(self: *const Self, offset_x: usize, offset_y: usize) void {
        self.renderAreaAt(offset_x, offset_y, 0, 0, self.width, self.height);
    }

    pub fn setCell(self: *const Self, x: usize, y: usize, ch: u21, fg: u32, bg: u32) void {
        self.grid[self.width * y + x] = .{ .ch = ch, .fg = fg, .bg = bg };
    }

    // TODO: draw multiple layers as needed
    pub fn drawXP(self: *const Self, map: *const RexMap) void {
        var y: usize = 0;
        while (y < map.height and y < self.height) : (y += 1) {
            var x: usize = 0;
            while (x < map.width and y < self.width) : (x += 1) {
                const tile = map.get(x, y);

                if (tile.bg.r == 255 and tile.bg.g == 0 and tile.bg.b == 255) {
                    continue;
                }

                self.setCell(x, y, RexMap.DEFAULT_TILEMAP[tile.ch], tile.fg.asU32(), tile.bg.asU32());
            }
        }
    }

    pub fn drawTextAtf(self: *const Self, startx: usize, starty: usize, comptime format: []const u8, args: anytype, opts: DrawStrOpts) usize {
        const str = std.fmt.allocPrint(state.GPA.allocator(), format, args) catch err.oom();
        defer state.GPA.allocator().free(str);
        return self.drawTextAt(startx, starty, str, opts);
    }

    // Re-implementation of _drawStr
    //
    // Returns lines/rows used
    pub fn drawTextAt(self: *const Self, startx: usize, starty: usize, str: []const u8, opts: DrawStrOpts) usize {
        var x = startx;
        var y = starty;
        var skipped: usize = 0; // TODO: remove

        var fg = opts.fg;
        var bg: ?u32 = opts.bg;

        var fibuf = StackBuffer(u8, 4096).init(null);
        var fold_iter = utils.FoldedTextIterator.init(str, self.width + 1);
        while (fold_iter.next(&fibuf)) |line| : ({
            y += 1;
            x = startx;
        }) {
            if (skipped < opts.skip_lines) {
                skipped += 1;
                y -= 1; // Stay on the same line
                continue;
            }

            if (y >= self.height or (opts.endy != null and y >= opts.endy.?)) {
                break;
            }

            var utf8 = (std.unicode.Utf8View.init(line) catch err.bug("bad utf8", .{})).iterator();
            while (utf8.nextCodepointSlice()) |encoded_codepoint| {
                const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch err.bug("bad utf8", .{});
                const def_bg = self.grid[y * self.width + x].bg;

                switch (codepoint) {
                    '\n' => {
                        y += 1;
                        x = startx;
                        continue;
                    },
                    '\r' => err.bug("Bad character found in string.", .{}),
                    '$' => {
                        const next_encoded_codepoint = utf8.nextCodepointSlice() orelse
                            err.bug("Found incomplete escape sequence", .{});
                        const next_codepoint = std.unicode.utf8Decode(next_encoded_codepoint) catch err.bug("bad utf8", .{});
                        switch (next_codepoint) {
                            '.' => {
                                fg = opts.fg;
                                bg = opts.bg;
                            },
                            '~' => {
                                const t = fg;
                                fg = bg orelse def_bg;
                                bg = t;
                            },
                            'g' => fg = colors.GREY,
                            'G' => fg = colors.DARK_GREY,
                            'C' => fg = colors.CONCRETE,
                            'c' => fg = colors.LIGHT_CONCRETE,
                            'p' => fg = colors.PINK,
                            'b' => fg = colors.LIGHT_STEEL_BLUE,
                            'r' => fg = colors.PALE_VIOLET_RED,
                            'a' => fg = colors.AQUAMARINE,
                            'o' => fg = colors.GOLD,
                            else => err.bug("[Console] Found unknown escape sequence '${u}' (line: '{s}')", .{ next_codepoint, line }),
                        }
                        continue;
                    },
                    else => {
                        self.setCell(x, y, codepoint, fg, bg orelse def_bg);
                        x += 1;
                    },
                }

                if (!opts.fold and x == self.width) {
                    x -= 1;
                }
            }
        }

        return y - starty;
    }

    // Reimplementation of _drawBar
    fn drawBarAt(self: *const Console, x: usize, endx: usize, y: usize, current: usize, max: usize, description: []const u8, bg: u32, fg: u32, opts: struct {
        detail: bool = true,
        detail_type: enum { Specific, Percent } = .Specific,
    }) usize {
        assert(current <= max);

        const depleted_bg = colors.percentageOf(bg, 40);
        const percent = if (max == 0) 100 else (current * 100) / max;
        const bar = ((endx - x - 1) * percent) / 100;
        const bar_end = x + bar;

        self.clearLineTo(x, endx - 1, y, .{ .ch = ' ', .fg = fg, .bg = depleted_bg });
        if (percent != 0)
            self.clearLineTo(x, bar_end, y, .{ .ch = ' ', .fg = fg, .bg = bg });

        _ = self.drawTextAt(x + 1, y, description, .{ .fg = fg, .bg = null });

        if (opts.detail) switch (opts.detail_type) {
            .Percent => {
                const info_width = @intCast(usize, std.fmt.count("{}%", .{percent}));
                _ = self.drawTextAtf(endx - info_width - 1, y, "{}%", .{percent}, .{ .fg = fg, .bg = null });
            },
            .Specific => {
                const info_width = @intCast(usize, std.fmt.count("{} / {}", .{ current, max }));
                _ = self.drawTextAtf(endx - info_width - 1, y, "{} / {}", .{ current, max }, .{ .fg = fg, .bg = null });
            },
        };

        return y + 1;
    }
};

// Animations {{{

pub const Animation = union(enum) {
    PopChar: struct {
        coord: Coord,
        char: u32,
        fg: u32 = colors.LIGHT_CONCRETE,
        delay: usize = 80,
    },
    BlinkChar: struct {
        coords: []const Coord,
        char: u32,
        fg: ?u32 = null,
        delay: usize = 170,
        repeat: usize = 1,
    },
    EncircleChar: struct {
        coord: Coord,
        char: u32,
        fg: u32,
    },
    TraverseLine: struct {
        start: Coord,
        end: Coord,
        extra: usize = 0,
        char: u32,
        fg: ?u32 = null,
        path_char: ?u32 = null,
    },
    // Used for elec bolt.
    //
    // TODO: merge with TraverseLine?
    AnimatedLine: struct {
        approach: ?usize = null,
        start: Coord,
        end: Coord,
        chars: []const u8,
        fg: u32,
        bg: ?u32,
        bg_mix: ?f64,
    },

    pub const ELEC_LINE_CHARS = "AEFHIKLMNTYZ13457*-=+~?!@#%&";
    pub const ELEC_LINE_FG = 0x9fefff;
    pub const ELEC_LINE_BG = 0x8fdfff;
    pub const ELEC_LINE_MIX = 0.02;

    pub fn blink(coords: []const Coord, char: u32, fg: ?u32, opts: struct {
        repeat: usize = 1,
        delay: usize = 170,
    }) Animation {
        return Animation{ .BlinkChar = .{
            .coords = coords,
            .char = char,
            .fg = fg,
            .repeat = opts.repeat,
            .delay = opts.delay,
        } };
    }

    pub fn apply(self: Animation) void {
        const mapwin = dimensions(.Main);

        drawNoPresent();

        state.player.tickFOV();

        switch (self) {
            .PopChar => |anim| {
                const dx = anim.coord.x + mapwin.startx;
                const dy = anim.coord.y + mapwin.starty;
                const old = display.getCell(dx, dy);

                display.setCell(dx, dy, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });
                display.present();

                std.time.sleep(anim.delay * 1_000_000);

                display.setCell(dx, dy, .{ .ch = old.ch, .fg = old.fg, .bg = old.bg });
                display.setCell(dx - 1, dy - 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });
                display.setCell(dx + 1, dy - 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });
                display.setCell(dx - 1, dy + 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });
                display.setCell(dx + 1, dy + 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });

                display.present();

                std.time.sleep(anim.delay * 1_000_000);
            },
            .BlinkChar => |anim| {
                assert(anim.coords.len < 256); // XXX: increase if necessary
                var old_cells = StackBuffer(display.Cell, 256).init(null);
                var some_coords_seen = false;
                for (anim.coords) |coord| {
                    if (state.player.cansee(coord))
                        some_coords_seen = true;
                    const dx = coord.x + mapwin.startx;
                    const dy = coord.y + mapwin.starty;
                    old_cells.append(display.getCell(dx, dy)) catch err.wat();
                }

                if (!some_coords_seen) {
                    // Player can't see any coord, bail out
                    return;
                }

                var ctr: usize = anim.repeat;
                while (ctr > 0) : (ctr -= 1) {
                    for (anim.coords) |coord, i| if (state.player.cansee(coord)) {
                        const dx = coord.x + mapwin.startx;
                        const dy = coord.y + mapwin.starty;
                        const old = old_cells.constSlice()[i];
                        display.setCell(dx, dy, .{ .ch = anim.char, .fg = anim.fg orelse old.fg, .bg = colors.BG });
                    };

                    display.present();
                    std.time.sleep(anim.delay * 1_000_000);

                    for (anim.coords) |coord, i| if (state.player.cansee(coord)) {
                        const dx = coord.x + mapwin.startx;
                        const dy = coord.y + mapwin.starty;
                        const old = old_cells.constSlice()[i];
                        display.setCell(dx, dy, .{ .ch = old.ch, .fg = old.fg, .bg = old.bg });
                    };

                    if (ctr > 1) {
                        display.present();
                        std.time.sleep(anim.delay * 1_000_000);
                    }
                }
            },
            .EncircleChar => |anim| {
                const directions = [_]Direction{ .NorthWest, .North, .NorthEast, .East, .SouthEast, .South, .SouthWest, .West, .NorthWest, .North, .NorthEast };
                for (&directions) |d| if (anim.coord.move(d, state.mapgeometry)) |neighbor| {
                    const dx = neighbor.x + mapwin.startx;
                    const dy = neighbor.y + mapwin.starty;
                    const old = display.getCell(dx, dy);

                    display.setCell(dx, dy, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG });
                    display.present();

                    std.time.sleep(90_000_000);

                    display.setCell(dx, dy, .{ .ch = old.ch, .fg = old.fg, .bg = old.bg });
                    display.present();
                };
            },
            .TraverseLine => |anim| {
                const line = anim.start.drawLine(anim.end, state.mapgeometry, anim.extra);
                for (line.constSlice()) |coord| {
                    if (!state.player.cansee(coord)) {
                        continue;
                    }

                    const dx = coord.x + mapwin.startx;
                    const dy = coord.y + mapwin.starty;
                    const old = display.getCell(dx, dy);

                    display.setCell(dx, dy, .{ .ch = anim.char, .fg = anim.fg orelse old.fg, .bg = colors.BG });
                    display.present();

                    std.time.sleep(80_000_000);

                    if (anim.path_char) |path_char| {
                        display.setCell(dx, dy, .{ .ch = path_char, .fg = colors.CONCRETE, .bg = old.bg });
                    } else {
                        display.setCell(dx, dy, .{ .ch = old.ch, .fg = old.fg, .bg = old.bg });
                    }

                    display.present();
                }
            },
            .AnimatedLine => |anim| {
                const line = anim.start.drawLine(anim.end, state.mapgeometry, 0);

                var animated_len: usize = if (anim.approach != null) 1 else line.len;
                var animated: []const Coord = line.data[0..animated_len];

                const iters: usize = 15;
                var counter: usize = iters;
                while (counter > 0) : (counter -= 1) {
                    for (animated) |coord| {
                        if (!state.player.cansee(coord)) {
                            continue;
                        }

                        const special = coord.eq(anim.start) or coord.eq(anim.end);

                        const dx = coord.x + mapwin.startx;
                        const dy = coord.y + mapwin.starty;
                        const old = display.getCell(dx, dy);

                        const char = if (special) old.ch else rng.chooseUnweighted(u8, anim.chars);
                        const fg = if (special) old.fg else colors.percentageOf(anim.fg, counter * 100 / (iters / 2));

                        const bg = if (anim.bg) |color|
                            colors.mix(
                                old.bg,
                                colors.percentageOf(color, counter * 100 / iters),
                                anim.bg_mix.?,
                            )
                        else
                            colors.BG;

                        display.setCell(dx, dy, .{ .ch = char, .fg = fg, .bg = bg });
                    }

                    display.present();
                    std.time.sleep(40_000_000);

                    if (anim.approach != null and animated_len < line.len) {
                        animated_len = math.min(line.len, animated_len + anim.approach.?);
                        animated = line.data[0..animated_len];
                    }
                }
            },
        }

        draw();
    }
};

// }}}
