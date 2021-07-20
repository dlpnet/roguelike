usingnamespace @import("types.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");

pub const CAST_FREEZE = Spell{ .name = "freeze", .cast_type = .Cast, .effect_type = .{ .Status = .Paralysis } };
pub const CAST_FAMOUS = Spell{ .name = "famous", .cast_type = .Cast, .effect_type = .{ .Status = .Corona } };
pub const CAST_FERMENT = Spell{ .name = "ferment", .cast_type = .Cast, .effect_type = .{ .Status = .Confusion } };
pub const CAST_PAIN = Spell{ .name = "pain", .cast_type = .Cast, .effect_type = .{ .Status = .Pain } };

fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    if (rng.onein(10)) return false;
    return (rng.rangeClumping(usize, 1, 100, 2) * caster.willpower) >
        (rng.rangeClumping(usize, 1, 100, 2) * target.willpower);
}

pub const SpellOptions = struct {
    status_duration: usize = Status.MAX_DURATION,
    status_power: usize = 0,
};

pub const SpellInfo = struct {
    spell: *const Spell,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
};

pub const Spell = struct {
    name: []const u8,

    cast_type: union(enum) {
        Ray, Bolt, Cast
    },

    effect_type: union(enum) {
        Status: Status,
        Custom: fn (Coord) void,
    },

    pub fn use(self: Spell, caster: *Mob, target: Coord, opts: SpellOptions, comptime message: ?[]const u8) void {
        caster.declareAction(.Cast);

        switch (self.cast_type) {
            .Ray, .Bolt => @panic("TODO"),
            .Cast => {
                const mob = state.dungeon.at(target).mob.?;

                if (!willSucceedAgainstMob(caster, mob))
                    return;

                if (mob.coord.eq(state.player.coord)) {
                    state.message(
                        .SpellCast,
                        message orelse "The {0} gestures ominously!",
                        .{caster.species},
                    );
                }

                switch (self.effect_type) {
                    .Status => |s| mob.addStatus(s, opts.status_power, opts.status_duration),
                    .Custom => |c| c(target),
                }
            },
        }
    }
};
