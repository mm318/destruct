/* 
 * OpenTyrian: A modern cross-platform port of Tyrian
 * Copyright (C) 2007-2009  The OpenTyrian Development Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
#ifndef DESTRUCT_H
#define DESTRUCT_H

#include "SDL.h"

#include "opentyr.h"
#include "config_file.h"


enum de_state_t
{
    STATE_INIT,
    STATE_RELOAD,
    STATE_CONTINUE
};

enum de_mode_t
{
    MODE_5CARDWAR = 0,
    MODE_TRADITIONAL,
    MODE_HELIASSAULT,
    MODE_HELIDEFENSE,
    MODE_OUTGUNNED,
    MODE_CUSTOM,
    MAX_MODES,
    MODE_NONE = -1
};

enum de_player_t
{
    PLAYER_LEFT = 0,
    PLAYER_RIGHT = 1,
    MAX_PLAYERS = 2
};

enum de_team_t
{
    TEAM_LEFT = 0,
    TEAM_RIGHT = 1,
    MAX_TEAMS = 2
};

/* de_keys_t and de_move_t should line up. */
enum de_keys_t
{
    KEY_LEFT = 0,
    KEY_RIGHT,
    KEY_UP,
    KEY_DOWN,
    KEY_CHANGE,
    KEY_FIRE,
    KEY_CYUP,
    KEY_CYDN,
    MAX_KEY = 8
};

enum de_move_t
{
    MOVE_LEFT = 0,
    MOVE_RIGHT,
    MOVE_UP,
    MOVE_DOWN,
    MOVE_CHANGE,
    MOVE_FIRE,
    MOVE_CYUP,
    MOVE_CYDN,
    MAX_MOVE = 8
};

enum de_expl_t
{
    EXPL_NONE,
    EXPL_MAGNET,
    EXPL_DIRT,
    EXPL_NORMAL
}; /* this needs a better name */

enum de_unit_t
{
    UNIT_TANK = 0,
    UNIT_NUKE,
    UNIT_DIRT,
    UNIT_SATELLITE,
    UNIT_MAGNET,
    UNIT_LASER,
    UNIT_JUMPER,
    UNIT_HELI,
    UNIT_FIRST = UNIT_TANK,
    UNIT_LAST = UNIT_HELI,
    MAX_UNITS = 8,
    UNIT_NONE = -1
};

enum de_shot_t
{
    SHOT_TRACER = 0,
    SHOT_SMALL,
    SHOT_LARGE,
    SHOT_MICRO,
    SHOT_SUPER,
    SHOT_DEMO,
    SHOT_SMALLNUKE,
    SHOT_LARGENUKE,
    SHOT_SMALLDIRT,
    SHOT_LARGEDIRT,
    SHOT_MAGNET,
    SHOT_MINILASER,
    SHOT_MEGALASER,
    SHOT_LASERTRACER,
    SHOT_MEGABLAST,
    SHOT_MINI,
    SHOT_BOMB,
    SHOT_FIRST = SHOT_TRACER,
    SHOT_LAST = SHOT_BOMB,
    MAX_SHOT_TYPES = 17,
    SHOT_INVALID = -1
};

/*** Structs ***/
struct destruct_config_s
{
    unsigned int max_shots;
    unsigned int min_walls;
    unsigned int max_walls;
    unsigned int max_explosions;
    unsigned int max_installations;
    bool allow_custom;
    bool alwaysalias;
    bool jumper_straight[2];
    bool ai[2];
};

struct destruct_world_s
{
    /* Map data & screen pointer */
    unsigned int baseMap[320];
    SDL_Surface * VGAScreen;
    struct destruct_wall_s * mapWalls;

    /* Map configuration */
    enum de_mode_t destructMode;
    unsigned int mapFlags;
};

struct destruct_shot_s
{
    bool isAvailable;

    float x;
    float y;
    float xmov;
    float ymov;
    bool gravity;
    unsigned int shottype;
    //int shotdur; /* This looks to be unused */
    unsigned int trailx[4], traily[4], trailc[4];
};

struct destruct_explo_s
{
    bool isAvailable;

    unsigned int x, y;
    unsigned int explowidth;
    unsigned int explomax;
    unsigned int explofill;
    enum de_expl_t exploType;
};

struct destruct_wall_s
{
    bool wallExist;
    unsigned int wallX, wallY;
};

struct destruct_unit_s
{
    /* Positioning/movement */
    unsigned int unitX; /* yep, one's an int and the other is a real */
    float        unitY;
    float        unitYMov;
    bool         isYInAir;

    /* What it is and what it fires */
    enum de_unit_t unitType;
    enum de_shot_t shotType;

    /* What it's pointed */
    float angle;
    float power;

    /* Misc */
    int lastMove;
    unsigned int ani_frame;
    int health;
};

struct destruct_keys_s
{
    SDL_Scancode Config[MAX_KEY];
};

struct destruct_moves_s
{
    bool actions[MAX_MOVE];
};

struct destruct_ai_s
{
    int c_Angle, c_Power, c_Fire;
    unsigned int c_noDown;
};

struct destruct_player_s
{
    bool is_cpu;
    struct destruct_ai_s aiMemory;

    struct destruct_unit_s * unit;
    struct destruct_moves_s moves;
    struct destruct_keys_s  keys;

    enum de_team_t team;
    unsigned int unitsRemaining;
    unsigned int unitSelected;
    unsigned int shotDelay;
    unsigned int score;
};

extern JE_boolean destructFirstTime;
extern JE_byte basetypes[10][11];

void load_destruct_config(Config *config_, struct destruct_config_s * config);

// Prep functions
void JE_introScreen(SDL_Surface * screen, SDL_Surface * destructInternalScreen);
void JE_helpScreen(SDL_Surface * screen,
                   SDL_Surface * destructPrevScreen,
                   struct destruct_player_s * destruct_player);

// level generating functions
void DE_ResetLevel(const struct destruct_config_s * config,
                   struct destruct_player_s * destruct_player,
                   struct destruct_shot_s * shotRec,
                   struct destruct_explo_s * exploRec,
                   struct destruct_world_s * world,
                   SDL_Surface * destructInternalScreen);

// player functions
void DE_ResetPlayers(struct destruct_player_s * destruct_player);

// unit functions
void DE_ResetUnits(const struct destruct_config_s * config, struct destruct_player_s * destruct_player);

// gameplay functions
enum de_state_t DE_RunTick(const struct destruct_config_s * config,
                           struct destruct_player_s * destruct_player,
                           struct destruct_shot_s * shotRec,
                           struct destruct_explo_s * exploRec,
                           struct destruct_world_s * world,
                           SDL_Surface * destructInternalScreen,
                           SDL_Surface * destructPrevScreen);

#endif /* DESTRUCT_H */
