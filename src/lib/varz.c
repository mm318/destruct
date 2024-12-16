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
#include "varz.h"

#include "config.h"
#include "joystick.h"
#include "lds_play.h"
#include "loudness.h"
#include "mtrand.h"
#include "network.h"
#include "nortsong.h"
#include "opentyr.h"
#include "sprite.h"
#include "vga256d.h"
#include "video.h"


/* Sound Effects Queue */
JE_byte soundQueue[8]; /* [0..7] */

void JE_tyrianHalt(JE_byte code)
{
	deinit_audio();
	deinit_video();
	deinit_joysticks();

	/* TODO: NETWORK */

	free_main_shape_tables();

	free_sprite2s(&shopSpriteSheet);
	free_sprite2s(&explosionSpriteSheet);
	free_sprite2s(&destructSpriteSheet);

	for (int i = 0; i < SOUND_COUNT; i++)
	{
		free(soundSamples[i]);
	}

	if (code != 9)
	{
		/*
		TODO?
		JE_drawANSI("exitmsg.bin");
		JE_gotoXY(1,22);
		*/
		JE_saveConfiguration();
	}

	/* endkeyboard; */

	if (code == 9)
	{
		/* OutputString('call=file0002.EXE' + #0'); TODO? */
	}

	if (code == 5)
	{
		code = 0;
	}

	if (trentWin)
	{
		printf("\n"
		       "\n"
		       "\n"
		       "\n"
		       "Sleep well, Trent, you deserve the rest.\n"
		       "You now have permission to borrow my ship on your next mission.\n"
		       "\n"
		       "Also, you might want to try out the YESXMAS parameter in Dos.\n"
		       "  Type: File0001 YESXMAS\n"
		       "\n"
		       " Press a Key to Quit\n"
		       "\n");
	}

	SDL_Quit();
	exit(code);
}
