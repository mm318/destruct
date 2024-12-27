const std = @import("std");
const SDL = @import("sdl2");

const c = @cImport({
    @cInclude("destruct.h");
    @cInclude("config.h");
    @cInclude("fonthand.h");
    @cInclude("keyboard.h");
    @cInclude("helptext.h");
    @cInclude("palette.h");
    @cInclude("picload.h");
    @cInclude("sprite.h");
    @cInclude("video.h");
});

const Destruct = @This();

config: c.destruct_config_s = .{
    .max_shots = 40,
    .min_walls = 20,
    .max_walls = 20,
    .max_explosions = 40,
    .max_installations = 10,
    .allow_custom = false,
    .alwaysalias = false,
    .jumper_straight = .{ true, false },
    .ai = .{ true, false },
},
destruct_player: [c.MAX_PLAYERS]c.destruct_player_s = undefined,
world: c.destruct_world_s = undefined,
shotRec: *c.destruct_shot_s = undefined,
exploRec: *c.destruct_explo_s = undefined,
destructTempScreen: *c.SDL_Surface = undefined,

// Startup
pub fn JE_destructGame() void {
    var self = Destruct{};

    // This is the entry function.  Any one-time actions we need to perform can go in here.
    c.JE_clr256(c.VGAScreen);
    c.JE_showVGA();

    c.load_destruct_config(&c.opentyrian_config, &self.config);

    // malloc things that have customizable sizes
    self.shotRec = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_shot_s) * self.config.max_shots).?));
    defer c.free(self.shotRec);
    self.exploRec = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_explo_s) * self.config.max_explosions).?));
    defer c.free(self.exploRec);
    self.world.mapWalls = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_wall_s) * self.config.max_walls).?));
    defer c.free(self.world.mapWalls);

    //Malloc enough structures to cover all of this session's possible needs.
    for (0..10) |i| {
        self.config.max_installations = c.MAX(self.config.max_installations, c.basetypes[i][0]);
    }
    self.destruct_player[c.PLAYER_LEFT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_player[c.PLAYER_LEFT].unit);
    self.destruct_player[c.PLAYER_RIGHT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_player[c.PLAYER_RIGHT].unit);

    self.destructTempScreen = c.game_screen;
    self.world.VGAScreen = c.VGAScreen;

    c.JE_loadCompShapes(&c.destructSpriteSheet, '~');
    defer c.free_sprite2s(&c.destructSpriteSheet);

    c.fade_black(1);

    self.JE_destructMain();
}

fn JE_destructMain(self: *Destruct) void {
    var curState: c.de_state_t = c.STATE_INIT;

    c.JE_loadPic(self.world.VGAScreen, 11, false);
    c.JE_introScreen();

    c.DE_ResetPlayers(&self.destruct_player);

    self.destruct_player[c.PLAYER_LEFT].is_cpu = self.config.ai[c.PLAYER_LEFT];
    self.destruct_player[c.PLAYER_RIGHT].is_cpu = self.config.ai[c.PLAYER_RIGHT];

    while (true) {
        self.world.destructMode = menu(&self.config);
        if (self.world.destructMode == c.MODE_NONE) {
            break; // User is quitting
        }

        while (true) {
            c.destructFirstTime = true;
            c.JE_loadPic(self.world.VGAScreen, 11, false);

            c.DE_ResetUnits(&self.config, &self.destruct_player);
            c.DE_ResetLevel(
                &self.config,
                &self.destruct_player,
                self.shotRec,
                self.exploRec,
                &self.world,
                self.destructTempScreen,
            );

            while (true) {
                curState = c.DE_RunTick(
                    &self.config,
                    &self.destruct_player,
                    self.shotRec,
                    self.exploRec,
                    &self.world,
                    self.destructTempScreen,
                );
                if (curState != c.STATE_CONTINUE) {
                    break;
                }
            }
            c.fade_black(25);

            if (curState != c.STATE_RELOAD) {
                break;
            }
        }
    }
}

fn handleModeSelectMenu(config: *const c.destruct_config_s, mode: *c.de_mode_t) bool {
    var selection_made = false;

    // See what was pressed
    if (c.keysactive[SDL.SDL_SCANCODE_ESCAPE] != 0) {
        mode.* = c.MODE_NONE; // User is quitting, return failure
        selection_made = true;
    }
    if (c.keysactive[SDL.SDL_SCANCODE_RETURN] != 0) {
        selection_made = true; // User has selected, return choice */
    }
    if (c.keysactive[SDL.SDL_SCANCODE_UP] != 0) {
        if (mode.* == c.MODE_FIRST) {
            if (config.allow_custom == true) {
                mode.* = c.MODE_LAST;
            } else {
                mode.* = c.MODE_LAST - 1;
            }
        } else {
            mode.* -= 1;
        }
    }
    if (c.keysactive[SDL.SDL_SCANCODE_DOWN] != 0) {
        if (mode.* >= c.MODE_LAST - 1) {
            if (config.allow_custom == true and mode.* == c.MODE_LAST - 1) {
                mode.* += 1;
            } else {
                mode.* = c.MODE_FIRST;
            }
        } else {
            mode.* += 1;
        }
    }

    // Helper function of JE_modeSelect.  Do not use elsewhere.
    for (0..@as(c.de_mode_t, c.DESTRUCT_MODES)) |i| {
        c.JE_textShade(
            c.VGAScreen,
            c.JE_fontCenter(&c.destructModeName[i], c.TINY_FONT),
            @intCast(82 + i * 12),
            &c.destructModeName[i],
            12,
            @intCast(@intFromBool(i == mode.*) * @as(c_int, 4)),
            c.FULL_SHADE,
        );
    }
    if (config.allow_custom == true) {
        const i = @as(c.de_mode_t, c.DESTRUCT_MODES);
        c.JE_textShade(
            c.VGAScreen,
            c.JE_fontCenter("Custom", c.TINY_FONT),
            @intCast(82 + i * 12),
            "Custom",
            12,
            @intCast(@intFromBool(i == mode.*) * @as(c_int, 4)),
            c.FULL_SHADE,
        );
    }

    return selection_made;
}

////// menu()
// The return value is the selected mode, or -1 (MODE_NONE) if the user quits.
fn menu(config: *const c.destruct_config_s) c.de_mode_t {
    _ = c.memcpy(c.VGAScreen2.*.pixels, c.VGAScreen.*.pixels, @intCast(c.VGAScreen2.*.h * c.VGAScreen2.*.pitch));
    var mode = c.MODE_5CARDWAR;

    // Draw the menu and fade us in
    _ = handleModeSelectMenu(config, &mode);

    c.JE_showVGA();
    c.fade_palette(&c.colors, 15, 0, 255);

    // Get input in a loop
    while (true) {
        // Grab keys
        c.newkey = false;
        while (true) {
            c.service_SDL_events(false);
            SDL.SDL_Delay(16);
            if (c.newkey) {
                break;
            }
        }

        // Re-draw the menu every iteration
        const selection_made = handleModeSelectMenu(config, &mode);

        c.JE_showVGA();

        if (selection_made) {
            break;
        }
    }

    c.fade_black(15);
    _ = c.memcpy(c.VGAScreen.*.pixels, c.VGAScreen2.*.pixels, @intCast(c.VGAScreen.*.h * c.VGAScreen.*.pitch));
    c.JE_showVGA();

    return mode;
}
