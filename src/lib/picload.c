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
#include "picload.h"

#include "file.h"
#include "opentyr.h"
#include "palette.h"
#include "pcxmast.h"
#include "video.h"

#include <string.h>
#include <stdlib.h>

void JE_loadPic(const char * pic_buffer,
				const size_t pic_buffer_size,
				SDL_Surface *screen,
				JE_byte PCXnumber,
				JE_boolean storepal)
{
	PCXnumber--;

	FILE *f = fmemopen(pic_buffer, pic_buffer_size, "rb");

	static bool first = true;
	if (first)
	{
		first = false;

		Uint16 temp;
		fread_u16_die(&temp, 1, f);

		fread_s32_die(pcxpos, PCX_NUM, f);
		pcxpos[PCX_NUM] = ftell_eof(f);
	}

	unsigned int size = pcxpos[PCXnumber + 1] - pcxpos[PCXnumber];
	Uint8 *buffer = malloc(size);

	fseek(f, pcxpos[PCXnumber], SEEK_SET);
	fread_u8_die(buffer, size, f);
	fclose(f);

	Uint8 *p = buffer;
	Uint8 *s; /* screen pointer, 8-bit specific */

	s = (Uint8 *)screen->pixels;

	for (int i = 0; i < vga_width * vga_height; )
	{
		if ((*p & 0xc0) == 0xc0)
		{
			i += (*p & 0x3f);
			memset(s, *(p + 1), (*p & 0x3f));
			s += (*p & 0x3f); p += 2;
		}
		else
		{
			i++;
			*s = *p;
			s++; p++;
		}
		if (i && (i % vga_width == 0))
		{
			s += screen->pitch - vga_width;
		}
	}

	free(buffer);

	memcpy(colors, palettes[pcxpal[PCXnumber]], sizeof(colors));

	if (storepal)
		set_palette(colors, 0, 255);
}
