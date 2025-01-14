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

pub const assets = @import("assets");

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
destruct_players: [c.MAX_PLAYERS]c.destruct_player_s = undefined,
world: c.destruct_world_s = undefined,
shotRec: *c.destruct_shot_s = undefined,
exploRec: *c.destruct_explo_s = undefined,
destructInternalScreen: *c.SDL_Surface = undefined,
destructPrevScreen: *c.SDL_Surface = undefined,

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
    self.destruct_players[c.PLAYER_LEFT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_players[c.PLAYER_LEFT].unit);
    self.destruct_players[c.PLAYER_RIGHT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_players[c.PLAYER_RIGHT].unit);

    self.world.VGAScreen = c.VGAScreen;
    self.destructInternalScreen = c.game_screen;
    self.destructPrevScreen = c.VGAScreen2;

    c.JE_loadCompShapes(assets.game_sprites.ptr, assets.game_sprites.len, &c.destructSpriteSheet);
    defer c.free_sprite2s(&c.destructSpriteSheet);

    c.fade_black(1);

    self.JE_destructMain();
}

fn JE_destructMain(self: *Destruct) void {
    var curState: c.de_state_t = c.STATE_INIT;

    c.JE_loadPic(assets.game_screen.ptr, assets.game_screen.len, self.world.VGAScreen, 11, false);
    c.JE_introScreen(self.world.VGAScreen, self.destructInternalScreen);

    c.DE_ResetPlayers(&self.destruct_players);

    self.destruct_players[c.PLAYER_LEFT].is_cpu = self.config.ai[c.PLAYER_LEFT];
    self.destruct_players[c.PLAYER_RIGHT].is_cpu = self.config.ai[c.PLAYER_RIGHT];

    while (true) {
        self.world.destructMode = JE_destructMenu(
            self.world.VGAScreen,
            self.destructInternalScreen,
            self.destructPrevScreen,
            &self.config,
            &self.destruct_players,
        );
        if (self.world.destructMode == c.MODE_NONE) {
            break; // User is quitting
        }

        while (true) {
            c.destructFirstTime = true;
            c.JE_loadPic(assets.game_screen.ptr, assets.game_screen.len, self.world.VGAScreen, 11, false);

            c.DE_ResetUnits(&self.config, &self.destruct_players);
            c.DE_ResetLevel(
                &self.config,
                &self.destruct_players,
                self.shotRec,
                self.exploRec,
                &self.world,
                self.destructInternalScreen,
            );

            while (true) {
                curState = c.DE_RunTick(
                    &self.config,
                    &self.destruct_players,
                    self.shotRec,
                    self.exploRec,
                    &self.world,
                    self.destructInternalScreen,
                    self.destructPrevScreen,
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

    fn handleKeyPress(
        self: *MainMenu,
        currScreen: *c.SDL_Surface,
        destructPrevScreen: *c.SDL_Surface,
        destructPlayers: [*]c.destruct_player_s,
    ) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_F1] != 0) {
            JE_helpScreen(currScreen, destructPrevScreen, destructPlayers);
        }
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

    fn draw(self: *const MainMenu, currScreen: *c.SDL_Surface) void {
        inline for (0.., std.meta.fields(Options)) |i, f| {
            c.JE_textShade(
                currScreen,
                c.JE_fontCenter(MainMenu.getName(@enumFromInt(f.value)).ptr, c.TINY_FONT),
                @intCast(82 + i * 12),
                MainMenu.getName(@enumFromInt(f.value)).ptr,
                12,
                @intFromBool(@as(Options, @enumFromInt(f.value)) == self.state) * @as(c_int, 4),
                c.FULL_SHADE,
            );

            // "press F1 for help" message
            c.JE_outText(currScreen, c.JE_fontCenter(&c.miscText[64], c.TINY_FONT), 180, &c.miscText[64], 15, 2);

            // "press F10 to toggle human/cpu" message
            c.JE_outText(currScreen, c.JE_fontCenter(&c.miscText[65], c.TINY_FONT), 190, &c.miscText[65], 15, 2);
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
    fn handleKeyPress(
        self: *NewGameMenu,
        currScreen: *c.SDL_Surface,
        destructPrevScreen: *c.SDL_Surface,
        config: *const c.destruct_config_s,
        destructPlayers: [*]c.destruct_player_s,
    ) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_F1] != 0) {
            JE_helpScreen(currScreen, destructPrevScreen, destructPlayers);
        }
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

    // Helper function of JE_modeSelect. Do not use elsewhere.
    fn draw(self: *const NewGameMenu, currScreen: *c.SDL_Surface, config: *const c.destruct_config_s) void {
        var i: usize = 0;

        for (0..@as(c.de_mode_t, c.DESTRUCT_MODES)) |_| {
            c.JE_textShade(
                currScreen,
                c.JE_fontCenter(&c.destructModeName[i], c.TINY_FONT),
                @intCast(58 + i * 12),
                &c.destructModeName[i],
                12,
                @intCast(@intFromBool(self.state == i) * @as(c_int, 4)),
                c.FULL_SHADE,
            );
            i += 1;
        }
        if (config.allow_custom == true) {
            c.JE_textShade(
                currScreen,
                c.JE_fontCenter("Custom", c.TINY_FONT),
                @intCast(58 + i * 12),
                "Custom",
                12,
                @intCast(@intFromBool(self.state == i) * @as(c_int, 4)),
                c.FULL_SHADE,
            );
            i += 1;
        }

        i += 1; // add vertical spacing

        c.JE_textShade(
            currScreen,
            c.JE_fontCenter("Back", c.TINY_FONT),
            @intCast(58 + i * 12),
            "Back",
            12,
            @intCast(@intFromBool(self.state == c.MAX_MODES) * @as(c_int, 4)),
            c.FULL_SHADE,
        );

        // "press F1 for help" message
        c.JE_outText(currScreen, c.JE_fontCenter(&c.miscText[64], c.TINY_FONT), 180, &c.miscText[64], 15, 2);

        // "press F10 to toggle human/cpu" message
        c.JE_outText(currScreen, c.JE_fontCenter(&c.miscText[65], c.TINY_FONT), 190, &c.miscText[65], 15, 2);
    }
};

const ControllerMenu = struct {
    const KEY_ORDER = [_]c.de_keys_t{
        c.KEY_FIRE,
        c.KEY_CYUP,
        c.KEY_CYDN,
        c.KEY_CHANGE,
        c.KEY_UP,
        c.KEY_DOWN,
        c.KEY_LEFT,
        c.KEY_RIGHT,
    };

    player_state: c.de_player_t = c.PLAYER_LEFT,
    key_state: c.de_keys_t = c.KEY_FIRE,
    set_key: bool = false,

    fn up(option: c.de_keys_t) c.de_keys_t {
        return switch (option) {
            c.KEY_LEFT => c.KEY_DOWN,
            c.KEY_RIGHT => c.KEY_LEFT,
            c.KEY_UP => c.KEY_CHANGE,
            c.KEY_DOWN => c.KEY_UP,
            c.KEY_CHANGE => c.KEY_CYDN,
            c.KEY_FIRE => c.MAX_KEY,
            c.KEY_CYUP => c.KEY_FIRE,
            c.KEY_CYDN => c.KEY_CYUP,
            c.MAX_KEY => c.KEY_RIGHT,
            else => unreachable,
        };
    }

    fn down(option: c.de_keys_t) c.de_keys_t {
        return switch (option) {
            c.KEY_LEFT => c.KEY_RIGHT,
            c.KEY_RIGHT => c.MAX_KEY,
            c.KEY_UP => c.KEY_DOWN,
            c.KEY_DOWN => c.KEY_LEFT,
            c.KEY_CHANGE => c.KEY_UP,
            c.KEY_FIRE => c.KEY_CYUP,
            c.KEY_CYUP => c.KEY_CYDN,
            c.KEY_CYDN => c.KEY_CHANGE,
            c.MAX_KEY => c.KEY_FIRE,
            else => unreachable,
        };
    }

    fn leftOrRight(option: c.de_player_t) c.de_player_t {
        return switch (option) {
            c.PLAYER_LEFT => c.PLAYER_RIGHT,
            c.PLAYER_RIGHT => c.PLAYER_LEFT,
            else => unreachable,
        };
    }

    // key_state == c.MAX_KEY means return to main menu
    fn handleKeyPress(self: *ControllerMenu, destructPlayers: [*]c.destruct_player_s) bool {
        var selection_made = false;

        if (self.set_key) {
            switch (c.lastkey_scan) {
                SDL.SDL_SCANCODE_ESCAPE => {
                    self.set_key = false;
                },
                SDL.SDL_SCANCODE_F1 => {}, // reserved for bringing up help screen (controller menu)
                SDL.SDL_SCANCODE_F10 => {}, // reserved for toggling left player to be cpu/human
                SDL.SDL_SCANCODE_F11 => {}, // reserved for toggling right player to be cpu/human
                SDL.SDL_SCANCODE_BACKSPACE => {}, // reserved for starting new round
                else => {
                    for (0..c.MAX_PLAYERS) |curr_player| {
                        for (0..c.MAX_KEY) |curr_key| {
                            if (destructPlayers[curr_player].keys.Config[curr_key] == c.lastkey_scan) {
                                destructPlayers[curr_player].keys.Config[curr_key] = SDL.SDL_SCANCODE_UNKNOWN;
                            }
                        }
                    }
                    destructPlayers[self.player_state].keys.Config[self.key_state] = c.lastkey_scan;
                    self.set_key = false;
                },
            }
        } else {
            // See what was pressed
            if (c.keysactive[SDL.SDL_SCANCODE_ESCAPE] != 0) {
                self.key_state = c.MAX_KEY;
                selection_made = true;
            }
            if (c.keysactive[SDL.SDL_SCANCODE_RETURN] != 0) {
                if (self.key_state == c.MAX_KEY) {
                    selection_made = true;
                } else {
                    self.set_key = true;
                }
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
        }
        return selection_made;
    }

    fn draw(self: *const ControllerMenu, currScreen: *c.SDL_Surface, destructPlayers: [*]const c.destruct_player_s) void {
        c.JE_clr256(currScreen);

        for (0..2) |i| {
            c.JE_outText(currScreen, @intCast(105 + i * 105), 10, &c.destructHelp[i * 12 + 0], 2, 4);
            c.JE_outText(currScreen, @intCast(105 + i * 105), 20, &c.destructHelp[i * 12 + 1], 2, 1);
        }

        c.JE_outText(currScreen, 10, @intCast(25 + 2 * 12), "Fire", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 3 * 12), "Next weapon", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 4 * 12), "Previous weapon", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 5 * 12), "Change vehicle", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 6 * 12), "Increase velocity", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 7 * 12), "Decrease velocity", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 8 * 12), "Change angle CCW", 1, 3);
        c.JE_outText(currScreen, 10, @intCast(25 + 9 * 12), "Change angle CW", 1, 3);

        for (0.., 0..c.MAX_PLAYERS) |i, curr_player| {
            for (0.., KEY_ORDER) |j, curr_key| {
                c.JE_textShade(
                    currScreen,
                    @intCast(110 + i * 110),
                    @intCast(25 + (j + 2) * 12),
                    if (self.player_state == curr_player and self.key_state == curr_key and self.set_key)
                        "---"
                    else if (destructPlayers[curr_player].keys.Config[curr_key] == SDL.SDL_SCANCODE_UNKNOWN)
                        "---"
                    else
                        SDL.SDL_GetScancodeName(destructPlayers[curr_player].keys.Config[curr_key]),
                    12,
                    @intCast(@intFromBool(self.player_state == curr_player and self.key_state == curr_key) * @as(c_int, 4)),
                    c.FULL_SHADE,
                );
            }
        }

        c.JE_textShade(
            currScreen,
            c.JE_fontCenter("Back", c.TINY_FONT),
            @intCast(25 + 11 * 12),
            "Back",
            12,
            @intCast(@intFromBool(self.key_state == c.MAX_KEY) * @as(c_int, 4)),
            c.FULL_SHADE,
        );

        c.JE_outText(currScreen, c.JE_fontCenter(&c.destructHelp[24], c.TINY_FONT), 190, &c.destructHelp[24], 3, 4);

        c.JE_showVGA();
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

    fn handleKeyPress(
        self: *MenuState,
        currScreen: *c.SDL_Surface,
        destructPrevScreen: *c.SDL_Surface,
        config: *const c.destruct_config_s,
        destructPlayers: [*]c.destruct_player_s,
    ) bool {
        var terminal = false;
        switch (self.state) {
            Menus.main => |*menu| {
                const selection_made = menu.handleKeyPress(currScreen, destructPrevScreen, destructPlayers);
                if (selection_made) {
                    switch (menu.state) {
                        MainMenu.Options.new_game => self.* = .{ .state = .{ .new_game = .{} }, .screen_changed = true },
                        MainMenu.Options.controller => self.* = .{ .state = .{ .controller = .{} }, .screen_changed = true },
                        MainMenu.Options.quit => terminal = true,
                    }
                }
            },
            Menus.new_game => |*menu| {
                const selection_made = menu.handleKeyPress(currScreen, destructPrevScreen, config, destructPlayers);
                if (selection_made) {
                    switch (menu.state) {
                        c.MAX_MODES => self.* = .{ .state = .{ .main = .{} }, .screen_changed = true },
                        else => terminal = true,
                    }
                }
            },
            Menus.controller => |*menu| {
                const selection_made = menu.handleKeyPress(destructPlayers);
                if (selection_made) {
                    switch (menu.key_state) {
                        c.MAX_KEY => self.* = .{ .state = .{ .main = .{} }, .screen_changed = true },
                        else => unreachable,
                    }
                }
            },
        }
        return terminal;
    }

    fn draw(
        self: *MenuState,
        currScreen: *c.SDL_Surface,
        destructInternalScreen: *c.SDL_Surface,
        config: *const c.destruct_config_s,
        destructPlayers: [*]const c.destruct_player_s,
    ) void {
        if (self.screen_changed) {
            _ = c.memcpy(currScreen.*.pixels, destructInternalScreen.*.pixels, @intCast(currScreen.*.h * currScreen.*.pitch));
            self.screen_changed = false;
        }
        switch (self.state) {
            Menus.main => |*menu| menu.draw(currScreen),
            Menus.new_game => |*menu| menu.draw(currScreen, config),
            Menus.controller => |*menu| menu.draw(currScreen, destructPlayers),
        }
    }
};

////// JE_destructMenu()
// The return value is the selected mode, or -1 (MODE_NONE) if the user quits.
fn JE_destructMenu(
    currScreen: *c.SDL_Surface,
    destructInternalScreen: *c.SDL_Surface,
    destructPrevScreen: *c.SDL_Surface,
    config: *const c.destruct_config_s,
    destructPlayers: [*]c.destruct_player_s,
) c.de_mode_t {
    _ = c.memcpy(
        destructInternalScreen.*.pixels,
        currScreen.*.pixels,
        @intCast(destructInternalScreen.*.h * destructInternalScreen.*.pitch),
    );
    var menu_state: MenuState = .{ .state = .{ .main = .{} }, .screen_changed = true };

    // Draw the menu and fade us in
    menu_state.draw(currScreen, destructInternalScreen, config, destructPlayers);
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

        const exit = menu_state.handleKeyPress(currScreen, destructPrevScreen, config, destructPlayers);
        menu_state.draw(currScreen, destructInternalScreen, config, destructPlayers); // Re-draw the menu every iteration

        c.JE_showVGA();

        if (exit) {
            break;
        }
    }

    c.fade_black(15);
    _ = c.memcpy(
        currScreen.*.pixels,
        destructInternalScreen.*.pixels,
        @intCast(currScreen.*.h * currScreen.*.pitch),
    );
    c.JE_showVGA();

    return switch (menu_state.state) {
        MenuState.Menus.main => c.MODE_NONE,
        MenuState.Menus.new_game => |menu| menu.state,
        MenuState.Menus.controller => unreachable,
    };
}

export fn JE_helpScreen(
    currScreen: *c.SDL_Surface,
    destructPrevScreen: *c.SDL_Surface,
    destructPlayers: [*]c.destruct_player_s,
) void {
    // JE_getVGA();  didn't do anything anyway?
    c.fade_black(15);
    _ = c.memcpy(destructPrevScreen.*.pixels, currScreen.*.pixels, @intCast(destructPrevScreen.*.h * destructPrevScreen.*.pitch));

    var menu_state = ControllerMenu{};
    menu_state.draw(currScreen, destructPlayers);

    c.fade_palette(&c.colors, 15, 0, 255);

    while (true) {
        // wait until user hits a key
        while (true) {
            c.service_SDL_events(true);
            SDL.SDL_Delay(16);
            if (c.newkey) {
                break;
            }
        }

        const exit = menu_state.handleKeyPress(destructPlayers);
        menu_state.draw(currScreen, destructPlayers);

        c.JE_showVGA();

        if (exit) {
            break;
        }
    }

    c.fade_black(15);
    _ = c.memcpy(currScreen.*.pixels, destructPrevScreen.*.pixels, @intCast(currScreen.*.h * currScreen.*.pitch));
    c.JE_showVGA();
    c.fade_palette(&c.colors, 15, 0, 255);
}
