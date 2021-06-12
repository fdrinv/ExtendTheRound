/*
* Extend The Round
* by: DENFER © 2021
*
* https://github.com/KWDENFER/ExtendTheRound
* https://vk.com/denferez
* https://steamcommunity.com/id/denferez
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the GNU General Public License, version 3.0, as published by the
* Free Software Foundation.
* 
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
* details.
*
* You should have received a copy of the GNU General Public License along with
* this program. If not, see <http://www.gnu.org/licenses/>.
*/

// SourceMod Includes 
#include <sourcemod>
#include <cstrike>
#include <sdktools>

// Custom includes 
#include <autoexecconfig>
#include <colorvariables>

// Defines
#define EXTENDTHEROUND_VERSION    "1.0"     
#define AUTHOR 	                  "DENFER"

// Pragma 
#pragma newdecls required
#pragma semicolon 				1
#pragma tabsize 				0 

// Strings
char g_sPrefix[64];

// ArrayLists
ArrayList g_hIntervals;

// Handles 
Handle g_hTimer;
Handle g_hBoostTimer;

// ConVars
ConVar gc_flRoundTime;
ConVar gc_iLowerBoundPlayers;
ConVar gc_flAdditionalTime;
ConVar gc_bCountDeadPlayers;
ConVar gc_iStartTimerInterval;
ConVar gc_iTimerRepeat;
ConVar gc_sInterval;
ConVar gc_sPrefix;
ConVar gc_sAdminFlags;
ConVar gc_sAdminCommands;
ConVar gc_bMessages;
ConVar gc_iMode;

// Floats
float g_flSecondsCounter;

// Integers
int g_iPreviousNumberOfPlayers;
int g_iPreviousInterval;
int g_iSaveSeconds;
int g_iTimerCounter;

// Booleans
bool g_bEventRoundEnd;
bool g_bBoostTimer;

// Informations
public Plugin myinfo = {
	name = "ExtendTheRound",
	author = "DENFER (for all questions - https://vk.com/denferez)",
	description = "A plugin that extends the round time depending on the number of players on the server",
	version = EXTENDTHEROUND_VERSION,
};

// ***********************************************//
//                                                //
/*                      CORE                      */
//                                                //
// ***********************************************//

public void OnPluginStart()
{
    // Translation 
	LoadTranslations("ExtendTheRound.phrases");

    // AutoExecConfig
    AutoExecConfig_SetCreateDirectory(true);
    AutoExecConfig_SetCreateFile(true);
    AutoExecConfig_SetFile("ExtendTheRound", AUTHOR);

    // Console Commands 

    // ---
    char time[8];
    GetConVarString(FindConVar("mp_roundtime"), time, sizeof(time));

    if(StringToFloat(time) < 0.05)
    {
        strcopy(time, sizeof(time), "1.92");
        LogError("Значение переменной \"mp_roundtime\" должно быть больше 0! Установите соответсвующее значение переменной отличной от нуля или равной \"mp_roundtime_hostage\", \"mp_roundtime_defuse\".");
    } 

    // ConVars
    gc_sPrefix = AutoExecConfig_CreateConVar("sm_er_prefix", "[{green}SM{default}]", "Префикс перед сообщениями плагина");
    gc_bMessages = AutoExecConfig_CreateConVar("sm_er_messages", "1", "Включить сообщения плагина? (0 - выкл, 1 - вкл)", 0, true, 0.0, true, 1.0);
    gc_flRoundTime = AutoExecConfig_CreateConVar("sm_er_round_time", time, "Время длительности раунда по умолчанию (стандарное время длительности раунда) (указывать в минутах)", 0, true, 0.05, false);
    gc_iMode = AutoExecConfig_CreateConVar("sm_er_mode", "1", "Режим работы плагина, всего 2 режима: 0 - Плагин будет учитывать всех игроков на сервере (спектаторы в том числе и люди, которые подключаются к серверу), 1 - только игроков, которые находятся в команде T / CT");
    gc_iLowerBoundPlayers = AutoExecConfig_CreateConVar("sm_er_lower_bound", "5", "Минимальное число игроков, после чего к основному времени будет добавляться дополнительное за каждого НОВОГО игрока", 0, true, 0.0, true, 64.0);
    gc_flAdditionalTime = AutoExecConfig_CreateConVar("sm_er_additional_time", "1", "Дополнительное время, которое будет добавляться к основному за каждого игрока (если переменная не равно нулю \"sm_er_lower_bound\", то эти игроки не будут учтены) (указывать в минутах)", 0, true, 0.0, false);
    gc_bCountDeadPlayers = AutoExecConfig_CreateConVar("sm_er_count_dead_players", "0", "Учитывать мертвых игроков, как игроков за которых стоит манипулировать длительностью раунда? (0 - нет, 1 - да)", 0, true, 0.0, true, 1.0);
    gc_sInterval = AutoExecConfig_CreateConVar("sm_er_interval", "5, 10, 15, 20, 25, 30", "Промежутки, числа в них - это количество игроков, при которых нужно увеличивать длительность раунда (то есть в отличие от \"sm_er_lower_bound\", данная переменная будет увеличивать длительность раунда при достижение определенного числа игроков на соотвествующее время)", 0, false);
    gc_sAdminCommands = AutoExecConfig_CreateConVar("sm_er_admin_command", "er, extend", "Название команды, которая вызывает специальное меню (указывать в строку, разделяя каждую команду через запятую без использования приставки sm_)", 0, false);
    gc_sAdminFlags = AutoExecConfig_CreateConVar("sm_er_admin_flags", "z", "Флаги доступа к специальному меню от плагина (указывать в строку, без пробелом и прочих знаков)", 0, false);

    // Advanced Convars
    gc_iStartTimerInterval = AutoExecConfig_CreateConVar("sm_er_timer_interval", "10", "В течение скольки секунд после начала раунда проверять на сколько стоит изменить длительность раунда? (указывать в секундах)", 0, true, 1.0, false);
    gc_iTimerRepeat = AutoExecConfig_CreateConVar("sm_er_check_interval", "5", "Сколько осуществить проверок на длительность раунда в промежутке времени, когда осуществляется основная проверка? (см. \"sm_er_interval\")", 0, true, 1.0, false);

    // Hooks 
    HookConVarChange(FindConVar("mp_roundtime"), ConVarChange);
    HookConVarChange(FindConVar("mp_roundtime_hostage"), ConVarChange);
    HookConVarChange(FindConVar("mp_roundtime_defuse"), ConVarChange);

    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);

    // AutoExecConfig
    AutoExecConfig_ExecuteFile();
    AutoExecConfig_CleanFile();
}

// ***********************************************//
//                                                //
/*                      FORWARDS                  */
//                                                //
// ***********************************************//

public void OnConfigsExecuted()
{
    // Init Plugin Prefix
    gc_sPrefix.GetString(g_sPrefix, sizeof(g_sPrefix));

    // Admin Console Commands
    int count = 0;
	char Commands[256], CommandsL[16][32], Command[64], Flags[16];
    gc_sAdminFlags.GetString(Flags, sizeof(Flags));
    int bit = ReadFlagString(Flags);

    gc_sAdminCommands.GetString(Commands, sizeof(Commands));
	ReplaceString(Commands, sizeof(Commands), " ", "");
	count = ExplodeString(Commands, ",", CommandsL, sizeof(CommandsL), sizeof(CommandsL[])); // количество команд 

    for(int i = 0; i < count; ++i)
	{
		Format(Command, sizeof(Command), "sm_%s", CommandsL[i]);
		if (GetCommandFlags(Command) == INVALID_FCVAR_FLAGS)
        {
			RegAdminCmd(Command, Menu_ExtendTheRound, bit);
        }
	}

    // Init Intervals
    if(gc_sInterval.IntValue != 0)
    {
        g_hIntervals = new ArrayList();
        char sInterval[128];
        char buffers[64][8];

        GetConVarString(gc_sInterval, sInterval, sizeof(sInterval));

        ExplodeString(sInterval, ",", buffers, 64, 8);
        
        for(int i = 0; i < 64; ++i)
        {
            TrimString(buffers[i]);

            if(strlen(buffers[i]) != 0)
            {
                g_hIntervals.Push(StringToInt(buffers[i]));
            }
        }

        g_hIntervals.Sort(Sort_Ascending, Sort_Integer);
    }
}

public void OnPluginEnd()
{
    UnhookConVarChange(FindConVar("mp_roundtime"), ConVarChange);
    UnhookConVarChange(FindConVar("mp_roundtime_hostage"), ConVarChange); 
    UnhookConVarChange(FindConVar("mp_roundtime_defuse"), ConVarChange); 
}

// ***********************************************//
//                                                //
/*                      EVENTS                    */
//                                                //
// ***********************************************//
void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bEventRoundEnd = false;
    
    if(g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }

    g_iPreviousNumberOfPlayers = 0;
    g_iSaveSeconds = 0;
    g_iTimerCounter = 0;
    g_flSecondsCounter = 0.0;

    if(gc_iLowerBoundPlayers.IntValue)
    {
        CheckAdditionalTime();
        g_hTimer = CreateTimer(gc_iStartTimerInterval.FloatValue / gc_iTimerRepeat.FloatValue, Timer_CheckAdditionalTime, 0, TIMER_REPEAT);
    }
    else 
    {
        CheckAdditionalTimeInterval();
        g_hTimer = CreateTimer(gc_iStartTimerInterval.FloatValue / gc_iTimerRepeat.FloatValue, Timer_CheckAdditionalTimeInterval, 0, TIMER_REPEAT);
    }
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bEventRoundEnd = true;
}

// ***********************************************//
//                                                //
/*                   FUNCTIONS                    */
//                                                //
// ***********************************************//

void ConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(convar.FloatValue != gc_flRoundTime.FloatValue)
    {
        SetConVarFloat(convar, gc_flRoundTime.FloatValue);  
        SetConVarBounds(convar, ConVarBound_Lower, true, 0.05);
        SetConVarBounds(convar, ConVarBound_Upper, false);
    }
}

// flag: true - увеличить, false - уменьшить
void ChangeRoundTime(int delta, bool flag)
{
    if(flag)
    {
        g_iSaveSeconds = RoundToNearest(delta * gc_flAdditionalTime.FloatValue * 60);
        GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) + RoundToNearest(delta * gc_flAdditionalTime.FloatValue * 60), 4, 0, true);
    }
    else 
    {
        if(GameRules_GetProp("m_iRoundTime", 4, 0) - RoundToNearest(delta * gc_flAdditionalTime.FloatValue * 60) >= 3)
        {
            GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - RoundToNearest(delta * gc_flAdditionalTime.FloatValue * 60), 4, 0, true);
        }
    }
}

int GetTeamAliveClientCount(int team)
{
    int counter = 0;

    for(int i = 1; i <= MaxClients; ++i)
    {
        if(IsClientInGame(i) && GetClientTeam(i) == team && IsPlayerAlive(i))
        {
            ++counter;
        }
    }

    return counter;
}

void CheckAdditionalTime()
{
    int iPlayers;

    if(gc_bCountDeadPlayers.BoolValue)
    {
        if(gc_iMode.IntValue)
        {
            iPlayers = GetTeamClientCount(CS_TEAM_CT) + GetTeamClientCount(CS_TEAM_T);
        }
        else 
        {
            iPlayers = NumberOfPlayers();
        }

        if(iPlayers)
        {
            if(iPlayers > gc_iLowerBoundPlayers.IntValue)
            {
                if(iPlayers > g_iPreviousNumberOfPlayers)
                {
                    ChangeRoundTime(iPlayers - gc_iLowerBoundPlayers.IntValue, true);
                }
            }
        }
    }
    else 
    {
        iPlayers = GetTeamAliveClientCount(CS_TEAM_CT) + GetTeamAliveClientCount(CS_TEAM_T);

        if(iPlayers)
        {
            if(iPlayers > gc_iLowerBoundPlayers.IntValue)
            {
                if(iPlayers > g_iPreviousNumberOfPlayers)
                {
                    ChangeRoundTime(iPlayers - gc_iLowerBoundPlayers.IntValue, true);
                }
            }
        }
    }

    g_iPreviousNumberOfPlayers = iPlayers;
}

void CheckAdditionalTimeInterval()
{
    int iPlayers;

    if(gc_bCountDeadPlayers.BoolValue)
    {
        if(gc_iMode.IntValue)
        {
            iPlayers = GetTeamClientCount(CS_TEAM_CT) + GetTeamClientCount(CS_TEAM_T);
        }
        else 
        {
            iPlayers = NumberOfPlayers();
        }
        

        if(iPlayers)
        {
            ChangeRoundTime(GetInterval(iPlayers), true);
        }
    }
    else 
    {
        iPlayers = GetTeamAliveClientCount(CS_TEAM_CT) + GetTeamAliveClientCount(CS_TEAM_T);

        if(iPlayers)
        {
            ChangeRoundTime(GetInterval(iPlayers), true);
        }
    }

    g_iPreviousInterval = GetInterval(iPlayers);
}

int GetInterval(int players)
{
    for(int i = 0; i < g_hIntervals.Length; ++i)
    {
        if(players >= g_hIntervals.Get(g_hIntervals.Length - 1))
        {
            return (g_hIntervals.Length - 1); 
        }

        if(players >= g_hIntervals.Get(i) && players < g_hIntervals.Get(i + 1))
        {
            return i + 1;
        }
    }

    return 0;
}

void AdditionTime(int time)
{
    GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) + time, 4, 0, true);

    if(gc_bMessages.BoolValue)
    {
        for(int i = 1; i <= MaxClients; ++i)
        {
            if(IsClientInGame(i))
            {
                time < 60 ? CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Time_Increased_Sec", LANG_SERVER, time) : CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Time_Increased_Min", LANG_SERVER, time / 60);
            }
        }
    }
}

void DecreaseTime(int client, int time)
{
    if(GameRules_GetProp("m_iRoundTime", 4, 0) - time <= 3)
    {
        if(gc_bMessages.BoolValue)
        {
            CPrintToChat(client, "%s %T", "Chat_Time_Cant_Be_Reduced", g_sPrefix, LANG_SERVER);
        }

        return;
    }

    GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - time, 4, 0, true);

    if(gc_bMessages.BoolValue)
    {
        for(int i = 1; i <= MaxClients; ++i)
        {
            if(IsClientInGame(i))
            {
                time < 60 ? CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Time_Reduced_Sec", LANG_SERVER, time) : CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Time_Reduced_Min", LANG_SERVER, time / 60);
            }
        }
    }
}

void BoostTime(int x)
{
    if(g_hBoostTimer != null)
    {
        KillTimer(g_hBoostTimer);
        g_hBoostTimer = null;
    }

    g_bBoostTimer = true;
    g_hBoostTimer = CreateTimer(1.0, Timer_BoostTime, x, TIMER_REPEAT);

    if(gc_bMessages.BoolValue)
    {
        for(int i = 1; i <= MaxClients; ++i)
        {
            if(IsClientInGame(i))
            {
                CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Speed_Up_Time", LANG_SERVER, x * 100);
            }
        }
    }
}

int NumberOfPlayers()
{
    int counter = 0;

    for(int i = 0; i <= MaxClients; ++i)
    {
        if(IsClientInGame(i))
        {
            counter++;
        }
    }

    return counter;
}

// ***********************************************//
//                                                //
/*                      TIMERS                    */
//                                                //
// ***********************************************//

Action Timer_CheckAdditionalTime(Handle timer)
{
    g_flSecondsCounter += gc_iStartTimerInterval.FloatValue / gc_iTimerRepeat.FloatValue;

    if(g_iTimerCounter == gc_iTimerRepeat.IntValue || g_bEventRoundEnd)
    {
        g_hTimer = null;
        return Plugin_Stop;
    }

    int iPlayers;

    if(gc_bCountDeadPlayers.BoolValue)
    {
        if(gc_iMode.IntValue)
        {
            iPlayers = GetTeamClientCount(CS_TEAM_CT) + GetTeamClientCount(CS_TEAM_T);
        }
        else 
        {
            iPlayers = NumberOfPlayers();
        }

        if(iPlayers)
        {
            if(iPlayers > gc_iLowerBoundPlayers.IntValue)
            {
                if(iPlayers > g_iPreviousNumberOfPlayers)
                {
                    ChangeRoundTime(iPlayers - gc_iLowerBoundPlayers.IntValue, true);
                }
            }

            if(iPlayers < g_iPreviousNumberOfPlayers)
            {
                if(iPlayers <= gc_iLowerBoundPlayers.IntValue)
                {
                    if(GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)) >= 3)
                    {
                        GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)), 4, 0, true);
                    }
                }
                else 
                {
                    ChangeRoundTime(g_iPreviousNumberOfPlayers - iPlayers, false);
                }
            }
        }
    }
    else 
    {
        iPlayers = GetTeamAliveClientCount(CS_TEAM_CT) + GetTeamAliveClientCount(CS_TEAM_T);

        if(iPlayers)
        {
            if(iPlayers > gc_iLowerBoundPlayers.IntValue)
            {
                if(iPlayers > g_iPreviousNumberOfPlayers)
                {
                    ChangeRoundTime(iPlayers - gc_iLowerBoundPlayers.IntValue, true);
                }
            }

            if(iPlayers < g_iPreviousNumberOfPlayers)
            {
                if(iPlayers <= gc_iLowerBoundPlayers.IntValue)
                {
                    if(GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)) >= 3)
                    {
                        GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)), 4, 0, true);
                    }
                }
                else 
                {
                    ChangeRoundTime(g_iPreviousNumberOfPlayers - iPlayers, false);
                }
            }
        }
    }

    ++g_iTimerCounter;
    g_iPreviousNumberOfPlayers = iPlayers;
    g_hTimer = null;

    return Plugin_Continue;
}

Action Timer_CheckAdditionalTimeInterval(Handle timer)
{
    g_flSecondsCounter += gc_iStartTimerInterval.FloatValue / gc_iTimerRepeat.FloatValue;

    if(g_iTimerCounter == gc_iTimerRepeat.IntValue || g_bEventRoundEnd)
    {
        g_hTimer = null;
        return Plugin_Stop;
    }

    int iPlayers;

    if(gc_bCountDeadPlayers.BoolValue)
    {
        if(gc_iMode.IntValue)
        {
            iPlayers = GetTeamClientCount(CS_TEAM_CT) + GetTeamClientCount(CS_TEAM_T);
        }
        else 
        {
            iPlayers = NumberOfPlayers();
        }

        if(iPlayers)
        {
            if(GetInterval(iPlayers) > g_iPreviousInterval)
            {
                ChangeRoundTime(GetInterval(iPlayers) - g_iPreviousInterval, true);
            }

            if(GetInterval(iPlayers) < g_iPreviousInterval)
            {
                if(GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)) >= 3)
                {
                    GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)), 4, 0, true);
                }
            }
        }
    }
    else 
    {

        iPlayers = GetTeamAliveClientCount(CS_TEAM_CT) + GetTeamAliveClientCount(CS_TEAM_T);

        if(iPlayers)
        {
            if(GetInterval(iPlayers) > g_iPreviousInterval)
            {
                ChangeRoundTime(GetInterval(iPlayers) - g_iPreviousInterval, true);
            }

            if(iPlayers < g_iPreviousInterval)
            {
                if(GetInterval(iPlayers) < g_iPreviousInterval)
            {
                if(GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)) >= 3)
                {
                    GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - (g_iSaveSeconds + RoundToNearest(g_flSecondsCounter)), 4, 0, true);
                }
            }
            }
        }
    }

    ++g_iTimerCounter;
    g_iPreviousInterval = GetInterval(iPlayers);
    g_hTimer = null;

    return Plugin_Continue;
}

Action Timer_BoostTime(Handle timer, int x)
{
    if(!g_bBoostTimer)
    {
        g_hBoostTimer = null;
        return Plugin_Stop;
    }

    GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0) - x, 4, 0, true);

    g_hBoostTimer = null;
    return Plugin_Continue;
}

// ***********************************************//
//                                                //
/*                      MENU                      */
//                                                //
// ***********************************************//

Action Menu_ExtendTheRound(int client, int argc)
{
    Menu menu = new Menu(HandlerMenu_ExtendTheRound);
	char info[128];

    menu.SetTitle("%T", "Menu_Title_Extend", LANG_SERVER);

    FormatEx(info, sizeof(info), "%T", "Menu_Increase", LANG_SERVER);
	menu.AddItem("increase", info);
		
	FormatEx(info, sizeof(info), "%T", "Menu_Reduce", LANG_SERVER);
	menu.AddItem("reduce", info);

    FormatEx(info, sizeof(info), "%T", "Menu_Title_Speed_Up", LANG_SERVER);
	menu.AddItem("speedup", info);

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

public int HandlerMenu_ExtendTheRound(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
	{
		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(param2, info, sizeof(info));

            if(!strcmp(info, "increase"))
            {
                Menu_Increase(param1);
            }
            else if(!strcmp(info, "reduce"))
            {
                Menu_Reduce(param1);
            }
            else if(!strcmp(info, "speedup"))
            {
                Menu_SpeedUp(param1);
            }
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void Menu_Increase(int client)
{
    Menu menu = new Menu(HandlerMenu_Increase);
	char info[128];

    menu.SetTitle("%T", "Menu_Title_Increase", LANG_SERVER);

    FormatEx(info, sizeof(info), "%T", "5s", LANG_SERVER);
	menu.AddItem("5s", info);
		
	FormatEx(info, sizeof(info), "%T", "10s", LANG_SERVER);
	menu.AddItem("10s", info);

    FormatEx(info, sizeof(info), "%T", "15s", LANG_SERVER);
	menu.AddItem("15s", info);

    FormatEx(info, sizeof(info), "%T", "30s", LANG_SERVER);
	menu.AddItem("30s", info);

    FormatEx(info, sizeof(info), "%T", "1m", LANG_SERVER);
	menu.AddItem("1m", info);

    FormatEx(info, sizeof(info), "%T", "2m", LANG_SERVER);
	menu.AddItem("2m", info);

    FormatEx(info, sizeof(info), "%T", "3m", LANG_SERVER);
	menu.AddItem("3m", info);

    FormatEx(info, sizeof(info), "%T", "5m", LANG_SERVER);
	menu.AddItem("5m", info);

    FormatEx(info, sizeof(info), "%T", "10m", LANG_SERVER);
	menu.AddItem("10m", info);

    menu.ExitButton = true;
	menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int HandlerMenu_Increase(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
	{
		case MenuAction_Select:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof(info));

            if(!strcmp(info, "5s"))
            {
                AdditionTime(5);
            }
            else if(!strcmp(info, "10s"))
            {
                AdditionTime(10);
            }
            else if(!strcmp(info, "15s"))
            {
                AdditionTime(15);
            }
            else if(!strcmp(info, "30s"))
            {
                AdditionTime(30);
            }
            else if(!strcmp(info, "1m"))
            {
                AdditionTime(60);
            }
            else if(!strcmp(info, "2m"))
            {
                AdditionTime(120);
            }
            else if(!strcmp(info, "3m"))
            {
                AdditionTime(180);
            }
            else if(!strcmp(info, "5m"))
            {
                AdditionTime(300);
            }
            else if(!strcmp(info, "10m"))
            {
                AdditionTime(600);
            }

            Menu_Increase(param1);
		}
        case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
			{
				Menu_ExtendTheRound(param1, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void Menu_Reduce(int client)
{
    Menu menu = new Menu(HandlerMenu_Reduce);
	char info[128];

    menu.SetTitle("%T", "Menu_Title_Reduce", LANG_SERVER);

    FormatEx(info, sizeof(info), "%T", "5s", LANG_SERVER);
	menu.AddItem("5s", info);
		
	FormatEx(info, sizeof(info), "%T", "10s", LANG_SERVER);
	menu.AddItem("10s", info);

    FormatEx(info, sizeof(info), "%T", "15s", LANG_SERVER);
	menu.AddItem("15s", info);

    FormatEx(info, sizeof(info), "%T", "30s", LANG_SERVER);
	menu.AddItem("30s", info);

    FormatEx(info, sizeof(info), "%T", "1m", LANG_SERVER);
	menu.AddItem("1m", info);

    FormatEx(info, sizeof(info), "%T", "2m", LANG_SERVER);
	menu.AddItem("2m", info);

    FormatEx(info, sizeof(info), "%T", "3m", LANG_SERVER);
	menu.AddItem("3m", info);

    FormatEx(info, sizeof(info), "%T", "5m", LANG_SERVER);
	menu.AddItem("5m", info);

    FormatEx(info, sizeof(info), "%T", "10m", LANG_SERVER);
	menu.AddItem("10m", info);

    menu.ExitButton = true;
	menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int HandlerMenu_Reduce(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
	{
		case MenuAction_Select:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof(info));

            if(!strcmp(info, "5s"))
            {
                DecreaseTime(param1, 5);
            }
            else if(!strcmp(info, "10s"))
            {
                DecreaseTime(param1, 10);
            }
            else if(!strcmp(info, "15s"))
            {
                DecreaseTime(param1, 15);
            }
            else if(!strcmp(info, "30s"))
            {
                DecreaseTime(param1, 30);
            }
            else if(!strcmp(info, "1m"))
            {
                DecreaseTime(param1, 60);
            }
            else if(!strcmp(info, "2m"))
            {
                DecreaseTime(param1, 120);
            }
            else if(!strcmp(info, "3m"))
            {
                DecreaseTime(param1, 180);
            }
            else if(!strcmp(info, "5m"))
            {
                DecreaseTime(param1, 300);
            }
            else if(!strcmp(info, "10m"))
            {
                DecreaseTime(param1, 600);
            }

            Menu_Reduce(param1);
		}
        case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
			{
				Menu_ExtendTheRound(param1, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

Action Menu_SpeedUp(int client)
{
    Menu menu = new Menu(HandlerMenu_SpeedUp);
	char info[128];

    menu.SetTitle("%T", "Menu_Title_Speed_Up", LANG_SERVER);

    FormatEx(info, sizeof(info), "%T", "1x", LANG_SERVER); // 100%
	menu.AddItem("1x", info);
		
	FormatEx(info, sizeof(info), "%T", "2x", LANG_SERVER); // 200%
	menu.AddItem("2x", info);

    FormatEx(info, sizeof(info), "%T", "3x", LANG_SERVER); // 300%
	menu.AddItem("3x", info);

    FormatEx(info, sizeof(info), "%T", "4x", LANG_SERVER); // 400%
	menu.AddItem("4x", info);

    FormatEx(info, sizeof(info), "%T", "5x", LANG_SERVER); // 500%
	menu.AddItem("5x", info);

    FormatEx(info, sizeof(info), "%T", "Cancel_Acceleration", LANG_SERVER);
	menu.AddItem("cancel", info);

    menu.ExitButton = true;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int HandlerMenu_SpeedUp(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
	{
		case MenuAction_Select:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof(info));

            if(!strcmp(info, "1x"))
            {
                BoostTime(1);
            }
            else if(!strcmp(info, "2x"))
            {
                BoostTime(2);
            }
            else if(!strcmp(info, "3x"))
            {
                BoostTime(3);
            }
            else if(!strcmp(info, "4x"))
            {
                BoostTime(4);
            }
            else if(!strcmp(info, "5x"))
            {
                BoostTime(5);
            }
            else if(!strcmp(info, "cancel"))
            {
                g_bBoostTimer = false;

                if(gc_bMessages.BoolValue)
                {
                    for(int i = 1; i <= MaxClients; ++i)
                    {
                        if(IsClientInGame(i))
                        {
                            CPrintToChat(i, "%s %T", g_sPrefix, "All_Chat_Speed_Up_Time_Cancel", LANG_SERVER);
                        }
                    }
                }
            }

            Menu_SpeedUp(param1);
		}
        case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
			{
				Menu_ExtendTheRound(param1, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}