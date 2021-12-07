// Version: 1.0.3

#if defined _colors_included
#endinput
#endif
#define _colors_included

#define SZF(%0)			%0, sizeof(%0)

#define TO_MENU 		-2	// Сообщение возвращается с вырезанными цветами и никому не отправляется (полезно для меню).
#define TO_ALL	 		-1	// Сообщение в чат для всех игроков.
#define TO_SERVER		 0	// Сообщение в консоль сервера.

static char s[512];
static StringMap s_trie = null;
static EngineVersion s_engine;
static int  s_iServerLanguage;
static bool s_bUseColors;	// Если false, то {цвета} нужно вырезать , т.к. сообщение отправляется в консоль/меню, где они не нужны.
static bool s_bSayText2 ;	// Если true , то в сообщении было {team}, используем StartMessage("SayText2"..

static void Init()
{
	s_trie = new StringMap();
		
	switch ((s_engine = GetEngineVersion()))
	{
		case Engine_CSGO:
		{
			s_trie.SetValue("red"		, 0x02);
			s_trie.SetValue("lightred"	, 0x07);
			s_trie.SetValue("blue"		, 0x0C);
			s_trie.SetValue("lightblue"	, 0x0B);
			s_trie.SetValue("lightgreen", 0x05);
			s_trie.SetValue("lime"		, 0x06);
			s_trie.SetValue("yellow"	, 0x09);
			s_trie.SetValue("orange"	, 0x10);
			s_trie.SetValue("pink"		, 0x0E);
			s_trie.SetValue("purple"	, 0x03);
			s_trie.SetValue("gray"		, 0x0A);
		}
		case Engine_CSS:
		{
			s_trie.SetValue("lightgreen", 0x03);
			s_trie.SetValue("darkgreen"	, 0x05);
		}
		case Engine_SourceSDK2006: {
			s_trie.SetValue("lightgreen", 0x03);
		}
		default: {
			SetFailState("This game is not supported");
		}
	}
	
	// Одинаковые цвета во всех играх.
	s_trie.SetValue("default"	, 0x01);
	s_trie.SetValue("green"		, 0x04);
	s_trie.SetValue("team"		, 0x03);
	
	s_iServerLanguage = GetServerLanguage();
}

// Поиск/замена цветов. Такой вариант должен быть быстрее, чем ReplaceString.
static void ReplaceColors(int client, int bytes)
{
	// Самый короткий цвет: "{red}" 5
	if (bytes < 6) {
		return;
	}
	
	static int i;
	static int i_start;
	static int i_end;
	static int c;
	static int team;
	static bool replaced;
	
	i			= -1;
	i_start		= -1;
	team		= 0 ;
	replaced	= false;
		
	while (++i < bytes ) {
		if (s[i] == '{') {
			i_start = i;
		}
		else if (s[i] == '}' && i_start != -1)
		{
			i_end = i;
			
			// Самый длинный цвет: "{lightgreen}" 12 и "{#FFFFFF}" 9.
			if ((i_end - i_start) < 12 && (s[i_start+1] != '#' || (s_engine == Engine_CSS && (i_end - i_start) == 8))) {
				if (s[i_start+1] == '#') {
					if (s_bUseColors) {
						// "{#FFFFFF}"="0\x07FFFFFF0"
						s[i_start	] = 0;
						s[i_start+1	] = 0x07;
						s[i_end		] = 0;
					}
					else{
						while (i_start <= i_end) {
							s[i_start++] = 0; // Цвета не нужны.
						}
					}
					replaced = true;
				}
				else{
					s[i_end] = 0;
					if (s_trie.GetValue(s[i_start+1], c)) {
						// Цвет поддерживается.
						if (!s_bUseColors) {
							while (i_start <= i_end) {
								s[i_start++] = 0; // Цвета не нужны.
							}
						}
						else{
							if (c == 0x03 && s[i_start+1] == 't' && client > 0) {
								// {team}
								if (s_engine == Engine_CSGO) {
									// В csgo можно обойтись и без SayText2.
									switch (team ? team : (team = GetClientTeam(client))) {
										case 2: {
											c = 0x09; // t
										}
										case 3: {
											c = 0x0B; // ct
										}
										default: {
											c = 0x02; // spec
										}
									}
								}
								else{
									s_bSayText2 = view_as<bool>('w' + 'S');
								}
							}
							// "{red}Msg" = "0000\x02Msg"
							while (i_start < i_end) {
								s[i_start++] = 0;
							}
							s[i_end] = c;
						}
						replaced = true;
					}
					else{
						// Цвет не поддерживается. Это может быть {userid} и тд, поэтому не очищаем (на всякий).
						s[i_end] = '}' ;
					}
				}
			}
			
			i_start = -1; // Снова ищем '{', игнорируя '}'.
		}
	}
	
	if (replaced) {
		// Сдвигаем всё влево, удаляя ненужные символы конца строки.
		i = -1;
		while (++i < bytes) {
			if (!s[i]) {
				c = i;
				while (++c < bytes) {
					if (s[c]) {
						s[i] = s[c];
						s[c] = 0;
						break;
					}
				}
				if (!s[i]) {
					break; // Справа одни нули.
				}
			}
		}
	}
}

/**
 * Отправить сообщение в чат или консоль сервера.
 *
 * @param client  	Индекс игрока или TO_MENU/TO_ALL/TO_SERVER.
 *
 * @param phrase	Фраза, которая должна быть переведена, или "", если перевод не требуется.
 *					Если фраза не переведена, то ошибки не будет, а вместо перевода отобразится фраза.
 *
 * @param format	Правила форматирования или "".
 *
 *					Перевод не используется:
 *					CPrint(client, _, "{default}Hi, {team}%N", client);
 *
 *					Перевод используется и переменных "#format" нет :
 *					CPrint(client, "my phrase");
 *
 *					Перевод используется и переменные "#format" есть:
 *					CPrint(client, "my phrase", "%t", "my phrase", var1, var2);
 
 *					Текст нужен для меню с вырезанными цветами:
 *					panel.DrawText(CPrint(TO_MENU, "your hp", "%T", "your hp", client, GetClientHealth(client)));
 *
 * @return			Последнее отредактированное сообщение или "".
 */
stock char[] CPrint(int client, const char[] phrase="", const char[] format="", any ...)
{
	if (!s_trie) {
		Init();
	}
	
	s[0] = 0;
	
	if (!phrase[0] && !format[0]) {
		return s;
	}
	
	bool translationError = phrase[0] && !IsTranslatedForLanguage(phrase, s_iServerLanguage);
	if ( translationError) {
		strcopy(SZF(s), phrase);
	}
	else{
		s_bUseColors = client > 0 || client == TO_ALL;
	}
	
	s_bSayText2 = false;
	
	for (int target = 1; target <= MaxClients; target++)
	{
		// Всем.
		if (client == TO_ALL) {
			if (!IsClientInGame(target)) {
				continue;
			}
		}
		// Одному игроку.
		else if ((target = client) > 0) {
			if (target > MaxClients) {
				break;	// @param client указан неверно.
			}
		}
		// В консоль сервера/меню.
		else if (target != TO_SERVER && target != TO_MENU) {
			break;		// @param client указан неверно.
		}
		
		if (!translationError) {
			if (format[0]) {
				if (phrase[0]) {
					SetGlobalTransTarget(s_bUseColors ? target : LANG_SERVER);
				}
				ReplaceColors(target, VFormat (SZF(s), format, 4));
			}
			else
			{
				// phrase точно указана. Т.к. FormatEx быстрее, чем SetGlobalTransTarget + VFormat, то используем его когда можно.
				ReplaceColors(target, FormatEx(SZF(s), "%T", phrase, (s_bUseColors ? target : LANG_SERVER), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0));
			}
		}
	
		if (s[0] && target != TO_MENU)
		{
			if (target == TO_SERVER) {
				PrintToServer("%s", s);
			}
			else if (s_bSayText2)
			{
				// css + css v34
				int players[1];
				players[0]  = target;
				Handle hMsg = StartMessage("SayText2", players, 1);
				if (hMsg) {
					if (s[0] != 0x01) {
						Format(SZF(s), "\x01%s", s);
					}
					BfWriteByte  (hMsg, target);
					BfWriteByte  (hMsg, true);
					BfWriteString(hMsg, s);
					EndMessage();
				}
				else{
					PrintToChat(target, "%s%s", (s[0] == 0x01 ? "" : "\x01"), s);
				}
			}
			else{
				PrintToChat(target, "%s%s", (s[0] == 0x01 ? "" : "\x01"), s);
				if (s_engine == Engine_CSGO) {
					// В css если отправить сообщение в чат, то оно отображается и в консоле, но в csgo это не так.
					PrintToConsole(target, "%s", s);
				}
			}
		}
		
		if (client != TO_ALL) {
			break;
		}
	}
	
	return s;
}