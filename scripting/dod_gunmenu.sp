/**
* DoD:S GunMenu by Root
*
* Description:
*   Provides a menu to choose weapons which are automatically given at respawn, automatically gives ammo, nades etc.
*
* Version 1.0
* Changelog & more info at http://goo.gl/4nKhJ
*/

#pragma semicolon 1 // We like semicolon

// ====[ INCLUDES ]====================================================
#include <sourcemod>
#include <sdktools>

// ====[ CONSTANTS ]===================================================
#define PLUGIN_NAME        "DoD:S GunMenu"
#define PLUGIN_VERSION     "1.0"

#define DOD_MAXPLAYERS       33
#define PRIMARY_WEAPON_COUNT 12
#define DEFAULT_WEAPON_COUNT 4
#define RANDOM_WEAPON        0x12
#define TEAM_SPECTATOR       1
#define SHOW_MENU            -1

enum Slots
{
	Slot_Primary = 0,
	Slot_Secondary,
	Slot_Melee,
	Slot_Grenade
};

// ====[ VARIABLES ]===================================================
new Handle:gunmenu_enable = INVALID_HANDLE;

new g_Ammo_Offset,
	g_configLevel,
	g_PrimaryGunCount,
	g_SecondaryGunCount,
	g_MeleeCount,
	g_GrenadesCount;

new String:g_PrimaryGuns  [PRIMARY_WEAPON_COUNT][32],
	String:g_SecondaryGuns[DEFAULT_WEAPON_COUNT][32],
	String:g_MeleeWeapons [DEFAULT_WEAPON_COUNT][32],
	String:g_Grenades     [DEFAULT_WEAPON_COUNT][32];

new bool:g_MenuOpen[DOD_MAXPLAYERS] = {false, ...};

new g_PlayerPrimary  [DOD_MAXPLAYERS],
	g_PlayerSecondary[DOD_MAXPLAYERS],
	g_PlayerMelee    [DOD_MAXPLAYERS],
	g_PlayerGrenades [DOD_MAXPLAYERS];

new Handle:g_PrimaryMenu   = INVALID_HANDLE,
	Handle:g_SecondaryMenu = INVALID_HANDLE,
	Handle:g_MeleeMenu     = INVALID_HANDLE,
	Handle:g_GrenadesMenu  = INVALID_HANDLE;

// ====[ PLUGIN ]======================================================
public Plugin:myinfo =
{
	name			= PLUGIN_NAME,
	author			= "Root",
	description		= "Lets players select from a menu of allowed weapons",
	version			= PLUGIN_VERSION,
	url				= "http://dodsplugins.com/"
};


/**
 * ---------------------------------------------------------------------
 *	   ____           ______                  __  _
 *	  / __ \____     / ____/__  ______  _____/ /_(_)____  ____  _____
 *	 / / / / __ \   / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *	/ /_/ / / / /  / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *	\____/_/ /_/  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * ---------------------------------------------------------------------
*/

/* OnPluginStart()
 *
 * When the plugin starts up.
 * --------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create ConVars
	CreateConVar("dod_gunmenu_version",  PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED);
	gunmenu_enable = CreateConVar("sm_gunmenu_enable",    "1", "Enable or disable plugin", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	// Create/register console commands
	RegConsoleCmd("guns",    Command_GunMenu);
	RegConsoleCmd("weapons", Command_GunMenu);
	RegConsoleCmd("gunmenu", Command_GunMenu);

	// Hook convar changes and events
	HookConVarChange(gunmenu_enable, OnConVarChange);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team",  Event_PlayerTeam);

	// Cache Send property offsets
	if ((g_Ammo_Offset = FindSendPropOffs("CDODPlayer", "m_iAmmo")) == -1)
	{
		SetFailState("Fatal Error: Unable to find prop offset \"CDODPlayer::m_iAmmo\"!");
	}
}

/* OnConVarChange()
 *
 * Called when a convar's value is changed.
 * --------------------------------------------------------------------- */
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	switch (StringToInt(newValue))
	{
		// If plugin is disabled - unhook spawn event, because at this event plugin re-equip each player
		case 0: UnhookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
		case 1: HookEvent  ("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	}
}

/* OnMapStart()
 *
 * When the map starts.
 * --------------------------------------------------------------------- */
public OnMapStart()
{
	// Checking GunMenu config
	CheckConfig("configs/weapons.ini");
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * --------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	// If plugin is disabled - skip event
	if (GetConVarBool(gunmenu_enable))
	{
		// To prevent some issues - check if client is in game
		if (IsClientInGame(client))
		{
			// Disable menu, because we will show it when client spawned
			g_MenuOpen[client] = false;

			// Show menu to humans
			if (!IsFakeClient(client))
			{
				g_PlayerPrimary[client]   = SHOW_MENU;
				g_PlayerSecondary[client] = SHOW_MENU;
				g_PlayerMelee[client]     = SHOW_MENU;
				g_PlayerGrenades[client]  = SHOW_MENU;
			}
			// Give random weapons to a bots
			else g_PlayerPrimary[client]  = RANDOM_WEAPON;
		}
	}
}


/**
 * ---------------------------------------------------------------------
 *		______                  __
 *	   / ____/_   _____  ____  / /______
 *	  / __/  | | / / _ \/ __ \/ __/ ___/
 *	 / /___  | |/ /  __/ / / / /_(__  )
 *	/_____/  |___/\___/_/ /_/\__/____/
 *
 * ---------------------------------------------------------------------
*/

/* Event_player_spawn()
 *
 * Called when a player spawns.
 * --------------------------------------------------------------------- */
public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarBool(gunmenu_enable))
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(client))
		{
			// Show menu if client not choose weapons yet
			if (g_PlayerPrimary[client] == SHOW_MENU && g_PlayerSecondary[client] == SHOW_MENU && g_PlayerMelee[client] == SHOW_MENU && g_PlayerGrenades[client] == SHOW_MENU)
			{
				// Check if menu is valid (i.e have any weapon(s) in a config)
				if (g_PrimaryMenu != INVALID_HANDLE)
					DisplayMenu(g_PrimaryMenu, client, MENU_TIME_FOREVER);
				else if (g_SecondaryMenu != INVALID_HANDLE)
					DisplayMenu(g_SecondaryMenu, client, MENU_TIME_FOREVER);
				else if (g_MeleeMenu != INVALID_HANDLE)
					DisplayMenu(g_MeleeMenu, client, MENU_TIME_FOREVER);
				else if (g_GrenadesMenu != INVALID_HANDLE)
					DisplayMenu(g_GrenadesMenu, client, MENU_TIME_FOREVER);
			}
			else /* Otherwise give chosen guns to a player */
			{
				GivePrimary(client);
				GiveSecondary(client);
				GiveMelee(client);
				GiveGrenades(client);
			}
		}
	}
}

/* Event_player_team()
 *
 * Called when a player has switched team.
 * --------------------------------------------------------------------- */
public Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Dont check teamchange if plugin is disabled
	if (GetConVarBool(gunmenu_enable))
	{
		// Close any gun menus if player spectating
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (g_MenuOpen[client] && IsClientObserver(client))
		{
			CancelClientMenu(client);
			g_MenuOpen[client] = false;
		}
	}
}


/**
 * ---------------------------------------------------------------------
 *		__  ___
 *	   /  |/  /___  ___  __  ________
 *	  / /|_/ / _ \/ __ \/ / / // ___/
 *	 / /  / /  __/ / / / /_/ /(__  )
 *	/_/  /_/\___/_/ /_/\__,_/_____/
 *
 * ---------------------------------------------------------------------
*/

/* Command_GunMenu()
 *
 * Show gun menu to a player.
 * --------------------------------------------------------------------- */
public Action:Command_GunMenu(client, args)
{
	// Plugin disabled - GunMenu disabled
	if (GetConVarBool(gunmenu_enable))
	{
		// Allow only valid players to use gun menu command
		if (IsValidClient(client))
		{
			/* Menu with primary guns */
			if (g_PrimaryMenu != INVALID_HANDLE)
				DisplayMenu(g_PrimaryMenu, client, MENU_TIME_FOREVER);
			/* with secondary */
			else if (g_SecondaryMenu != INVALID_HANDLE)
				DisplayMenu(g_SecondaryMenu, client, MENU_TIME_FOREVER);
			/* with melee */
			else if (g_MeleeMenu != INVALID_HANDLE)
				DisplayMenu(g_MeleeMenu, client, MENU_TIME_FOREVER);
			/* & grenades */
			else if (g_GrenadesMenu != INVALID_HANDLE)
				DisplayMenu(g_GrenadesMenu, client, MENU_TIME_FOREVER);
		}
	}
	return Plugin_Continue;
}

/* InitializeMenus()
 *
 * Create menus if config is valid.
 * --------------------------------------------------------------------- */
InitializeMenus()
{
	// To prepare menus we should first reset amount of weapons
	g_PrimaryGunCount = 0;
	CheckCloseHandle(g_PrimaryMenu);
	g_PrimaryMenu = CreateMenu(MenuHandler_ChoosePrimary, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	SetMenuTitle(g_PrimaryMenu, "Choose a Primary Weapon:");

	// Add button to use random weapons
	AddMenuItem(g_PrimaryMenu, "12", "Random");

	g_SecondaryGunCount = 0;
	CheckCloseHandle(g_SecondaryMenu); /* Check if menu was not called before */
	g_SecondaryMenu = CreateMenu(MenuHandler_ChooseSecondary, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	SetMenuTitle(g_SecondaryMenu, "Choose a Secondary Weapon:");
	AddMenuItem(g_SecondaryMenu, "12", "Random");

	g_MeleeCount = 0;
	CheckCloseHandle(g_MeleeMenu); /* Create specified menu for weapon type */
	g_MeleeMenu = CreateMenu(MenuHandler_ChooseMelee, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	SetMenuTitle(g_MeleeMenu, "Choose a Melee Weapon:");

	g_GrenadesCount = 0;
	CheckCloseHandle(g_GrenadesMenu);
	g_GrenadesMenu = CreateMenu(MenuHandler_ChooseGrenades, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);

	// And sets the menu title
	SetMenuTitle(g_GrenadesMenu, "Choose a Grenades:");
}

/* MenuHandler_ChoosePrimary()
 *
 * Menu to set player's primary weapon.
 * --------------------------------------------------------------------- */
public MenuHandler_ChoosePrimary(Handle:menu, MenuAction:action, param1, param2)
{
	// Display a menu
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		new client = param1;
		decl String:weapon_id[4];
		GetMenuItem(menu, param2, weapon_id, sizeof(weapon_id));
		new weapon = StringToInt(weapon_id, 16);

		g_PlayerPrimary[client] = weapon;

		// Give a weapon to a correct player
		if (IsValidClient(client))
			GivePrimary(client);

		// If client pressed something - call menu with secondary weapons immediate
		DisplayMenu(g_SecondaryMenu, client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		g_MenuOpen[param1] = false;
		if (param2 == MenuCancel_Exit) // CancelClientMenu sends MenuCancel_Interrupted reason
		{
			if (g_SecondaryMenu != INVALID_HANDLE)
				DisplayMenu(g_SecondaryMenu, param1, MENU_TIME_FOREVER);
		}
	}
}

/* MenuHandler_ChooseSecondary()
 *
 * Menu to set player's secondary weapon.
 * --------------------------------------------------------------------- */
public MenuHandler_ChooseSecondary(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select) /* Called when player pressed something in a menu */
	{
		// Getting weapon name from config file
		new client = param1;
		decl String:weapon_id[4];
		GetMenuItem(menu, param2, weapon_id, sizeof(weapon_id));
		new weapon = StringToInt(weapon_id, 16);

		g_PlayerSecondary[client] = weapon;
		if (IsValidClient(client))
			GiveSecondary(client);

		DisplayMenu(g_MeleeMenu, client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel) /* When client pressed 0 */
	{
		// Close a menu with secondary weapons
		g_MenuOpen[param1] = false;
		if (param2 == MenuCancel_Exit)
		{
			if (g_MeleeMenu != INVALID_HANDLE)
				DisplayMenu(g_MeleeMenu, param1, MENU_TIME_FOREVER);
		}
	}
}

/* MenuHandler_ChooseMelee()
 *
 * Menu to set player's melee weapon.
 * --------------------------------------------------------------------- */
public MenuHandler_ChooseMelee(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		new client = param1;
		decl String:weapon_id[4];

		// Give weapon which is covered under this title
		GetMenuItem(menu, param2, weapon_id, sizeof(weapon_id));
		new weapon = StringToInt(weapon_id, 16);

		g_PlayerMelee[client] = weapon;
		if (IsValidClient(client))
			GiveMelee(client);

		DisplayMenu(g_GrenadesMenu, client, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel)
	{
		g_MenuOpen[param1] = false;

		// Client pressed exit on a melee weapon menu - call last grenade menu
		if (param2 == MenuCancel_Exit)
		{
			// Call only if menu is valid (ie config have Grenades section)
			if (g_GrenadesMenu != INVALID_HANDLE)
				DisplayMenu(g_GrenadesMenu, param1, MENU_TIME_FOREVER);
		}
	}
}

/* MenuHandler_ChooseGrenades()
 *
 * Menu to set grenades.
 * --------------------------------------------------------------------- */
public MenuHandler_ChooseGrenades(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		new client = param1;
		decl String:weapon_id[4];
		GetMenuItem(menu, param2, weapon_id, sizeof(weapon_id));
		new weapon = StringToInt(weapon_id, 16);

		g_PlayerGrenades[client] = weapon;
		if (IsValidClient(client))
			GiveGrenades(client);
	}
	else if (action == MenuAction_Cancel)
	{
		// And now we can close menu at all
		g_MenuOpen[param1] = false;
	}
}


/**
 * ---------------------------------------------------------------------
 *	  _    __    __
 *	 | |  /  |  / /___  ____ _____  ____  ____  _____
 *	 | | / / | / // _ \/ __ `/ __ \/ __ \/ __ \/ ___/
 *	 | |/ /| |/ //  __/ /_/ / /_/ / /_/ / / / (__  )
 *	 |___/ |___/ \___/\__,_/ .___/\____/_/ /_/____/
 *                         /_/
 * ---------------------------------------------------------------------
*/

/* Give_:Slot()
 *
 * Removing old weapon and replaces to a new one.
 * --------------------------------------------------------------------- */
GivePrimary(client)
{
	new weapon = g_PlayerPrimary[client];

	// Check if player choose random
	if (weapon == RANDOM_WEAPON) weapon = GetRandomInt(0, g_PrimaryGunCount-1);
	if (weapon >= 0 && weapon <= g_PrimaryGunCount)
	{
		RemoveWeaponBySlot(client, Slot_Primary);
		GivePlayerItem(client, g_PrimaryGuns[weapon]);
		SetAmmo(client, Slot_Primary);
	}
}

GiveSecondary(client)
{
	new weapon = g_PlayerSecondary[client];
	if (weapon == RANDOM_WEAPON) weapon = GetRandomInt(0, g_SecondaryGunCount-1);

	// Number should be more or equal to zero, because if client choose a random weapon - he may not take it
	if (weapon >= 0 && weapon <= g_SecondaryGunCount)
	{
		// Remove old secondary weapon
		RemoveWeaponBySlot(client, Slot_Secondary);
		GivePlayerItem(client, g_SecondaryGuns[weapon]);
		SetAmmo(client, Slot_Secondary);
	}
}

GiveMelee(client)
{
	new weapon = g_PlayerMelee[client];
	if (weapon > 0 && weapon <= g_MeleeCount)
	{
		RemoveWeaponBySlot(client, Slot_Melee);

		// Then give exact item
		GivePlayerItem(client, g_MeleeWeapons[weapon]);
	}
}

GiveGrenades(client)
{
	new weapon = g_PlayerGrenades[client];

	// No random here - no check
	if (weapon > 0 && weapon <= g_GrenadesCount)
	{
		RemoveWeaponBySlot(client, Slot_Grenade);
		GivePlayerItem(client, g_Grenades[weapon]);

		// And add ammo for it
		SetAmmo(client, Slot_Grenade);
	}
}

/* SetAmmo()
 *
 * Adds magazines to a specified weapons.
 * --------------------------------------------------------------------- */
SetAmmo(client, Slots:slot)
{
	new weapon = GetPlayerWeaponSlot(client, _:slot);

	// Checking if weapon is valid
	if (IsValidEntity(weapon))
	{
		// I dont know how its working, but its working well
		switch (GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1) * 4)
		{
			case 4:  SetEntData(client, g_Ammo_Offset + 4,   14); /* Colt */
			case 8:  SetEntData(client, g_Ammo_Offset + 8,   16); /* P38 */
			case 12: SetEntData(client, g_Ammo_Offset + 12,  40); /* C96 */
			case 16: SetEntData(client, g_Ammo_Offset + 16,  80); /* Garand */
			case 20: SetEntData(client, g_Ammo_Offset + 20,  60); /* K98+scoped */
			case 24: SetEntData(client, g_Ammo_Offset + 24,  30); /* M1 Carbine */
			case 28: SetEntData(client, g_Ammo_Offset + 28,  50); /* Spring */
			case 32: SetEntData(client, g_Ammo_Offset + 32, 180); /* Thompson, MP40 & STG44 */
			case 36: SetEntData(client, g_Ammo_Offset + 36, 240); /* BAR */
			case 40: SetEntData(client, g_Ammo_Offset + 40, 300); /* 30cal */
			case 44: SetEntData(client, g_Ammo_Offset + 44, 250); /* MG42 */
			case 48: SetEntData(client, g_Ammo_Offset + 48,   4); /* Bazooka, Panzerschreck */
			case 52: SetEntData(client, g_Ammo_Offset + 52,   2); /* US frag gren */
			case 56: SetEntData(client, g_Ammo_Offset + 56,   2); /* Stick gren */
			case 68: SetEntData(client, g_Ammo_Offset + 68,   1); /* US Smoke */
			case 72: SetEntData(client, g_Ammo_Offset + 72,   1); /* Stick smoke */
			case 84: SetEntData(client, g_Ammo_Offset + 84,   2); /* Riflegren US */
			case 88: SetEntData(client, g_Ammo_Offset + 88,   2); /* Riflegren GER */
		}
	}
}

/* RemoveWeaponBySlot()
 *
 * Remove's player weapon by slot.
 * --------------------------------------------------------------------- */
RemoveWeaponBySlot(client, Slots:slot)
{
	// Checking slot
	new weapon = GetPlayerWeaponSlot(client, _:slot);

	// Checking if weapon is valid
	if (IsValidEntity(weapon))
	{
		// Proper weapon removing
		RemovePlayerItem(client, weapon);
		AcceptEntityInput(weapon, "Kill");
	}
}


/**
 * ---------------------------------------------------------------------
 *	   ______            _____
 *	  / ____/___  ____  / __(_)___ _
 *	 / /   / __ \/ __ \/ /_/ / __ `/
 *	/ /___/ /_/ / / / / __/ / /_/ /
 *	\____/\____/_/ /_/_/ /_/\__, /
 *                         /____/
 * ---------------------------------------------------------------------
*/

/* ParseConfigFile()
 *
 * Parses a config file.
 * --------------------------------------------------------------------- */
bool:ParseConfigFile(const String:file[])
{
	// Create parser with all sections (start & end)
	new Handle:parser = SMC_CreateParser();
	SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	SMC_SetParseEnd(parser, Config_End);

	// Checking for error
	decl String:error[128];
	new line = 0;
	new col = 0;
	new SMCError:result = SMC_ParseFile(parser, file, line, col);

	// Close handle
	CloseHandle(parser);

	// Log an error
	if (result != SMCError_Okay)
	{
		SMC_GetErrorString(result, error, sizeof(error));
		LogError("%s on line %d, col %d of %s", error, line, col, file);
	}
	return (result == SMCError_Okay);
}

/* Config_NewSection()
 *
 * Called when the parser is entering a new section or sub-section.
 * --------------------------------------------------------------------- */
public SMCResult:Config_NewSection(Handle:parser, const String:section[], bool:quotes)
{
	// Ignore first config level (GunMenu Weapons)
	g_configLevel++;

	// Checking second config level
	if (g_configLevel == 2)
	{
		// Checking if menu names is correct
		if (StrEqual("Primary Guns", section, false))
			SMC_SetReaders(parser, Config_NewSection, Config_PrimaryKeyValue, Config_EndSection);

		/* If correct - sets the three main reader functions */
		else if (StrEqual("Secondary Guns", section, false))
			SMC_SetReaders(parser, Config_NewSection, Config_SecondaryKeyValue, Config_EndSection);

		/* for specified menu */
		else if (StrEqual("Melee Weapons", section, false))
			SMC_SetReaders(parser, Config_NewSection, Config_MeleeKeyValue, Config_EndSection);
		else if (StrEqual("Grenades", section, false))
			SMC_SetReaders(parser, Config_NewSection, Config_GrenadeKeyValue, Config_EndSection);
	}
	// Anyway create pointers.
	else SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	return SMCParse_Continue;
}

/* Config_UnknownKeyValue()
 *
 * Called when the parser finds a new key/value pair.
 * --------------------------------------------------------------------- */
public SMCResult:Config_UnknownKeyValue(Handle:parser, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	// Log an error if unknown key value found in a config file
	SetFailState("\nDidn't recognize configuration: %s=%s", key, value);
	return SMCParse_Continue;
}

/* Config_PrimaryKeyValue()
 *
 * Called when the parser finds a primary key/value pair.
 * --------------------------------------------------------------------- */
public SMCResult:Config_PrimaryKeyValue(Handle:parser, const String:weapon_class[], const String:weapon_name[], bool:key_quotes, bool:value_quotes)
{
	// Weapons should not exceed real value
	if (g_PrimaryGunCount > PRIMARY_WEAPON_COUNT)
		SetFailState("\nToo many weapons declared!");

	decl String:weapon_id[4];

	// Copies one string to another string
	strcopy(g_PrimaryGuns[g_PrimaryGunCount], sizeof(g_PrimaryGuns[]), weapon_class);
	Format(weapon_id, sizeof(weapon_id), "%02.2X", g_PrimaryGunCount++);
	AddMenuItem(g_PrimaryMenu, weapon_id, weapon_name);
	return SMCParse_Continue;
}

/* Config_SecondaryKeyValue()
 *
 * Called when the parser finds a secondary key/value pair.
 * --------------------------------------------------------------------- */
public SMCResult:Config_SecondaryKeyValue(Handle:parser, const String:weapon_class[], const String:weapon_name[], bool:key_quotes, bool:value_quotes)
{
	if (g_SecondaryGunCount > DEFAULT_WEAPON_COUNT)
		SetFailState("\nToo many weapons declared!");

	decl String:weapon_id[4];
	strcopy(g_SecondaryGuns[g_SecondaryGunCount], sizeof(g_SecondaryGuns[]), weapon_class);

	// Calculate number of avalible secondary weapons
	Format(weapon_id, sizeof(weapon_id), "%02.2X", g_SecondaryGunCount++);
	AddMenuItem(g_SecondaryMenu, weapon_id, weapon_name);
	return SMCParse_Continue;
}

/* Config_MeleeKeyValue()
 *
 * Called when the parser finds a melee key/value pair.
 * --------------------------------------------------------------------- */
public SMCResult:Config_MeleeKeyValue(Handle:parser, const String:weapon_class[], const String:weapon_name[], bool:key_quotes, bool:value_quotes)
{
	if (g_MeleeCount > DEFAULT_WEAPON_COUNT)
		SetFailState("\nToo many weapons declared!");

	decl String:weapon_id[4];
	strcopy(g_MeleeWeapons[g_MeleeCount], sizeof(g_MeleeWeapons[]), weapon_class);
	Format(weapon_id, sizeof(weapon_id), "%02.2X", g_MeleeCount++);

	// Add every weapon as menu item
	AddMenuItem(g_MeleeMenu, weapon_id, weapon_name);
	return SMCParse_Continue;
}

/* Config_GrenadeKeyValue()
 *
 * Called when the parser finds a grenade's key/value pair.
 * --------------------------------------------------------------------- */
public SMCResult:Config_GrenadeKeyValue(Handle:parser, const String:weapon_class[], const String:weapon_name[], bool:key_quotes, bool:value_quotes)
{
	if (g_GrenadesCount > DEFAULT_WEAPON_COUNT)
		SetFailState("\nToo many weapons declared!");

	// If grenades aren't avalible at all, dont add greandes in a menu
	decl String:weapon_id[4];
	strcopy(g_Grenades[g_GrenadesCount], sizeof(g_Grenades[]), weapon_class);
	Format(weapon_id, sizeof(weapon_id), "%02.2X", g_GrenadesCount++);
	AddMenuItem(g_GrenadesMenu, weapon_id, weapon_name);

	// @return
	return SMCParse_Continue;
}

/* Config_EndSection()
 *
 * Called when the parser finds the end of the current section.
 * --------------------------------------------------------------------- */
public SMCResult:Config_EndSection(Handle:parser)
{
	// Config is ready - return to original level
	g_configLevel--;

	// I prefer textparse, because there is possible to add/remove weapons/sections with no errors
	SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	return SMCParse_Continue;
}

/* Config_End()
 *
 * Called when the config is ready.
 * --------------------------------------------------------------------- */
public Config_End(Handle:parser, bool:halted, bool:failed)
{
	// Failed to load config. Maybe we missed bkt/smth?
	if (failed) SetFailState("\nPlugin configuration error");
}


/**
 * ---------------------------------------------------------------------
 *		__  ____
 *	   /  |/  (_)__________
 *	  / /|_/ / // ___/ ___/
 *	 / /  / / /(__  ) /__
 *	/_/  /_/_//____/\___/
 *
 * ---------------------------------------------------------------------
*/

/* Config_End()
 *
 * Checks GunMenu config file from sourcemod/configs directory.
 * --------------------------------------------------------------------- */
CheckConfig(const String:ini_file[])
{
	// Loads config from sourcemod/configs dir
	decl String:file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), ini_file);

	// Create menus and parse a config
	InitializeMenus();
	ParseConfigFile(file);
}

/* CheckCloseHandle()
 *
 * Checks if handle is closed or not and close handle.
 * --------------------------------------------------------------------- */
CheckCloseHandle(&Handle:handle)
{
	// Close handle if not closed yet
	if (handle != INVALID_HANDLE)
	{
		CloseHandle(handle);
		handle = INVALID_HANDLE;
	}
}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * --------------------------------------------------------------------- */
bool:IsValidClient(client)
{
	// Since its a boolean, we should return a value
	return (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) > TEAM_SPECTATOR) ? true : false;
}