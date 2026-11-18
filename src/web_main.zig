//! Non-blocking browser loop. Simulation and palette fades keep the original
//! timer period; rendering is coalesced to one presentation per animation frame.
const std = @import("std");
const c = @import("c");
const Destruct = @import("destruct.zig");

const Phase = enum {
    fade,
    intro,
    intro_done,
    menu,
    menu_done,
    playing,
    round_done,
    help_open,
    help,
    help_restore,
    paused,
    quit,
};

var game: Destruct = .{};
var phase: Phase = .intro;
var fade_next: Phase = .intro;
var fade_steps: c_int = 0;
var fade_diff: [256][3]c_int = undefined;
var menu: Destruct.MenuState = .{ .state = .{ .main = .{} }, .screen_changed = true };
var help: Destruct.ControllerMenu = .{};
var help_return: Phase = .menu;
var reload_round = false;
var previous_time: f64 = 0;
var accumulator: f64 = 0;
var hidden = false;
var cleanup: *const fn () void = undefined;

pub fn start(on_quit: *const fn () void) void {
    cleanup = on_quit;
    game.init();
    c.set_colors(.{ .r = 0, .g = 0, .b = 0, .a = 255 }, 0, 255);
    c.JE_loadPic(Destruct.assets.game_screen.ptr, Destruct.assets.game_screen.len, game.world.VGAScreen, 11, false);
    c.JE_introScreen(game.world.VGAScreen, game.destructInternalScreen);

    c.DE_ResetPlayers(&game.destruct_players);
    game.destruct_players[c.PLAYER_LEFT].is_cpu = game.config.ai[c.PLAYER_LEFT];
    game.destruct_players[c.PLAYER_RIGHT].is_cpu = game.config.ai[c.PLAYER_RIGHT];
    c.newkey = false;
    beginFade(false, 15, .intro);
    previous_time = c.emscripten_get_now();
    _ = c.emscripten_set_visibilitychange_callback(null, false, visibilityChanged);
    c.emscripten_set_main_loop(frame, 0, false);
}

fn visibilityChanged(_: c_int, event: [*c]const c.EmscriptenVisibilityChangeEvent, _: ?*anyopaque) callconv(.c) bool {
    hidden = event.*.hidden;
    // Hidden tabs receive no animation callbacks. Do not simulate the time away.
    previous_time = c.emscripten_get_now();
    accumulator = 0;
    return false;
}

fn frame() callconv(.c) void {
    c.service_SDL_events(false);
    const now = c.emscripten_get_now();
    const period: f64 = @floatFromInt(c.get_delay_period());
    const elapsed = std.math.clamp(now - previous_time, 0, period * 4);
    previous_time = now;

    if (!hidden) {
        accumulator += elapsed;
        // Limit recovery after a stall, while preserving the original physics
        // speed on both 60 Hz and high-refresh displays.
        var steps: usize = 0;
        while (accumulator >= period and steps < 4 and phase != .quit) : (steps += 1) {
            accumulator -= period;
            step();
        }
    }

    if (c.quit_requested or phase == .quit) {
        c.emscripten_cancel_main_loop();
        game.deinit();
        cleanup();
        return;
    }
    c.JE_showVGA(true);
}

fn copyScreen(destination: *c.SDL_Surface, source: *c.SDL_Surface) void {
    _ = c.memcpy(destination.pixels, source.pixels, @intCast(source.h * source.pitch));
}

fn beginFade(black: bool, steps: c_int, next: Phase) void {
    if (black) {
        c.init_step_fade_solid(&fade_diff, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, 0, 255);
    } else {
        c.init_step_fade_palette(&fade_diff, &c.colors, 0, 255);
    }
    fade_steps = steps;
    fade_next = next;
    phase = .fade;
    c.newkey = false;
    c.JE_showVGA(false);
}

fn beginMenu() void {
    copyScreen(game.destructInternalScreen, game.world.VGAScreen);
    menu = .{ .state = .{ .main = .{} }, .screen_changed = true };
    drawMenu();
    beginFade(false, 15, .menu);
}

fn drawMenu() void {
    menu.draw(game.world.VGAScreen, game.destructInternalScreen, &game.config, &game.destruct_players);
    c.JE_showVGA(false);
}

fn runTick() c.de_state_t {
    return c.DE_RunTick(&game.config, &game.destruct_players, game.shotRec, game.exploRec, &game.world, game.destructInternalScreen, game.destructPrevScreen);
}

fn beginRound() void {
    Destruct.browser_help_requested = false;
    Destruct.browser_pause_requested = false;
    c.destructFirstTime = true;
    c.JE_loadPic(Destruct.assets.game_screen.ptr, Destruct.assets.game_screen.len, game.world.VGAScreen, 11, false);
    c.DE_ResetUnits(&game.config, &game.destruct_players);
    c.DE_ResetLevel(&game.config, &game.destruct_players, game.shotRec, game.exploRec, &game.world, game.destructInternalScreen);
    const result = runTick();
    if (result == c.STATE_CONTINUE) {
        beginFade(false, 25, .playing);
    } else {
        // Input received during the menu fade can already request leaving or
        // restarting this round. Honor it just as on subsequent ticks.
        reload_round = result == c.STATE_RELOAD;
        beginFade(true, 25, .round_done);
    }
}

fn beginHelp(return_to: Phase) void {
    Destruct.browser_help_requested = false;
    help_return = return_to;
    // Save before fading; the saved 8-bit pixels are independent of the palette.
    copyScreen(game.destructPrevScreen, game.world.VGAScreen);
    beginFade(true, 15, .help_open);
}

fn step() void {
    switch (phase) {
        .fade => {
            c.step_fade_palette(&fade_diff, fade_steps, 0, 255);
            c.JE_showVGA(false);
            fade_steps -= 1;
            if (fade_steps == 0) {
                phase = fade_next;
                c.newkey = false;
            }
        },
        .intro => {
            if (c.newkey) beginFade(true, 15, .intro_done);
        },
        .intro_done => {
            copyScreen(game.world.VGAScreen, game.destructInternalScreen);
            beginMenu();
        },
        .menu => {
            if (!c.newkey) return;
            c.newkey = false;
            const terminal = menu.handleKeyPress(game.world.VGAScreen, game.destructPrevScreen, &game.config, &game.destruct_players);
            drawMenu();
            if (Destruct.browser_help_requested) {
                beginHelp(.menu);
            } else if (terminal) {
                game.world.destructMode = switch (menu.state) {
                    .main => c.MODE_NONE,
                    .new_game => |selected| selected.state,
                    .controller => unreachable,
                };
                beginFade(true, 15, .menu_done);
            }
        },
        .menu_done => {
            copyScreen(game.world.VGAScreen, game.destructInternalScreen);
            if (game.world.destructMode == c.MODE_NONE) {
                phase = .quit;
            } else {
                beginRound();
            }
        },
        .playing => {
            const result = runTick();
            if (result != c.STATE_CONTINUE) {
                reload_round = result == c.STATE_RELOAD;
                beginFade(true, 25, .round_done);
            } else if (Destruct.browser_pause_requested) {
                Destruct.browser_pause_requested = false;
                copyScreen(game.destructPrevScreen, game.world.VGAScreen);
                c.set_volume(@truncate(c.tyrMusicVolume / 2), @truncate(c.fxVolume));
                c.JE_outText(game.world.VGAScreen, c.JE_fontCenter(&c.miscText[22], c.TINY_FONT), 90, &c.miscText[22], 12, 5);
                c.JE_showVGA(false);
                c.newkey = false;
                phase = .paused;
            } else if (Destruct.browser_help_requested) {
                beginHelp(.playing);
            }
        },
        .round_done => {
            if (reload_round) beginRound() else beginMenu();
        },
        .help_open => {
            help = .{};
            help.draw(game.world.VGAScreen, &game.destruct_players);
            beginFade(false, 15, .help);
        },
        .help => {
            if (!c.newkey) return;
            c.newkey = false;
            const done = help.handleKeyPress(&game.destruct_players);
            help.draw(game.world.VGAScreen, &game.destruct_players);
            if (done) beginFade(true, 15, .help_restore);
        },
        .help_restore => {
            copyScreen(game.world.VGAScreen, game.destructPrevScreen);
            beginFade(false, 15, help_return);
        },
        .paused => {
            if (!c.newkey) return;
            c.newkey = false;
            c.keysactive[c.lastkey_scan] = 0;
            copyScreen(game.world.VGAScreen, game.destructPrevScreen);
            c.JE_showVGA(false);
            c.set_volume(@truncate(c.tyrMusicVolume), @truncate(c.fxVolume));
            phase = .playing;
        },
        .quit => {},
    }
}
