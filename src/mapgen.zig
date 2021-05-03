const std = @import("std");

const rng = @import("rng.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

fn _add_guard_station(stationy: usize, stationx: usize) void {
    var guard = GuardTemplate;
    guard.occupation.Guard.patrol_start = Coord.new(stationy, stationx);
    guard.occupation.Guard.patrol_end = Coord.new(stationy, stationx);
    state.dungeon[stationy][stationx].mob = guard;
}

pub fn add_guard_stations() void {
    // --- Guard route patterns ---
    const patterns = [_][9]TileType{
        // ###
        // #G.
        // #..
        [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Floor },
        // ###
        // .G#
        // .##
        [_]TileType{ .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Wall, .Wall },
        // ###
        // #G.
        // ###
        [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Wall, .Wall },
    };

    var y: usize = 1;
    while (y < (state.HEIGHT - 1)) : (y += 1) {
        var x: usize = 1;
        while (x < (state.WIDTH - 1)) : (x += 1) {
            const neighbors = [_]TileType{
                state.dungeon[y - 1][x - 1].type,
                state.dungeon[y - 1][x - 0].type,
                state.dungeon[y - 1][x + 1].type,
                state.dungeon[y + 0][x - 1].type,
                state.dungeon[y + 0][x - 0].type,
                state.dungeon[y + 0][x + 1].type,
                state.dungeon[y + 1][x - 1].type,
                state.dungeon[y + 1][x - 0].type,
                state.dungeon[y + 1][x + 1].type,
            };

            for (patterns) |pattern| {
                if (std.mem.eql(TileType, &neighbors, &pattern)) {
                    _add_guard_station(y, x);
                    break;
                }
            }
        }
    }
}

pub fn drunken_walk() void {
    const center_weight = 20;
    const fill_goal = @intToFloat(f64, state.WIDTH * state.HEIGHT) * 0.35;
    const prev_direction_weight = 90;
    const max_iterations = 5000;

    var prev_direction: Direction = .North;
    var filled: usize = 0;
    var iterations: usize = 0;
    var walker = Coord.new(state.WIDTH / 2, state.HEIGHT / 2);

    while (true) {
        // probability of going in a direction
        var north: usize = 100;
        var south: usize = 100;
        var east: usize = 100;
        var west: usize = 100;

        if (state.WIDTH > state.HEIGHT) {
            east += ((state.WIDTH * 100) / state.HEIGHT);
            west += ((state.WIDTH * 100) / state.HEIGHT);
        } else if (state.HEIGHT > state.WIDTH) {
            north += ((state.HEIGHT * 100) / state.WIDTH);
            south += ((state.HEIGHT * 100) / state.WIDTH);
        }

        // weight the random walk against map edges
        if (@intToFloat(f64, walker.x) < (@intToFloat(f64, state.WIDTH) * 0.25)) {
            // walker is at far left
            east += center_weight;
        } else if (@intToFloat(f64, walker.x) > (@intToFloat(f64, state.WIDTH) * 0.75)) {
            // walker is at far right
            west += center_weight;
        }

        if (@intToFloat(f64, walker.y) < (@intToFloat(f64, state.HEIGHT) * 0.25)) {
            // walker is at the top
            south += center_weight;
        } else if (@intToFloat(f64, walker.y) > (@intToFloat(f64, state.HEIGHT) * 0.75)) {
            // walker is at the bottom
            north += center_weight;
        }

        // Don't break into a previously-built enclosure
        // TODO

        // weight the walker to previous direction
        switch (prev_direction) {
            .North => north += prev_direction_weight,
            .South => south += prev_direction_weight,
            .West => west += prev_direction_weight,
            .East => east += prev_direction_weight,
        }

        // normalize probabilities
        const total = north + south + east + west;
        north = north * 100 / total;
        south = south * 100 / total;
        east = east * 100 / total;
        west = west * 100 / total;

        // choose direction
        var directions = CARDINAL_DIRECTIONS;
        rng.shuffle(Direction, &directions);

        const direction = rng.choose(Direction, &CARDINAL_DIRECTIONS, &[_]usize{ north, south, east, west }) catch unreachable;

        if (walker.move(direction, Coord.new(state.WIDTH, state.HEIGHT))) {
            if (state.dungeon[walker.y][walker.x].type == .Wall) {
                filled += 1;
                state.dungeon[walker.y][walker.x].type = .Floor;
                prev_direction = direction;
            } else {
                prev_direction = direction.opposite();
                if (rng.boolean()) {
                    prev_direction = direction.turnright();
                } else {
                    prev_direction = direction.turnleft();
                }
            }
        } else {
            prev_direction = direction.opposite();
        }

        iterations += 1;
        if (filled > fill_goal or iterations > max_iterations)
            break;
    }
}
