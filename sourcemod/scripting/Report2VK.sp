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



#define STEAMWORKS_ON()	(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest")	== FeatureStatus_Available)
#define RIP_ON()		(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "HTTPClient.HTTPClient")			== FeatureStatus_Available)

#pragma newdecls required

#if defined _ripext_included_
HTTPClient g_hHTTPClient;
#endif

bool 
isAdvertTurned, g_bHideAdmins, g_bBlockMuted;

char
sServerName[256], a_Prefix[128], g_sFormat[512],
vk_Token[128], vk_PeerID[16];

int
g_iDelay, m_iDelays[65], // Хранение задержек между репортами
isReporting[65], // Для определения того, кого репортит игрок (и репортит ли вообще)
g_iAdDelay, g_iCurAdDelay, // Хранение задержек напоминания
g_iMuteType = 0; // Тип плагина для банов/мутов


public Plugin myinfo = 
{
	name		= "Report2VK [R2VK]",
	version		= "1.1a",
	description	= "Sends player's reports in VK. Отправка репортов игроков в ВК.",
	author		= "NickFox",
	url			= "https://vk.com/nf_dev"
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max) 
{
	CreateNative("R2VK_SendVK", Native_SendVK);    
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
	LoadIni(); // Работаем с конфигурационным файлом
	
}



public int Native_SendVK(Handle hPlugin, int iNumParams)
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
	if(CheckCommandAccess(client, "BypassPremiumCheck", ADMFLAG_ROOT, true)){
		LoadIni();
		CPrintToChat(client,"{grey}[%s{grey}] {default}Конфиг перезагружен", a_Prefix);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}


void DisplayChooseMenu(int client) // Функция показа меню с выбором игрока
{
	Menu menu = new Menu(MenuHandler_ChooseMenu); // Прикрепляем обработчик при выборе в категории
	menu.SetTitle("Выбрать игрока"); // Устанавливаем заголовок
	menu.ExitBackButton = true; // Активируем кнопку выхода	
	
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
		PrepSendReport(target,client);		
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
		delete menu; // Выход из меню
}

public void PrepSendReport(int target,int client){

	CPrintToChat(client,"{grey}[%s{grey}]  {default}Введите причину, по которой хотите пожаловаться на игрока", a_Prefix);	
	isReporting[client]=target;
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
		
		SendVK(message);
	}
	else CPrintToChat(client,"{grey}[%s{grey}]  {default}Выбранный игрок вышел с сервера", a_Prefix);	
	
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
	
	if (STEAMWORKS_ON()) SW_SendMessage(sURL);
	else if (RIP_ON()) RIP_SendMessage(sURL);
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
  if (isReporting[client]!=0){
  

	
	char text[256];
	GetCmdArg(1, text, sizeof(text));
	
	SendVKReport(client,isReporting[client],text);
	isReporting[client] = 0;
	CPrintToChat(client,"{grey}[%s{grey}] {default}Жалоба на игрока успешно отправлена!", a_Prefix);	
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

public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "sourcebans++", true))
	{
		g_iMuteType = 1;
	}
	else
	{
		if (StrEqual(sName, "materialadmin", true))
		{
			g_iMuteType = 2;
		}
	}
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
			
			g_iDelay = kv.GetNum("Delay");
			g_iAdDelay = kv.GetNum("AdDelay");
			
			kv.GetString("Format", g_sFormat, sizeof(g_sFormat));
			kv.GetString("VK_Token", vk_Token, sizeof(vk_Token));
			kv.GetString("VK_PeerID", vk_PeerID, sizeof(vk_PeerID));
			
			kv.Rewind();
		}
	}
	else SetFailState("[R2VK] KeyValues Error!");
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
	if (hResponse.Status != HTTPStatus_OK) LogMessage("VK-Response[RIP]: %d", hResponse.Status);
}
#endif

#if defined _SteamWorks_Included
void SW_SendMessage(const char[] sURL)
{
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);
	SteamWorks_SetHTTPCallbacks(hRequest, OnRequestCompleteSW);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "User-Agent", "Test");
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