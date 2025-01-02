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
    self.destruct_player[c.PLAYER_LEFT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_player[c.PLAYER_LEFT].unit);
    self.destruct_player[c.PLAYER_RIGHT].unit = @alignCast(@ptrCast(c.malloc(@sizeOf(c.destruct_unit_s) * self.config.max_installations).?));
    defer c.free(self.destruct_player[c.PLAYER_RIGHT].unit);

    self.world.VGAScreen = c.VGAScreen;
    self.destructInternalScreen = c.game_screen;
    self.destructPrevScreen = c.VGAScreen2;

    c.JE_loadCompShapes(&c.destructSpriteSheet, '~');
    defer c.free_sprite2s(&c.destructSpriteSheet);

    c.fade_black(1);

    self.JE_destructMain();
}

fn JE_destructMain(self: *Destruct) void {
    var curState: c.de_state_t = c.STATE_INIT;

    c.JE_loadPic(self.world.VGAScreen, 11, false);
    c.JE_introScreen(self.world.VGAScreen, self.destructInternalScreen);

    c.DE_ResetPlayers(&self.destruct_player);

    self.destruct_player[c.PLAYER_LEFT].is_cpu = self.config.ai[c.PLAYER_LEFT];
    self.destruct_player[c.PLAYER_RIGHT].is_cpu = self.config.ai[c.PLAYER_RIGHT];

    while (true) {
        self.world.destructMode = JE_destructMenu(
            self.world.VGAScreen,
            self.destructInternalScreen,
            self.destructPrevScreen,
            &self.config,
        );
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
                self.destructInternalScreen,
            );

            while (true) {
                curState = c.DE_RunTick(
                    &self.config,
                    &self.destruct_player,
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
    ) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_F1] != 0) {
            JE_helpScreen(currScreen, destructPrevScreen);
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
    ) bool {
        var selection_made = false;

        // See what was pressed
        if (c.keysactive[SDL.SDL_SCANCODE_F1] != 0) {
            JE_helpScreen(currScreen, destructPrevScreen);
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
                currScreen,
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
            currScreen,
            c.JE_fontCenter("Back", c.TINY_FONT),
            @intCast(82 + i * 12),
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
    key_state: c.de_keys_t = c.KEY_LEFT,
    player_state: c.de_player_t = c.PLAYER_LEFT,

    fn up(option: c.de_keys_t) c.de_keys_t {
        return switch (option) {
            0 => c.MAX_KEY,
            else => option - 1,
        };
    }

    fn down(option: c.de_keys_t) c.de_keys_t {
        return switch (option) {
            c.MAX_KEY => 0,
            else => option + 1,
        };
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
            if (self.key_state == c.MAX_KEY) {
                selection_made = true;
            } else {
                // set key here
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

        return selection_made;
    }

    fn draw(self: *const ControllerMenu, currScreen: *c.SDL_Surface) void {
        _ = self;

        c.JE_clr256(currScreen);

        for (0..2) |i| {
            c.JE_outText(currScreen, 100, @intCast(5 + i * 90), &c.destructHelp[i * 12 + 0], 2, 4);
            c.JE_outText(currScreen, 100, @intCast(15 + i * 90), &c.destructHelp[i * 12 + 1], 2, 1);
            for (3..12 + 1) |j| {
                c.JE_outText(
                    currScreen,
                    @intCast(((j - 1) % 2) * 160 + 10),
                    @intCast(15 + ((j - 1) / 2) * 12 + i * 90),
                    &c.destructHelp[i * 12 + j - 1],
                    1,
                    3,
                );
            }
        }
        c.JE_outText(currScreen, 30, 190, &c.destructHelp[24], 3, 4);

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
    ) bool {
        var terminal = false;
        switch (self.state) {
            Menus.main => |*menu| {
                const selection_made = menu.handleKeyPress(currScreen, destructPrevScreen);
                if (selection_made) {
                    switch (menu.state) {
                        MainMenu.Options.new_game => self.* = .{ .state = .{ .new_game = .{} }, .screen_changed = true },
                        MainMenu.Options.controller => self.* = .{ .state = .{ .controller = .{} }, .screen_changed = true },
                        MainMenu.Options.quit => terminal = true,
                    }
                }
            },
            Menus.new_game => |*menu| {
                const selection_made = menu.handleKeyPress(currScreen, destructPrevScreen, config);
                if (selection_made) {
                    switch (menu.state) {
                        c.MAX_MODES => self.* = .{ .state = .{ .main = .{} }, .screen_changed = true },
                        else => terminal = true,
                    }
                }
            },
            Menus.controller => |*menu| {
                const selection_made = menu.handleKeyPress();
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
    ) void {
        if (self.screen_changed) {
            _ = c.memcpy(currScreen.*.pixels, destructInternalScreen.*.pixels, @intCast(currScreen.*.h * currScreen.*.pitch));
            self.screen_changed = false;
        }
        switch (self.state) {
            Menus.main => |*menu| menu.draw(currScreen),
            Menus.new_game => |*menu| menu.draw(currScreen, config),
            Menus.controller => |*menu| menu.draw(currScreen),
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
) c.de_mode_t {
    _ = c.memcpy(
        destructInternalScreen.*.pixels,
        currScreen.*.pixels,
        @intCast(destructInternalScreen.*.h * destructInternalScreen.*.pitch),
    );
    var menu_state: MenuState = .{ .state = .{ .main = .{} }, .screen_changed = true };

    // Draw the menu and fade us in
    menu_state.draw(currScreen, destructInternalScreen, config);
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

        const exit = menu_state.handleKeyPress(currScreen, destructPrevScreen, config);
        menu_state.draw(currScreen, destructInternalScreen, config); // Re-draw the menu every iteration

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

export fn JE_helpScreen(currScreen: *c.SDL_Surface, destructPrevScreen: *c.SDL_Surface) void {
    // JE_getVGA();  didn't do anything anyway?
    c.fade_black(15);
    _ = c.memcpy(destructPrevScreen.*.pixels, currScreen.*.pixels, @intCast(destructPrevScreen.*.h * destructPrevScreen.*.pitch));

    var menu_state = ControllerMenu{};
    menu_state.draw(currScreen);

    c.fade_palette(&c.colors, 15, 0, 255);

    // wait until user hits a key
    while (true) {
        c.service_SDL_events(true);
        SDL.SDL_Delay(16);
        if (c.newkey) {
            break;
        }
    }

    c.fade_black(15);
    _ = c.memcpy(currScreen.*.pixels, destructPrevScreen.*.pixels, @intCast(currScreen.*.h * currScreen.*.pitch));
    c.JE_showVGA();
    c.fade_palette(&c.colors, 15, 0, 255);
}
