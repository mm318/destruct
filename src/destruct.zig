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

const MainMenu = struct {
    const Options = enum {
        new_game,
        controller,
        quit,
    };

    state: Options = Options.new_game,

    fn getName(option: Options) []const u8 {
        return switch (option) {
            Options.new_game => "New Game",
            Options.controller => "Controller Setup",
            Options.quit => "Quit",
        };
    }

    fn up(option: Options) Options {
        return switch (option) {
            Options.new_game => Options.quit,
            Options.controller => Options.new_game,
            Options.quit => Options.controller,
        };
    }

    fn down(option: Options) Options {
        return switch (option) {
            Options.new_game => Options.controller,
            Options.controller => Options.quit,
            Options.quit => Options.new_game,
        };
    }

    fn handleKeyPress(self: *MainMenu) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_ESCAPE] != 0) {
            self.state = Options.quit;
            selection_made = true;
        }
        if (c.keysactive[SDL.SDL_SCANCODE_RETURN] != 0) {
            selection_made = true;
        }
        if (c.keysactive[SDL.SDL_SCANCODE_UP] != 0) {
            self.state = MainMenu.up(self.state);
        }
        if (c.keysactive[SDL.SDL_SCANCODE_DOWN] != 0) {
            self.state = MainMenu.down(self.state);
        }

        return selection_made;
    }

    fn draw(self: *const MainMenu) void {
        inline for (0.., std.meta.fields(Options)) |i, f| {
            c.JE_textShade(
                c.VGAScreen,
                c.JE_fontCenter(MainMenu.getName(@enumFromInt(f.value)).ptr, c.TINY_FONT),
                @intCast(82 + i * 12),
                MainMenu.getName(@enumFromInt(f.value)).ptr,
                12,
                @intFromBool(@as(Options, @enumFromInt(f.value)) == self.state) * @as(c_int, 4),
                c.FULL_SHADE,
            );
        }
    }
};

const NewGameMenu = struct {
    state: c.de_mode_t = c.MODE_5CARDWAR,

    fn up(option: c.de_mode_t, config: *const c.destruct_config_s) c.de_mode_t {
        var mode = option;

        mode -= 1;
        if (mode < 0) {
            mode = c.MAX_MODES;
        } else if (mode == c.MODE_CUSTOM and !config.allow_custom) {
            mode = c.MODE_CUSTOM - 1;
        }

        return mode;
    }

    fn down(option: c.de_mode_t, config: *const c.destruct_config_s) c.de_mode_t {
        var mode = option;

        mode += 1;
        if (mode > c.MAX_MODES) {
            mode = 0;
        } else if (mode == c.MODE_CUSTOM and !config.allow_custom) {
            mode = c.MODE_CUSTOM + 1;
        }

        return mode;
    }

    // state == c.MAX_MODES means return to main menu
    // state == c.MODE_NONE means terminate application
    fn handleKeyPress(self: *NewGameMenu, config: *const c.destruct_config_s) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_ESCAPE] != 0) {
            self.state = c.MAX_MODES; // User is quitting, return failure
            selection_made = true;
        }
        if (c.keysactive[SDL.SDL_SCANCODE_RETURN] != 0) {
            selection_made = true; // User has selected, return choice
        }
        if (c.keysactive[SDL.SDL_SCANCODE_UP] != 0) {
            self.state = NewGameMenu.up(self.state, config);
        }
        if (c.keysactive[SDL.SDL_SCANCODE_DOWN] != 0) {
            self.state = NewGameMenu.down(self.state, config);
        }

        return selection_made;
    }

    // Helper function of JE_modeSelect.  Do not use elsewhere.
    fn draw(self: *const NewGameMenu, config: *const c.destruct_config_s) void {
        var i: usize = 0;

        for (0..@as(c.de_mode_t, c.DESTRUCT_MODES)) |_| {
            c.JE_textShade(
                c.VGAScreen,
                c.JE_fontCenter(&c.destructModeName[i], c.TINY_FONT),
                @intCast(82 + i * 12),
                &c.destructModeName[i],
                12,
                @intCast(@intFromBool(self.state == i) * @as(c_int, 4)),
                c.FULL_SHADE,
            );
            i += 1;
        }
        if (config.allow_custom == true) {
            c.JE_textShade(
                c.VGAScreen,
                c.JE_fontCenter("Custom", c.TINY_FONT),
                @intCast(82 + i * 12),
                "Custom",
                12,
                @intCast(@intFromBool(self.state == i) * @as(c_int, 4)),
                c.FULL_SHADE,
            );
            i += 1;
        }

        i += 1; // add vertical spacing

        c.JE_textShade(
            c.VGAScreen,
            c.JE_fontCenter("Back", c.TINY_FONT),
            @intCast(82 + i * 12),
            "Back",
            12,
            @intCast(@intFromBool(self.state == c.MAX_MODES) * @as(c_int, 4)),
            c.FULL_SHADE,
        );
    }
};

const ControllerMenu = struct {
    key_state: c.de_keys_t = c.KEY_LEFT,
    player_state: c.de_player_t = c.PLAYER_LEFT,

    fn up(option: c.de_keys_t) c.de_keys_t {
        var result = option - 1;
        if (result < 0) {
            result = c.MAX_KEY;
        }
        return result;
    }

    fn down(option: c.de_keys_t) c.de_keys_t {
        var result = option + 1;
        if (result > c.MAX_KEY) {
            result = 0;
        }
        return result;
    }

    fn leftOrRight(option: c.de_player_t) c.de_player_t {
        return switch (option) {
            c.PLAYER_LEFT => c.PLAYER_RIGHT,
            c.PLAYER_RIGHT => c.PLAYER_LEFT,
            else => c.PLAYER_LEFT,
        };
    }

    // key_state == c.MAX_KEY means return to main menu
    fn handleKeyPress(self: *ControllerMenu) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_ESCAPE] != 0) {
            self.key_state = c.MAX_KEY;
            selection_made = true;
        }
        if (c.keysactive[SDL.SDL_SCANCODE_RETURN] != 0) {
            selection_made = true;
        }
        if (c.keysactive[SDL.SDL_SCANCODE_UP] != 0) {
            self.key_state = ControllerMenu.up(self.key_state);
        }
        if (c.keysactive[SDL.SDL_SCANCODE_DOWN] != 0) {
            self.key_state = ControllerMenu.down(self.key_state);
        }
        if (c.keysactive[SDL.SDL_SCANCODE_LEFT] != 0 or c.keysactive[SDL.SDL_SCANCODE_RIGHT] != 0) {
            self.player_state = ControllerMenu.leftOrRight(self.player_state);
        }

        return selection_made;
    }

    fn draw(self: *const ControllerMenu) void {
        _ = self;
    }
};

const MenuState = struct {
    const Menus = union(enum) {
        main: MainMenu,
        new_game: NewGameMenu,
        controller: ControllerMenu,
    };

    state: Menus,
    screen_changed: bool,

    fn handleKeyPress(self: *MenuState, config: *const c.destruct_config_s) bool {
        var terminal = false;
        switch (self.state) {
            Menus.main => |*value| {
                const selection_made = value.handleKeyPress();
                if (selection_made) {
                    switch (value.state) {
                        MainMenu.Options.new_game => self.* = .{ .state = .{ .new_game = .{} }, .screen_changed = true },
                        MainMenu.Options.controller => self.* = .{ .state = .{ .controller = .{} }, .screen_changed = true },
                        MainMenu.Options.quit => terminal = true,
                    }
                }
            },
            Menus.new_game => |*value| {
                const selection_made = value.handleKeyPress(config);
                if (selection_made) {
                    switch (value.state) {
                        c.MAX_MODES => self.* = .{ .state = .{ .main = .{} }, .screen_changed = true },
                        else => terminal = true,
                    }
                }
            },
            Menus.controller => |*value| {
                const selection_made = value.handleKeyPress();
                if (selection_made) {
                    switch (value.key_state) {
                        c.MAX_KEY => self.* = .{ .state = .{ .main = .{} }, .screen_changed = true },
                        else => {
                            // TODO: set new key
                        },
                    }
                }
            },
        }
        return terminal;
    }

    fn draw(self: *MenuState, config: *const c.destruct_config_s) void {
        if (self.screen_changed) {
            _ = c.memcpy(c.VGAScreen2.*.pixels, c.VGAScreen.*.pixels, @intCast(c.VGAScreen2.*.h * c.VGAScreen2.*.pitch));
            self.screen_changed = false;
        }
        switch (self.state) {
            Menus.main => |*value| value.draw(),
            Menus.new_game => |*value| value.draw(config),
            Menus.controller => |*value| value.draw(),
        }
    }
};

////// menu()
// The return value is the selected mode, or -1 (MODE_NONE) if the user quits.
fn menu(config: *const c.destruct_config_s) c.de_mode_t {
    var menu_state: MenuState = .{ .state = .{ .main = .{} }, .screen_changed = true };

    // Draw the menu and fade us in
    menu_state.draw(config);
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

        const exit = menu_state.handleKeyPress(config);
        menu_state.draw(config); // Re-draw the menu every iteration

        c.JE_showVGA();

        if (exit) {
            break;
        }
    }

    c.fade_black(15);
    _ = c.memcpy(c.VGAScreen.*.pixels, c.VGAScreen2.*.pixels, @intCast(c.VGAScreen.*.h * c.VGAScreen.*.pitch));
    c.JE_showVGA();

    return switch (menu_state.state) {
        MenuState.Menus.main => c.MODE_NONE,
        MenuState.Menus.new_game => |value| value.state,
        MenuState.Menus.controller => unreachable,
    };
}
