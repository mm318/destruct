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
#include "sprite.h"

#include "file.h"
#include "opentyr.h"
#include "video.h"

#include <assert.h>
#include <ctype.h>
#include <stdlib.h>

Sprite_array sprite_table[SPRITE_TABLES_MAX];

Sprite2_array destructSpriteSheet;

Sprite2_array spriteSheet8;
Sprite2_array spriteSheet9;
Sprite2_array spriteSheet10;
Sprite2_array spriteSheet11;
Sprite2_array spriteSheet12;
Sprite2_array spriteSheetT2000;


void free_sprites(unsigned int table)
{
    for (unsigned int i = 0; i < sprite_table[table].count; ++i)
    {
        Sprite * const cur_sprite = sprite(table, i);

        cur_sprite->width  = 0;
        cur_sprite->height = 0;
        cur_sprite->size   = 0;

        free(cur_sprite->data);
        cur_sprite->data = NULL;
    }

    sprite_table[table].count = 0;
}

void load_sprites(unsigned int table, FILE *f)
{
    free_sprites(table);

    Uint16 temp;
    fread_u16_die(&temp, 1, f);

    sprite_table[table].count = temp;

    assert(sprite_table[table].count <= SPRITES_PER_TABLE_MAX);

    for (unsigned int i = 0; i < sprite_table[table].count; ++i)
    {
        Sprite * const cur_sprite = sprite(table, i);

        bool populated;
        fread_bool_die(&populated, f);
        if (!populated) // sprite is empty
            continue;

        fread_u16_die(&cur_sprite->width,  1, f);
        fread_u16_die(&cur_sprite->height, 1, f);
        fread_u16_die(&cur_sprite->size,   1, f);

        cur_sprite->data = malloc(cur_sprite->size);

        fread_u8_die(cur_sprite->data, cur_sprite->size, f);
    }
}

// does not clip on left or right edges of surface
// unsafe because it doesn't check that value won't overflow into hue
// we can replace it when we know that we don't rely on that 'feature'
void blit_sprite_hv_unsafe(SDL_Surface *surface, int x, int y, unsigned int table, unsigned int index, Uint8 hue, Sint8 value)
{
	if (index >= sprite_table[table].count || !sprite_exists(table, index))
	{
		assert(false);
		return;
	}
	
	hue <<= 4;
	
	const Sprite * const cur_sprite = sprite(table, index);
	
	const Uint8 *data = cur_sprite->data;
	const Uint8 * const data_ul = data + cur_sprite->size;
	
	const unsigned int width = cur_sprite->width;
	unsigned int x_offset = 0;
	
	assert(surface->format->BitsPerPixel == 8);
	Uint8 *             pixels =    (Uint8 *)surface->pixels + (y * surface->pitch) + x;
	const Uint8 * const pixels_ll = (Uint8 *)surface->pixels,  // lower limit
	            * const pixels_ul = (Uint8 *)surface->pixels + (surface->h * surface->pitch);  // upper limit
	
	for (; data < data_ul; ++data)
	{
		switch (*data)
		{
		case 255:  // transparent pixels
			data++;  // next byte tells how many
			pixels += *data;
			x_offset += *data;
			break;
			
		case 254:  // next pixel row
			pixels += width - x_offset;
			x_offset = width;
			break;
			
		case 253:  // 1 transparent pixel
			pixels++;
			x_offset++;
			break;
			
		default:  // set a pixel
			if (pixels >= pixels_ul)
				return;
			if (pixels >= pixels_ll)
				*pixels = hue | ((*data & 0x0f) + value);
			
			pixels++;
			x_offset++;
			break;
		}
		if (x_offset >= width)
		{
			pixels += surface->pitch - x_offset;
			x_offset = 0;
		}
	}
}

// does not clip on left or right edges of surface
void blit_sprite_hv_blend(SDL_Surface *surface, int x, int y, unsigned int table, unsigned int index, Uint8 hue, Sint8 value)
{
	if (index >= sprite_table[table].count || !sprite_exists(table, index))
	{
		assert(false);
		return;
	}
	
	hue <<= 4;
	
	const Sprite * const cur_sprite = sprite(table, index);
	
	const Uint8 *data = cur_sprite->data;
	const Uint8 * const data_ul = data + cur_sprite->size;
	
	const unsigned int width = cur_sprite->width;
	unsigned int x_offset = 0;
	
	assert(surface->format->BitsPerPixel == 8);
	Uint8 *             pixels =    (Uint8 *)surface->pixels + (y * surface->pitch) + x;
	const Uint8 * const pixels_ll = (Uint8 *)surface->pixels,  // lower limit
	            * const pixels_ul = (Uint8 *)surface->pixels + (surface->h * surface->pitch);  // upper limit
	
	for (; data < data_ul; ++data)
	{
		switch (*data)
		{
		case 255:  // transparent pixels
			data++;  // next byte tells how many
			pixels += *data;
			x_offset += *data;
			break;
			
		case 254:  // next pixel row
			pixels += width - x_offset;
			x_offset = width;
			break;
			
		case 253:  // 1 transparent pixel
			pixels++;
			x_offset++;
			break;
			
		default:  // set a pixel
			if (pixels >= pixels_ul)
				return;
			if (pixels >= pixels_ll)
			{
				Uint8 temp_value = (*data & 0x0f) + value;
				if (temp_value > 0xf)
					temp_value = (temp_value >= 0x1f) ? 0x0 : 0xf;
				
				*pixels = hue | (((*pixels & 0x0f) + temp_value) / 2);
			}
			
			pixels++;
			x_offset++;
			break;
		}
		if (x_offset >= width)
		{
			pixels += surface->pitch - x_offset;
			x_offset = 0;
		}
	}
}

// does not clip on left or right edges of surface
void blit_sprite_dark(SDL_Surface *surface, int x, int y, unsigned int table, unsigned int index, bool black)
{
	if (index >= sprite_table[table].count || !sprite_exists(table, index))
	{
		assert(false);
		return;
	}
	
	const Sprite * const cur_sprite = sprite(table, index);
	
	const Uint8 *data = cur_sprite->data;
	const Uint8 * const data_ul = data + cur_sprite->size;
	
	const unsigned int width = cur_sprite->width;
	unsigned int x_offset = 0;
	
	assert(surface->format->BitsPerPixel == 8);
	Uint8 *             pixels =    (Uint8 *)surface->pixels + (y * surface->pitch) + x;
	const Uint8 * const pixels_ll = (Uint8 *)surface->pixels,  // lower limit
	            * const pixels_ul = (Uint8 *)surface->pixels + (surface->h * surface->pitch);  // upper limit
	
	for (; data < data_ul; ++data)
	{
		switch (*data)
		{
		case 255:  // transparent pixels
			data++;  // next byte tells how many
			pixels += *data;
			x_offset += *data;
			break;
			
		case 254:  // next pixel row
			pixels += width - x_offset;
			x_offset = width;
			break;
			
		case 253:  // 1 transparent pixel
			pixels++;
			x_offset++;
			break;
			
		default:  // set a pixel
			if (pixels >= pixels_ul)
				return;
			if (pixels >= pixels_ll)
				*pixels = black ? 0x00 : ((*pixels & 0xf0) | ((*pixels & 0x0f) / 2));
			
			pixels++;
			x_offset++;
			break;
		}
		if (x_offset >= width)
		{
			pixels += surface->pitch - x_offset;
			x_offset = 0;
		}
	}
}

void JE_loadCompShapes(const char * sprites_buffer, const size_t sprites_buffer_size, Sprite2_array * sprite2s)
{
	free_sprite2s(sprite2s);
	
	FILE *f = fmemopen(sprites_buffer, sprites_buffer_size, "rb");

	sprite2s->size = ftell_eof(f);
	
	JE_loadCompShapesB(sprite2s, f);

	fclose(f);
}

void JE_loadCompShapesB(Sprite2_array *sprite2s, FILE *f)
{
	assert(sprite2s->data == NULL);

	sprite2s->data = malloc(sprite2s->size);
	fread_u8_die(sprite2s->data, sprite2s->size, f);
}

void free_sprite2s(Sprite2_array *sprite2s)
{
	free(sprite2s->data);
	sprite2s->data = NULL;

	sprite2s->size = 0;
}

// does not clip on left or right edges of surface
void blit_sprite2(SDL_Surface *surface, int x, int y, Sprite2_array sprite2s, unsigned int index)
{
	assert(surface->format->BitsPerPixel == 8);
	Uint8 *             pixels =    (Uint8 *)surface->pixels + (y * surface->pitch) + x;
	const Uint8 * const pixels_ll = (Uint8 *)surface->pixels,  // lower limit
	            * const pixels_ul = (Uint8 *)surface->pixels + (surface->h * surface->pitch);  // upper limit
	
	const Uint8 *data = sprite2s.data + SDL_SwapLE16(((Uint16 *)sprite2s.data)[index - 1]);
	
	for (; *data != 0x0f; ++data)
	{
		pixels += *data & 0x0f;                   // second nibble: transparent pixel count
		unsigned int count = (*data & 0xf0) >> 4; // first nibble: opaque pixel count
		
		if (count == 0) // move to next pixel row
		{
			pixels += VGAScreen->pitch - 12;
		}
		else
		{
			while (count--)
			{
				++data;
				
				if (pixels >= pixels_ul)
					return;
				if (pixels >= pixels_ll)
					*pixels = *data;
				
				++pixels;
			}
		}
	}
}

void JE_loadMainShapeTables(const char *shp_buffer, const size_t shp_buffer_size)
{
    enum { SHP_NUM = 13 };

    FILE *f = fmemopen(shp_buffer, shp_buffer_size, "rb");

    JE_word shpNumb;
    JE_longint shpPos[SHP_NUM + 1]; // +1 for storing file length

    fread_u16_die(&shpNumb, 1, f);
    assert(shpNumb + 1u == COUNTOF(shpPos));

    fread_s32_die(shpPos, shpNumb, f);

    fseek(f, 0, SEEK_END);
    for (unsigned int i = shpNumb; i < COUNTOF(shpPos); ++i)
        shpPos[i] = ftell(f);

    int i;
    // fonts, interface, option sprites
    for (i = 0; i < 7; i++)
    {
        fseek(f, shpPos[i], SEEK_SET);
        load_sprites(i, f);
    }

    // player shot sprites
    spriteSheet8.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheet8, f);
    i++;

    // player ship sprites
    spriteSheet9.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheet9 , f);
    i++;

    // power-up sprites
    spriteSheet10.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheet10, f);
    i++;

    // coins, datacubes, etc sprites
    spriteSheet11.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheet11, f);
    i++;

    // more player shot sprites
    spriteSheet12.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheet12, f);
    i++;

    // tyrian 2000 ship sprites
    spriteSheetT2000.size = shpPos[i + 1] - shpPos[i];
    JE_loadCompShapesB(&spriteSheetT2000, f);

    fclose(f);
}

void free_main_shape_tables(void)
{
    for (uint i = 0; i < COUNTOF(sprite_table); ++i)
        free_sprites(i);

    free_sprite2s(&spriteSheet8);
    free_sprite2s(&spriteSheet9);
    free_sprite2s(&spriteSheet10);
    free_sprite2s(&spriteSheet11);
    free_sprite2s(&spriteSheet12);
}
