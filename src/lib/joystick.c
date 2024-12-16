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
#include "joystick.h"

#include "config.h"
#include "config_file.h"
#include "file.h"
#include "keyboard.h"
#include "nortsong.h"
#include "opentyr.h"
#include "params.h"
#include "varz.h"
#include "video.h"

#include <assert.h>
#include <ctype.h>
#include <string.h>

int joystick_axis_threshold(int j, int value);
int check_assigned(SDL_Joystick *joystick_handle, const Joystick_assignment assignment[2]);

const char *assignment_to_code(const Joystick_assignment *assignment);
void code_to_assignment(Joystick_assignment *assignment, const char *buffer);

int joystick_repeat_delay = 300; // milliseconds, repeat delay for buttons
bool joydown = false;            // any joystick buttons down, updated by poll_joysticks()
bool ignore_joystick = false;

int joysticks = 0;
Joystick *joystick = NULL;

static const int joystick_analog_max = 32767;

// eliminates axis movement below the threshold

// converts joystick axis to sane Tyrian-usable value (based on sensitivity)

// converts analog joystick axes to an angle
// returns false if axes are centered (there is no angle)

/* gives back value 0..joystick_analog_max indicating that one of the assigned
 * buttons has been pressed or that one of the assigned axes/hats has been moved
 * in the assigned direction
 */

// updates joystick state

// updates all joystick states

// sends SDL KEYDOWN and KEYUP events for a key

// helps us be lazy by pretending joysticks are a keyboard (useful for menus)

// initializes SDL joystick system and loads assignments for joysticks found
void init_joysticks(void)
{
	if (ignore_joystick)
		return;
	
	if (SDL_InitSubSystem(SDL_INIT_JOYSTICK))
	{
		fprintf(stderr, "warning: failed to initialize joystick system: %s\n", SDL_GetError());
		ignore_joystick = true;
		return;
	}
	
	SDL_JoystickEventState(SDL_IGNORE);
	
	joysticks = SDL_NumJoysticks();
	joystick = malloc(joysticks * sizeof(*joystick));
	
	for (int j = 0; j < joysticks; j++)
	{
		memset(&joystick[j], 0, sizeof(*joystick));
		
		joystick[j].handle = SDL_JoystickOpen(j);
		if (joystick[j].handle != NULL)
		{
			printf("joystick detected: %s ", SDL_JoystickName(joystick[j].handle));
			printf("(%d axes, %d buttons, %d hats)\n", 
			       SDL_JoystickNumAxes(joystick[j].handle),
			       SDL_JoystickNumButtons(joystick[j].handle),
			       SDL_JoystickNumHats(joystick[j].handle));
			
			if (!load_joystick_assignments(&opentyrian_config, j))
				reset_joystick_assignments(j);
		}
	}
	
	if (joysticks == 0)
		printf("no joysticks detected\n");
}

// deinitializes SDL joystick system and saves joystick assignments
void deinit_joysticks(void)
{
	if (ignore_joystick)
		return;
	
	for (int j = 0; j < joysticks; j++)
	{
		if (joystick[j].handle != NULL)
		{
			save_joystick_assignments(&opentyrian_config, j);
			SDL_JoystickClose(joystick[j].handle);
		}
	}
	
	free(joystick);
	
	SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
}

void reset_joystick_assignments(int j)
{
	assert(j < joysticks);
	
	// defaults: first 2 axes, first hat, first 6 buttons
	for (uint a = 0; a < COUNTOF(joystick[j].assignment); a++)
	{
		// clear assignments
		for (uint i = 0; i < COUNTOF(joystick[j].assignment[a]); i++)
			joystick[j].assignment[a][i].type = NONE;
		
		if (a < 4)
		{
			if (SDL_JoystickNumAxes(joystick[j].handle) >= 2)
			{
				joystick[j].assignment[a][0].type = AXIS;
				joystick[j].assignment[a][0].num = (a + 1) % 2;
				joystick[j].assignment[a][0].negative_axis = (a == 0 || a == 3);
			}
			
			if (SDL_JoystickNumHats(joystick[j].handle) >= 1)
			{
				joystick[j].assignment[a][1].type = HAT;
				joystick[j].assignment[a][1].num = 0;
				joystick[j].assignment[a][1].x_axis = (a == 1 || a == 3);
				joystick[j].assignment[a][1].negative_axis = (a == 0 || a == 3);
			}
		}
		else
		{
			if (a - 4 < (unsigned)SDL_JoystickNumButtons(joystick[j].handle))
			{
				joystick[j].assignment[a][0].type = BUTTON;
				joystick[j].assignment[a][0].num = a - 4;
			}
		}
	}
	
	joystick[j].analog = false;
	joystick[j].sensitivity = 5;
	joystick[j].threshold = 5;
}

static const char* const assignment_names[] =
{
	"up",
	"right",
	"down",
	"left",
	"fire",
	"change fire",
	"left sidekick",
	"right sidekick",
	"menu",
	"pause",
};

bool load_joystick_assignments(Config *config, int j)
{
	ConfigSection *section = config_find_section(config, "joystick", SDL_JoystickName(joystick[j].handle));
	if (section == NULL)
		return false;
	
	if (!config_get_bool_option(section, "analog", &joystick[j].analog))
		joystick[j].analog = false;
	
	joystick[j].sensitivity = config_get_or_set_int_option(section, "sensitivity", 5);

	joystick[j].threshold = config_get_or_set_int_option(section, "threshold", 5);
	
	for (size_t a = 0; a < COUNTOF(assignment_names); ++a)
	{
		for (unsigned int i = 0; i < COUNTOF(joystick[j].assignment[a]); ++i)
			joystick[j].assignment[a][i].type = NONE;
		
		ConfigOption *option = config_get_option(section, assignment_names[a]);
		if (option == NULL)
			continue;
		
		foreach_option_i_value(i, value, option)
		{
			if (i >= COUNTOF(joystick[j].assignment[a]))
				break;
			
			code_to_assignment(&joystick[j].assignment[a][i], value);
		}
	}
	
	return true;
}

bool save_joystick_assignments(Config *config, int j)
{
	ConfigSection *section = config_find_or_add_section(config, "joystick", SDL_JoystickName(joystick[j].handle));
	if (section == NULL)
		exit(EXIT_FAILURE);  // out of memory
	
	config_set_bool_option(section, "analog", joystick[j].analog, NO_YES);
	
	config_set_int_option(section, "sensitivity", joystick[j].sensitivity);
	
	config_set_int_option(section, "threshold", joystick[j].threshold);
	
	for (size_t a = 0; a < COUNTOF(assignment_names); ++a)
	{
		ConfigOption *option = config_set_option(section, assignment_names[a], NULL);
		if (option == NULL)
			exit(EXIT_FAILURE);  // out of memory
		
		option = config_set_value(option, NULL);
		if (option == NULL)
			exit(EXIT_FAILURE);  // out of memory

		for (size_t i = 0; i < COUNTOF(joystick[j].assignment[a]); ++i)
		{
			if (joystick[j].assignment[a][i].type == NONE)
				continue;
			
			option = config_add_value(option, assignment_to_code(&joystick[j].assignment[a][i]));
			if (option == NULL)
				exit(EXIT_FAILURE);  // out of memory
		}
	}
	
	return true;
}

// fills buffer with comma separated list of assigned joystick functions

// reverse of assignment_to_code()
void code_to_assignment(Joystick_assignment *assignment, const char *buffer)
{
	memset(assignment, 0, sizeof(*assignment));
	
	char axis = 0, direction = 0;
	
	if (sscanf(buffer, " AX %d%c", &assignment->num, &direction) == 2)
		assignment->type = AXIS;
	else if (sscanf(buffer, " BTN %d", &assignment->num) == 1)
		assignment->type = BUTTON;
	else if (sscanf(buffer, " H %d%c%c", &assignment->num, &axis, &direction) == 3)
		assignment->type = HAT;
	
	if (assignment->num == 0)
		assignment->type = NONE;
	else
		--assignment->num;
	
	assignment->x_axis = (toupper(axis) == 'X');
	assignment->negative_axis = (toupper(direction) == '-');
}

/* gives the short (6 or less characters) identifier for a joystick assignment
 * 
 * two of these per direction/action is all that can fit on the joystick config screen,
 * assuming two digits for the axis/button/hat number
 */
const char *assignment_to_code(const Joystick_assignment *assignment)
{
	static char name[7];
	
	switch (assignment->type)
	{
	case NONE:
		strcpy(name, "");
		break;
		
	case AXIS:
		snprintf(name, sizeof(name), "AX %d%c",
		         assignment->num + 1,
		         assignment->negative_axis ? '-' : '+');
		break;
		
	case BUTTON:
		snprintf(name, sizeof(name), "BTN %d",
		         assignment->num + 1);
		break;
		
	case HAT:
		snprintf(name, sizeof(name), "H %d%c%c",
		         assignment->num + 1,
		         assignment->x_axis ? 'X' : 'Y',
		         assignment->negative_axis ? '-' : '+');
		break;
	}
	
	return name;
}

// captures joystick input for configuring assignments
// returns false if non-joystick input was detected
// TODO: input from joystick other than the one being configured probably should not be ignored

// compares relevant parts of joystick assignments for equality
