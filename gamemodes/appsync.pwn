#include <a_samp>

/*
    AppSync RP - base didatica em portugues

    Ideia principal:
    - O servidor e a autoridade. Dinheiro, inventario, armas e organizacao ficam aqui.
    - O APK/IDE apenas mostra a interface e pede a acao.
    - Quando o jogador clica em "Inventario", o APK envia: /app inv
    - A GM responde com mensagens APP|inventory.slot|...
    - Quando o jogador clica em "Usar", o APK envia: /app useitem <slot>
    - A GM valida o slot, valida o item e so entao aplica o efeito.

    Isso evita abuso porque o client nunca escolhe vida, dinheiro, quantidade
    de item ou arma. Ele apenas pede. Quem confirma tudo e o servidor.
*/

#define APP_COLOR             0xA9E34BFF
#define COLOR_INFO            0xD8DEE9FF
#define COLOR_WARN            0xFFD166FF
#define COLOR_ERROR           0xFF6B6BFF

#define MAX_INV_SLOTS         8
#define APP_CHUNK_SIZE        70
#define APP_RATE_MS           100
#define APP_ACTION_RATE_MS    200
#define ANTI_CHEAT_RATE_MS    1000
#define VEHICLE_MODEL_RHINO   432
#define VEHICLE_MODEL_REMINGTON 534
#define VEHICLE_RESPAWN_TIME  180
#define VEHICLE_DESTROY_DELAY_MS 4000
#define VEHICLE_SPAWN_AFTER_DETACH_MS 4200
#define VEHICLE_LOCK_DISTANCE 8.0
#define WORLD_CONFIG_FILE     "appsync_world.cfg"
#define WORLD_CONFIG_POLL_MS  1000
#define COLSCAN_STEP_MS       6500
#define COLWALK_STEP_MS       900

// ---- Sistema de cabelo ----
#define HAIR_SLOT             9    // slot de attached object reservado para cabelo
#define HAIR_BONE_HEAD        1    // bone da cabeca no SA-MP
#define HAIR_COLOR_DEFAULT    0
#define HAIR_COLOR_BLOND      1
#define HAIR_COLOR_RED        2
#define HAIR_COLOR_BLACK      3
#define HAIR_COLOR_BLUE       4
#define HAIR_COLOR_GREEN      5
#define HAIR_COLOR_PINK       6
#define HAIR_COLOR_BALD       7
#define COLWALK_MOVE_STEPS    16
#define COLWALK_DROP_SETTLE_STEPS 12
#define COLSCAN_DROP_Z        140.0

#include "colscan_points.generated.inc"

/*
    Spawn aberto para teste automatico de veiculos. Usamos o eixo da pista
    09L/27R do aeroporto de LS para nao prender carro/moto/heli em muros.
*/
#define SPAWN_X               1744.0000
#define SPAWN_Y               -2494.0000
#define SPAWN_Z               14.0000
#define SPAWN_ANGLE           90.0000
#define COLFALL_X             1954.1200
#define COLFALL_Y             -2147.6200
#define COLFALL_Z             24.0000
#define COLFALL_ANGLE         180.0000
#define SPAWN_AUDIT_OBJECTS   8
#define OBJ_SELFTEST_OBJECTS  4

#define ITEM_NONE             0
#define ITEM_MEDKIT           1
#define ITEM_PHONE            2
#define ITEM_RADIO            3
#define ITEM_WATER            4

#define ORG_NONE              0
#define ORG_POLICE            1

new bool:gPlayerReady[MAX_PLAYERS];
new gPlayerCash[MAX_PLAYERS];
new gPlayerPhoneNumber[MAX_PLAYERS];
new gPlayerOrg[MAX_PLAYERS];
new gPlayerRank[MAX_PLAYERS];
new gPlayerSkin[MAX_PLAYERS];
new gPlayerHairColor[MAX_PLAYERS];  // cor de cabelo: 0=default 1=blond 2=red 3=black 4=blue 5=green 6=pink 7=bald
new gInventoryItem[MAX_PLAYERS][MAX_INV_SLOTS];
new gInventoryAmount[MAX_PLAYERS][MAX_INV_SLOTS];
new bool:gAuthWeapon[MAX_PLAYERS][47];
new gAuthWeaponAmmo[MAX_PLAYERS][47];
new gPlayerSpawnedVehicle[MAX_PLAYERS];
new bool:gPlayerVehicleLocked[MAX_PLAYERS];
new gSpawnAuditObject[SPAWN_AUDIT_OBJECTS];
new gObjSelfTest[MAX_PLAYERS][OBJ_SELFTEST_OBJECTS];
new Text:gTextDrawSelfTestBackplate;
new Text:gTextDrawSelfTestButton;
new Text:gTextDrawSelfTestEmptyButton;
new bool:gTextDrawSelfTestReady;
new gLastAppTick[MAX_PLAYERS];
new gLastActionTick[MAX_PLAYERS];
new gLastAntiCheatTick[MAX_PLAYERS];
new gLastVehicleDetachTick[MAX_PLAYERS];
new gPendingVehicleModel[MAX_PLAYERS];
new bool:gPendingCollisionFall[MAX_PLAYERS];
new gColScanTimer[MAX_PLAYERS];
new gColScanIndex[MAX_PLAYERS];
new gColScanEndIndex[MAX_PLAYERS];
new bool:gColScanWalkMode[MAX_PLAYERS];
new bool:gColScanDropMode[MAX_PLAYERS];
new gColWalkSubStep[MAX_PLAYERS];
new gWorldRevision = -1;
new gWorldWeather = 0;
new gWorldHour = 12;
new gWorldMinute = 0;
new bool:gWorldFreezeTime = true;
new gWorldConfigTimer;

forward ResyncSpawnedVehicle(vehicleid, playerid);
forward DestroyVehicleLater(vehicleid);
forward CreatePlayerVehicleLater(playerid, modelid);
forward PollWorldConfig();
forward CreateSpawnAuditObjects();
forward CreateTextDrawSelfTest();
forward DestroyObjSelfTestLater(playerid);
forward RunCollisionScanStep(playerid);

new Float:gColWalkVelX[COLWALK_MOVE_STEPS] = {
    0.18, 0.13, 0.0, -0.13, -0.18, -0.13, 0.0, 0.13,
    0.26, 0.19, 0.0, -0.19, -0.26, -0.19, 0.0, 0.19
};
new Float:gColWalkVelY[COLWALK_MOVE_STEPS] = {
    0.0, 0.13, 0.18, 0.13, 0.0, -0.13, -0.18, -0.13,
    0.0, 0.19, 0.26, 0.19, 0.0, -0.19, -0.26, -0.19
};
new Float:gColWalkAngle[COLWALK_MOVE_STEPS] = {
    90.0, 45.0, 0.0, 315.0, 270.0, 225.0, 180.0, 135.0,
    90.0, 45.0, 0.0, 315.0, 270.0, 225.0, 180.0, 135.0
};

main()
{
    print("\n--------------------------------------------");
    print(" AppSync RP - GM simples autoritativa");
    print(" Servidor manda, APK apenas mostra/pede.");
    print("--------------------------------------------\n");
}

public OnGameModeInit()
{
    SetGameModeText("AppSync RP 0.1");
    UsePlayerPedAnims();
    EnableStuntBonusForAll(0);
    ShowPlayerMarkers(PLAYER_MARKERS_MODE_OFF);
    ShowNameTags(1);
    SetNameTagDrawDistance(18.0);
    ManualVehicleEngineAndLights();
    new worldTimerCallback[] = "PollWorldConfig";
    gWorldConfigTimer = SetTimer(worldTimerCallback, WORLD_CONFIG_POLL_MS, true);
    PollWorldConfig();
    ApplyWorldSettingsToAll("servidor");

    for (new playerid = 0; playerid < MAX_PLAYERS; playerid++)
    {
        gPlayerSpawnedVehicle[playerid] = INVALID_VEHICLE_ID;
        gPlayerVehicleLocked[playerid] = false;
        gColScanTimer[playerid] = 0;
        gColScanIndex[playerid] = 0;
        gColScanWalkMode[playerid] = false;
        gColScanDropMode[playerid] = false;
        gColWalkSubStep[playerid] = 0;
    }

    AddPlayerClass(0, SPAWN_X, SPAWN_Y, SPAWN_Z, SPAWN_ANGLE, 0, 0, 0, 0, 0, 0);
    AddStaticVehicle(560, SPAWN_X + 20.0, SPAWN_Y, SPAWN_Z + 0.6, SPAWN_ANGLE, 0, 0);
    AddStaticVehicleEx(VEHICLE_MODEL_RHINO, 0.0, 0.0, -100.0, 0.0, 43, 0, VEHICLE_RESPAWN_TIME);
    CreateTextDrawSelfTest();
    /*
        Desligado neste ciclo de diagnostico: qualquer objeto de apoio perto
        do spawn mascara o buraco real de colisao arm64.
    */
    // CreateSpawnAuditObjects();

    print("[AppSync] Gamemode carregada.");
    print("[AppSync] Use /app sync, /inv, /cel, /orgmembros, /skin, /veiculo, /app ak.");
    return 1;
}

public OnGameModeExit()
{
    if (gWorldConfigTimer) KillTimer(gWorldConfigTimer);
    if (gTextDrawSelfTestReady)
    {
        TextDrawDestroy(gTextDrawSelfTestBackplate);
        TextDrawDestroy(gTextDrawSelfTestButton);
        TextDrawDestroy(gTextDrawSelfTestEmptyButton);
        gTextDrawSelfTestReady = false;
    }
    print("[AppSync] Gamemode encerrada.");
    return 1;
}

public OnPlayerConnect(playerid)
{
    ResetPlayerState(playerid);
    GiveStarterData(playerid);

    new name[MAX_PLAYER_NAME], msg[144];
    GetPlayerName(playerid, name, sizeof name);
    if (!strcmp(name, "codex_colfall", true) || !strcmp(name, "codexcolfall", true))
    {
        gPendingCollisionFall[playerid] = true;
        printf("[AppSync][colfall-arm] player=%d armed-by-nick", playerid);
    }
    format(msg, sizeof msg, "[AppSync] %s entrou. Dados criados no servidor.", name);
    SendClientMessageToAll(COLOR_INFO, msg);
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    StopCollisionScan(playerid);
    DestroyPlayerSpawnedVehicle(playerid);
    gPendingVehicleModel[playerid] = 0;
    gPlayerReady[playerid] = false;
    return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
    SetPlayerPos(playerid, SPAWN_X, SPAWN_Y, SPAWN_Z);
    SetPlayerCameraPos(playerid, SPAWN_X + 6.7, SPAWN_Y - 0.1, SPAWN_Z + 2.8);
    SetPlayerCameraLookAt(playerid, SPAWN_X, SPAWN_Y, SPAWN_Z);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    // AddPlayerClass ja envia a posicao de spawn. Evita um segundo SetPlayerPos
    // que parece teleporte de volta durante diagnostico de colisao.
    SetPlayerInterior(playerid, 0);
    SetPlayerVirtualWorld(playerid, 0);
    ApplyWorldSettingsToPlayer(playerid);
    SetPlayerHealth(playerid, 100.0);
    SetPlayerArmour(playerid, 0.0);
    RestoreAuthorizedWeapons(playerid);
    SetServerMoney(playerid, gPlayerCash[playerid]);
    ApplyPlayerHair(playerid, gPlayerHairColor[playerid]);
    SendFullAppSync(playerid);
    SendClientMessage(playerid, COLOR_INFO, "GM AppSync: use /inv, /cel, /orgmembros, /skin, /veiculo ou /app sync.");
    SendClientMessage(playerid, COLOR_WARN, "Para testar AK pelo servidor autoritativo, use /app ak.");
    if (gPendingCollisionFall[playerid])
    {
        gPendingCollisionFall[playerid] = false;
        SetPlayerPos(playerid, COLFALL_X, COLFALL_Y, COLFALL_Z);
        SetPlayerFacingAngle(playerid, COLFALL_ANGLE);
        SetPlayerVelocity(playerid, 0.0, 0.0, 0.0);
        SendClientMessage(playerid, COLOR_INFO, "COLFALL64: spawn real na posicao da queda, sem apoio artificial.");
        printf("[AppSync][colfall-spawn] player=%d pos=%.2f %.2f %.2f angle=%.2f expected_ground=20.00", playerid, COLFALL_X, COLFALL_Y, COLFALL_Z, COLFALL_ANGLE);
    }
    else
    {
        SetPlayerFacingAngle(playerid, SPAWN_ANGLE);
    }
    return 1;
}

public CreateSpawnAuditObjects()
{
    /*
        Cenario separado para auditar RPC 44/CreateObject no cliente arm64.
        Nao usar durante teste de queda/collision hole.
    */
    gSpawnAuditObject[0] = CreateObject(1215, 1955.70, 1349.90, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[1] = CreateObject(1215, 1960.80, 1349.90, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[2] = CreateObject(1215, 1955.70, 1354.40, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[3] = CreateObject(1215, 1960.80, 1354.40, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[4] = CreateObject(1432, 1958.20, 1351.60, 10.45, 0.0, 0.0, 180.0, 120.0);
    gSpawnAuditObject[5] = CreateObject(1238, 1958.20, 1349.60, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[6] = CreateObject(1238, 1958.20, 1354.70, 10.45, 0.0, 0.0, 0.0, 120.0);
    gSpawnAuditObject[7] = INVALID_OBJECT_ID;

    printf("[AppSync] Spawn audit objects criados: %d %d %d %d %d %d %d %d",
        gSpawnAuditObject[0], gSpawnAuditObject[1], gSpawnAuditObject[2], gSpawnAuditObject[3],
        gSpawnAuditObject[4], gSpawnAuditObject[5], gSpawnAuditObject[6], gSpawnAuditObject[7]);
    return 1;
}

public CreateTextDrawSelfTest()
{
    new backplateText[] = " ";
    gTextDrawSelfTestBackplate = TextDrawCreate(215.0, 180.0, backplateText);
    TextDrawAlignment(gTextDrawSelfTestBackplate, 1);
    TextDrawFont(gTextDrawSelfTestBackplate, 1);
    TextDrawLetterSize(gTextDrawSelfTestBackplate, 0.42, 1.65);
    TextDrawColor(gTextDrawSelfTestBackplate, 0x00000000);
    TextDrawBackgroundColor(gTextDrawSelfTestBackplate, 0x000000AA);
    TextDrawUseBox(gTextDrawSelfTestBackplate, 1);
    TextDrawBoxColor(gTextDrawSelfTestBackplate, 0x111827DD);
    TextDrawTextSize(gTextDrawSelfTestBackplate, 425.0, 62.0);
    TextDrawSetSelectable(gTextDrawSelfTestBackplate, 1);

    new tdText[] = "TD_TEST64_CLIQUE";
    gTextDrawSelfTestButton = TextDrawCreate(220.0, 185.0, tdText);
    TextDrawAlignment(gTextDrawSelfTestButton, 1);
    TextDrawFont(gTextDrawSelfTestButton, 2);
    TextDrawLetterSize(gTextDrawSelfTestButton, 0.42, 1.65);
    TextDrawColor(gTextDrawSelfTestButton, 0xFFFFFFFF);
    TextDrawSetOutline(gTextDrawSelfTestButton, 1);
    TextDrawBackgroundColor(gTextDrawSelfTestButton, 0x000000AA);
    TextDrawUseBox(gTextDrawSelfTestButton, 1);
    TextDrawBoxColor(gTextDrawSelfTestButton, 0x2A9D8FCC);
    TextDrawTextSize(gTextDrawSelfTestButton, 420.0, 52.0);
    TextDrawSetSelectable(gTextDrawSelfTestButton, 1);

    new emptyText[] = "";
    gTextDrawSelfTestEmptyButton = TextDrawCreate(220.0, 185.0, emptyText);
    TextDrawAlignment(gTextDrawSelfTestEmptyButton, 1);
    TextDrawFont(gTextDrawSelfTestEmptyButton, 1);
    TextDrawLetterSize(gTextDrawSelfTestEmptyButton, 0.42, 1.65);
    TextDrawColor(gTextDrawSelfTestEmptyButton, 0x00000000);
    TextDrawBackgroundColor(gTextDrawSelfTestEmptyButton, 0x00000000);
    TextDrawUseBox(gTextDrawSelfTestEmptyButton, 1);
    TextDrawBoxColor(gTextDrawSelfTestEmptyButton, 0x00000000);
    TextDrawTextSize(gTextDrawSelfTestEmptyButton, 420.0, 52.0);
    TextDrawSetSelectable(gTextDrawSelfTestEmptyButton, 1);

    gTextDrawSelfTestReady = true;
    print("[AppSync][td-test] textdraw seletivo criado com camada vazia.");
    return 1;
}

stock HandleTextDrawSelfTestCommand(playerid)
{
    if (!gTextDrawSelfTestReady)
    {
        SendClientMessage(playerid, COLOR_ERROR, "TD_TEST64 indisponivel no servidor.");
        return 1;
    }

    TextDrawShowForPlayer(playerid, gTextDrawSelfTestBackplate);
    TextDrawShowForPlayer(playerid, gTextDrawSelfTestButton);
    TextDrawShowForPlayer(playerid, gTextDrawSelfTestEmptyButton);
    SelectTextDraw(playerid, 0xA9E34BFF);
    SendClientMessage(playerid, COLOR_INFO, "TD_TEST64: clique no botao verde para confirmar textdraw clicavel.");
    printf("[AppSync][td-test] shown player=%d backplate=%d button=%d empty=%d", playerid, _:gTextDrawSelfTestBackplate, _:gTextDrawSelfTestButton, _:gTextDrawSelfTestEmptyButton);
    return 1;
}

public OnPlayerClickTextDraw(playerid, Text:clickedid)
{
    if (_:clickedid == 65535)
    {
        printf("[AppSync][td-test] cancelled player=%d", playerid);
        return 1;
    }

    if (gTextDrawSelfTestReady && clickedid == gTextDrawSelfTestEmptyButton)
    {
        TextDrawHideForPlayer(playerid, gTextDrawSelfTestBackplate);
        TextDrawHideForPlayer(playerid, gTextDrawSelfTestButton);
        TextDrawHideForPlayer(playerid, gTextDrawSelfTestEmptyButton);
        CancelSelectTextDraw(playerid);
        SendClientMessage(playerid, COLOR_INFO, "TD_TEST64 OK: clique recebido pelo servidor em camada vazia.");
        printf("[AppSync][td-test] click-ok player=%d textdraw=%d empty=%d", playerid, _:clickedid, _:gTextDrawSelfTestEmptyButton);
        return 1;
    }

    if (gTextDrawSelfTestReady && clickedid == gTextDrawSelfTestButton)
    {
        SendClientMessage(playerid, COLOR_ERROR, "TD_TEST64 FAIL: clique atravessou camada vazia e caiu no botao visivel.");
        printf("[AppSync][td-test] click-visible-fail player=%d textdraw=%d expected_empty=%d", playerid, _:clickedid, _:gTextDrawSelfTestEmptyButton);
        return 1;
    }

    if (gTextDrawSelfTestReady && clickedid == gTextDrawSelfTestBackplate)
    {
        SendClientMessage(playerid, COLOR_ERROR, "TD_TEST64 FAIL: clique caiu na camada de fundo.");
        printf("[AppSync][td-test] click-backplate-fail player=%d textdraw=%d expected=%d", playerid, _:clickedid, _:gTextDrawSelfTestButton);
        return 1;
    }

    printf("[AppSync][td-test] click-other player=%d textdraw=%d", playerid, _:clickedid);
    return 1;
}

public OnPlayerUpdate(playerid)
{
    if (!gPlayerReady[playerid]) return 1;

    new now = GetTickCount();
    if (now - gLastAntiCheatTick[playerid] < ANTI_CHEAT_RATE_MS) return 1;
    gLastAntiCheatTick[playerid] = now;

    if (GetPlayerMoney(playerid) != gPlayerCash[playerid])
    {
        SetServerMoney(playerid, gPlayerCash[playerid]);
        SendAppToast(playerid, "warn", "Dinheiro corrigido pelo servidor.");
    }

    new weaponid = GetPlayerWeapon(playerid);
    if (weaponid > 0 && weaponid < 47 && !gAuthWeapon[playerid][weaponid])
    {
        RestoreAuthorizedWeapons(playerid);
        SendClientMessage(playerid, COLOR_ERROR, "Anti-cheat: arma nao autorizada removida.");
        SendAppToast(playerid, "warn", "Arma nao autorizada removida.");
    }
    return 1;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
    printf("[Command] player=%d cmdtext=\"%s\"", playerid, cmdtext);
    new cmd[32], params[128];
    SplitFirst(cmdtext, cmd, sizeof cmd, params, sizeof params);

    if (!strcmp(cmd, "/app", true))
    {
        HandleAppCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/inv", true) || !strcmp(cmd, "/inventario", true))
    {
        SendInventorySync(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/cel", true) || !strcmp(cmd, "/celular", true) || !strcmp(cmd, "/phone", true))
    {
        SendPhoneSync(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/orgmembros", true) || !strcmp(cmd, "/membros", true))
    {
        SendOrgMembersSync(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/ak", true))
    {
        GiveServerWeapon(playerid, 30, 250);
        SendClientMessage(playerid, COLOR_INFO, "AK-47 liberada pelo servidor.");
        SendAppToast(playerid, "ok", "AK-47 liberada pelo servidor.");
        return 1;
    }
    if (!strcmp(cmd, "/tdtest", true) || !strcmp(cmd, "/testetextdraw", true))
    {
        HandleTextDrawSelfTestCommand(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/objtest", true) || !strcmp(cmd, "/testeobjetos", true))
    {
        HandleObjectSelfTestCommand(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/skin", true))
    {
        HandleSkinCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/cabelo", true) || !strcmp(cmd, "/hair", true) || !strcmp(cmd, "/correcabelo", true))
    {
        HandleHairCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/testspawn", true) || !strcmp(cmd, "/spawn_teste", true))
    {
        HandleTestSpawnCommand(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/colfall", true) || !strcmp(cmd, "/queda_colisao", true))
    {
        HandleCollisionFallCommand(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/colscan", true) || !strcmp(cmd, "/varrer_colisao", true))
    {
        HandleCollisionScanCommand(playerid, params, false, false);
        return 1;
    }
    if (!strcmp(cmd, "/coldropscan", true) || !strcmp(cmd, "/queda_mapa", true))
    {
        HandleCollisionScanCommand(playerid, params, false, true);
        return 1;
    }
    if (!strcmp(cmd, "/colwalkscan", true) || !strcmp(cmd, "/botscan", true) || !strcmp(cmd, "/bot_colisao", true))
    {
        HandleCollisionScanCommand(playerid, params, true, false);
        return 1;
    }
    if (!strcmp(cmd, "/coldropwalkscan", true) || !strcmp(cmd, "/botqueda", true) || !strcmp(cmd, "/bot_queda", true))
    {
        HandleCollisionScanCommand(playerid, params, true, true);
        return 1;
    }
    if (!strcmp(cmd, "/veiculo", true) || !strcmp(cmd, "/veh", true) || !strcmp(cmd, "/carro", true))
    {
        HandleVehicleCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/clima", true) || !strcmp(cmd, "/weather", true))
    {
        HandleWeatherCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/hora", true) || !strcmp(cmd, "/time", true))
    {
        HandleTimeCommand(playerid, params);
        return 1;
    }
    if (!strcmp(cmd, "/tank", true) || !strcmp(cmd, "/tanque", true))
    {
        HandleVehicleCommand(playerid, "432");
        return 1;
    }

    SendClientMessage(playerid, COLOR_WARN, "Comando desconhecido. Use /app sync, /inv, /cel, /orgmembros, /skin, /cabelo, /veiculo, /colfall, /colscan, /coldropwalkscan, /clima, /hora ou /tank.");
    return 1;
}

stock HandleTestSpawnCommand(playerid)
{
    QueueDestroySpawnedVeh(playerid, VEHICLE_DESTROY_DELAY_MS);
    if (IsPlayerInAnyVehicle(playerid))
    {
        RemovePlayerFromVehicle(playerid);
        gLastVehicleDetachTick[playerid] = GetTickCount();
    }

    SpawnPlayer(playerid);
    SetPlayerInterior(playerid, 0);
    SetPlayerVirtualWorld(playerid, 0);
    SetPlayerPos(playerid, SPAWN_X, SPAWN_Y, SPAWN_Z);
    SetPlayerFacingAngle(playerid, SPAWN_ANGLE);
    ApplyWorldSettingsToPlayer(playerid);
    SendClientMessage(playerid, COLOR_INFO, "TEST_SPAWN64: reposicionado para isolar o proximo teste.");
    printf("[AppSync][testspawn] player=%d pos=%.2f %.2f %.2f angle=%.2f", playerid, SPAWN_X, SPAWN_Y, SPAWN_Z, SPAWN_ANGLE);
    return 1;
}

stock HandleCollisionFallCommand(playerid)
{
    gPendingCollisionFall[playerid] = true;
    QueueDestroySpawnedVeh(playerid, VEHICLE_DESTROY_DELAY_MS);
    if (IsPlayerInAnyVehicle(playerid))
    {
        RemovePlayerFromVehicle(playerid);
        gLastVehicleDetachTick[playerid] = GetTickCount();
    }

    SpawnPlayer(playerid);
    SetPlayerInterior(playerid, 0);
    SetPlayerVirtualWorld(playerid, 0);
    SetPlayerPos(playerid, COLFALL_X, COLFALL_Y, COLFALL_Z);
    SetPlayerFacingAngle(playerid, COLFALL_ANGLE);
    SetPlayerVelocity(playerid, 0.0, 0.0, 0.0);
    ApplyWorldSettingsToPlayer(playerid);
    SendClientMessage(playerid, COLOR_INFO, "COLFALL64: posicao real da queda, sem apoio artificial.");
    printf("[AppSync][colfall] player=%d pos=%.2f %.2f %.2f angle=%.2f expected_ground=20.00", playerid, COLFALL_X, COLFALL_Y, COLFALL_Z, COLFALL_ANGLE);
    return 1;
}

stock StopCollisionScan(playerid)
{
    if (gColScanTimer[playerid] != 0)
    {
        KillTimer(gColScanTimer[playerid]);
        gColScanTimer[playerid] = 0;
    }
    gColScanIndex[playerid] = 0;
    gColScanEndIndex[playerid] = 0;
    gColScanWalkMode[playerid] = false;
    gColScanDropMode[playerid] = false;
    gColWalkSubStep[playerid] = 0;
    return 1;
}

stock NormalizeColScanInterior(interior)
{
    /*
        Muitos IPLs usam valores como 256/1024/2048 como flags do mapa,
        nao como interior SA-MP real. Enviar isso no RPC vira byte truncado
        e pode mascarar a rota; para a varredura, esses pontos sao mundo 0.
    */
    if (interior < 0 || interior > 30)
    {
        return 0;
    }
    return interior;
}

stock HandleCollisionScanCommand(playerid, const params[], bool:walkMode, bool:dropMode)
{
    if (!IsEmpty(params) && (!strcmp(params, "stop", true) || !strcmp(params, "parar", true)))
    {
        StopCollisionScan(playerid);
        SendClientMessage(playerid, COLOR_WARN, "COLSCAN64: varredura parada.");
        printf("[AppSync][colscan-stop] player=%d", playerid);
        return 1;
    }

    StopCollisionScan(playerid);
    QueueDestroySpawnedVeh(playerid, VEHICLE_DESTROY_DELAY_MS);
    if (IsPlayerInAnyVehicle(playerid))
    {
        RemovePlayerFromVehicle(playerid);
        gLastVehicleDetachTick[playerid] = GetTickCount();
    }

    SpawnPlayer(playerid);
    new startIndex, endIndex;
    ParseCollisionScanRange(params, startIndex, endIndex);
    gColScanIndex[playerid] = startIndex;
    gColScanEndIndex[playerid] = endIndex;
    gColScanWalkMode[playerid] = walkMode;
    gColScanDropMode[playerid] = dropMode;
    gColWalkSubStep[playerid] = 0;
    RunCollisionScanStep(playerid);

    new timerCallback[] = "RunCollisionScanStep";
    new timerMs = COLSCAN_STEP_MS;
    if (walkMode) timerMs = COLWALK_STEP_MS;
    gColScanTimer[playerid] = SetTimerEx(timerCallback, timerMs, true, "i", playerid);
    if (walkMode && dropMode)
    {
        SendClientMessage(playerid, COLOR_INFO, "COLDROPWALK64: bot local cai e anda usando colisao real, sem apoio artificial.");
    }
    else if (walkMode)
    {
        SendClientMessage(playerid, COLOR_INFO, "COLWALK64: bot local andando pelo mapa sem apoio artificial.");
    }
    else if (dropMode)
    {
        SendClientMessage(playerid, COLOR_INFO, "COLDROP64: queda real sobre o mapa, sem FindZ e sem apoio artificial.");
    }
    else
    {
        SendClientMessage(playerid, COLOR_INFO, "COLSCAN64: varrendo mapa sem apoio artificial.");
    }
    printf("[AppSync][colscan-start] player=%d start=%d end=%d count=%d total=%d step_ms=%d walk=%d drop=%d drop_z=%.1f",
        playerid,
        startIndex,
        endIndex,
        endIndex - startIndex,
        COLSCAN_POINTS,
        timerMs,
        walkMode ? 1 : 0,
        dropMode ? 1 : 0,
        COLSCAN_DROP_Z);
    return 1;
}

public RunCollisionScanStep(playerid)
{
    if (!IsPlayerConnected(playerid))
    {
        StopCollisionScan(playerid);
        return 0;
    }

    new index = gColScanIndex[playerid];
    new endIndex = gColScanEndIndex[playerid];
    if (endIndex <= 0 || endIndex > COLSCAN_POINTS) endIndex = COLSCAN_POINTS;
    if (index >= endIndex)
    {
        StopCollisionScan(playerid);
        SendClientMessage(playerid, COLOR_INFO, "COLSCAN64: varredura concluida. Conferir logcat/prints.");
        printf("[AppSync][colscan-done] player=%d end=%d total=%d", playerid, endIndex, COLSCAN_POINTS);
        return 0;
    }

    if (gColScanWalkMode[playerid] && gColWalkSubStep[playerid] < 0)
    {
        printf("[AppSync][colwalk-settle] player=%d index=%d remaining=%d",
            playerid,
            index,
            -gColWalkSubStep[playerid]);
        gColWalkSubStep[playerid]++;
        if (gColWalkSubStep[playerid] == 0)
        {
            gColWalkSubStep[playerid] = 1;
        }
        return 1;
    }

    if (gColScanWalkMode[playerid] && gColWalkSubStep[playerid] > 0)
    {
        new moveStep = gColWalkSubStep[playerid] - 1;
        if (moveStep < 0) moveStep = 0;
        if (moveStep >= COLWALK_MOVE_STEPS) moveStep = COLWALK_MOVE_STEPS - 1;

        new Float:oldVelX, Float:oldVelY, Float:oldVelZ;
        GetPlayerVelocity(playerid, oldVelX, oldVelY, oldVelZ);
        SetPlayerFacingAngle(playerid, gColWalkAngle[moveStep]);
        SetPlayerVelocity(playerid, gColWalkVelX[moveStep], gColWalkVelY[moveStep], oldVelZ);
        printf("[AppSync][colwalk-step] player=%d index=%d sub=%d vel=%.3f %.3f %.3f angle=%.2f",
            playerid,
            index,
            moveStep + 1,
            gColWalkVelX[moveStep],
            gColWalkVelY[moveStep],
            oldVelZ,
            gColWalkAngle[moveStep]);

        if (gColWalkSubStep[playerid] >= COLWALK_MOVE_STEPS)
        {
            gColWalkSubStep[playerid] = 0;
            gColScanIndex[playerid] = index + 1;
        }
        else
        {
            gColWalkSubStep[playerid]++;
        }
        return 1;
    }

    new scanInterior = NormalizeColScanInterior(gColScanInterior[index]);
    new Float:spawnZ = gColScanZ[index];
    if (gColScanDropMode[playerid])
    {
        spawnZ += COLSCAN_DROP_Z;
    }
    SetPlayerInterior(playerid, scanInterior);
    SetPlayerVirtualWorld(playerid, 0);
    SetPlayerPos(playerid, gColScanX[index], gColScanY[index], spawnZ);
    SetPlayerFacingAngle(playerid, gColScanA[index]);
    SetPlayerVelocity(playerid, 0.0, 0.0, 0.0);
    ApplyWorldSettingsToPlayer(playerid);
    printf("[AppSync][colscan-step] player=%d index=%d scan_id=%d interior=%d raw_interior=%d pos=%.2f %.2f %.2f raw_z=%.2f drop=%d drop_z=%.1f angle=%.2f inst=%d ground=%d findz=0",
        playerid,
        index,
        gColScanSourceId[index],
        scanInterior,
        gColScanInterior[index],
        gColScanX[index],
        gColScanY[index],
        spawnZ,
        gColScanZ[index],
        gColScanDropMode[playerid] ? 1 : 0,
        gColScanDropMode[playerid] ? COLSCAN_DROP_Z : 0.0,
        gColScanA[index],
        gColScanInstanceCount[index],
        gColScanGroundCount[index]);
    if (gColScanWalkMode[playerid])
    {
        if (gColScanDropMode[playerid])
        {
            gColWalkSubStep[playerid] = -COLWALK_DROP_SETTLE_STEPS;
        }
        else
        {
            gColWalkSubStep[playerid] = 1;
        }
    }
    else
    {
        gColScanIndex[playerid] = index + 1;
    }
    return 1;
}

stock ParseCollisionScanRange(const params[], &startIndex, &endIndex)
{
    startIndex = 0;
    endIndex = COLSCAN_POINTS;

    if (IsEmpty(params))
    {
        return 1;
    }

    new startText[16], rest[32], countText[16], ignored[16];
    SplitFirst(params, startText, sizeof startText, rest, sizeof rest);
    if (!strcmp(startText, "all", true) || !strcmp(startText, "tudo", true))
    {
        return 1;
    }

    startIndex = strval(startText);
    if (startIndex < 0) startIndex = 0;
    if (startIndex >= COLSCAN_POINTS) startIndex = COLSCAN_POINTS - 1;

    SplitFirst(rest, countText, sizeof countText, ignored, sizeof ignored);
    if (!IsEmpty(countText))
    {
        new count = strval(countText);
        if (count > 0)
        {
            endIndex = startIndex + count;
        }
    }
    if (endIndex <= startIndex) endIndex = COLSCAN_POINTS;
    if (endIndex > COLSCAN_POINTS) endIndex = COLSCAN_POINTS;
    return 1;
}

stock DestroyObjectSelfTest(playerid)
{
    for (new i = 0; i < OBJ_SELFTEST_OBJECTS; i++)
    {
        if (gObjSelfTest[playerid][i] != INVALID_OBJECT_ID)
        {
            DestroyObject(gObjSelfTest[playerid][i]);
            gObjSelfTest[playerid][i] = INVALID_OBJECT_ID;
        }
    }
    return 1;
}

public DestroyObjSelfTestLater(playerid)
{
    DestroyObjectSelfTest(playerid);
    printf("[AppSync][obj-test] cleanup player=%d", playerid);
    return 1;
}

stock HandleObjectSelfTestCommand(playerid)
{
    DestroyObjectSelfTest(playerid);

    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);

    /*
        Objetos ficam ao lado do jogador, nunca embaixo dele. Assim testamos RPC,
        material e colisao sem mascarar queda/limbo.
    */
    gObjSelfTest[playerid][0] = CreateObject(1215, x + 4.0, y + 2.0, z - 0.2, 0.0, 0.0, 0.0, 120.0);
    gObjSelfTest[playerid][1] = CreateObject(1238, x + 6.0, y + 2.0, z - 0.7, 0.0, 0.0, 0.0, 120.0);
    gObjSelfTest[playerid][2] = CreateObject(1432, x + 8.0, y + 2.0, z - 0.6, 0.0, 0.0, 180.0, 120.0);
    gObjSelfTest[playerid][3] = CreateObject(19482, x + 5.0, y + 4.0, z + 1.0, 0.0, 0.0, 90.0, 120.0);

    if (gObjSelfTest[playerid][3] != INVALID_OBJECT_ID)
    {
        new materialText[] = "OBJ_TEST64 MATERIAL OK";
        new materialFont[] = "Arial";
        SetObjectMaterialText(gObjSelfTest[playerid][3], materialText, 0,
            OBJECT_MATERIAL_SIZE_256x128, materialFont, 24, 1,
            0xFFFFFFFF, 0x000000AA, OBJECT_MATERIAL_TEXT_ALIGN_CENTER);
    }
    if (gObjSelfTest[playerid][2] != INVALID_OBJECT_ID)
    {
        new materialTxd[] = "matcolours";
        new materialTex[] = "grey-95-percent";
        SetObjectMaterial(gObjSelfTest[playerid][2], 0, 18646, materialTxd, materialTex, 0xFFFFFFFF);
    }

    SendClientMessage(playerid, COLOR_INFO, "OBJ_TEST64: objetos/material criados ao lado, sem apoio embaixo do player.");
    printf("[AppSync][obj-test] player=%d ids=%d %d %d %d pos=%.2f %.2f %.2f",
        playerid,
        gObjSelfTest[playerid][0], gObjSelfTest[playerid][1],
        gObjSelfTest[playerid][2], gObjSelfTest[playerid][3],
        x, y, z);

    new cleanupCallback[] = "DestroyObjSelfTestLater";
    SetTimerEx(cleanupCallback, 25000, false, "i", playerid);
    return 1;
}

stock ResetPlayerState(playerid)
{
    gPlayerReady[playerid] = true;
    gPlayerCash[playerid] = 500;
    gPlayerPhoneNumber[playerid] = 1000 + playerid;
    gPlayerOrg[playerid] = ORG_POLICE;
    gPlayerRank[playerid] = 1;
    gPlayerSkin[playerid] = 0;
    gPlayerHairColor[playerid] = HAIR_COLOR_DEFAULT;
    gPlayerSpawnedVehicle[playerid] = INVALID_VEHICLE_ID;
    gPlayerVehicleLocked[playerid] = false;
    gLastAppTick[playerid] = 0;
    gLastActionTick[playerid] = 0;
    gLastAntiCheatTick[playerid] = 0;
    gLastVehicleDetachTick[playerid] = 0;
    gPendingVehicleModel[playerid] = 0;
    gPendingCollisionFall[playerid] = false;
    DestroyObjectSelfTest(playerid);

    for (new slot = 0; slot < MAX_INV_SLOTS; slot++)
    {
        gInventoryItem[playerid][slot] = ITEM_NONE;
        gInventoryAmount[playerid][slot] = 0;
    }
    for (new weapon = 0; weapon < 47; weapon++)
    {
        gAuthWeapon[playerid][weapon] = false;
        gAuthWeaponAmmo[playerid][weapon] = 0;
    }
    ResetPlayerWeapons(playerid);
    ResetPlayerMoney(playerid);
}

stock GiveStarterData(playerid)
{
    SetInventorySlot(playerid, 0, ITEM_MEDKIT, 2);
    SetInventorySlot(playerid, 1, ITEM_PHONE, 1);
    SetInventorySlot(playerid, 2, ITEM_RADIO, 1);
    SetInventorySlot(playerid, 3, ITEM_WATER, 3);
}

stock bool:CheckAppRate(playerid, delay, bool:action = false)
{
    new now = GetTickCount();
    if (!action)
    {
        if (now - gLastAppTick[playerid] < delay)
        {
            SendClientMessage(playerid, COLOR_WARN, "Calma: comandos do app em rate limit.");
            return false;
        }
        gLastAppTick[playerid] = now;
        return true;
    }

    if (now - gLastActionTick[playerid] < delay)
    {
        SendAppToast(playerid, "warn", "Aguarde antes de fazer outra acao.");
        return false;
    }
    gLastActionTick[playerid] = now;
    return true;
}

stock HandleAppCommand(playerid, const params[])
{
    if (!CheckAppRate(playerid, APP_RATE_MS)) return 1;

    new action[32], rest[128];
    SplitFirst(params, action, sizeof action, rest, sizeof rest);

    if (IsEmpty(action) || !strcmp(action, "sync", true))
    {
        SendFullAppSync(playerid);
        return 1;
    }
    if (!strcmp(action, "ping", true))
    {
        SendAppEvent(playerid, "pong", "{\"ok\":true}");
        return 1;
    }
    if (!strcmp(action, "inv", true) || !strcmp(action, "inventory", true))
    {
        SendInventorySync(playerid);
        return 1;
    }
    if (!strcmp(action, "useitem", true))
    {
        if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;
        UseInventorySlot(playerid, strval(rest));
        return 1;
    }
    if (!strcmp(action, "phone", true))
    {
        SendPhoneSync(playerid);
        return 1;
    }
    if (!strcmp(action, "phone_send", true))
    {
        if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;
        HandlePhoneSend(playerid, rest);
        return 1;
    }
    if (!strcmp(action, "orgmembers", true) || !strcmp(action, "org", true))
    {
        SendOrgMembersSync(playerid);
        return 1;
    }
    if (!strcmp(action, "orgchat", true))
    {
        if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;
        HandleOrgChat(playerid, rest);
        return 1;
    }
    if (!strcmp(action, "ak", true))
    {
        if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;
        GiveServerWeapon(playerid, 30, 250);
        SendInventorySync(playerid);
        SendAppToast(playerid, "ok", "AK-47 liberada pelo servidor.");
        return 1;
    }
    if (!strcmp(action, "lock", true) || !strcmp(action, "trancar", true))
    {
        HandleAppVehicleLockCommand(playerid);
        return 1;
    }

    SendAppToast(playerid, "error", "Acao /app desconhecida.");
    return 1;
}

// ============================================================
// Sistema de cabelo
// ============================================================

stock HandleHairCommand(playerid, const params[])
{
    if (IsEmpty(params))
    {
        SendClientMessage(playerid, COLOR_WARN, "Uso: /cabelo [cor]");
        SendClientMessage(playerid, COLOR_INFO, "Cores: blond, red, black, blue, green, pink, bald, default");
        SendClientMessage(playerid, COLOR_INFO, "Em portugues: loiro, vermelho, preto, azul, verde, rosa, careca, normal");
        return 1;
    }
    if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;

    new colorId = GetHairColorId(params);
    if (colorId == -1)
    {
        SendClientMessage(playerid, COLOR_ERROR, "Cor invalida. Use: blond, red, black, blue, green, pink, bald, default");
        SendAppToast(playerid, "error", "Cor de cabelo invalida.");
        return 1;
    }

    ApplyPlayerHair(playerid, colorId);

    new colorName[16], msg[80];
    GetHairColorName(colorId, colorName, sizeof colorName);
    format(msg, sizeof msg, "Cabelo alterado para: %s", colorName);
    SendClientMessage(playerid, COLOR_INFO, msg);
    SendAppToast(playerid, "ok", msg);
    SendHairSync(playerid);
    printf("[Hair] player=%d colorId=%d (%s)", playerid, colorId, colorName);
    return 1;
}

stock GetHairColorId(const name[])
{
    if (!strcmp(name, "blond", true)   || !strcmp(name, "loiro", true))     return HAIR_COLOR_BLOND;
    if (!strcmp(name, "red", true)     || !strcmp(name, "vermelho", true))   return HAIR_COLOR_RED;
    if (!strcmp(name, "black", true)   || !strcmp(name, "preto", true))      return HAIR_COLOR_BLACK;
    if (!strcmp(name, "blue", true)    || !strcmp(name, "azul", true))       return HAIR_COLOR_BLUE;
    if (!strcmp(name, "green", true)   || !strcmp(name, "verde", true))      return HAIR_COLOR_GREEN;
    if (!strcmp(name, "pink", true)    || !strcmp(name, "rosa", true))       return HAIR_COLOR_PINK;
    if (!strcmp(name, "bald", true)    || !strcmp(name, "careca", true))     return HAIR_COLOR_BALD;
    if (!strcmp(name, "default", true) || !strcmp(name, "normal", true))     return HAIR_COLOR_DEFAULT;
    return -1;
}

stock GetHairColorName(colorId, dest[], size)
{
    switch (colorId)
    {
        case HAIR_COLOR_BLOND:   format(dest, size, "Loiro");
        case HAIR_COLOR_RED:     format(dest, size, "Vermelho");
        case HAIR_COLOR_BLACK:   format(dest, size, "Preto");
        case HAIR_COLOR_BLUE:    format(dest, size, "Azul");
        case HAIR_COLOR_GREEN:   format(dest, size, "Verde");
        case HAIR_COLOR_PINK:    format(dest, size, "Rosa");
        case HAIR_COLOR_BALD:    format(dest, size, "Careca");
        default:                 format(dest, size, "Normal");
    }
    return 1;
}

stock GetHairARGB(colorId)
{
    // Retorna cor ARGB para colorir o objeto de cabelo
    new argbResult;
    switch (colorId)
    {
        case HAIR_COLOR_BLOND:  argbResult = 0xFFD4A017; // loiro dourado
        case HAIR_COLOR_RED:    argbResult = 0xFFAA1111; // vermelho escuro
        case HAIR_COLOR_BLACK:  argbResult = 0xFF111111; // preto
        case HAIR_COLOR_BLUE:   argbResult = 0xFF2244EE; // azul
        case HAIR_COLOR_GREEN:  argbResult = 0xFF228B22; // verde
        case HAIR_COLOR_PINK:   argbResult = 0xFFFF69B4; // rosa
        default:                argbResult = 0xFF8B5E3C; // castanho (default)
    }
    return argbResult;
}

/*
    ApplyPlayerHair — aplica a cor de cabelo via SetPlayerAttachedObject.
    Modelo 19054: cabelo curto do GTA SA que existe nos arquivos do cliente Android.
    Bone 1 = cabeca. Offset/rot/scale calibrados para ficar sobre a cabeca.
*/
stock ApplyPlayerHair(playerid, colorId)
{
    gPlayerHairColor[playerid] = colorId;

    // Remove objeto de cabelo anterior se existir
    if (IsPlayerAttachedObjectSlotUsed(playerid, HAIR_SLOT))
        RemovePlayerAttachedObject(playerid, HAIR_SLOT);

    // Careca = sem objeto (apenas remove)
    if (colorId == HAIR_COLOR_BALD) return 1;

    // Para colorId DEFAULT: nao aplica objeto extra (cabelo nativo do skin)
    if (colorId == HAIR_COLOR_DEFAULT) return 1;

    new argb = GetHairARGB(colorId);

    // Modelo 19054: cabelo curto/afro do GTA SA — existe no cliente Android
    // Bone 1 (cabeca), posicao ligeiramente acima do centro da cabeca
    SetPlayerAttachedObject(
        playerid,
        HAIR_SLOT,        // slot 9
        19054,            // modelid: cabelo curto GTA SA
        HAIR_BONE_HEAD,   // bone 1 = cabeca
        0.00, 0.00, 0.06, // offset X Y Z (acima da cabeca)
        0.00, 0.00, 0.00, // rot X Y Z
        1.00, 1.00, 1.00, // scale
        argb,             // cor material 1 (cor do cabelo)
        0x00000000        // cor material 2 (transparente)
    );
    return 1;
}

// ============================================================

stock HandleSkinCommand(playerid, const params[])
{
    if (IsEmpty(params))
    {
        SendClientMessage(playerid, COLOR_WARN, "Uso: /skin [0-311]. Exemplo: /skin 29");
        SendAppToast(playerid, "warn", "Use /skin 0-311.");
        return 1;
    }
    if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;

    new skinid = strval(params);
    if (!IsValidSkinId(skinid))
    {
        SendClientMessage(playerid, COLOR_ERROR, "Skin invalida. Use um ID entre 0 e 311, menos 74.");
        SendAppToast(playerid, "error", "Skin invalida.");
        return 1;
    }

    ApplyPlayerSkinSafely(playerid, skinid);
    printf("[AppSync] %d trocou skin para %d.", playerid, skinid);

    new msg[96];
    format(msg, sizeof msg, "Skin alterada pelo servidor para ID %d.", skinid);
    SendClientMessage(playerid, COLOR_INFO, msg);
    SendAppToast(playerid, "ok", "Skin alterada pelo servidor.");
    return 1;
}

stock ApplyPlayerSkinSafely(playerid, skinid)
{
    new Float:x, Float:y, Float:z, Float:a;
    new Float:health, Float:armour;
    new interior = GetPlayerInterior(playerid);
    new world = GetPlayerVirtualWorld(playerid);

    GetPlayerPos(playerid, x, y, z);
    GetPlayerFacingAngle(playerid, a);
    GetPlayerHealth(playerid, health);
    GetPlayerArmour(playerid, armour);

    if (IsPlayerInAnyVehicle(playerid))
    {
        RemovePlayerFromVehicle(playerid);
    }

    gPlayerSkin[playerid] = skinid;
    SetPlayerSkin(playerid, skinid);
    SetPlayerInterior(playerid, interior);
    SetPlayerVirtualWorld(playerid, world);
    SetPlayerPos(playerid, x, y, z);
    SetPlayerFacingAngle(playerid, a);
    SetPlayerHealth(playerid, health);
    SetPlayerArmour(playerid, armour);
    RestoreAuthorizedWeapons(playerid);
    ApplyWorldSettingsToPlayer(playerid);
    return 1;
}

stock bool:IsPlayerNearOwnedVehicle(playerid, vehicleid, Float:maxDistance)
{
    new Float:px, Float:py, Float:pz;
    new Float:vx, Float:vy, Float:vz;
    GetPlayerPos(playerid, px, py, pz);
    GetVehiclePos(vehicleid, vx, vy, vz);

    new Float:dx = px - vx;
    new Float:dy = py - vy;
    new Float:dz = pz - vz;
    return ((dx * dx) + (dy * dy) + (dz * dz)) <= (maxDistance * maxDistance);
}

stock SendVehicleLockSync(playerid, vehicleid, bool:locked)
{
    new payload[96];
    format(payload, sizeof payload, "{\"vehicle\":%d,\"locked\":%d}", vehicleid, locked ? 1 : 0);
    SendAppEvent(playerid, "lock", payload);
    return 1;
}

stock HandleAppVehicleLockCommand(playerid)
{
    if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;

    new vehicleid = gPlayerSpawnedVehicle[playerid];
    if (vehicleid == INVALID_VEHICLE_ID || GetVehicleModel(vehicleid) == 0)
    {
        gPlayerSpawnedVehicle[playerid] = INVALID_VEHICLE_ID;
        gPlayerVehicleLocked[playerid] = false;
        SendVehicleLockSync(playerid, INVALID_VEHICLE_ID, false);
        SendAppToast(playerid, "error", "Nenhum veiculo seu para trancar.");
        return 1;
    }

    if (IsPlayerInAnyVehicle(playerid) && !IsPlayerInVehicle(playerid, vehicleid))
    {
        SendAppToast(playerid, "error", "Voce so pode trancar o seu veiculo.");
        return 1;
    }

    if (!IsPlayerInVehicle(playerid, vehicleid) && !IsPlayerNearOwnedVehicle(playerid, vehicleid, VEHICLE_LOCK_DISTANCE))
    {
        SendAppToast(playerid, "warn", "Chegue perto do seu veiculo.");
        return 1;
    }

    new engine, lights, alarm, doors, bonnet, boot, objective;
    GetVehicleParamsEx(vehicleid, engine, lights, alarm, doors, bonnet, boot, objective);

    gPlayerVehicleLocked[playerid] = !gPlayerVehicleLocked[playerid];
    new doorState = gPlayerVehicleLocked[playerid] ? 1 : 0;
    SetVehicleParamsEx(vehicleid, engine, lights, alarm, doorState, bonnet, boot, objective);
    SendVehicleLockSync(playerid, vehicleid, gPlayerVehicleLocked[playerid]);

    if (gPlayerVehicleLocked[playerid])
    {
        SendAppToast(playerid, "ok", "Veiculo trancado.");
    }
    else
    {
        SendAppToast(playerid, "ok", "Veiculo destrancado.");
    }

    printf("[AppSync][veh-lock] player=%d vehicle=%d locked=%d", playerid, vehicleid, doorState);
    return 1;
}

stock HandleVehicleCommand(playerid, const params[])
{
    if (!CheckAppRate(playerid, APP_ACTION_RATE_MS, true)) return 1;

    new modelid = IsEmpty(params) ? 560 : strval(params);
    if (!IsValidVehicleModelId(modelid))
    {
        SendClientMessage(playerid, COLOR_ERROR, "Veiculo invalido. Use modelo 400-611. Exemplo: /veiculo 411");
        SendAppToast(playerid, "error", "Modelo de veiculo invalido.");
        return 1;
    }
    if (IsBlockedMobileVehicleModelId(modelid))
    {
        SendClientMessage(playerid, COLOR_ERROR, "Veiculo 534 bloqueado: esse modelo causa crash no cliente mobile.");
        SendAppToast(playerid, "error", "Veiculo 534 bloqueado no mobile.");
        return 1;
    }

    new bool:recentlyDetached = false;
    new now = GetTickCount();
    if (gLastVehicleDetachTick[playerid] != 0 && now - gLastVehicleDetachTick[playerid] < VEHICLE_SPAWN_AFTER_DETACH_MS)
    {
        recentlyDetached = true;
    }
    if (IsPlayerInAnyVehicle(playerid) || gPlayerSpawnedVehicle[playerid] != INVALID_VEHICLE_ID || recentlyDetached)
    {
        QueueDestroySpawnedVeh(playerid, VEHICLE_DESTROY_DELAY_MS);
        gPendingVehicleModel[playerid] = modelid;
        new spawnCallback[] = "CreatePlayerVehicleLater";
        SetTimerEx(spawnCallback, VEHICLE_SPAWN_AFTER_DETACH_MS, false, "ii", playerid, modelid);
        SendClientMessage(playerid, COLOR_INFO, "Preparando troca segura de veiculo...");
        return 1;
    }

    return SpawnPlayerVehicleNow(playerid, modelid);
}

stock SpawnPlayerVehicleNow(playerid, modelid)
{
    new Float:x, Float:y, Float:z, Float:a;
    GetPlayerPos(playerid, x, y, z);
    GetPlayerFacingAngle(playerid, a);

    new Float:distance = modelid == VEHICLE_MODEL_RHINO ? 14.0 : 8.0;
    new Float:spawnZ = modelid == VEHICLE_MODEL_RHINO ? z + 1.5 : z + 0.8;
    new Float:spawnX = x + floatsin(-a, degrees) * distance;
    new Float:spawnY = y + floatcos(-a, degrees) * distance;
    new color1 = modelid == VEHICLE_MODEL_RHINO ? 43 : -1;
    new color2 = modelid == VEHICLE_MODEL_RHINO ? 0 : -1;

    new vehicleid = CreateVehicle(modelid, spawnX, spawnY, spawnZ, a, color1, color2, VEHICLE_RESPAWN_TIME);
    printf("[AppSync][veh-test] player=%d model=%d base=%.2f %.2f %.2f angle=%.2f spawn=%.2f %.2f %.2f", playerid, modelid, x, y, z, a, spawnX, spawnY, spawnZ);
    if (vehicleid == INVALID_VEHICLE_ID)
    {
        SendClientMessage(playerid, COLOR_ERROR, "Servidor nao conseguiu criar o veiculo agora.");
        SendAppToast(playerid, "error", "Falha criando veiculo.");
        return 1;
    }

    gPlayerSpawnedVehicle[playerid] = vehicleid;
    gPlayerVehicleLocked[playerid] = false;
    LinkVehicleToInterior(vehicleid, GetPlayerInterior(playerid));
    SetVehicleVirtualWorld(vehicleid, GetPlayerVirtualWorld(playerid));
    SetVehicleHealth(vehicleid, 1000.0);
    RepairVehicle(vehicleid);
    SetVehicleParamsEx(vehicleid, 1, 0, 0, gPlayerVehicleLocked[playerid] ? 1 : 0, 0, 0, 0);
    PutPlayerInVehicle(playerid, vehicleid, 0);
    new resyncCallback[] = "ResyncSpawnedVehicle";
    SetTimerEx(resyncCallback, 250, false, "ii", vehicleid, playerid);

    new msg[112];
    format(msg, sizeof msg, "Veiculo modelo %d criado pelo servidor. Use /veiculo [400-611] ou /tank.", modelid);
    SendClientMessage(playerid, COLOR_INFO, msg);
    SendAppToast(playerid, "ok", "Veiculo criado pelo servidor.");
    return 1;
}

public CreatePlayerVehicleLater(playerid, modelid)
{
    if (!IsPlayerConnected(playerid) || gPendingVehicleModel[playerid] != modelid)
    {
        return 1;
    }
    gPendingVehicleModel[playerid] = 0;
    SpawnPlayerVehicleNow(playerid, modelid);
    return 1;
}

public ResyncSpawnedVehicle(vehicleid, playerid)
{
    if (vehicleid == INVALID_VEHICLE_ID || GetVehicleModel(vehicleid) == 0)
    {
        return 1;
    }

    SetVehicleHealth(vehicleid, 1000.0);
    RepairVehicle(vehicleid);
    SetVehicleParamsEx(vehicleid, 1, 0, 0, gPlayerVehicleLocked[playerid] ? 1 : 0, 0, 0, 0);

    if (IsPlayerConnected(playerid) && gPlayerSpawnedVehicle[playerid] == vehicleid)
    {
        LinkVehicleToInterior(vehicleid, GetPlayerInterior(playerid));
        SetVehicleVirtualWorld(vehicleid, GetPlayerVirtualWorld(playerid));
        if (!IsPlayerInVehicle(playerid, vehicleid))
        {
            PutPlayerInVehicle(playerid, vehicleid, 0);
        }
    }
    return 1;
}

public DestroyVehicleLater(vehicleid)
{
    if (vehicleid != INVALID_VEHICLE_ID && GetVehicleModel(vehicleid) != 0)
    {
        DestroyVehicle(vehicleid);
        printf("[AppSync][veh-cleanup] delayed-destroy vehicle=%d", vehicleid);
    }
    return 1;
}

public PollWorldConfig()
{
    if (!fexist(WORLD_CONFIG_FILE)) return 1;

    new File:file = fopen(WORLD_CONFIG_FILE, io_read);
    if (!file) return 1;

    new line[96], key[32], value[64];
    new revision = gWorldRevision;
    new weather = gWorldWeather;
    new hour = gWorldHour;
    new minute = gWorldMinute;
    new freeze = gWorldFreezeTime ? 1 : 0;

    while (fread(file, line, sizeof line))
    {
        if (!ParseConfigLine(line, key, sizeof key, value, sizeof value)) continue;
        if (!strcmp(key, "revision", true)) revision = strval(value);
        else if (!strcmp(key, "weather", true)) weather = strval(value);
        else if (!strcmp(key, "hour", true)) hour = strval(value);
        else if (!strcmp(key, "minute", true)) minute = strval(value);
        else if (!strcmp(key, "freeze", true)) freeze = strval(value);
    }
    fclose(file);

    if (revision != gWorldRevision)
    {
        gWorldRevision = revision;
        gWorldWeather = ClampInt(weather, 0, 255);
        gWorldHour = ClampInt(hour, 0, 23);
        gWorldMinute = ClampInt(minute, 0, 59);
        gWorldFreezeTime = freeze != 0;
        ApplyWorldSettingsToAll("servidor");
    }
    return 1;
}

stock HandleWeatherCommand(playerid, const params[])
{
    if (IsEmpty(params))
    {
        SendClientMessage(playerid, COLOR_WARN, "Uso: /clima [0-255]. Exemplos: /clima 0, /clima 8, /clima 19.");
        return 1;
    }

    new weather = strval(params);
    if (weather < 0 || weather > 255)
    {
        SendClientMessage(playerid, COLOR_ERROR, "Clima invalido. Use um ID entre 0 e 255.");
        return 1;
    }

    gWorldRevision++;
    gWorldWeather = weather;
    ApplyWorldSettingsToAll("comando");
    return 1;
}

stock HandleTimeCommand(playerid, const params[])
{
    if (IsEmpty(params))
    {
        SendClientMessage(playerid, COLOR_WARN, "Uso: /hora [0-23] [minuto]. Exemplos: /hora 12, /hora 21 30.");
        return 1;
    }

    new hourText[12], minuteText[12];
    SplitFirst(params, hourText, sizeof hourText, minuteText, sizeof minuteText);
    new hour = strval(hourText);
    new minute = IsEmpty(minuteText) ? 0 : strval(minuteText);

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
    {
        SendClientMessage(playerid, COLOR_ERROR, "Horario invalido. Hora 0-23, minuto 0-59.");
        return 1;
    }

    gWorldRevision++;
    gWorldHour = hour;
    gWorldMinute = minute;
    gWorldFreezeTime = true;
    ApplyWorldSettingsToAll("comando");
    return 1;
}

stock ApplyWorldSettingsToAll(const source[])
{
    SetWeather(gWorldWeather);
    SetWorldTime(gWorldHour);

    for (new playerid = 0; playerid < MAX_PLAYERS; playerid++)
    {
        if (IsPlayerConnected(playerid))
        {
            ApplyWorldSettingsToPlayer(playerid);
            SendWorldSettingsMessage(playerid, source);
        }
    }
    return 1;
}

stock ApplyWorldVisualFromSource(playerid, const source[])
{
    #pragma unused playerid
    return ApplyWorldSettingsToAll(source);
}

stock ApplyWorldSettingsToPlayer(playerid)
{
    SetPlayerWeather(playerid, gWorldWeather);
    SetPlayerTime(playerid, gWorldHour, gWorldMinute);
    TogglePlayerClock(playerid, gWorldFreezeTime ? 1 : 0);
    return 1;
}

stock SendWorldSettingsMessage(playerid, const source[])
{
    new weatherName[40], timeName[24], msg[144];
    GetWeatherName(gWorldWeather, weatherName, sizeof weatherName);
    GetTimeName(gWorldHour, timeName, sizeof timeName);
    format(msg, sizeof msg, "[Servidor] Clima: %s (%d). Horario: %02d:%02d (%s). Origem: %s.",
        weatherName,
        gWorldWeather,
        gWorldHour,
        gWorldMinute,
        timeName,
        source);
    SendClientMessage(playerid, COLOR_INFO, msg);
    return 1;
}

stock ParseConfigLine(const line[], key[], keySize, value[], valueSize)
{
    new equals = strfind(line, "=", false);
    if (equals <= 0) return 0;

    new end = strlen(line);
    while (end > equals + 1 && (line[end - 1] == '\r' || line[end - 1] == '\n' || line[end - 1] == ' ')) end--;

    strmid(key, line, 0, equals, keySize);
    strmid(value, line, equals + 1, end, valueSize);
    return 1;
}

stock ClampInt(value, minValue, maxValue)
{
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
}

stock GetWeatherName(weather, dest[], size)
{
    switch (weather)
    {
        case 0, 1, 5, 6, 10, 11, 13, 14, 17, 18, 21, 22, 23, 37, 38, 40:
            format(dest, size, "Ensolarado");
        case 4, 7, 12, 15, 31, 36, 39, 42:
            format(dest, size, "Nublado");
        case 8, 16, 29, 32:
            format(dest, size, "Chuva");
        case 9, 26, 27, 28, 33:
            format(dest, size, "Neblina");
        case 19:
            format(dest, size, "Tempestade de areia");
        case 24, 25, 43:
            format(dest, size, "Entardecer");
        case 30, 44, 45:
            format(dest, size, "Noite");
        default:
            format(dest, size, "Clima custom");
    }
    return 1;
}

stock GetTimeName(hour, dest[], size)
{
    if (hour >= 5 && hour < 8) format(dest, size, "Amanhecer");
    else if (hour >= 8 && hour < 12) format(dest, size, "Manha");
    else if (hour >= 12 && hour < 18) format(dest, size, "Tarde");
    else if (hour >= 18 && hour < 21) format(dest, size, "Entardecer");
    else if (hour >= 21 || hour < 2) format(dest, size, "Noite");
    else format(dest, size, "Madrugada");
    return 1;
}

stock IsValidSkinId(skinid)
{
    return skinid >= 0 && skinid <= 311 && skinid != 74;
}

stock IsValidVehicleModelId(modelid)
{
    return modelid >= 400 && modelid <= 611;
}

stock IsBlockedMobileVehicleModelId(modelid)
{
    return modelid == VEHICLE_MODEL_REMINGTON;
}

stock DestroyPlayerSpawnedVehicle(playerid)
{
    return QueueDestroySpawnedVeh(playerid, 0);
}

stock QueueDestroySpawnedVeh(playerid, delayMs)
{
    new vehicleid = gPlayerSpawnedVehicle[playerid];
    if (vehicleid != INVALID_VEHICLE_ID)
    {
        gPlayerSpawnedVehicle[playerid] = INVALID_VEHICLE_ID;
        gPlayerVehicleLocked[playerid] = false;
        if (IsPlayerConnected(playerid))
        {
            SendVehicleLockSync(playerid, INVALID_VEHICLE_ID, false);
        }
        if (IsPlayerConnected(playerid) && IsPlayerInVehicle(playerid, vehicleid))
        {
            RemovePlayerFromVehicle(playerid);
            gLastVehicleDetachTick[playerid] = GetTickCount();
        }

        if (delayMs > 0)
        {
            new cleanupCallback[] = "DestroyVehicleLater";
            SetTimerEx(cleanupCallback, delayMs, false, "i", vehicleid);
        }
        else if (GetVehicleModel(vehicleid) != 0)
        {
            DestroyVehicle(vehicleid);
        }
    }
    return 1;
}

stock SendFullAppSync(playerid)
{
    SendInventorySync(playerid);
    SendPhoneSync(playerid);
    SendOrgMembersSync(playerid);
    SendHairSync(playerid);
    SendVehicleLockSync(playerid, gPlayerSpawnedVehicle[playerid], gPlayerVehicleLocked[playerid]);
    SendAppToast(playerid, "ok", "Dados sincronizados pelo servidor.");
}

stock SendHairSync(playerid)
{
    new colorName[16], payload[80];
    GetHairColorName(gPlayerHairColor[playerid], colorName, sizeof colorName);
    format(payload, sizeof payload, "{\"colorId\":%d,\"colorName\":\"%s\"}",
        gPlayerHairColor[playerid], colorName);
    SendAppEvent(playerid, "hair.sync", payload);
}

stock SendInventorySync(playerid)
{
    SendNativeInventorySlots(playerid);

    new payload[900], part[128], itemName[32];
    format(payload, sizeof payload, "{\"cash\":%d,\"slots\":[", gPlayerCash[playerid]);

    for (new slot = 0; slot < MAX_INV_SLOTS; slot++)
    {
        GetItemName(gInventoryItem[playerid][slot], itemName, sizeof itemName);
        format(part, sizeof part, "%s{\"slot\":%d,\"id\":%d,\"name\":\"%s\",\"amount\":%d,\"usable\":%d}",
            slot == 0 ? "" : ",",
            slot,
            gInventoryItem[playerid][slot],
            itemName,
            gInventoryAmount[playerid][slot],
            IsUsableItem(gInventoryItem[playerid][slot]));
        strcat(payload, part, sizeof payload);
    }
    strcat(payload, "]}", sizeof payload);
    SendAppEvent(playerid, "inventory.update", payload);
}

stock SendNativeInventorySlots(playerid)
{
    new line[180], itemName[32], safeName[40];

    format(line, sizeof line, "APP|inventory.reset|{\"cash\":%d}", gPlayerCash[playerid]);
    SendClientMessage(playerid, APP_COLOR, line);

    for (new slot = 0; slot < MAX_INV_SLOTS; slot++)
    {
        GetItemName(gInventoryItem[playerid][slot], itemName, sizeof itemName);
        JsonSafe(itemName, safeName, sizeof safeName);

        format(line, sizeof line,
            "APP|inventory.slot|{\"slot\":%d,\"id\":%d,\"name\":\"%s\",\"amount\":%d,\"usable\":%d}",
            slot,
            gInventoryItem[playerid][slot],
            safeName,
            gInventoryAmount[playerid][slot],
            IsUsableItem(gInventoryItem[playerid][slot]));

        SendClientMessage(playerid, APP_COLOR, line);
    }
    return 1;
}

stock SendPhoneSync(playerid)
{
    new payload[1200], part[128], name[MAX_PLAYER_NAME], safeName[MAX_PLAYER_NAME + 8];
    format(payload, sizeof payload, "{\"number\":%d,\"contacts\":[", gPlayerPhoneNumber[playerid]);

    new count;
    for (new id = 0; id < MAX_PLAYERS && count < 12; id++)
    {
        if (!IsPlayerConnected(id) || id == playerid) continue;
        GetPlayerName(id, name, sizeof name);
        JsonSafe(name, safeName, sizeof safeName);
        format(part, sizeof part, "%s{\"id\":%d,\"name\":\"%s\",\"number\":%d}",
            count == 0 ? "" : ",",
            id,
            safeName,
            gPlayerPhoneNumber[id]);
        strcat(payload, part, sizeof payload);
        count++;
    }
    strcat(payload, "]}", sizeof payload);
    SendAppEvent(playerid, "phone.update", payload);
}

stock SendOrgMembersSync(playerid)
{
    new payload[1400], part[144], name[MAX_PLAYER_NAME], safeName[MAX_PLAYER_NAME + 8], rankName[24];
    new orgName[32];
    GetOrgName(gPlayerOrg[playerid], orgName, sizeof orgName);
    format(payload, sizeof payload, "{\"orgId\":%d,\"orgName\":\"%s\",\"members\":[",
        gPlayerOrg[playerid],
        orgName);

    new count;
    for (new id = 0; id < MAX_PLAYERS && count < 16; id++)
    {
        if (!IsPlayerConnected(id) || gPlayerOrg[id] != gPlayerOrg[playerid]) continue;
        GetPlayerName(id, name, sizeof name);
        JsonSafe(name, safeName, sizeof safeName);
        GetRankName(gPlayerRank[id], rankName, sizeof rankName);
        format(part, sizeof part, "%s{\"id\":%d,\"name\":\"%s\",\"rank\":%d,\"rankName\":\"%s\",\"online\":true}",
            count == 0 ? "" : ",",
            id,
            safeName,
            gPlayerRank[id],
            rankName);
        strcat(payload, part, sizeof payload);
        count++;
    }
    strcat(payload, "]}", sizeof payload);
    SendAppEvent(playerid, "org.members", payload);
}

stock UseInventorySlot(playerid, slot)
{
    if (slot < 0 || slot >= MAX_INV_SLOTS)
    {
        SendAppToast(playerid, "error", "Slot invalido.");
        return 0;
    }

    new itemid = gInventoryItem[playerid][slot];
    new amount = gInventoryAmount[playerid][slot];
    if (itemid == ITEM_NONE || amount <= 0)
    {
        SendAppToast(playerid, "error", "Nao existe item neste slot.");
        return 0;
    }

    if (itemid == ITEM_MEDKIT)
    {
        new Float:health;
        GetPlayerHealth(playerid, health);
        if (health >= 95.0)
        {
            SendAppToast(playerid, "warn", "Sua vida ja esta cheia.");
            return 0;
        }
        SetPlayerHealth(playerid, 100.0);
        DecrementInventorySlot(playerid, slot, 1);
        SendClientMessage(playerid, COLOR_INFO, "Voce usou um kit medico.");
        SendAppToast(playerid, "ok", "Kit medico usado.");
        SendInventorySync(playerid);
        return 1;
    }
    if (itemid == ITEM_PHONE)
    {
        SendPhoneSync(playerid);
        SendAppToast(playerid, "ok", "Celular aberto.");
        return 1;
    }
    if (itemid == ITEM_RADIO)
    {
        SendOrgMembersSync(playerid);
        SendAppToast(playerid, "ok", "Radio sincronizado com a organizacao.");
        return 1;
    }
    if (itemid == ITEM_WATER)
    {
        DecrementInventorySlot(playerid, slot, 1);
        SendClientMessage(playerid, COLOR_INFO, "Voce bebeu agua.");
        SendAppToast(playerid, "ok", "Agua usada.");
        SendInventorySync(playerid);
        return 1;
    }

    SendAppToast(playerid, "error", "Este item nao tem uso implementado.");
    return 0;
}

stock HandlePhoneSend(playerid, const rest[])
{
    new numberText[16], rawMessage[96], safeMessage[128], senderName[MAX_PLAYER_NAME], safeName[MAX_PLAYER_NAME + 8];
    SplitFirst(rest, numberText, sizeof numberText, rawMessage, sizeof rawMessage);

    if (IsEmpty(numberText) || IsEmpty(rawMessage))
    {
        SendAppToast(playerid, "error", "Uso: /app phone_send numero mensagem");
        return 0;
    }

    new target = FindPlayerByPhone(strval(numberText));
    if (target == INVALID_PLAYER_ID)
    {
        SendAppToast(playerid, "error", "Numero offline ou inexistente.");
        return 0;
    }

    JsonSafe(rawMessage, safeMessage, sizeof safeMessage);
    GetPlayerName(playerid, senderName, sizeof senderName);
    JsonSafe(senderName, safeName, sizeof safeName);

    new payload[220];
    format(payload, sizeof payload, "{\"fromNumber\":%d,\"fromName\":\"%s\",\"text\":\"%s\"}",
        gPlayerPhoneNumber[playerid],
        safeName,
        safeMessage);
    SendAppEvent(target, "phone.message", payload);
    SendAppToast(playerid, "ok", "Mensagem enviada.");
    SendClientMessage(target, COLOR_INFO, "Voce recebeu uma mensagem no celular.");
    return 1;
}

stock HandleOrgChat(playerid, const text[])
{
    if (IsEmpty(text))
    {
        SendAppToast(playerid, "error", "Uso: /app orgchat mensagem");
        return 0;
    }

    new name[MAX_PLAYER_NAME], safeName[MAX_PLAYER_NAME + 8], safeText[128], payload[260];
    GetPlayerName(playerid, name, sizeof name);
    JsonSafe(name, safeName, sizeof safeName);
    JsonSafe(text, safeText, sizeof safeText);

    format(payload, sizeof payload, "{\"from\":%d,\"name\":\"%s\",\"text\":\"%s\"}", playerid, safeName, safeText);
    for (new id = 0; id < MAX_PLAYERS; id++)
    {
        if (!IsPlayerConnected(id) || gPlayerOrg[id] != gPlayerOrg[playerid]) continue;
        SendAppEvent(id, "org.chat", payload);
    }
    SendAppToast(playerid, "ok", "Mensagem enviada para a organizacao.");
    return 1;
}

stock SendAppToast(playerid, const level[], const text[])
{
    new safeText[128], payload[180];
    JsonSafe(text, safeText, sizeof safeText);
    format(payload, sizeof payload, "{\"level\":\"%s\",\"text\":\"%s\"}", level, safeText);
    SendAppEvent(playerid, "toast", payload);
}

stock SendAppEvent(playerid, const eventName[], const payload[])
{
    new len = strlen(payload);
    new line[180];

    if (len + strlen(eventName) + 6 < 136)
    {
        format(line, sizeof line, "APP|%s|%s", eventName, payload);
        SendClientMessage(playerid, APP_COLOR, line);
        return 1;
    }

    new total = (len + APP_CHUNK_SIZE - 1) / APP_CHUNK_SIZE;
    new segment[APP_CHUNK_SIZE + 4];
    for (new part = 0, offset = 0; part < total; part++, offset += APP_CHUNK_SIZE)
    {
        strmid(segment, payload, offset, min(offset + APP_CHUNK_SIZE, len), sizeof segment);
        format(line, sizeof line, "APPCHUNK|%s|%d|%d|%s", eventName, part + 1, total, segment);
        SendClientMessage(playerid, APP_COLOR, line);
    }
    return 1;
}

stock SetInventorySlot(playerid, slot, itemid, amount)
{
    if (slot < 0 || slot >= MAX_INV_SLOTS) return 0;
    gInventoryItem[playerid][slot] = itemid;
    gInventoryAmount[playerid][slot] = amount;
    if (amount <= 0)
    {
        gInventoryItem[playerid][slot] = ITEM_NONE;
        gInventoryAmount[playerid][slot] = 0;
    }
    return 1;
}

stock DecrementInventorySlot(playerid, slot, amount)
{
    if (slot < 0 || slot >= MAX_INV_SLOTS) return 0;
    gInventoryAmount[playerid][slot] -= amount;
    if (gInventoryAmount[playerid][slot] <= 0)
    {
        gInventoryItem[playerid][slot] = ITEM_NONE;
        gInventoryAmount[playerid][slot] = 0;
    }
    return 1;
}

stock SetServerMoney(playerid, amount)
{
    gPlayerCash[playerid] = amount;
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, gPlayerCash[playerid]);
}

stock GiveServerWeapon(playerid, weaponid, ammo)
{
    if (weaponid <= 0 || weaponid >= 47 || ammo <= 0) return 0;
    gAuthWeapon[playerid][weaponid] = true;
    gAuthWeaponAmmo[playerid][weaponid] = ammo;
    GivePlayerWeapon(playerid, weaponid, ammo);
    return 1;
}

stock RestoreAuthorizedWeapons(playerid)
{
    ResetPlayerWeapons(playerid);
    for (new weaponid = 1; weaponid < 47; weaponid++)
    {
        if (!gAuthWeapon[playerid][weaponid]) continue;
        GivePlayerWeapon(playerid, weaponid, gAuthWeaponAmmo[playerid][weaponid]);
    }
}

stock FindPlayerByPhone(number)
{
    for (new id = 0; id < MAX_PLAYERS; id++)
    {
        if (IsPlayerConnected(id) && gPlayerPhoneNumber[id] == number)
        {
            return id;
        }
    }
    return INVALID_PLAYER_ID;
}

stock SplitFirst(const text[], first[], firstSize, rest[], restSize)
{
    new len = strlen(text);
    new start;
    while (start < len && text[start] == ' ') start++;

    new pos = start;
    while (pos < len && text[pos] != ' ') pos++;

    strmid(first, text, start, pos, firstSize);
    while (pos < len && text[pos] == ' ') pos++;

    if (pos < len) strmid(rest, text, pos, len, restSize);
    else rest[0] = EOS;
    return 1;
}

stock IsEmpty(const text[])
{
    return text[0] == EOS;
}

stock JsonSafe(const input[], output[], outputSize)
{
    new out;
    for (new i = 0, len = strlen(input); i < len && out < outputSize - 1; i++)
    {
        switch (input[i])
        {
            case '"', '\\', '|':
            {
                output[out++] = ' ';
            }
            case '\r', '\n', '\t':
            {
                output[out++] = ' ';
            }
            default:
            {
                output[out++] = input[i];
            }
        }
    }
    output[out] = EOS;
    return 1;
}

stock GetItemName(itemid, dest[], size)
{
    switch (itemid)
    {
        case ITEM_MEDKIT: format(dest, size, "Kit medico");
        case ITEM_PHONE: format(dest, size, "Celular");
        case ITEM_RADIO: format(dest, size, "Radio");
        case ITEM_WATER: format(dest, size, "Agua");
        default: format(dest, size, "Vazio");
    }
    return 1;
}

stock IsUsableItem(itemid)
{
    switch (itemid)
    {
        case ITEM_MEDKIT, ITEM_PHONE, ITEM_RADIO, ITEM_WATER: return 1;
    }
    return 0;
}

stock GetOrgName(orgid, dest[], size)
{
    switch (orgid)
    {
        case ORG_POLICE: format(dest, size, "Policia");
        default: format(dest, size, "Civil");
    }
    return 1;
}

stock GetRankName(rank, dest[], size)
{
    switch (rank)
    {
        case 1: format(dest, size, "Recruta");
        case 2: format(dest, size, "Membro");
        case 3: format(dest, size, "Lider");
        default: format(dest, size, "Civil");
    }
    return 1;
}
