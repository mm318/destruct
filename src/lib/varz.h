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
#ifndef VARZ_H
#define VARZ_H

#include "opentyr.h"

enum
{
	SA_NONE = 0,
	SA_NORTSHIPZ = 7,
	SA_LASTSHIP = 9,
	
	// only used for code entry
	SA_DESTRUCT = 10,
	SA_ENGAGE = 11,
	
	// only used in pItems[P_SUPERARCADE]
	SA_SUPERTYRIAN = 254,
	SA_ARCADE = 255
};

extern JE_byte soundQueue[8];

void JE_tyrianHalt(JE_byte code); /* This ends the game */

#endif /* VARZ_H */
