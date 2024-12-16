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
#ifndef CONFIG_H
#define CONFIG_H

#include "opentyr.h"
#include "config_file.h"

#include "SDL.h"

#include <stdio.h>

#define SAVE_FILES_NUM (11 * 2)

/* These are necessary because the size of the structure has changed from the original, but we
   need to know the original sizes in order to find things in TYRIAN.SAV */
#define SAVE_FILES_SIZE 2398
#define SIZEOF_SAVEGAMETEMP SAVE_FILES_SIZE + 4 + 100
#define SAVE_FILE_SIZE (SIZEOF_SAVEGAMETEMP - 4)

/*#define SAVE_FILES_SIZE (2502 - 4)
#define SAVE_FILE_SIZE (SAVE_FILES_SIZE)*/

enum
{
	DIFFICULTY_WIMP = 0,
	DIFFICULTY_EASY,
	DIFFICULTY_NORMAL,
	DIFFICULTY_HARD,
	DIFFICULTY_IMPOSSIBLE,
	DIFFICULTY_INSANITY,
	DIFFICULTY_SUICIDE,
	DIFFICULTY_MANIACAL,
	DIFFICULTY_ZINGLON,  // aka Lord of the Game
	DIFFICULTY_NORTANEOUS,
	DIFFICULTY_10,
};

// NOTE: Do not reorder.  This ordering corresponds to the keyboard
//       configuration menu and to the bits stored in demo files.
enum
{
	KEY_SETTING_UP,
	KEY_SETTING_DOWN,
	KEY_SETTING_LEFT,
	KEY_SETTING_RIGHT,
	KEY_SETTING_FIRE,
	KEY_SETTING_CHANGE_FIRE,
	KEY_SETTING_LEFT_SIDEKICK,
	KEY_SETTING_RIGHT_SIDEKICK,
};

typedef JE_byte DosKeySettings[8];  // fka KeySettingType

typedef SDL_Scancode KeySettings[8];

typedef JE_byte MouseSettings[3];

typedef JE_byte JE_PItemsType[12]; /* [1..12] */

typedef JE_byte JE_EditorItemAvailType[100]; /* [1..100] */

typedef struct
{
	JE_word       encode;
	JE_word       level;
	JE_PItemsType items;
	JE_longint    score;
	JE_longint    score2;
	char          levelName[11]; /* string [9]; */ /* SYN: Added one more byte to match lastLevelName below */
	JE_char       name[15]; /* [1..14] */ /* SYN: Added extra byte for null */
	JE_byte       cubes;
	JE_byte       power[2]; /* [1..2] */
	JE_byte       episode;
	JE_PItemsType lastItems;
	JE_byte       difficulty;
	JE_byte       secretHint;
	JE_byte       input1;
	JE_byte       input2;
	JE_boolean    gameHasRepeated; /*See if you went from one episode to another*/
	JE_byte       initialDifficulty;

	/* High Scores - Each episode has both sets of 1&2 player selections - with 3 in each */
	JE_longint    highScore1;
	JE_longint    highScore2;  // unused
	char          highScoreName[30]; /* string [29] */
	JE_byte       highScoreDiff;
} JE_SaveFileType;

typedef JE_SaveFileType JE_SaveFilesType[SAVE_FILES_NUM]; /* [1..savefilesnum] */
typedef JE_byte JE_SaveGameTemp[SAVE_FILES_SIZE + 4 + 100]; /* [1..sizeof(savefilestype) + 4 + 100] */

typedef struct
{
	// Tyrian 2000 uses a different high scores struct and appends it to TYRIAN.SAV
	JE_longint    score;
	char          playerName[30];
	JE_byte       difficulty;
} T2KHighScoreType;

// First 10 are timed battle, next 10 are episodes
extern T2KHighScoreType t2kHighScores[20][3];

extern const JE_byte cryptKey[10];
extern const DosKeySettings defaultDosKeySettings;  // fka defaultKeySettings
extern const KeySettings defaultKeySettings;
extern const MouseSettings defaultMouseSettings;
extern char defaultHighScoreNames[39][23];
extern char defaultTeamNames[10][25];
extern const JE_EditorItemAvailType initialItemAvail;

enum
{
	SHOT_FRONT,
	SHOT_REAR,
	SHOT_LEFT_SIDEKICK,
	SHOT_RIGHT_SIDEKICK,
	SHOT_MISC,
	SHOT_P2_CHARGE,
	SHOT_P1_SUPERBOMB,
	SHOT_P2_SUPERBOMB,
	SHOT_SPECIAL,
	SHOT_NORTSPARKS,
	SHOT_SPECIAL2
};

extern DosKeySettings dosKeySettings;  // fka keySettings
extern KeySettings keySettings;
extern MouseSettings mouseSettings;
extern JE_boolean trentWin;
extern JE_byte inputDevice[2];
extern JE_byte gammaCorrection;
extern JE_boolean youAreCheating, smoothScroll;
extern JE_byte versionNum;
extern JE_byte fastPlay;
extern JE_byte gameSpeed;
extern JE_byte processorType;
extern JE_SaveFilesType saveFiles;
extern JE_SaveGameTemp saveTemp;
extern JE_word editorLevel;

extern Config opentyrian_config;

void JE_initProcessorType(void);
const char *get_user_directory(void);
void JE_loadConfiguration(void);
void JE_saveConfiguration(void);

void JE_saveGame(JE_byte slot, const char *name);

void JE_encryptSaveTemp(void);
void JE_decryptSaveTemp(void);

#endif /* CONFIG_H */
