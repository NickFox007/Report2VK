/* =================================================================================
					Changelog
										
	1.0 - Первая полноценная версия плагина
  1.0.1 - Фикс несрабатывания команды у игроков, не являющихся администраторами
		- Отказ от использования функционала библиотеки adminmenu
		- Боты и текущий игрок больше не доступны для выбора при репорте
		- Подчищены "хвосты" лишнего кода
	1.1 - Теперь Вы сами можете настроить частоту напоминания о команде
		(указывается промежуток в виде количества раундов)
		- Немного изменён формат отправляемых сообщений
		- Появилась возможность использования возможностей	данного плагина в
		других благодаря инклуду r2vk.inc.	Достаточно просто использовать
		функцию SendVK(<текст сообщения>), после чего во все беседы, указанные
		в конфиге, придет указанное сообщение
		- Возможность скрывать админов в списке игроков для репорта
		- Возможность отключить команду для находящихся в муте
		- Другие некритичные фиксы	
  1.1.1 - Фикс ошибки "Client is invalid", которая проявлялась на серверах
		с малым количеством слотов
  1.2.0 - Фикс ошибки с ненайденным нативом расширения RestInPawn
		- Переключение между SteamWorks и RiP (параметр SWorRIP [1 - SW, 0 - RiP]
		- Добавлено взаимодействие с Discord [Core]
		от Kruzya (параметр Discord [1 - ВКЛ, 0 - ВЫКЛ])
		- Теперь функция из r2vk.inc переименована из R2VK_SendVK в R2VK_Send
		- Иные мелкие фиксы
  1.3.0 - Добавлено логирование сообщений в файл (параметр Logging [1 - ВКЛ, 0 - ВЫКЛ])
		- Фикс ошибки неверного хэндла при нажатии кнопки выхода (убраны ненужные кнопки)
		- Добавлено меню для выбора причины репорта
		(настраивается в файле config/r2vk_reasons.ini)
		- Добавлено переключение возможности вписать собственную причину при репорте
		(параметр AllowOwnReason [1 - ВКЛ, 0 - ВЫКЛ])
		- Некоторые поправки во фразах
   ================================================================================= */		


#pragma semicolon 1

#define IS_CLIENT(%1)       (1 <= %1 <= MaxClients)

#include <colors>
#include <r2vk>

#undef REQUIRE_EXTENSIONS
#tryinclude <SteamWorks>
#tryinclude <ripext>
#undef REQUIRE_PLUGIN
#tryinclude <sourcecomms>
#tryinclude <materialadmin>
#tryinclude <discord_extended>

#pragma newdecls required

#if defined _SteamWorks_Included
#define STEAMWORKS_ON()	(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest")	== FeatureStatus_Available)
#endif

#if defined _ripext_included_
#define RIP_ON()		(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "HTTPClient.HTTPClient")			== FeatureStatus_Available)
#endif


#if defined _ripext_included_
HTTPClient g_hHTTPClient;
#endif

Handle
fileHandle       = INVALID_HANDLE;

bool 
isAdvertTurned, g_bHideAdmins, g_bBlockMuted,
DISCORD_ON,
g_bUseDiscord, g_bUseSW,
g_bLogging, g_bAllowOwnReason,
g_bUseOwnReason[65];

char
sServerName[256], a_Prefix[128], g_sFormat[512],
vk_Token[128], vk_PeerID[16], // Данные ВК
logFile[128];// Хранение названия файла
StringMap g_sReasons;



int
g_iDelay, m_iDelays[65], // Хранение задержек между репортами
isReporting[65], // Для определения того, кого репортит игрок (и репортит ли вообще)
g_iAdDelay, g_iCurAdDelay, // Хранение задержек напоминания
g_iMuteType = 0, // Тип плагина для банов/мутов
g_iReasonsCount; // Количество причин из конфига


public Plugin myinfo = 
{
	name		= "Report2VK [R2VK]",
	version		= "1.2.1",
	description	= "Sends player's reports in VK. Отправка репортов игроков в ВК.",
	author		= "NickFox",
	url			= "https://vk.com/nf_dev"
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max) 
{
	CreateNative("R2VK_Send", Native_Send);    
	RegPluginLibrary("r2vk");
	return APLRes_Success;
}

public void OnPluginStart()
{	

	#if defined _ripext_included_
	if (RIP_ON()) g_hHTTPClient = new HTTPClient("https://api.vk.com");
	#endif

	RegConsoleCmd("sm_report", Cmd_Report); // Регистрация команды для репортов sm_report (!report)
	RegConsoleCmd("sm_r2vk_reload", Cmd_Reload); // Регистрация команды для перезагрузки конфиг-файла sm_r2vk_reload (!r2vk_reload)
			
	HookEvent("round_freeze_end", RoundFreezeEnd, EventHookMode_PostNoCopy); // Перехватываем событие старта раунда
	AddCommandListener(HookPlayerChat, "say"); // Перехватываем сообщение в чате
	AddCommandListener(HookPlayerChat, "say_team"); // Перехватываем сообщение в тим-чате
	
	BuildPath(Path_SM, logFile, PLATFORM_MAX_PATH, "/logs/r2vk.log");
	
	LoadIni(); // Работаем с конфигурационным файлом
	LoadIni2(); // Работаем с конфигурационным файлом списка причин
	
}

public void Log(const char[] text){

	char time[21], date[21];
	
	char log[1024];
	
	FormatTime(time, sizeof(time), "%H:%M:%S", -1)	;
	FormatTime(date, sizeof(date), "%d.%m.%y", -1);
	
	Format(log, sizeof(log), "%s %s\n%s\n", date, time, text);
	
	fileHandle = OpenFile(logFile, "a");  /* Append */
	WriteFileLine(fileHandle, log);
	CloseHandle(fileHandle);

}

public void OnLibraryAdded(const char[] szName) 
{
	if(StrEqual(szName, "discord_extended")) DISCORD_ON = true;
	if (StrEqual(szName, "sourcebans++", true))
	{
		g_iMuteType = 1;
	}
	else
	{
		if (StrEqual(szName, "materialadmin", true))
		{
			g_iMuteType = 2;
		}
	}

}

public void OnLibraryRemoved(const char[] szName) 
{
	if(StrEqual(szName, "discord_extended")) DISCORD_ON = false;	
}


public int Native_Send(Handle hPlugin, int iNumParams)
{	
	char text[256];	
	GetNativeString(1, text, sizeof(text));
	char message[512];
	char szPluginName[64];	
	GetPluginInfo(hPlugin, PlInfo_Name,szPluginName, sizeof(szPluginName));
	Format(message,sizeof(message),"%s\n==============================\n%s",szPluginName,text);
	SendVK(message);

}

public Action Cmd_Report(int client, int args){
	
	if(g_bBlockMuted&&isMuted(client)) CPrintToChat(client,"{grey}[%s{grey}] {lime} Нельзя использовать данную команду, находясь в муте",a_Prefix);
	else if(m_iDelays[client]) CPrintToChat(client,"{grey}[%s{grey}] {lime}Подождите перед следующей отправкой репорта ещё %u раундов",a_Prefix,m_iDelays[client]);
	else DisplayChooseMenu(client);
	return Plugin_Handled;
}

public Action Cmd_Reload(int client, int args){
	if(client==0){
		LoadIni();
		PrintToServer("[R2VK] Config reloaded!");
		return Plugin_Handled;
	
	}
	if(CheckCommandAccess(client, "BypassPremiumCheck", ADMFLAG_ROOT, true)){
		LoadIni();		
		CPrintToChat(client,"{grey}[%s{grey}] {default}Конфиг перезагружен!", a_Prefix);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}


void DisplayChooseMenu(int client) // Функция показа меню с выбором игрока
{
	Menu menu = new Menu(MenuHandler_ChooseMenu); // Прикрепляем обработчик при выборе в категории
	menu.SetTitle("Выберите игрока"); // Устанавливаем заголовок
	//menu.ExitBackButton = true; // Активируем кнопку выхода	
	
	char userid[15], name[32];
	// Добавляем игроков в меню выбора
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && i!=client) 
		{ 
			if (!(g_bHideAdmins&&CheckCommandAccess(i, "BypassPremiumCheck", ADMFLAG_GENERIC, true))){
		
				IntToString(GetClientUserId(i), userid, 15); 
				GetClientName(i, name, 32); 
				menu.AddItem(userid, name); 
			}
		}
	}
	
	
	menu.Display(client, MENU_TIME_FOREVER);
}


void DisplayChooseReasonMenu(int client) // Функция показа меню с выбором игрока
{
	Menu menu = new Menu(MenuHandler_ChooseReasonMenu); // Прикрепляем обработчик при выборе в категории
	menu.SetTitle("Выберите причину"); // Устанавливаем заголовок
	//menu.ExitBackButton = true; // Активируем кнопку выхода	
	
	char Sindex[3], szBuff[32];
	// Добавляем причины в меню выбора
	for (int i = 0; i < g_iReasonsCount; i++) 
	{			
		IntToString(i, Sindex, sizeof(Sindex));
		
		g_sReasons.GetString(Sindex, szBuff, sizeof(szBuff));		
		
		menu.AddItem(Sindex, szBuff); 
	}
	
	if (g_bAllowOwnReason) menu.AddItem("own", "Своя причина"); 
	
	
	menu.Display(client, MENU_TIME_FOREVER);
}




public int MenuHandler_ChooseMenu(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
		delete menu; // Выход из меню
	else if(action == MenuAction_Select) // Если игрок был выбран
	{
		char info[8];
		int target;
		menu.GetItem(param2, info, sizeof(info));
		target = GetClientOfUserId(StringToInt(info));			
		//PrepSendReport(target,client);		
		isReporting[client] = target;
		DisplayChooseReasonMenu(client);
	}
	else if(action == MenuAction_Cancel)
		delete menu; // Выход из меню
}


public int MenuHandler_ChooseReasonMenu(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End){
		isReporting [client] = 0;
		delete menu; // Выход из меню		
	}
	else if(action == MenuAction_Select) // Если игрок был выбран
	{		
		char info[4], reason[256];		
		menu.GetItem(param2, info, sizeof(info));		
		
		if (StrEqual(info,"own")) PrepSendReport(client);
		
		else
		{
		
			g_sReasons.GetString(info, reason, sizeof(reason));
			
			SendVKReport(client,isReporting[client],reason);
		}
	}
	else if(action == MenuAction_Cancel){
		isReporting [client] = 0;
		delete menu; // Выход из меню	
	}
}


public void PrepSendReport(int client){
	g_bUseOwnReason[client] = true;
	CPrintToChat(client,"{grey}[%s{grey}] {default}Введите причину, по которой хотите пожаловаться на игрока", a_Prefix);	
}

public void SendVKReport(int client, int target, char text[256]){

	if (IsClientInGame(target)){
	
		m_iDelays[client] = g_iDelay;
		
		char sSteam[64],client_url[128],target_url[128];
		char client_name[MAX_NAME_LENGTH],target_name[MAX_NAME_LENGTH];
		
		GetClientName(client, client_name, sizeof(client_name));
		GetClientName(target, target_name, sizeof(target_name));
		
		GetClientAuthId(client, AuthId_SteamID64, sSteam, sizeof(sSteam), true);
		Format(client_url, sizeof(client_url), "steamcommunity.com/profiles/%s", sSteam);
		
		GetClientAuthId(target, AuthId_SteamID64, sSteam, sizeof(sSteam), true);
		Format(target_url, sizeof(target_url), "steamcommunity.com/profiles/%s", sSteam);

		char message[1024];	
		char sTime[16],sDate[16];
		
		FormatTime(sTime,sizeof(sTime), "%H:%M:%S");
		FormatTime(sDate,sizeof(sDate), "%d.%m.%Y");	
		FormatEx(message,sizeof(message), g_sFormat,sServerName,client_name,client_url,target_name,target_url,sDate,sTime,text);
		
		if (g_bLogging) Log(message);		
		
		isReporting[client] = 0;
		
		SendVK(message);		

		#if defined _discord_extended_included
		
			if (DISCORD_ON&&g_bUseDiscord) SendDiscord(message);
				
		
		#endif
		
		CPrintToChat(client,"{grey}[%s{grey}] {default}Жалоба на игрока успешно отправлена!", a_Prefix);
		
	}
	else CPrintToChat(client,"{grey}[%s{grey}]  {default}Выбранный игрок вышел с сервера", a_Prefix);	
	
}

public void SendDiscord(char[] message){

	Discord_StartMessage();
	Discord_SetUsername("R2VK");
	Discord_SetContent(message);
	Discord_EndMessage("report", true); // отправляем сообщение на веб-хук chat_logger из конфига, одобряя использование стандартного веб-хука, если нужного нет.

}

public void SendVK(char[] message){
	char sURL[2048];
	
	FormatEx(sURL, sizeof(sURL), "https://api.vk.com/method/messages.send?v=5.121&random_id=%i&access_token=%s&peer_id=%s&message=%s",
		GetRandomInt(1, 14881337),
		vk_Token,
		vk_PeerID,
		message
	);
	
	//Костыли текста
	ReplaceString(sURL, sizeof(sURL), " ", "%20", false);
	ReplaceString(sURL, sizeof(sURL), "NWLN", "%0A", false);
	ReplaceString(sURL, sizeof(sURL), "\n", "%0A", false);
	ReplaceString(sURL, sizeof(sURL), "#", "%23", false);
	
	if (STEAMWORKS_ON()&&g_bUseSW)	SW_SendMessage(sURL);
	else if (RIP_ON()&&!g_bUseSW)	RIP_SendMessage(sURL);
}

public bool isMuted(int i){
	int iMute = 0;
	if (g_iMuteType==1) iMute = SourceComms_GetClientMuteType(i);
	if (g_iMuteType==2) iMute = MAGetClientMuteType(i);
	if (iMute==0) return false;
	else return true;
}



public Action HookPlayerChat(int client, char[] command, int args)  // Если поступило сообщение в чат, то вызывается это событие
{
  if (isReporting[client]!=0&&g_bUseOwnReason[client]){
	
	g_bUseOwnReason[client] = false;
	char text[256];
	GetCmdArg(1, text, sizeof(text));
	
	SendVKReport(client,isReporting[client],text);
	return Plugin_Handled; // Блокируем показ сообщения в чате
	
  }
  return Plugin_Continue;
}

public void OnClientPutInServer(int client){	
	isReporting[client] = 0; // Ставим каждому зашедшему изначальный статус того, что он не в состоянии репорта
	m_iDelays[client] = 0; // Обнуляем каждому зашедшему счетчик задержки
}


public void OnConfigsExecuted(){
	Handle hHostName;
	if( (hHostName = FindConVar("hostname")) == INVALID_HANDLE)
	{
		PrintToServer("[R2VK] Error while getting ServerName");
		return;
	}
	
	GetConVarString(hHostName, sServerName, sizeof(sServerName));
}


void LoadIni(){

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/r2vk.ini");
	KeyValues kv = new KeyValues("R2VK");
	if (!FileExists(sPath, false)){
		if (kv.JumpToKey("Settings", true)){
			kv.SetString("Advert_Prefix","{darkred}R2VK");
			kv.SetNum("Advertisement", 1);
			kv.SetNum("HideAdmins", 1);
			kv.SetNum("Block4Muted", 1);
			kv.SetNum("SWorRIP", 0);
			kv.SetNum("Discord", 1);
			kv.SetNum("Logging", 1);
			kv.SetNum("AllowOwnReason", 1);
			kv.SetNum("Delay", 3);
			kv.SetNum("AdDelay", 3);	
			kv.SetString("Format", "[R2VK] %s\n\nИгрок %s\n[%s]\n\nпожаловался на %s\n[%s]\n\nДата - %s\nВремя - %s\n\nПричина: %s");
			kv.SetString("VK_Token", "Put your token here!");
			kv.SetString("VK_PeerID", "Put needed peerID here!");			
			kv.Rewind();
		}
		kv.ExportToFile(sPath);
	}
	
	if (kv.ImportFromFile(sPath)){
		if (kv.JumpToKey("Settings", false)){
		
			kv.GetString("Advert_Prefix", a_Prefix, sizeof(a_Prefix));
			
			if (kv.GetNum("Block4Muted") == 1) g_bBlockMuted = true;
			else g_bBlockMuted = false;
			
			if (kv.GetNum("HideAdmins") == 1) g_bHideAdmins = true;
			else g_bHideAdmins = false;
			
			if (kv.GetNum("Advertisement") == 1) isAdvertTurned = true;
			else isAdvertTurned = false;
			
			if (kv.GetNum("SWorRIP") == 0) g_bUseSW = true;
			else g_bUseSW = false;
			
			if (kv.GetNum("Discord") == 1) g_bUseDiscord = true;
			else g_bUseDiscord = false;
			
			if (kv.GetNum("Logging") == 1) g_bLogging = true;
			else g_bLogging = false;
			
			if (kv.GetNum("AllowOwnReason") == 1) g_bAllowOwnReason = true;
			else g_bAllowOwnReason = false;
			
			g_iDelay = kv.GetNum("Delay");
			g_iAdDelay = kv.GetNum("AdDelay");
			
			kv.GetString("Format", g_sFormat, sizeof(g_sFormat));
			kv.GetString("VK_Token", vk_Token, sizeof(vk_Token));
			kv.GetString("VK_PeerID", vk_PeerID, sizeof(vk_PeerID));
			
			kv.Rewind();
		}
	}
	else SetFailState("[R2VK] KeyValues Error[1]!");
	delete kv;
}

void LoadIni2(){
	
	if(g_sReasons) delete g_sReasons;

	g_sReasons = new StringMap();
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/r2vk_reasons.ini");
	KeyValues kv = new KeyValues("R2VK");
	if (!FileExists(sPath, false)){
		if (kv.JumpToKey("Reasons", true)){
			kv.SetString("0", "Читы");
			kv.SetString("1", "Оскорбления");
			kv.SetString("2", "Иные нарушения правил");
			kv.Rewind();
		}
		kv.ExportToFile(sPath);
	}
	
	if (kv.ImportFromFile(sPath)){
		if (kv.JumpToKey("Reasons", false)){		
			
			int index = 0;
			char Sindex[4];
			char str[32];
			Sindex = "0";
			
			str = "not null";
			
			while(!StrEqual(str,""))
			{				
				kv.GetString(Sindex, str, sizeof(str));
				g_sReasons.SetString(Sindex, str);
				index++;
				IntToString(index,Sindex,sizeof(Sindex));
			}
			
			
			g_iReasonsCount = index-1;
			
			kv.Rewind();
		}
	}
	else SetFailState("[R2VK] KeyValues Error [2]!");
	delete kv;	
	
}


public bool iVP(int iClient){

	if (IS_CLIENT(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient) && IsPlayerAlive(iClient)) return true;
	else return false;

}


public void RoundFreezeEnd(Event event, const char[] name, bool dbc)
{	
	for(int i = 1;i<65;i++) if(m_iDelays[i]) m_iDelays[i]--;
	else if(isAdvertTurned){
		if(g_iCurAdDelay) g_iCurAdDelay--;
		else {
			if (iVP(i)) CPrintToChat(i,"{grey}[%s{grey}] {lime}Увидел нарушителя? Отправь жалобу на него с помощью команды !report",a_Prefix);
			g_iCurAdDelay=g_iAdDelay;
		}
	}
}

#if defined _ripext_included_
void RIP_SendMessage(const char[] sURL)
{
	g_hHTTPClient.SetHeader("User-Agent", "Test");
	g_hHTTPClient.Get(sURL[19], OnRequestCompleteRIP);
}

public void OnRequestCompleteRIP(HTTPResponse hResponse, any iData)
{
	if (hResponse.Status != HTTPStatus_OK) 
	LogMessage("VK-Response[RIP]: %d", hResponse.Status);
		
}
#endif

#if defined _SteamWorks_Included
void SW_SendMessage(const char[] sURL)
{
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);
	SteamWorks_SetHTTPCallbacks(hRequest, OnRequestCompleteSW);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "User-Agent", "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36");
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnRequestCompleteSW(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	int length;
	SteamWorks_GetHTTPResponseBodySize(hRequest, length);
	char[] sBody = new char[length];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, length);
	LogMessage("VK-Response[SW]: %s",sBody);
	delete hRequest;
}
#endif