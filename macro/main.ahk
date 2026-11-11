#SingleInstance Off
#NoEnv
#Include %A_ScriptDir%\ahk\language.ahk
#Include %A_ScriptDir%\ahk\hotkeys.ahk
#Include %A_ScriptDir%\ahk\maps.ahk
#Include %A_ScriptDir%\ahk\map_ocr.ahk
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen
DetectHiddenWindows, On
SendMode, Input

; ---- Автоперезапуск: если старый экземпляр уже запущен — убиваем его ----
; #SingleInstance Force не перезагружает код, а лишь показывает старое окно.
; Поэтому вручную ищем старый процесс этого же скрипта и завершаем его,
; чтобы каждый запуск гарантированно загружал свежий код с диска.
DetectHiddenWindows, On
WinGet, thisHwnd, ID, ahk_class AutoHotkey
; Ищем другие окна AHK с тем же именем скрипта (A_ScriptName)
WinGet, id, List, ahk_class AutoHotkey
Loop, %id% {
    hwnd := id%A_Index%
    if (hwnd = thisHwnd)
        continue
    WinGetTitle, t, ahk_id %hwnd%
    if (t = A_ScriptName) {
        WinGet, otherPid, PID, ahk_id %hwnd%
        if (otherPid > 0) {
            Process, Close, %otherPid%
            Sleep, 300
        }
    }
}

; ===================== НАСТРОЙКИ =====================
WinTitle := "ahk_exe RobloxPlayerBeta.exe"
GameAreaW := 1280
GameAreaH := 720
SidebarW  := 320

MapsDir := A_ScriptDir . "\maps"
; Игровые режимы: у каждого своя папка карт внутри maps\.
GameModes := ["infinite", "raid", "summer"]
GameModeLabels := {infinite: "Infinite", raid: "Raid", summer: "Summer Event"}
GameMode := "infinite"

; ---- Распознавание названия карты (координаты игровой области) ----
; В этой области на экране загрузки находится только название карты.
DetectTitleX := 20
DetectTitleY := 55
DetectTitleW := 1100
DetectTitleH := 75
OcrScriptPath := A_ScriptDir . "\ocr_title.ps1"
OcrCapturePath := A_Temp . "\mmacro_title_ocr.bmp"
DetectTitleTolerance := 30   ; допуск сравнения по каждому каналу (0-255)
DetectTitleThreshold := 85   ; минимальный % совпадения, чтобы считать карту определённой
DetectTitleCaptureThreshold := 60 ; порог автоподстановки карты при захвате; для определения в UI остаётся 85
DetectTitleRoam := 20        ; на сколько пикселей искать заголовок вокруг сохранённой точки
DetectTitleCoarseStep := 4   ; шаг грубого прохода по этой области
DetectTitleFineRoam := 2     ; уточнение положения шагом 1 px (грубая сетка ±2 покрывает)
TitleCaptureMap := ""        ; карта, для которой сейчас снимается заголовок
TitleTemplates := []         ; кэш загруженных шаблонов заголовков
TitleTplPixels := ""       ; пиксели шаблона, который сравнивается сейчас
TitleTemplatesMode := ""     ; режим, для которого построен кэш
DetectBandBuf := ""          ; пиксели полосы кадра, где ищем заголовок
DetectBandW := 0
DetectBandH := 0
DetectBandStride := 0
LastDetectedMap := ""
LastDetectScore := 0
ImagesDir := A_ScriptDir . "\images"
LogoDir := A_ScriptDir . "\logo"
LogoIconFile := LogoDir . "\mmacro.ico"
ConfigFile := A_ScriptDir . "\config.ini"
SettingsFile := A_ScriptDir . "\ahk\settings.ini"
SecretsFile := A_ScriptDir . "\ahk\secrets.ini"   ; не коммитится: токен Discord-бота
PresetsIni := A_ScriptDir . "\ahk\presets.ini"
TempShot := A_ScriptDir . "\_preview.bmp"

; Иконка Mmacro для трея и ярлыка запуска.
if FileExist(LogoIconFile) {
    Menu, Tray, Icon, %LogoIconFile%
    Menu, Tray, Tip, Mmacro
}

; ---- Discord bot integration ----
BotDir := A_ScriptDir . "\..\bot"
BotRuntimeDir := BotDir . "\runtime"
BotCommandsDir := BotRuntimeDir . "\commands"
BotResponsesDir := BotRuntimeDir . "\responses"
BotActionsDir := BotDir . "\actions"
BotStateFile := BotRuntimeDir . "\state.ini"
BotScreenshotFile := BotRuntimeDir . "\discord_screenshot.bmp"
LastCaptureX := 0
LastCaptureY := 0
LastCaptureW := 1280
LastCaptureH := 720
BotPython := "pythonw.exe"
BotToken := ""
BotEnabled := false
BotAutoStart := false
BotGuildId := ""
BotAllowedUserIds := ""
BotProcessPid := 0
BotDepsLogFile := BotRuntimeDir . "\pip_install.log"
BotDepsScriptFile := BotRuntimeDir . "\install_bot_deps.ps1"
BotPythonPathFile := BotRuntimeDir . "\python_path.txt"
BotVenvDir := BotRuntimeDir . "\.venv"
BotVenvPythonFile := BotVenvDir . "\Scripts\python.exe"
BotLaunchScriptFile := BotRuntimeDir . "\start_bot.ps1"
BotLaunchErrorFile := BotRuntimeDir . "\bot_start_error.log"
BotLaunchOutputFile := BotRuntimeDir . "\bot_stdout.log"
BotRunning := false
PendingMapChange := ""
BotMapRecordActive := false
BotMapRecordMap := ""
BotMapRecordActions := []
BotMapRecordLastTime := 0
BotMapRecordLastX := 0
BotMapRecordLastY := 0
BotMapRecordPending := false
BotMapActions := []

IfNotExist, %BotRuntimeDir%
    FileCreateDir, %BotRuntimeDir%
IfNotExist, %BotCommandsDir%
    FileCreateDir, %BotCommandsDir%
IfNotExist, %BotResponsesDir%
    FileCreateDir, %BotResponsesDir%
IfNotExist, %BotActionsDir%
    FileCreateDir, %BotActionsDir%

; ---- Автообновление с GitHub ----
CURRENT_VERSION := "1.0.13"
GH_REPO := "mozrze/Mmacro"           ; пользователь/репозиторий
GH_TOKEN_FILE := A_ScriptDir . "\ahk\token.ini"
GH_TOKEN := ""
IniRead, GH_TOKEN, %GH_TOKEN_FILE%, GitHub, Token, ""
GH_API_URL := "https://api.github.com/repos/" . GH_REPO . "/releases/latest"
PendingUpdateURL := ""
PendingUpdateOldVer := ""
PendingUpdateNewVer := ""
IfNotExist, %MapsDir%
    FileCreateDir, %MapsDir%
IfNotExist, %ImagesDir%
    FileCreateDir, %ImagesDir%

MapList := []      ; Имена карт берутся из общего каталога, файлы карт — необязательны
MapCoords := {}   ; MapCoords[map] := [{num,x,y}, ...]

; Координаты кнопок (калибруются кликом по скриншоту)
UpgradeX := 0
UpgradeY := 0
AutoX := 0
AutoY := 0
StartGameX := 0
StartGameY := 0
RepeatStageX := 0
RepeatStageY := 0

; ---- настройки задержек (из ahk/settings.ini) ----
ClickDelay := 80
SlotClickDelay := 250
UpgradeClickDelay := 150
AutoClickDelay := 120
UnitSleepDelay := 200
StartGameDelay := 500
HoverDelay := 200   ; КД после наведения на место перед выбором юнита
MouseSpeed := 70    ; скорость движения мыши (0-100, выше = быстрее)
MouseSpeedEnabled := true ; плавное движение мыши
ZoomEnabled := false ; включать зум перед расстановкой юнитов
ZoomScrolls := 0    ; зум перед расстановкой: + приближение, - отдаление
TopCameraEnabled := false ; верхний ракурс перед обычным зумом
ImgVariation := 30
StartGameColor := 0x4ECD0C
StartGameColorVar := 30
StartGameCenterX := 640
StartGameCenterY := 500
StartGameRadius := 200

; ---- автоматический реконнект при вылете/ошибке игры ----
RejoinEnabled       := false
RejoinShareLink     := ""   ; полная ссылка вида https://www.roblox.com/share?code=...&type=Server
RejoinMaxAttempts   := 3
RejoinWaitTimeout   := 40   ; сек, сколько ждать появления окна Roblox после запуска ссылки
RejoinPostJoinDelay := 6    ; сек, пауза после появления окна перед продолжением фарма
RejoinPostActionsDelay := 3  ; сек, пауза после выполнения Post-Rejoin действий
BotMapPostActionsDelay := 3  ; сек, пауза после действий входа на карту через Discord

Running := false
FarmRunCount := 0
StartZoomApplied := false ; обычный зум уже применён в текущей фарм-сессии
Embedded := false
GameHwnd := 0
OrigStyle := 0
OrigExStyle := 0
OrigParent := 0
OrigMainStyle := 0
; Исходная позиция/размер Roblox для восстановления после отсоединения
OrigRX := 0
OrigRY := 0
OrigRW := 0
OrigRH := 0
; Автопрокачка юнитов: приоритет = сколько раз кликнуть по кнопке AutoUpgrade
AutoUpgradeEnabled := false
AutoUpgradePriority := {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1}
AutoUpgradeUnitOffsetY := 20   ; смещение вверх при клике по юниту

; Режим фарма: units = расстановка юнитов, autoplay = только AutoPlay.
; В AutoPlay-режиме шаблоны AutoPlayOff/AutoPlayOn проверяются постоянно,
; поэтому после перезапуска этапа кнопка снова будет включена автоматически.
FarmMode := "units"
AutoPlayLastClickTick := 0
AutoPlayLastStartClickTick := 0
AutoPlayStartPending := false
AutoPlayStartPendingSince := 0
AutoPlayLastStageClickTick := 0
AutoPlayLastHeartbeatTick := 0
AutoPlayMissingTemplateWarned := false
AutoPlayLastDetectionState := ""

; ---- состояние окна разметки/калибровки ----
MarkMode := ""
MarkList := []
TemplateName := ""   ; заранее заданное имя шаблона (например "StartGame") или "" = спрашивать
ModalHwnd := 0

; ---- ручной перенос окна (ManualDragLoop) ----
WinDragActive := false
WinDragStartMX := 0, WinDragStartMY := 0
WinDragStartWX := 0, WinDragStartWY := 0
WinDragLastMouseX := "", WinDragLastMouseY := ""
WinDragLastTargetX := "", WinDragLastTargetY := ""
WinDragMonitor := 0
WinDragWorkLeft := 0, WinDragWorkTop := 0, WinDragWorkRight := 0, WinDragWorkBottom := 0

; ---- запись действий после Rejoin (Post-Rejoin Actions) ----
RejoinRecordActive := false
RejoinActions := []          ; [{x, y, delayMs}, ...]
RejoinRecordLastTime := 0
RejoinRecordLastX := 0
RejoinRecordLastY := 0
RejoinRecordPending := false ; ждём отпускания кнопки мыши

; ---- нативное окно назначения горячей клавиши ----
HotkeyCaptureTarget := ""
HotkeyCaptureHwnd := 0
HotkeyCaptureLastValue := ""

; Drag-select шаблонов (MarkMode = "template") теперь полностью в HTML-модалке.
; Глобальные OnMessage-перехваты больше не используются.

; ---- Горячие клавиши для записи Post-Rejoin действий ----
; WheelUp/Down включаются только во время записи; F1 заменяется настройкой.
Hotkey, ~WheelUp, RejoinWheelUp, Off
Hotkey, ~WheelDown, RejoinWheelDown, Off
; Roblox остаётся отдельным top-level окном, поэтому Windows само передаёт
; ему фокус по клику. Глобальный перехват LButton здесь не нужен и мог
; мешать кликам по HTML-панели после закрепления.
Hotkey, ~LButton, FocusEmbeddedGameClick, Off
; =======================================================

; Главное окно AHK = ТОЛЬКО боковая панель (сайдбар).
; Игровая область (Roblox) больше НЕ встраивается внутрь GUI — теперь это
; отдельное полноценное окно, к которому сайдбар "прилипает" сбоку (dock).
; Так Roblox остаётся играбельным (DirectX получает нормальный ввод),
; а сайдбар синхронно двигается вместе с окном игры.
SidebarTotalW := SidebarW
SidebarTotalH := GameAreaH

LoadConfig()
LoadSettings()
LoadAppLanguage()
LoadHotkeySettings()
ApplyConfiguredHotkeys()
MigrateMapsLayout()
ReloadMapList()
LoadAllMapCoords()

; ===================== GUI (тёмная тема + HTML на всё окно) =====================
Gui, +HwndMainGuiHwnd -Caption
Gui, Color, 0x121212

; ---- 1. HTML-панель на ВСЁ окно (первой — будет снизу) ----
; Включаем IE11 Edge Mode
RegRead, ieEmu, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, %A_ScriptName%
if (ErrorLevel || ieEmu < 11001)
    RegWrite, REG_DWORD, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, %A_ScriptName%, 11001

htmlDir := A_ScriptDir . "\..\UI"
Loop, %htmlDir%, 0, 0
    htmlDir := A_LoopFileLongPath
htmlPath := htmlDir . "\index.html"

; ---- Если index.html не найден по стандартному пути (A_ScriptDir\..\UI) —
; ищем в паре других вероятных мест, чтобы не зависеть от точной структуры
; папок на диске у конкретного пользователя.
if !FileExist(htmlPath) {
    altCandidates := [A_ScriptDir . "\UI\index.html"
                     , A_ScriptDir . "\..\..\UI\index.html"
                     , A_ScriptDir . "\index.html"]
    for i, cand in altCandidates {
        if FileExist(cand) {
            SplitPath, cand, , candDir
            htmlDir := candDir
            htmlPath := cand
            break
        }
    }
}

StringReplace, htmlPath, htmlPath, \, /, All
htmlURL := "file:///" . htmlPath

; Пишем реальный путь в файл рядом с main.ahk — чтобы сразу видеть в
; Проводнике/блокноте, какой именно index.html макрос пытается открыть,
; без необходимости лезть в лог приложения.
try {
    FileDelete, %A_ScriptDir%\_last_loaded_html_path.txt
    FileAppend, % htmlPath . "`r`nExists: " . (FileExist(htmlPath) ? "YES" : "NO — ФАЙЛ НЕ НАЙДЕН"), %A_ScriptDir%\_last_loaded_html_path.txt
} catch e {
}

if !FileExist(htmlPath) {
    MsgBox, 16, index.html не найден, Не удалось найти UI\index.html.`n`nПроверенные пути:`n%htmlPath%`n`nПоложи index.html рядом с main.ahk в подпапку UI, либо смотри файл _last_loaded_html_path.txt рядом с main.ahk.
}

Gui, Add, ActiveX, x0 y0 w%SidebarTotalW% h%SidebarTotalH% vWB, Shell.Explorer
WB.Silent := true
ComObjConnect(WB, "WB_")
; Flags=12 (4+8) — navNoReadFromCache|navNoWriteToCache: заставляет IE ActiveX
; всегда брать файл заново с диска, а не отдавать закэшированную версию
; (это была вероятная причина, почему после замены index.html
; в приложении продолжал грузиться старый контент).
WB.Navigate(htmlURL . "?_=" . A_TickCount, 12)

; Ждём загрузки HTML
WBWaitStart := A_TickCount
while (WB.ReadyState != 4 && A_TickCount - WBWaitStart < 15000)
    Sleep, 100
Sleep, 200

; ---- 2. Контейнер игры НЕ нужен ----
; Roblox НЕ встраивается внутрь GUI — это отдельное окно, к которому
; сайдбар прилипает (dock). См. BtnEmbed / SyncDockPosition.

; Центрируем сайдбар на экране при старте (до встраивания)
SysGet, Mon0, MonitorWorkArea
StartX := (Mon0Right - Mon0Left - SidebarTotalW) // 2
StartY := (Mon0Bottom - Mon0Top - SidebarTotalH) // 2
if (StartX < 0)
    StartX := 100
if (StartY < 0)
    StartY := 100

Gui, Show, x%StartX% y%StartY% w%SidebarTotalW% h%SidebarTotalH%, Mmacro Control

; Таймер опроса JS-команд
SetTimer, PollJSCmd, 20
SetTimer, PollBotCommands, 250
SetTimer, PublishBotState, 1000
; Отправляем начальное состояние в HTML
SetTimer, PushStateToHTML, -300
if (BotAutoStart)
    SetTimer, StartDiscordBot, -1000
; Проверяем версию после загрузки интерфейса, чтобы обновление не мешало старту GUI.
SetTimer, CheckForUpdate, -2000
return

#Include %A_ScriptDir%\ahk\version_check.ahk

FocusEmbeddedGameClick:
    if (!Embedded || !GameHwnd || !DllCall("IsWindow", "ptr", GameHwnd))
        return
    MouseGetPos, clickX, clickY
    if (!GameAreaOrigin(gameX, gameY))
        return
    if (clickX < gameX || clickY < gameY
        || clickX >= gameX + GameAreaW || clickY >= gameY + GameAreaH)
        return
    FocusEmbeddedGame()
return

FocusEmbeddedGame() {
    global GameHwnd, MainGuiHwnd
    if (!GameHwnd || !DllCall("IsWindow", "ptr", GameHwnd))
        return
    pid := 0
    gameTid := DllCall("GetWindowThreadProcessId", "ptr", GameHwnd, "uint*", pid, "uint")
    ourTid := DllCall("GetCurrentThreadId", "uint")
    attached := false
    if (gameTid && gameTid != ourTid)
        attached := DllCall("AttachThreadInput", "uint", ourTid, "uint", gameTid, "int", 1)
    ; Не используем SW_RESTORE: для развёрнутого Roblox он повторно
    ; восстанавливает старую позицию уже после dock и уводит окно влево.
    ; Во время закрепления окно уже видимо, поэтому достаточно SW_SHOW.
    DllCall("ShowWindow", "ptr", GameHwnd, "int", 5) ; SW_SHOW
    DllCall("BringWindowToTop", "ptr", GameHwnd)
    DllCall("SetForegroundWindow", "ptr", GameHwnd)
    DllCall("SetActiveWindow", "ptr", GameHwnd)
    DllCall("SetFocus", "ptr", GameHwnd)
    if (attached)
        DllCall("AttachThreadInput", "uint", ourTid, "uint", gameTid, "int", 0)
}

; ===================== CTRL+A / CTRL+V В HTML-ПОЛЯХ =====================
; ActiveX-контрол Shell.Explorer, встроенный в GUI, не реализует
; IOleInPlaceFrame::TranslateAccelerator — поэтому такие комбинации, как
; Ctrl+A (выделить всё) и Ctrl+V (вставить), в HTML-полях ввода (сайдбар,
; модалки настроек/пресетов и т.д.) просто ничего не делают, хотя обычный
; ввод текста работает нормально. Эмулируем эти комбинации вручную:
; для нативных Win32-полей (Edit в Mark/InputBox и т.п.) пропускаем
; комбинацию как есть, а для полей внутри "Internet Explorer_Server"
; подменяем её на Home/Shift+End (выделить всё) и посимвольный ввод
; буфера обмена (вставить).
#If IsOurWindowActive()
^a::HandleCtrlA()
^v::HandleCtrlV()
#If

IsOurWindowActive() {
    return WinActive("ahk_pid " . DllCall("GetCurrentProcessId", "uint"))
}

HandleCtrlA() {
    ControlGetFocus, fctl, A
    if InStr(fctl, "Internet Explorer_Server") {
        Send, {Home}
        Send, +{End}
    } else {
        Send, {Blind}^a
    }
}

HandleCtrlV() {
    ControlGetFocus, fctl, A
    if InStr(fctl, "Internet Explorer_Server") {
        if (Clipboard = "")
            return
        pasteText := Clipboard
        StringReplace, pasteText, pasteText, `r`n, %A_Space%, All
        StringReplace, pasteText, pasteText, `n, %A_Space%, All
        SendRaw, %pasteText%
    } else {
        Send, {Blind}^v
    }
}

; ===================== ЛОГ =====================
AddLog(msg, cls := "") {
    global WB
    FormatTime, ts,, HH:mm:ss
    ; Отправляем в HTML-панель
    if (WB && WB.ReadyState = 4) {
        jsCls := cls ? cls : ""
        safeMsg := StrReplace(msg, "\", "\\")
        safeMsg := StrReplace(safeMsg, """", "\""")
        safeMsg := StrReplace(safeMsg, "`r`n", "\n")
        safeMsg := StrReplace(safeMsg, "`n", "\n")
        js := "ahkLog(""" . safeMsg . """, """ . jsCls . """)"
        try {
            WB.Document.parentWindow.execScript(js)
        } catch e {
            ; HTML ещё не готов — ничего страшного
        }
    }
}

; ===================== КОНФИГ (координаты кнопок) =====================
LoadConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    if !FileExist(ConfigFile)
        return
    IniRead, v, %ConfigFile%, Buttons, UpgradeX, %UpgradeX%
    UpgradeX := v
    IniRead, v, %ConfigFile%, Buttons, UpgradeY, %UpgradeY%
    UpgradeY := v
    IniRead, v, %ConfigFile%, Buttons, AutoX, %AutoX%
    AutoX := v
    IniRead, v, %ConfigFile%, Buttons, AutoY, %AutoY%
    AutoY := v
    IniRead, v, %ConfigFile%, Buttons, StartGameX, %StartGameX%
    StartGameX := v
    IniRead, v, %ConfigFile%, Buttons, StartGameY, %StartGameY%
    StartGameY := v
    IniRead, v, %ConfigFile%, Buttons, RepeatStageX, %RepeatStageX%
    RepeatStageX := v
    IniRead, v, %ConfigFile%, Buttons, RepeatStageY, %RepeatStageY%
    RepeatStageY := v
}

SaveConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    IniWrite, %UpgradeX%,  %ConfigFile%, Buttons, UpgradeX
    IniWrite, %UpgradeY%,  %ConfigFile%, Buttons, UpgradeY
    IniWrite, %AutoX%,     %ConfigFile%, Buttons, AutoX
    IniWrite, %AutoY%,     %ConfigFile%, Buttons, AutoY
    IniWrite, %StartGameX%, %ConfigFile%, Buttons, StartGameX
    IniWrite, %StartGameY%, %ConfigFile%, Buttons, StartGameY
    IniWrite, %RepeatStageX%, %ConfigFile%, Buttons, RepeatStageX
    IniWrite, %RepeatStageY%, %ConfigFile%, Buttons, RepeatStageY
}

; ===================== НАСТРОЙКИ (ahk/settings.ini) =====================
LoadSettings() {
    global SettingsFile, ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, HoverDelay, MouseSpeed, MouseSpeedEnabled, ZoomEnabled, ZoomScrolls, TopCameraEnabled, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    global AutoUpgradePriority, AutoUpgradeUnitOffsetY, AutoUpgradeEnabled
    global FarmMode
    global RejoinEnabled, RejoinShareLink, RejoinMaxAttempts, RejoinWaitTimeout, RejoinPostJoinDelay
    global RejoinPostActionsDelay, BotMapPostActionsDelay
    global BotToken, BotEnabled, BotAutoStart, BotGuildId, BotAllowedUserIds
    if !FileExist(SettingsFile)
        return
    IniRead, v, %SettingsFile%, Delays, ClickDelay, %ClickDelay%
    ClickDelay := v
    IniRead, v, %SettingsFile%, Delays, SlotClickDelay, %SlotClickDelay%
    SlotClickDelay := v
    IniRead, v, %SettingsFile%, Delays, UpgradeClickDelay, %UpgradeClickDelay%
    UpgradeClickDelay := v
    IniRead, v, %SettingsFile%, Delays, AutoClickDelay, %AutoClickDelay%
    AutoClickDelay := v
    IniRead, v, %SettingsFile%, Delays, UnitSleepDelay, %UnitSleepDelay%
    UnitSleepDelay := v
    IniRead, v, %SettingsFile%, Delays, StartGameDelay, %StartGameDelay%
    StartGameDelay := v
    IniRead, v, %SettingsFile%, Delays, HoverDelay, %HoverDelay%
    HoverDelay := v
    IniRead, v, %SettingsFile%, Delays, MouseSpeed, %MouseSpeed%
    MouseSpeed := v
    IniRead, v, %SettingsFile%, Input, MouseSpeedEnabled, %MouseSpeedEnabled%
    MouseSpeedEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, Camera, ZoomScrolls, %ZoomScrolls%
    ZoomScrolls := v
    if (ZoomScrolls < -50 || ZoomScrolls > 50)
        ZoomScrolls := 0
    IniRead, v, %SettingsFile%, Camera, ZoomEnabled, %ZoomEnabled%
    ZoomEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, Camera, TopCameraEnabled, %TopCameraEnabled%
    TopCameraEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, ImageSearch, Variation, %ImgVariation%
    ImgVariation := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameColor, %StartGameColor%
    StartGameColor := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameColorVar, %StartGameColorVar%
    StartGameColorVar := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameCenterX, %StartGameCenterX%
    StartGameCenterX := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameCenterY, %StartGameCenterY%
    StartGameCenterY := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameRadius, %StartGameRadius%
    StartGameRadius := v
    Loop, 6 {
        IniRead, v, %SettingsFile%, AutoUpgrade, Priority%A_Index%, % AutoUpgradePriority[A_Index]
        if (v < 0 || v > 9)
            v := AutoUpgradePriority[A_Index]
        AutoUpgradePriority[A_Index] := v
    }
    IniRead, v, %SettingsFile%, AutoUpgrade, UnitOffsetY, %AutoUpgradeUnitOffsetY%
    AutoUpgradeUnitOffsetY := v
    IniRead, v, %SettingsFile%, AutoUpgrade, Enabled, %AutoUpgradeEnabled%
    AutoUpgradeEnabled := (v = 1 || v = "true") ? true : false

    IniRead, v, %SettingsFile%, Farm, Mode, %FarmMode%
    FarmMode := (v = "autoplay") ? "autoplay" : "units"

    IniRead, v, %SettingsFile%, Game, Mode, %GameMode%
    GameMode := IsValidGameMode(v) ? v : "infinite"

    IniRead, v, %SettingsFile%, Rejoin, Enabled, %RejoinEnabled%
    RejoinEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, Rejoin, ShareLink, %RejoinShareLink%
    RejoinShareLink := (v = "ERROR") ? "" : v
    IniRead, v, %SettingsFile%, Rejoin, MaxAttempts, %RejoinMaxAttempts%
    RejoinMaxAttempts := v
    IniRead, v, %SettingsFile%, Rejoin, WaitTimeout, %RejoinWaitTimeout%
    RejoinWaitTimeout := v
    IniRead, v, %SettingsFile%, Rejoin, PostJoinDelay, %RejoinPostJoinDelay%
    RejoinPostJoinDelay := v
    IniRead, v, %SettingsFile%, Rejoin, PostActionsDelay, %RejoinPostActionsDelay%
    RejoinPostActionsDelay := v
    IniRead, v, %SettingsFile%, DiscordBot, MapPostActionsDelay, %BotMapPostActionsDelay%
    BotMapPostActionsDelay := v
    if (BotMapPostActionsDelay < 0)
        BotMapPostActionsDelay := 0

    BotToken := LoadBotToken()
    IniRead, v, %SettingsFile%, DiscordBot, Enabled, %BotEnabled%
    BotEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, DiscordBot, AutoStart, %BotAutoStart%
    BotAutoStart := (v = 1 || v = "true") ? true : false
    IniRead, v, %SettingsFile%, DiscordBot, GuildId, %BotGuildId%
    BotGuildId := (v = "ERROR") ? "" : v
    IniRead, v, %SettingsFile%, DiscordBot, AllowedUserIds, %BotAllowedUserIds%
    BotAllowedUserIds := (v = "ERROR") ? "" : v
}

SaveSettings() {
    global SettingsFile, ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, HoverDelay, MouseSpeed, MouseSpeedEnabled, ZoomEnabled, ZoomScrolls, TopCameraEnabled, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    global AutoUpgradePriority, AutoUpgradeUnitOffsetY, AutoUpgradeEnabled
    global FarmMode
    global RejoinEnabled, RejoinShareLink, RejoinMaxAttempts, RejoinWaitTimeout, RejoinPostJoinDelay
    global RejoinPostActionsDelay, BotMapPostActionsDelay
    global BotToken, BotEnabled, BotAutoStart, BotGuildId, BotAllowedUserIds
    IniWrite, %ClickDelay%, %SettingsFile%, Delays, ClickDelay
    IniWrite, %SlotClickDelay%, %SettingsFile%, Delays, SlotClickDelay
    IniWrite, %UpgradeClickDelay%, %SettingsFile%, Delays, UpgradeClickDelay
    IniWrite, %AutoClickDelay%, %SettingsFile%, Delays, AutoClickDelay
    IniWrite, %UnitSleepDelay%, %SettingsFile%, Delays, UnitSleepDelay
    IniWrite, %StartGameDelay%, %SettingsFile%, Delays, StartGameDelay
    IniWrite, %HoverDelay%, %SettingsFile%, Delays, HoverDelay
    IniWrite, %MouseSpeed%, %SettingsFile%, Delays, MouseSpeed
    IniWrite, % (MouseSpeedEnabled ? 1 : 0), %SettingsFile%, Input, MouseSpeedEnabled
    IniWrite, % (ZoomEnabled ? 1 : 0), %SettingsFile%, Camera, ZoomEnabled
    IniWrite, %ZoomScrolls%, %SettingsFile%, Camera, ZoomScrolls
    IniWrite, % (TopCameraEnabled ? 1 : 0), %SettingsFile%, Camera, TopCameraEnabled
    IniWrite, %ImgVariation%, %SettingsFile%, ImageSearch, Variation
    IniWrite, %StartGameColor%, %SettingsFile%, PixelSearch, StartGameColor
    IniWrite, %StartGameColorVar%, %SettingsFile%, PixelSearch, StartGameColorVar
    IniWrite, %StartGameCenterX%, %SettingsFile%, PixelSearch, StartGameCenterX
    IniWrite, %StartGameCenterY%, %SettingsFile%, PixelSearch, StartGameCenterY
    IniWrite, %StartGameRadius%, %SettingsFile%, PixelSearch, StartGameRadius
    Loop, 6
        IniWrite, % AutoUpgradePriority[A_Index], %SettingsFile%, AutoUpgrade, Priority%A_Index%
    IniWrite, %AutoUpgradeUnitOffsetY%, %SettingsFile%, AutoUpgrade, UnitOffsetY
    IniWrite, % (AutoUpgradeEnabled ? 1 : 0), %SettingsFile%, AutoUpgrade, Enabled
    IniWrite, %FarmMode%, %SettingsFile%, Farm, Mode
    IniWrite, %GameMode%, %SettingsFile%, Game, Mode

    IniWrite, % (RejoinEnabled ? 1 : 0), %SettingsFile%, Rejoin, Enabled
    IniWrite, %RejoinShareLink%, %SettingsFile%, Rejoin, ShareLink
    IniWrite, %RejoinMaxAttempts%, %SettingsFile%, Rejoin, MaxAttempts
    IniWrite, %RejoinWaitTimeout%, %SettingsFile%, Rejoin, WaitTimeout
    IniWrite, %RejoinPostJoinDelay%, %SettingsFile%, Rejoin, PostJoinDelay
    IniWrite, %RejoinPostActionsDelay%, %SettingsFile%, Rejoin, PostActionsDelay
    IniWrite, %BotMapPostActionsDelay%, %SettingsFile%, DiscordBot, MapPostActionsDelay
    SaveBotToken()
    IniWrite, % (BotEnabled ? 1 : 0), %SettingsFile%, DiscordBot, Enabled
    IniWrite, % (BotAutoStart ? 1 : 0), %SettingsFile%, DiscordBot, AutoStart
    IniWrite, %BotGuildId%, %SettingsFile%, DiscordBot, GuildId
    IniWrite, %BotAllowedUserIds%, %SettingsFile%, DiscordBot, AllowedUserIds
    SaveHotkeySettings()
}

; ---- Токен Discord-бота: только в ahk\secrets.ini ----
; settings.ini лежит в git, поэтому секрет туда не пишется. Старые установки
; читаются как fallback, а при первом сохранении токен переносится в secrets.ini.
LoadBotToken() {
    global SecretsFile, SettingsFile
    IniRead, v, %SecretsFile%, DiscordBot, Token, ""
    if (v != "ERROR" && Trim(v) != "")
        return Trim(v)
    IniRead, v, %SettingsFile%, DiscordBot, Token, ""
    if (v = "ERROR")
        return ""
    return Trim(v)
}

SaveBotToken() {
    global SecretsFile, SettingsFile, BotToken
    if (BotToken = "") {
        IniDelete, %SecretsFile%, DiscordBot, Token
        IniDelete, %SettingsFile%, DiscordBot, Token
        return
    }
    ; Файл пишется явно в UTF-8: IniWrite для нового файла может выбрать UTF-16,
    ; а bot.py читает его как utf-8-sig.
    FileDelete, %SecretsFile%
    f := FileOpen(SecretsFile, "w", "UTF-8")
    if (!f) {
        AddLog("Не удалось записать " . SecretsFile . " — токен не сохранён", "error")
        return
    }
    f.Write("[DiscordBot]`r`nToken=" . BotToken . "`r`n")
    f.Close()
    ; Если токен остался в отслеживаемом файле, убираем его оттуда.
    IniDelete, %SettingsFile%, DiscordBot, Token
}

; ===================== КООРДИНАТЫ КАРТ (слоты) =====================
; Единственное правило имени файла для карты: им же пользуются слоты, записанные
; действия и папка bot\actions. Поэтому снимок карты и его *_slots.ini всегда
; получают одно и то же базовое имя.
; Базовое имя файлов карты: имя карты без символов, недопустимых в имени файла.
; Одно правило для снимка, заголовка, слотов и записанных действий, поэтому
; то, что видно в списке карт, совпадает с именем файлов в maps\<режим>.
; Имя, которое использовали прошлые версии макроса (пробелы -> "_", апостроф
; удалялся). Нужно только для чтения уже записанных файлов.
; Путь к файлу-спутнику карты. Если канонического имени нет, но есть файл под
; старым именем — возвращается он, иначе разметка прошлых версий потерялась бы.
; ---- Файл с Post-Rejoin Actions для конкретной карты ----
; ---- Шаблон заголовка карты для распознавания ----
; Существующий шаблон (.bmp, затем .png) или "" если его ещё не снимали.
; ===================== РАСПОЗНАВАНИЕ КАРТЫ ПО ЗАГОЛОВКУ =====================
; На экране "Travelling to..." название карты рисуется всегда в одном и том же
; месте, поэтому шаблон сравнивается не скользящим поиском, а по сохранённой
; позиции (с небольшим разбросом). Сравниваются только пиксели текста, так что
; фон-превью карты на результат не влияет.

; Читает 24-битный BMP в буфер пикселей, приводя строки к порядку «сверху вниз».
; Светло-синий пиксель — из таких нарисован текст заголовка.
; Точки заголовка для сравнения: пиксели текста, у которых рядом есть фон.
; Берём именно контуры букв: тогда сравнение не зависит от того, что нарисовано
; под заголовком (превью карты у каждой карты своё), и точек заметно меньше.
; Загружает шаблоны заголовков активного режима в кэш.
; Доля точек шаблона, совпавших с полосой кадра при смещении (dx, dy), в %.
; Кадр хранится в глобальном буфере: параметры передаются адресами, потому что
; NumGet по свойству объекта в AHK v1 трактует значение как адрес.
; Сравнивает заголовок на экране со всеми шаблонами режима.
; Возвращает true, если лучший результат не ниже порога.
; Сообщает результат распознавания в панель и в открытые модалки.
PushMapDetectResult(mapName, score, otherMap := "", otherMode := "") {
    global LastDetectedMap, LastDetectScore
    LastDetectedMap := mapName
    LastDetectScore := score + 0
    js := "ahkMapDetectResult('" . JsEscape(mapName) . "'," . LastDetectScore . ",'" . JsEscape(otherMap) . "','" . JsEscape(otherMode) . "')"
    WBH_CallJS(js)
    ModalCallJS(js)
}

; Сохраняет шаблон заголовка выбранной карты и его позицию в кадре.
SaveMapTitle(x1, y1, x2, y2) {
    global SelectedMapCtl, TempShot, TitleCaptureMap, MapCoords, RejoinActions
    name := (TitleCaptureMap != "") ? TitleCaptureMap : SelectedMapCtl
    TitleCaptureMap := ""
    if (name = "") {
        AddLog("Шаблон заголовка не сохранён: карта не выбрана", "warn")
        return false
    }
    w := x2 - x1 + 1
    h := y2 - y1 + 1
    if (w < 40 || h < 16) {
        AddLog("Заголовок слишком мелкий (" w "x" h ") — обведи весь текст названия", "warn")
        return false
    }
    out := MapTitlePath(name)
    if !CropBMP(TempShot, x1, y1, w, h, out) {
        AddLog("Не удалось сохранить шаблон заголовка", "error")
        return false
    }
    anchor := MapTitleAnchorPath(name)
    IniWrite, %x1%, %anchor%, Title, X
    IniWrite, %y1%, %anchor%, Title, Y
    IniWrite, %w%, %anchor%, Title, W
    IniWrite, %h%, %anchor%, Title, H
    InvalidateTitleTemplates()
    ; Карта могла быть новой — тогда она появляется в списке и сразу выбирается.
    ReloadMapList()
    if (SelectedMapCtl != name) {
        SelectedMapCtl := name
        if !MapCoords.HasKey(name)
            LoadMapCoordsOne(name)
        RejoinActions := []
        LoadRejoinActions(name)
        RefreshMapDropdown()
        WriteBotState()
    }
    AddLog("Шаблон заголовка сохранён: " . out . " (" w "x" h " в " x1 "," y1 ")", "success")
    return true
}

; ---- Загрузка записанных Post-Rejoin действий для карты ----
LoadRejoinActions(mapName) {
    global RejoinActions
    RejoinActions := []
    f := RejoinActionsFile(mapName)
    if !FileExist(f)
        return
    IniRead, count, %f%, Actions, Count, 0
    if (count < 1)
        return
    Loop, %count% {
        IniRead, raw, %f%, Actions, %A_Index%, -
        if (raw = "-")
            continue
        if (InStr(raw, "wheel,") = 1) {
            ; Формат: wheel,DELTA,delay
            rest := SubStr(raw, 7)
            StringSplit, wp, rest, `,
            if (wp0 >= 2)
                RejoinActions.Push({isWheel: true, delta: wp1, delay: wp2})
        } else {
            ; Формат: x,y,delay
            StringSplit, parts, raw, `,
            if (parts0 >= 3)
                RejoinActions.Push({x: parts1, y: parts2, delay: parts3})
        }
    }
}

; ---- Сохранение Post-Rejoin действий для карты ----
SaveRejoinActions(mapName) {
    global RejoinActions
    f := RejoinActionsFile(mapName)
    FileDelete, %f%
    count := RejoinActions.Length()
    IniWrite, %count%, %f%, Actions, Count
    Loop, %count% {
        a := RejoinActions[A_Index]
        if (a.isWheel)
            IniWrite, % "wheel," . a.delta . "," . a.delay, %f%, Actions, %A_Index%
        else
            IniWrite, % a.x . "," . a.y . "," . a.delay, %f%, Actions, %A_Index%
    }
}

LoadAllMapCoords() {
    global MapList
    for i, m in MapList
        LoadMapCoordsOne(m)
}

; Сбор списка карт активного режима: сначала единый каталог названий,
; затем файлы-карты для обратной совместимости.
ReloadMapList() {
    global MapList, GameMode
    MapList := []
    dir := ModeDir()
    if !InStr(FileExist(dir), "D")
        FileCreateDir, %dir%

    ; The catalog supplies selectable names before their title or snapshot exists.
    ; Existing assets are also appended for backwards compatibility.
    seen := {}
    if LoadMapCatalog(GameMode, catalogNames) {
        for _, name in catalogNames {
            name := Trim(name)
            StringLower, key, name
            if (name = "" || seen.HasKey(key))
                continue
            seen[key] := true
            MapList.Push(name)
        }
    } else if (GameMode = "infinite")
        AddLog("Каталог карт не найден: " . MapsDir . "\map_catalog.txt", "warn")
    if !InStr(FileExist(dir), "D")
        return
    for _, pattern in ["\*_title.bmp", "\*_title.png", "\*.bmp", "\*.png"] {
        Loop, Files, %dir%%pattern%
        {
            name := A_LoopFileName
            StringGetPos, dotPos, name, .
            if (dotPos >= 0)
                name := SubStr(name, 1, dotPos)
            name := RegExReplace(name, "i)_title$", "")
            name := Trim(name)
            StringLower, key, name
            if (name = "" || seen.HasKey(key))
                continue
            seen[key] := true
            MapList.Push(name)
        }
    }
}

; Разовая миграция: карты, лежавшие прямо в maps\, переезжают в maps\infinite.
; Новые версии хранят карты по папкам режимов.
MigrateMapsLayout() {
    global MapsDir
    flat := 0
    Loop, Files, %MapsDir%\*.bmp
        flat += 1
    if (flat = 0)
        return
    target := MapsDir . "\infinite"
    if !InStr(FileExist(target), "D")
        FileCreateDir, %target%
    moved := 0
    for _, pattern in ["\*.bmp", "\*.png", "\*_slots.ini", "\*_rejoin.ini"] {
        Loop, Files, %MapsDir%%pattern%
        {
            dest := target . "\" . A_LoopFileName
            if FileExist(dest)
                continue
            FileMove, %A_LoopFileFullPath%, %dest%
            if (!ErrorLevel)
                moved += 1
        }
    }
    if (moved > 0)
        AddLog("Карты: перенесено " . moved . " файл(ов) в maps\infinite", "success")
}

; Подпись режима для лога и бота.
GameModeLabel(mode) {
    global GameModeLabels
    return GameModeLabels.HasKey(mode) ? GameModeLabels[mode] : mode
}

; Перестроение списка карт в HTML-панели (с сохранением выбора).
RefreshMapDropdown() {
    global MapList, SelectedMapCtl
    UpdateMapListHTML()
    if (SelectedMapCtl != "")
        WBH_CallJS("ahkUpdateMap(""" . SelectedMapCtl . """)")
}

LoadMapCoordsOne(mapName) {
    global MapCoords
    f := MapSlotsFile(mapName)
    if !FileExist(f) {
        MapCoords.Delete(mapName)
        return
    }
    IniRead, cnt, %f%, Meta, Count, 0
    list := []
    Loop, %cnt% {
        IniRead, line, %f%, Slots, %A_Index%, ""
        if (line = "")
            continue
        StringSplit, p, line, `,
        list.Push({num: p1, x: p2, y: p3})
    }
    if (list.Length() > 0)
        MapCoords[mapName] := list
    else
        MapCoords.Delete(mapName)
}

SaveMapSlots(mapName, list) {
    f := MapSlotsFile(mapName)
    if FileExist(f)
        FileDelete, %f%
    IniWrite, % list.Length(), %f%, Meta, Count
    for i, s in list {
        line := s.num . "," . s.x . "," . s.y
        IniWrite, %line%, %f%, Slots, %i%
    }
}

; ===================== ФУНКЦИИ ОКНА / ВСТРАИВАНИЯ =====================
; Возвращает экранные координаты левого-верхнего угла игровой области.
; При встраивании (dock) это клиентская область окна Roblox (GameHwnd),
; иначе — главное окно AHK. Возвращает true при успехе.
GameAreaOrigin(ByRef ox, ByRef oy) {
    global Embedded, GameHwnd, WinTitle
    ; В обычном режиме игровое окно отдельное, поэтому нельзя брать
    ; координаты MainGuiHwnd (это только сайдбар макроса).
    hwnd := WinExist(WinTitle)
    if (Embedded && GameHwnd && DllCall("IsWindow", "ptr", GameHwnd))
        hwnd := GameHwnd
    if (!hwnd || !DllCall("IsWindow", "ptr", hwnd))
        return false
    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(0, pt, 4, "Int")
    DllCall("ClientToScreen", "ptr", hwnd, "ptr", &pt)
    ox := NumGet(pt, 0, "Int")
    oy := NumGet(pt, 4, "Int")
    return true
}

ToScreen(x, y) {
    global TS_X, TS_Y
    if (!GameAreaOrigin(ox, oy)) {
        AddLog("ToScreen: игровое окно недоступно")
        TS_X := x
        TS_Y := y
        return
    }
    TS_X := ox + x
    TS_Y := oy + y
}

GetClientSize(hwnd, ByRef cw, ByRef ch) {
    VarSetCapacity(rect, 16, 0)
    DllCall("GetClientRect", "ptr", hwnd, "ptr", &rect)
    cw := NumGet(rect, 8, "Int")
    ch := NumGet(rect, 12, "Int")
}

GetWorkAreaAtPoint(x, y, ByRef cachedMonitor, ByRef left, ByRef top, ByRef right, ByRef bottom) {
    point := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
    monitor := DllCall("MonitorFromPoint", "int64", point, "uint", 2, "ptr")
    if (!monitor)
        return false
    if (monitor = cachedMonitor)
        return true
    VarSetCapacity(info, 40, 0)
    NumPut(40, info, 0, "UInt")
    if (!DllCall("GetMonitorInfo", "ptr", monitor, "ptr", &info))
        return false
    left := NumGet(info, 4, "Int")
    top := NumGet(info, 8, "Int")
    right := NumGet(info, 12, "Int")
    bottom := NumGet(info, 16, "Int")
    cachedMonitor := monitor
    return true
}

; ===================== ПОИСК ИЗОБРАЖЕНИЙ (fallback) =====================
FindGameButton(imageFile, ByRef foundX, ByRef foundY) {
    global GameAreaW, GameAreaH, ImgVariation, WinTitle, Embedded, GameHwnd
    if (!GameAreaOrigin(sx, sy))
        return false
    ; После перезапуска Roblox клиентская область может получить другой
    ; размер. Не ищем за её пределами, иначе ImageSearch может молча не найти
    ; кнопку, хотя она видна на экране.
    ; При встраивании WinTitle указывает на исходное окно Roblox, а поиск
    ; выполняется по GameHwnd. После SetParent размеры этих окон могут
    ; отличаться, поэтому берём размер того же окна, откуда взят origin.
    hwnd := WinExist(WinTitle)
    if (Embedded && GameHwnd && DllCall("IsWindow", "ptr", GameHwnd))
        hwnd := GameHwnd
    if (hwnd) {
        GetClientSize(hwnd, clientW, clientH)
        searchW := (clientW > 0 && clientW < GameAreaW) ? clientW : GameAreaW
        searchH := (clientH > 0 && clientH < GameAreaH) ? clientH : GameAreaH
    }
    if (searchW = "")
        searchW := GameAreaW
    if (searchH = "")
        searchH := GameAreaH
    ex := sx + searchW
    ey := sy + searchH
    ImageSearch, foundX, foundY, sx, sy, ex, ey, *%ImgVariation% %imageFile%
    if (ErrorLevel = 0)
        return true
    ImageSearch, foundX, foundY, sx, sy, ex, ey, *100 %imageFile%
    if (ErrorLevel = 0)
        return true
    return false
}

FindGameButtonByColor(color, variation, ByRef foundX, ByRef foundY) {
    global StartGameCenterX, StartGameCenterY, StartGameRadius
    if (!GameAreaOrigin(baseX, baseY))
        return false
    cx := baseX + StartGameCenterX
    cy := baseY + StartGameCenterY
    sx := cx - StartGameRadius
    sy := cy - StartGameRadius
    ex := cx + StartGameRadius
    ey := cy + StartGameRadius
    PixelSearch, foundX, foundY, sx, sy, ex, ey, %color%, %variation%, Fast RGB
    return (ErrorLevel = 0)
}

; Поиск зелёной кнопки Start Game около её калиброванной точки.
; Старый поиск использовал StartGameCenterY=500, тогда как в текущем UI
; кнопка находится примерно на Y=214, поэтому он искал ниже кнопки.
FindStartGameByColor(color, variation, ByRef foundX, ByRef foundY) {
    global StartGameX, StartGameY, GameAreaW, GameAreaH
    if (!GameAreaOrigin(baseX, baseY))
        return false
    if (StartGameX > 0 && StartGameY > 0) {
        sx := baseX + StartGameX - 180
        sy := baseY + StartGameY - 35
        ex := baseX + StartGameX + 180
        ey := baseY + StartGameY + 90
    } else {
        sx := baseX + 300
        sy := baseY + 120
        ex := baseX + GameAreaW - 300
        ey := baseY + 360
    }
    PixelSearch, foundX, foundY, sx, sy, ex, ey, %color%, %variation%, Fast RGB
    return (ErrorLevel = 0)
}

ClickGameButton(imageFile, delayAfter := 0) {
    global ImagesDir, StartGameColor, StartGameColorVar
    full := ImagesDir . "\" . imageFile
    if FileExist(full) {
        if (FindGameButton(full, btnX, btnY)) {
            SmoothClick(btnX, btnY, 150)
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
        if (FindGameButtonByColor(StartGameColor, StartGameColorVar, btnX, btnY)) {
            SmoothClick(btnX, btnY, 150)
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    return false
}

BtnEmbed:
    if (Embedded) {
        UnembedGameWindow()
        Embedded := false
        WBH_CallJS("ahkUpdateEmbed(false)")
        return
    }
    if !WinExist(WinTitle) {
        AddLog("Ошибка встраивания: окно Roblox не найдено", "warn")
        WBH_CallJS("ahkUpdateEmbed(false)")
        return
    }
    GameHwnd := WinExist(WinTitle)
    WinGet, OrigStyle, Style, ahk_id %GameHwnd%
    WinGet, OrigExStyle, ExStyle, ahk_id %GameHwnd%
    OrigParent := DllCall("GetParent", "ptr", GameHwnd, "ptr")
    ; Запоминаем исходную позицию/размер Roblox для восстановления
    WinGetPos, OrigRX, OrigRY, OrigRW, OrigRH, ahk_id %GameHwnd%

    ; ---- Dock без SetParent ----
    ; Roblox остаётся отдельным top-level окном. SetParent превращает его в
    ; дочернее окно AHK и ломает часть DirectX/raw input: клики и клавиши
    ; начинают теряться. Боковая панель просто располагается рядом.
    SysGet, Mon1, MonitorWorkArea
    ; Сохраняем текущую позицию Roblox при закреплении. Раньше dockRX
    ; всегда был Mon1Left, из-за чего игра после короткой паузы уезжала
    ; в левый край монитора.
    dockRX := OrigRX
    dockRY := OrigRY
    totalDockW := GameAreaW + SidebarW
    if (dockRX + totalDockW > Mon1Right)
        dockRX := Mon1Right - totalDockW
    if (dockRX < Mon1Left)
        dockRX := Mon1Left
    WinGet, OrigMainStyle, Style, ahk_id %MainGuiHwnd%
    GuiControl, Move, WB, x0 y0 w%SidebarW% h%GameAreaH%
    sidebarX := dockRX + GameAreaW
    Gui, Show, x%sidebarX% y%dockRY% w%SidebarW% h%GameAreaH%, Mmacro Control

    ; Убираем рамку/заголовок, но не добавляем WS_CHILD и не удаляем WS_POPUP.
    dockStyle := OrigStyle
    dockStyle := dockStyle & ~0x00C00000  ; WS_CAPTION
    dockStyle := dockStyle & ~0x00040000  ; WS_THICKFRAME
    dockStyle := dockStyle & ~0x00800000  ; WS_BORDER
    SetWindowLongPtr(GameHwnd, -16, dockStyle)
    DllCall("SetWindowPos", "ptr", GameHwnd, "ptr", 0
        , "int", dockRX, "int", dockRY, "int", GameAreaW, "int", GameAreaH
        , "uint", 0x0060)  ; SWP_SHOWWINDOW | SWP_FRAMECHANGED
    DllCall("ShowWindow", "ptr", GameHwnd, "int", 5)  ; SW_SHOW

    Sleep, 150
    GetClientSize(GameHwnd, RealW, RealH)
    Embedded := true
    FocusEmbeddedGame()
    ; Не запускаем фоновую синхронизацию: постоянный SetWindowPos панели
    ; сбивал фокус у HTML-элементов. Связка перемещается в ManualDragLoop.
    SetTimer, SyncDockPosition, Off
    WBH_CallJS("ahkUpdateEmbed(true)")
    AddLog("Roblox закреплён рядом с панелью: " RealW "x" RealH " в " dockRX "," dockRY)
return

UnembedGameWindow() {
    global GameHwnd, OrigStyle, OrigExStyle, OrigParent, OrigMainStyle, MainGuiHwnd
    global OrigRX, OrigRY, OrigRW, OrigRH, GameAreaW, SidebarW, GameAreaH
    ; Останавливаем синхронизацию положения
    SetTimer, SyncDockPosition, Off
    if (!GameHwnd || !WinExist("ahk_id " . GameHwnd)) {
        GameHwnd := 0
        return
    }
    WinGetPos, hostX, hostY, , , ahk_id %MainGuiHwnd%
    ; При новом dock Roblox уже top-level. Восстанавливаем родителя только
    ; если он действительно был у окна до закрепления.
    if (OrigParent)
        DllCall("SetParent", "ptr", GameHwnd, "ptr", OrigParent)
    ; Возвращаем исходный стиль Roblox (заголовок/рамка/resize).
    SetWindowLongPtr(GameHwnd, -16, OrigStyle)
    SetWindowLongPtr(GameHwnd, -20, OrigExStyle)
    ; Восстанавливаем позицию/размер (если были сохранены)
    if (OrigRW > 0 && OrigRH > 0)
        DllCall("SetWindowPos", "ptr", GameHwnd, "ptr", 0
            , "int", OrigRX, "int", OrigRY, "int", OrigRW, "int", OrigRH
            , "uint", 0x0060)  ; SWP_SHOWWINDOW | SWP_FRAMECHANGED
    else
        DllCall("SetWindowPos", "ptr", GameHwnd, "ptr", 0
            , "int", 100, "int", 100, "int", 1280, "int", 720, "uint", 0x0060)
    DllCall("ShowWindow", "ptr", GameHwnd, "int", 5)
    ; При dock панель уже является отдельным окном справа от Roblox.
    ; hostX/hostY — её реальные координаты, поэтому GameAreaW здесь
    ; прибавлять нельзя: это уводит Mmacro за пределы экрана.
    sidebarX := hostX
    GuiControl, Move, WB, x0 y0 w%SidebarW% h%GameAreaH%
    Gui, Show, x%sidebarX% y%hostY% w%SidebarW% h%GameAreaH%, Mmacro Control
    Gui, Restore
    WinActivate, ahk_id %MainGuiHwnd%
    if (OrigMainStyle)
        SetWindowLongPtr(MainGuiHwnd, -16, OrigMainStyle)
    GameHwnd := 0
    AddLog("Roblox откреплён, окно восстановлено")
}

; ---- Синхронизация положения сайдбара с окном Roblox (dock) ----
; Roblox остаётся foreground-окном (играбельным), а сайдбар AHK следует
; за его перемещением. При ручном драге панели оба окна перемещаются
; одновременно в ManualDragLoop.
SyncDockPosition:
    global MainGuiHwnd, WinDragActive, SidebarW, GameAreaH
    if (!Embedded)
        return
    if (!GameHwnd || !DllCall("IsWindow", "ptr", GameHwnd)) {
        ; Roblox закрыт — открепляемся
        Embedded := false
        SetTimer, SyncDockPosition, Off
        WBH_CallJS("ahkUpdateEmbed(false)")
        AddLog("Окно Roblox закрыто, сайдбар откреплён")
        return
    }
    ; Roblox и панель — два отдельных окна. Таймер синхронизирует их
    ; положение, не меняя порядок окон и не перехватывая ввод игры.
    ; При системном drag браузерный mouseup может не вернуться в HTML.
    ; Завершаем ускоренный polling самостоятельно после отпускания кнопки.
    if (WinDragActive && !GetKeyState("LButton", "P")) {
        WinDragActive := false
        SetTimer, SyncDockPosition, Off
    }
    ; Проверяем состояние окна Roblox
    WinGet, minMax, MinMax, ahk_id %GameHwnd%
    if (minMax = -1) {
        ; Roblox свёрнут — прячем сайдбар
        if (DllCall("IsWindowVisible", "ptr", MainGuiHwnd))
            DllCall("ShowWindow", "ptr", MainGuiHwnd, "int", 0)  ; SW_HIDE
        return
    }
    if (!DllCall("IsWindowVisible", "ptr", MainGuiHwnd))
        DllCall("ShowWindow", "ptr", MainGuiHwnd, "int", 8)  ; SW_SHOWNA

    ; Roblox — главное окно пары. Панель всегда следует справа от его
    ; фактической позиции. Это исключает скачки влево из-за устаревших
    ; Embed_Last* координат или одновременного движения обоих окон.
    VarSetCapacity(rct, 16, 0)
    if (!DllCall("GetWindowRect", "ptr", GameHwnd, "ptr", &rct))
        return
    rx := NumGet(rct, 0, "Int")
    ry := NumGet(rct, 4, "Int")
    rw := NumGet(rct, 8, "Int") - rx
    newSx := rx + rw
    newSy := ry
    VarSetCapacity(sct, 16, 0)
    if (!DllCall("GetWindowRect", "ptr", MainGuiHwnd, "ptr", &sct))
        return
    sx := NumGet(sct, 0, "Int")
    sy := NumGet(sct, 4, "Int")
    if (sx != newSx || sy != newSy) {
        DllCall("SetWindowPos", "ptr", MainGuiHwnd, "ptr", 0
            , "int", newSx, "int", newSy
            , "int", SidebarW, "int", GameAreaH
            , "uint", 0x0213)  ; SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW | SWP_NOSIZE
    }
return

; Get/SetWindowLongPtr с совместимостью для 32- и 64-битного AutoHotkey.
SetWindowLongPtr(hwnd, index, value) {
    fn := (A_PtrSize = 8) ? "SetWindowLongPtr" : "SetWindowLong"
    return DllCall(fn, "ptr", hwnd, "int", index, "ptr", value, "ptr")
}

; ===================== ВЫБОР КАРТЫ =====================
JoinArr(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i = 1 ? "" : sep) . v
    return out
}

MapChanged:
    Gui, Submit, NoHide
    if (MapCoords.HasKey(SelectedMapCtl))
        AddLog("Карта """ SelectedMapCtl """: " MapCoords[SelectedMapCtl].Length() " слот(ов) размечено")
    else
        AddLog("Карта """ SelectedMapCtl """ ещё НЕ размечена")
    ; Загружаем Post-Rejoin действия для выбранной карты
    if (SelectedMapCtl != "")
        LoadRejoinActions(SelectedMapCtl)
    WriteBotState()
return

BtnClearMap:
    Gui, Submit, NoHide
    if (SelectedMapCtl = "") {
        AddLog("Сначала выбери карту")
        return
    }
    f := MapSlotsFile(SelectedMapCtl)
    if FileExist(f)
        FileDelete, %f%
    MapCoords.Delete(SelectedMapCtl)
    AddLog("Разметка карты """ SelectedMapCtl """ очищена")
return

; ===================== РЕЖИМ И РАСПОЗНАВАНИЕ КАРТЫ =====================
; Кнопка в настройках: показывает, какую карту макрос видит на экране
; "Travelling to...". Заодно переключает панель на эту карту — так удобно
; проверять, что разметка и записанные действия относятся к нужной карте.
MapDetectNow:
    if !WinExist(WinTitle) {
        AddLog("Проверка карты: окно Roblox не найдено", "warn")
        PushMapDetectResult("", 0)
        return
    }
    ; Модалка настроек может закрывать угол с заголовком — прячем её на время
    ; захвата кадра, иначе макрос увидит собственное окно вместо игры.
    hidden := false
    if (ModalHwnd && DllCall("IsWindow", "ptr", ModalHwnd) && DllCall("IsWindowVisible", "ptr", ModalHwnd)) {
        DllCall("ShowWindow", "ptr", ModalHwnd, "int", 0)
        hidden := true
        Sleep, 150
    }
    detected := DetectMapTitle(foundMap, foundScore, true)
    if (hidden)
        DllCall("ShowWindow", "ptr", ModalHwnd, "int", 5)
    if (detected) {
        AddLog("Определена карта: " foundMap " (" foundScore "%)", "success")
        PushMapDetectResult(foundMap, foundScore)
        if (foundMap != SelectedMapCtl) {
            SelectedMapCtl := foundMap
            RefreshMapDropdown()
            Gosub, MapChanged
            AddLog("Панель переключена на """ foundMap """")
        }
    } else {
        if (DetectedOtherMode != "")
            AddLog("Карта " . foundMap . " найдена в режиме " . DetectedOtherMode . ", выбери этот режим", "warn")
        else
            AddLog("Карта не найдена в каталоге выбранного режима", "warn")
        PushMapDetectResult("", foundScore, foundMap, DetectedOtherMode)
    }
return

; Снятие шаблона заголовка: всегда доступно, даже если карта ещё не распознана.
MapCaptureTitle:
    if !WinExist(WinTitle) {
        AddLog("Окно Roblox не найдено — открой игру и экран «Travelling to...»", "warn")
        return
    }
    name := SelectedMapCtl
    if (name = "") {
        InputBox, name, Название карты, Введи название карты для нового шаблона:`n`nОставь Roblox на экране «Travelling to...». ,, 360, 150
        if (ErrorLevel || Trim(name) = "") {
            AddLog("Снятие заголовка отменено: название карты не указано", "warn")
            return
        }
        name := MapFileBase(name)
        if (name = "") {
            AddLog("Снятие заголовка отменено: некорректное название карты", "warn")
            return
        }
    }
    TitleCaptureMap := name
    CaptureForMarking(TempShot)
    MarkMode := "maptitle"
    MarkList := []
    OpenMarkGui("Обведи название карты """ name """ на скриншоте — от левого края первой буквы до правого края последней. Отпусти мышь, шаблон сохранится.")
return

; Смена режима: список карт и разметка перечитываются из maps\<режим>.
SelectGameMode(modeName) {
    global GameMode, SelectedMapCtl, PendingMapChange, MapCoords, MapList, Running
    if (!IsValidGameMode(modeName)) {
        AddLog("Неизвестный режим: " . modeName, "warn")
        WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
        return
    }
    if (Running) {
        AddLog("Сначала останови фарм, чтобы сменить режим", "warn")
        WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
        return
    }
    if (modeName = GameMode) {
        WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
        return
    }
    GameMode := modeName
    SelectedMapCtl := ""
    PendingMapChange := ""
    MapCoords := {}
    InvalidateTitleTemplates()
    SaveSettings()
    ReloadMapList()
    LoadAllMapCoords()
    RefreshMapDropdown()
    WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
    WBH_CallJS("ahkUpdateMap('')")
    WriteBotState()
    AddLog("Режим: " . GameModeLabel(GameMode) . " (карт: " . MapList.Length() . ")", "success")
}

; ===================== СНИМОК КАРТЫ =====================
BtnCaptureMap:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    AddLog("Снимок сделан, открываю превью...")
    ShowSnapshotPreview()
return

ShowSnapshotPreview() {
    global TempShot
    ; Открываем HTML-модалку snap для превью снимка
    OpenModalWindow("snap", "Snapshot Preview", 700, 560)
    shotPath := TempShot
    StringReplace, shotPath, shotPath, \, /, All
    shotURL := "file:///" . shotPath . "?_=" . A_TickCount
    PushModalData("snap")
    ModalCallJS("ahkLoadSnap('" . shotURL . "')")
}

SnapConfirm:
    ; SnapName приходит из HTML-модалки (поле ввода), SnapName задан в PollModalClose
    global TempShot, SelectedMapCtl
    if (SnapName = "") {
        AddLog("Имя не указано, снимок не сохранён")
        return
    }
    ; Имя карты = имя файла снимка. Недопустимые символы заменяются, иначе
    ; FileCopy молча не сработает и карта не появится в списке.
    MapName := MapFileBase(SnapName)
    if (MapName = "") {
        AddLog("Имя карты пустое после замены недопустимых символов", "warn")
        return
    }
    FinalPath := ModeDir() . "\" . MapName . ".bmp"
    FileCopy, %TempShot%, %FinalPath%, 1
    if (ErrorLevel) {
        AddLog("Не удалось сохранить снимок: " . FinalPath, "error")
        return
    }
    AddLog("Снимок карты сохранён: " . FinalPath)
    ; Появляется в списке карт сразу после сохранения снимка
    ReloadMapList()
    SelectedMapCtl := MapName
    RefreshMapDropdown()
    AddLog("Карта """ . MapName . """ добавлена в список")
    ; Закрываем модалку снимка
    SetTimer, PollModalClose, Off
    Gui, Modal:Destroy
    ModalHwnd := 0
return

SnapCancel:
    SetTimer, PollModalClose, Off
    Gui, Modal:Destroy
    ModalHwnd := 0
    AddLog("Снимок отклонён, не сохранён")
return

; ===================== СКРИНШОТ ОБЛАСТИ ИГРЫ =====================
CaptureGameArea(filepath) {
    global GameAreaW, GameAreaH, LastCaptureX, LastCaptureY, LastCaptureW, LastCaptureH
    ; Игровая область: при dock-встраивании это клиентская область Roblox,
    ; иначе — главное окно AHK. GameAreaOrigin выбирает нужный HWND.
    if (!GameAreaOrigin(LastCaptureX, LastCaptureY)) {
        AddLog("CaptureGameArea: игровое окно недоступно")
        return
    }
    LastCaptureW := GameAreaW
    LastCaptureH := GameAreaH
    CaptureScreenshot(LastCaptureX, LastCaptureY, LastCaptureW, LastCaptureH, filepath)
    ; Если кадр вышел почти чёрным (игра свёрнута/не видна на экране) —
    ; пробуем PrintWindow по HWND игры
    if (IsMostlyBlack(filepath)) {
        AddLog("Захват экрана дал чёрный кадр, пробую PrintWindow...")
        if (CaptureGameWindow(filepath))
            return
        AddLog("PrintWindow тоже не дал кадр. Убедись, что Roblox встроен и виден на экране.")
    }
}

; ---- Захват окна игры через PrintWindow (запасной вариант) ----
CaptureGameWindow(filepath) {
    global GameHwnd, GameAreaW, GameAreaH, Embedded, WinTitle
    captureHwnd := (Embedded && GameHwnd) ? GameHwnd : WinExist(WinTitle)
    if (!captureHwnd || !WinExist("ahk_id " . captureHwnd))
        return false
    hdcWin := DllCall("GetDC", "ptr", captureHwnd, "ptr")
    if (!hdcWin)
        return false
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcWin, "ptr")
    hBmp   := DllCall("CreateCompatibleBitmap", "ptr", hdcWin, "int", GameAreaW, "int", GameAreaH, "ptr")
    hOld   := DllCall("SelectObject", "ptr", hdcMem, "ptr", hBmp, "ptr")
    ; PW_RENDERFULLCONTENT (0x2) — захват DirectX-контента
    ok := DllCall("PrintWindow", "ptr", captureHwnd, "ptr", hdcMem, "uint", 0x2)
    DllCall("SelectObject", "ptr", hdcMem, "ptr", hOld)
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", captureHwnd, "ptr", hdcWin)
    if (!ok) {
        DllCall("DeleteObject", "ptr", hBmp)
        return false
    }
    SaveHBITMAPToBMP(hBmp, filepath, GameAreaW, GameAreaH)
    DllCall("DeleteObject", "ptr", hBmp)
    return !IsMostlyBlack(filepath)
}

; ---- Проверка: не является ли кадр почти чёрным (сетка 5x5 точек) ----
IsMostlyBlack(filepath) {
    if !FileExist(filepath)
        return true
    file := FileOpen(filepath, "r")
    if !file
        return true
    w := 1280
    h := 720
    stride := ((w*3+3)//4)*4
    total := 0, n := 0
    Loop 5 {
        px := w//5 * A_Index - w//10
        Loop 5 {
            py := h//5 * A_Index - h//10
            file.Seek(54 + py*stride + px*3)
            b := file.ReadUChar()
            g := file.ReadUChar()
            r := file.ReadUChar()
            total += r + g + b
            n++
        }
    }
    file.Close()
    ; средний канал < 10 → почти чёрный
    return (total < n*30)
}

; ---- Захват с временным скрытием модального окна ----
; Прячет модальное окно калибровки/настроек (если открыто), чтобы оно не
; заслоняло игровую область при BitBlt, затем захватывает и возвращает окно.
CaptureForMarking(filepath) {
    global ModalHwnd
    hidden := false

    ; Прячем модальное окно если открыто
    if (ModalHwnd && DllCall("IsWindow", "ptr", ModalHwnd) && DllCall("IsWindowVisible", "ptr", ModalHwnd)) {
        DllCall("ShowWindow", "ptr", ModalHwnd, "int", 0)
        hidden := true
    }
    ; Sleep чтобы DWM успел перерисовать без модального окна
    Sleep, 150

    CaptureGameArea(filepath)

    ; Возвращаем модальное окно обратно
    if (hidden)
        DllCall("ShowWindow", "ptr", ModalHwnd, "int", 5)
}

CaptureScreenshot(x, y, w, h, filepath) {
    hDesktopDC := DllCall("GetDC", "ptr", 0, "ptr")
    hCaptureDC := DllCall("CreateCompatibleDC", "ptr", hDesktopDC, "ptr")
    hBitmap := DllCall("CreateCompatibleBitmap", "ptr", hDesktopDC, "int", w, "int", h, "ptr")
    hOld := DllCall("SelectObject", "ptr", hCaptureDC, "ptr", hBitmap, "ptr")
    ; SRCCOPY + CAPTUREBLT: захватываем и layered-компоненты окна Roblox.
    DllCall("BitBlt", "ptr", hCaptureDC, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hDesktopDC, "int", x, "int", y, "uint", 0x40CC0020)
    DllCall("SelectObject", "ptr", hCaptureDC, "ptr", hOld)
    DllCall("DeleteDC", "ptr", hCaptureDC)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hDesktopDC)
    SaveHBITMAPToBMP(hBitmap, filepath, w, h)
    DllCall("DeleteObject", "ptr", hBitmap)
}

SaveHBITMAPToBMP(hBitmap, filepath, w, h) {
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "UInt")
    NumPut(w, bi, 4, "Int")
    NumPut(-h, bi, 8, "Int")
    NumPut(1, bi, 12, "UShort")
    NumPut(24, bi, 14, "UShort")
    NumPut(0, bi, 16, "UInt")
    stride := ((w*3+3)//4)*4
    imageSize := stride*h
    VarSetCapacity(pixels, imageSize, 0)
    DllCall("GetDIBits", "ptr", hdc, "ptr", hBitmap, "uint", 0, "uint", h
        , "ptr", &pixels, "ptr", &bi, "uint", 0)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    VarSetCapacity(fh, 14, 0)
    NumPut(0x4D42, fh, 0, "UShort")
    fileSize := 14 + 40 + imageSize
    NumPut(fileSize, fh, 2, "UInt")
    NumPut(14 + 40, fh, 10, "UInt")
    ; FileOpen "w" сам перезапишет файл; FileDelete перед этим опасен:
    ; если между удалением и созданием произойдёт сбой, файл пропадёт.
    file := FileOpen(filepath, "w")
    file.RawWrite(&fh, 14)
    file.RawWrite(&bi, 40)
    file.RawWrite(&pixels, imageSize)
    file.Close()
}

; ===================== РАЗМЕТКА СЛОТОВ КАРТЫ =====================
BtnMarkSlots:
    Gui, Submit, NoHide
    if (SelectedMapCtl = "")
        Gosub, MapDetectNow
    if (SelectedMapCtl = "") {
        AddLog("Карта не определена автоматически. Открой экран Travelling to... и повтори разметку", "warn")
        return
    }
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "slots"
    ; Загружаем существующие слоты, если карта уже была размечена ранее
    if (MapCoords.HasKey(SelectedMapCtl)) {
        ; Клонируем чтобы не испортить оригинал при редактировании
        src := MapCoords[SelectedMapCtl]
        MarkList := []
        for i, v in src
            MarkList.Push({num: v.num, x: v.x, y: v.y})
    } else {
        MarkList := []
    }
    OpenMarkGui("Кликай по местам постановки юнитов (номер юнита спросит после каждого клика)")
    ; Показываем уже существующие слоты в списке
    Loop, % MarkList.Length() {
        s := MarkList[A_Index]
        GuiControl, Mark:, MarkListBox, % "Слот " A_Index ": юнит " s.num " -> (" s.x "," s.y ")"
    }
return

; ===================== КАЛИБРОВКА UPGRADE =====================
BtnCalibrateUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_upgrade"
    OpenMarkGui("Кликни на кнопку Upgrade")
return

; ===================== КАЛИБРОВКА START GAME =====================
BtnCalibrateStartGame:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_startgame"
    OpenMarkGui("Кликни на кнопку Start Game")
return

; ===================== КАЛИБРОВКА REPEAT STAGE =====================
BtnCalibrateRepeatStage:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_repeatstage"
    OpenMarkGui("Кликни на кнопку Repeat Stage")
return

; ===================== СНЯТИЕ ШАБЛОНА (Defeat/Victory) =====================
; Захватывает кадр, пользователь обводит 2 кликами небольшую область,
; макрос вырезает её в images\<имя>.png для ImageSearch-детекта.
BtnCaptureTemplate:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := ""
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи область (например слово VICTORY). Отпусти — шаблон сохранится.")
return

; ===================== СНЯТИЕ ШАБЛОНА КНОПКИ START GAME =====================
; То же самое, что Defeat/Victory, но имя шаблона задано заранее (StartGame) —
; без запроса имени. Потом этот шаблон ищет ClickStartGameRetry.
BtnCaptureStartGame:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "StartGame"
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи часть кнопки Start Game (слово START или иконку, БЕЗ рамки и краёв). Отпусти — шаблон сохранится как StartGame.bmp.")
return

SaveTemplateRegion(x1, y1, x2, y2) {
    global TempShot, ImagesDir, TemplateName, MarkMode
    ; Нормализуем углы
    if (x1 > x2) {
        t := x1, x1 := x2, x2 := t
    }
    if (y1 > y2) {
        t := y1, y1 := y2, y2 := t
    }
    ; Шаблон заголовка карты: сохраняется в maps\<режим>\<карта>_title.bmp.
    if (MarkMode = "maptitle") {
        MarkMode := ""
        SaveMapTitle(x1, y1, x2, y2)
        return
    }
    w := x2 - x1 + 1
    h := y2 - y1 + 1
    if (w < 8 || h < 8) {
        AddLog("Область слишком маленькая (" w "x" h "), шаблон не сохранён")
        return
    }
    ; Имя: либо задано заранее (Start Game), либо спрашиваем у пользователя (Defeat/Victory)
    if (TemplateName != "") {
        TplName := TemplateName
        TemplateName := ""
    } else {
        InputBox, TplName, Имя шаблона, Введи имя для шаблона (например: Victory или Defeat), , 320, 140
        if (ErrorLevel || TplName = "") {
            AddLog("Сохранение шаблона отменено")
            return
        }
    }
    ; Сохраняем как BMP (ImageSearch отлично работает с BMP, GDI+ не нужен)
    out := ImagesDir . "\" . TplName . ".bmp"
    if !CropBMP(TempShot, x1, y1, w, h, out) {
        AddLog("Не удалось вырезать шаблон")
        return
    }
    AddLog("Шаблон сохранён: images\" TplName ".bmp (" w "x" h ")")
    ; Сразу проверяем, что шаблон реально находится на экране
    if (FindGameButton(out, fx, fy))
        AddLog("Проверка: шаблон найден на экране в (" fx "," fy ") — детект будет работать!")
    else
        AddLog("ВНИМАНИЕ: шаблон НЕ найден на текущем экране. Проверь, что игра не изменилась после снятия кадра.")
}

; ---- Вырезает прямоугольную область из 24-бит BMP (src 1280x720) в новый BMP ----
CropBMP(srcBmp, x, y, w, h, dstBmp) {
    global GameAreaW, GameAreaH
    if !FileExist(srcBmp)
        return false
    src := FileOpen(srcBmp, "r")
    if !src
        return false
    ; 24-бит BMP, отрицательная высота = сверху вниз (как у нас в SaveHBITMAPToBMP)
    srcStride := ((GameAreaW*3+3)//4)*4
    dstStride := ((w*3+3)//4)*4
    ; Читаем строки y..y+h-1 из исходника, пишем в новый файл
    dst := FileOpen(dstBmp, "w")
    if !dst {
        src.Close()
        return false
    }
    ; Заголовок нового BMP
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "UInt")
    NumPut(w, bi, 4, "Int")
    NumPut(-h, bi, 8, "Int")   ; top-down
    NumPut(1, bi, 12, "UShort")
    NumPut(24, bi, 14, "UShort")
    VarSetCapacity(fh, 14, 0)
    NumPut(0x4D42, fh, 0, "UShort")
    NumPut(14 + 40 + dstStride*h, fh, 2, "UInt")
    NumPut(14 + 40, fh, 10, "UInt")
    dst.RawWrite(&fh, 14)
    dst.RawWrite(&bi, 40)
    ; Копируем пиксели построчно
    VarSetCapacity(rowBuf, srcStride, 0)
    Loop, %h% {
        row := y + A_Index - 1
        src.Seek(54 + row*srcStride + x*3)
        src.RawRead(&rowBuf, w*3)
        ; Дополняем строку нулями до dstStride
        if (dstStride > w*3) {
            VarSetCapacity(pad, dstStride - w*3, 0)
            dst.RawWrite(&rowBuf, w*3)
            dst.RawWrite(&pad, dstStride - w*3)
        } else {
            dst.RawWrite(&rowBuf, w*3)
        }
    }
    src.Close()
    dst.Close()
    return FileExist(dstBmp)
}

OpenMarkGui(promptText) {
    global TempShot, MarkMode, MarkList
    ; Открываем HTML-модалку mark. Размер — под картинку 1280x720 + панель.
    OpenModalWindow("mark", "Marking", 1320, 820)
    ; Путь к снимку для <img src>. file:/// + прямой слеш.
    shotPath := TempShot
    StringReplace, shotPath, shotPath, \, /, All
    shotURL := "file:///" . shotPath . "?_=" . A_TickCount
    ; Режим модалки: 'template'/'maptitle' — обвод области, 'slots' —
    ; расстановка юнитов (с попапом выбора номера), 'calib' — калибровка кнопок
    ; (просто клик-точка, без номера юнита).
    if (MarkMode = "template" || MarkMode = "maptitle")
        mode := "template"
    else if (InStr(MarkMode, "abs_"))
        mode := "calib"
    else
        mode := "slots"
    safePrompt := StrReplace(promptText, "'", "\'")
    safePrompt := StrReplace(safePrompt, """", "\""")
    PushModalData("mark")
    ModalCallJS("ahkLoadMark('" . shotURL . "', '" . mode . "', """ . safePrompt . """)")
    ; Сразу показываем уже размеченные слоты (если редактируем существующую карту)
    SendMarkSlotsToModal()
}

; ---- Отправка текущего списка слотов MarkList в HTML-модалку ----
SendMarkSlotsToModal() {
    global MarkList, MarkMode
    if (MarkMode = "template" || MarkMode = "maptitle")
        return  ; для шаблонов список слотов не нужен
    slotsStr := ""
    for i, s in MarkList {
        if (i > 1)
            slotsStr .= "|"
        slotsStr .= s.num . "," . s.x . "," . s.y
    }
    ModalCallJS("ahkSetMarkSlots('" . slotsStr . "')")
}


; ---- Команды mark-* из HTML-модалки ----
; mark-click: arg = "x/y" — калибровка кнопок (abs_*). Слоты теперь идут
; через отдельную команду mark-unit-num (номер выбирается в HTML-попапе,
; а не системным InputBox).
MarkClick:
    px := 0, py := 0
    StringSplit, mp, arg, /
    px := mp1
    py := mp2
    if (MarkMode = "abs_upgrade") {
        UpgradeX := px
        UpgradeY := py
        ModalCallJS("ahkSetMarkSlots('" px "," py ",0')")
    }
    else if (MarkMode = "abs_startgame") {
        StartGameX := px
        StartGameY := py
        ModalCallJS("ahkSetMarkSlots('" px "," py ",0')")
    }
    else if (MarkMode = "abs_repeatstage") {
        RepeatStageX := px
        RepeatStageY := py
        ModalCallJS("ahkSetMarkSlots('" px "," py ",0')")
    }
return

; ---- mark-unit-num: добавление слота (номер выбран в HTML-попапе) ----
; arg = "x/y/n" — координаты в пикселях исходника + номер юнита 1-6
MarkUnitNum:
    StringSplit, un, arg, /
    unX := un1, unY := un2, unN := un3
    if (MarkMode = "slots") {
        MarkList.Push({num: unN, x: unX, y: unY})
        SendMarkSlotsToModal()
    }
return

MarkUndo:
    if (MarkMode = "slots") {
        if (MarkList.Length() > 0)
            MarkList.Pop()
        SendMarkSlotsToModal()
    }
return

MarkDone:
    Gui, 1:Default
    if (MarkMode = "slots") {
        if (MarkList.Length() = 0) {
            AddLog("Разметка отменена: слотов не добавлено")
        } else {
            SaveMapSlots(SelectedMapCtl, MarkList)
            LoadMapCoordsOne(SelectedMapCtl)
            AddLog("Сохранено " MarkList.Length() " слотов для """ SelectedMapCtl """")
        }
    } else if (MarkMode = "abs_upgrade") {
        SaveConfig()
        AddLog("Калибровка Upgrade сохранена: (" UpgradeX "," UpgradeY ")")
    } else if (MarkMode = "abs_startgame") {
        SaveConfig()
        AddLog("Калибровка Start Game сохранена: (" StartGameX "," StartGameY ")")
    } else if (MarkMode = "abs_repeatstage") {
        SaveConfig()
        AddLog("Калибровка RepeatStage сохранена: (" RepeatStageX "," RepeatStageY ")")
    }
    MarkMode := ""
    SetTimer, PollModalClose, Off
    Gui, Modal:Destroy
    ModalHwnd := 0
    UpdateCoordsHTML()
    PushModalData("calibrate")
return

MarkCancel:
    MarkMode := ""
    TemplateName := ""
    TitleCaptureMap := ""
    AddLog("Разметка/калибровка отменена пользователем")
    SetTimer, PollModalClose, Off
    Gui, Modal:Destroy
    ModalHwnd := 0
return

; ===================== НАСТРОЙКИ (диалог) =====================
BtnSettings:
    OpenModalWindow("settings", "Settings", 480, 660)
return

; ===================== ПРЕСЕТЫ (отдельное окно) =====================
BtnOpenPresets:
    OpenModalWindow("presets", "Presets", 440, 370)
return

; ===================== КАЛИБРОВКА (отдельное окно) =====================
BtnOpenCalibration:
    OpenModalWindow("calibrate", "Calibration", 460, 550)
return

; ---- Проверка детекта победы/поражения на текущем экране ----
BtnTestDetection:
    global ImagesDir
    if (DetectVictory())
        AddLog("Проверка: VICTORY обнаружен на экране!")
    else if (DetectDefeat())
        AddLog("Проверка: DEFEAT обнаружен на экране!")
    else {
        AddLog("Проверка: ни VICTORY, ни DEFEAT не найдены на текущем экране.")
        if (!FileExist(ImagesDir . "\Victory.bmp") && !FileExist(ImagesDir . "\Victory.png"))
            AddLog("Victory-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон».")
        if (!FileExist(ImagesDir . "\Defeat.bmp") && !FileExist(ImagesDir . "\Defeat.png"))
            AddLog("Defeat-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон».")
        AddLog("Совет: открой экран победы в игре и нажми «Снять шаблон» ещё раз, обведя слово VICTORY.")
    }
return

; ---- Проверка детекта кнопки Start Game на текущем экране ----
BtnTestStartGame:
    global ImagesDir
    full := ImagesDir . "\StartGame.bmp"
    if !FileExist(full)
        full := ImagesDir . "\StartGame.png"
    if !FileExist(full) {
        AddLog("Проверка: StartGame-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон Start Game».")
        AddLog("Совет: открой в игре экран с кнопкой Start Game и сними шаблон, обведя ЧАСТЬ кнопки (слово START).")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("Проверка: StartGame-шаблон слишком большой — ImageSearch его не найдёт. Сними шаблон поменьше (обведи только слово START).")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: Start Game найден на экране в (" bx "," by ") — детект будет работать!")
    else
        AddLog("Проверка: Start Game НЕ найден на текущем экране. Открой экран с кнопкой Start Game и нажми проверку ещё раз.")
return

CalibStatusText() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    return "Up(" UpgradeX "," UpgradeY ")  Auto(" AutoX "," AutoY ")  Start(" StartGameX "," StartGameY ")  Repeat(" RepeatStageX "," RepeatStageY ")"
}

; Обновляет координаты в HTML-модалке калибровки (если открыта) и в сайдбаре.
UpdateCalibStatus() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    UpdateCoordsHTML()
    ; Если открыта модалка калибровки — обновим карточки координат в ней
    PushModalData("calibrate")
}

BtnPresetSave:
    ; PresetName задаётся модальным окном (из JS-моста).
    if (PresetName = "") {
        AddLog("Сохранение пресета отменено: имя не указано", "warn")
        return
    }
    ; ---- 1. Координаты кнопок (калибровка) ----
    IniWrite, %UpgradeX%,     %PresetsIni%, %PresetName%, UpgradeX
    IniWrite, %UpgradeY%,     %PresetsIni%, %PresetName%, UpgradeY
    IniWrite, %AutoX%,        %PresetsIni%, %PresetName%, AutoX
    IniWrite, %AutoY%,        %PresetsIni%, %PresetName%, AutoY
    IniWrite, %StartGameX%,   %PresetsIni%, %PresetName%, StartGameX
    IniWrite, %StartGameY%,   %PresetsIni%, %PresetName%, StartGameY
    IniWrite, %RepeatStageX%, %PresetsIni%, %PresetName%, RepeatStageX
    IniWrite, %RepeatStageY%, %PresetsIni%, %PresetName%, RepeatStageY
    ; ---- 2. Задержки (Delays) ----
    IniWrite, %ClickDelay%,        %PresetsIni%, %PresetName%, ClickDelay
    IniWrite, %SlotClickDelay%,    %PresetsIni%, %PresetName%, SlotClickDelay
    IniWrite, %UpgradeClickDelay%, %PresetsIni%, %PresetName%, UpgradeClickDelay
    IniWrite, %AutoClickDelay%,    %PresetsIni%, %PresetName%, AutoClickDelay
    IniWrite, %UnitSleepDelay%,    %PresetsIni%, %PresetName%, UnitSleepDelay
    IniWrite, %StartGameDelay%,    %PresetsIni%, %PresetName%, StartGameDelay
    IniWrite, %HoverDelay%,        %PresetsIni%, %PresetName%, HoverDelay
    IniWrite, %MouseSpeed%,        %PresetsIni%, %PresetName%, MouseSpeed
    IniWrite, % (MouseSpeedEnabled ? 1 : 0), %PresetsIni%, %PresetName%, MouseSpeedEnabled
    IniWrite, % (ZoomEnabled ? 1 : 0), %PresetsIni%, %PresetName%, ZoomEnabled
    IniWrite, %ZoomScrolls%,       %PresetsIni%, %PresetName%, ZoomScrolls
    IniWrite, % (TopCameraEnabled ? 1 : 0), %PresetsIni%, %PresetName%, TopCameraEnabled
    ; ---- 3. Поиск изображений (ImageSearch) ----
    IniWrite, %ImgVariation%, %PresetsIni%, %PresetName%, ImgVariation
    ; ---- 4. Поиск пикселя (PixelSearch) ----
    IniWrite, %StartGameColor%,    %PresetsIni%, %PresetName%, StartGameColor
    IniWrite, %StartGameColorVar%, %PresetsIni%, %PresetName%, StartGameColorVar
    IniWrite, %StartGameCenterX%,  %PresetsIni%, %PresetName%, StartGameCenterX
    IniWrite, %StartGameCenterY%,  %PresetsIni%, %PresetName%, StartGameCenterY
    IniWrite, %StartGameRadius%,   %PresetsIni%, %PresetName%, StartGameRadius
    ; ---- 5. Слоты всех карт (расположение юнитов) ----
    IniWrite, %GameMode%, %PresetsIni%, %PresetName%, GameMode
    IniWrite, % MapList.Length(), %PresetsIni%, %PresetName%, MapCount
    for idx, mapName in MapList {
        nameKey := "Map_" idx "_Name"
        IniWrite, %mapName%, %PresetsIni%, %PresetName%, %nameKey%
        if (MapCoords.HasKey(mapName)) {
            slots := MapCoords[mapName]
            slotCount := slots.Length()
        } else {
            slotCount := 0
        }
        cntKey := "Map_" idx "_SlotCount"
        IniWrite, %slotCount%, %PresetsIni%, %PresetName%, %cntKey%
        Loop, %slotCount% {
            s := slots[A_Index]
            slotKey := "Map_" idx "_Slot_" A_Index
            line := s.num . "," . s.x . "," . s.y
            IniWrite, %line%, %PresetsIni%, %PresetName%, %slotKey%
        }
    }
    AddLog("Пресет """ PresetName """ сохранён (координаты + настройки + слоты всех карт)")
return

BtnPresetLoad:
    ; PresetName задаётся модальным окном (из JS-моста).
    if (PresetName = "") {
        AddLog("Загрузка пресета отменена: имя не указано", "warn")
        return
    }
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeX, __NONE__
    if (v = "__NONE__") {
        AddLog("Пресет """ PresetName """ не найден", "warn")
        return
    }
    ; ---- 1. Координаты кнопок ----
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeX, 0
    UpgradeX := v
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeY, 0
    UpgradeY := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoX, 0
    AutoX := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoY, 0
    AutoY := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameX, 0
    StartGameX := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameY, 0
    StartGameY := v
    IniRead, v, %PresetsIni%, %PresetName%, RepeatStageX, 0
    RepeatStageX := v
    IniRead, v, %PresetsIni%, %PresetName%, RepeatStageY, 0
    RepeatStageY := v
    ; ---- 2. Задержки ----
    IniRead, v, %PresetsIni%, %PresetName%, ClickDelay, %ClickDelay%
    ClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, SlotClickDelay, %SlotClickDelay%
    SlotClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeClickDelay, %UpgradeClickDelay%
    UpgradeClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoClickDelay, %AutoClickDelay%
    AutoClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, UnitSleepDelay, %UnitSleepDelay%
    UnitSleepDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameDelay, %StartGameDelay%
    StartGameDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, HoverDelay, %HoverDelay%
    HoverDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, MouseSpeed, %MouseSpeed%
    MouseSpeed := v
    IniRead, v, %PresetsIni%, %PresetName%, MouseSpeedEnabled, %MouseSpeedEnabled%
    MouseSpeedEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %PresetsIni%, %PresetName%, ZoomEnabled, %ZoomEnabled%
    ZoomEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %PresetsIni%, %PresetName%, TopCameraEnabled, %TopCameraEnabled%
    TopCameraEnabled := (v = 1 || v = "true") ? true : false
    IniRead, v, %PresetsIni%, %PresetName%, ZoomScrolls, %ZoomScrolls%
    ZoomScrolls := v
    if (ZoomScrolls < -50 || ZoomScrolls > 50)
        ZoomScrolls := 0
    ; ---- 3. ImageSearch ----
    IniRead, v, %PresetsIni%, %PresetName%, ImgVariation, %ImgVariation%
    ImgVariation := v
    ; ---- 4. PixelSearch ----
    IniRead, v, %PresetsIni%, %PresetName%, StartGameColor, %StartGameColor%
    StartGameColor := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameColorVar, %StartGameColorVar%
    StartGameColorVar := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameCenterX, %StartGameCenterX%
    StartGameCenterX := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameCenterY, %StartGameCenterY%
    StartGameCenterY := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameRadius, %StartGameRadius%
    StartGameRadius := v
    ; ---- 5. Сохраняем загруженные значения в config.ini и settings.ini ----
    SaveConfig()
    SaveSettings()
    ; ---- 5a. Режим из пресета (если указан) ----
    IniRead, presetMode, %PresetsIni%, %PresetName%, GameMode, __NONE__
    if (presetMode != "__NONE__" && presetMode != "ERROR" && presetMode != "" && IsValidGameMode(presetMode) && presetMode != GameMode) {
        GameMode := presetMode
        SelectedMapCtl := ""
        MapCoords := {}
        InvalidateTitleTemplates()
        ReloadMapList()
        LoadAllMapCoords()
        RefreshMapDropdown()
        WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
        WBH_CallJS("ahkUpdateMap('')")
        AddLog("Пресет переключил режим: " . GameModeLabel(GameMode))
    }
    ; ---- 6. Слоты всех карт ----
    IniRead, mapCount, %PresetsIni%, %PresetName%, MapCount, 0
    Loop, %mapCount% {
        idx := A_Index
        nameKey := "Map_" idx "_Name"
        IniRead, mapName, %PresetsIni%, %PresetName%, %nameKey%, __NONE__
        if (mapName = "" || mapName = "ERROR" || mapName = "__NONE__")
            continue
        cntKey := "Map_" idx "_SlotCount"
        IniRead, slotCount, %PresetsIni%, %PresetName%, %cntKey%, 0
        slotList := []
        Loop, %slotCount% {
            slotKey := "Map_" idx "_Slot_" A_Index
            IniRead, slotLine, %PresetsIni%, %PresetName%, %slotKey%, __NONE__
            if (slotLine = "" || slotLine = "ERROR" || slotLine = "__NONE__")
                continue
            StringSplit, p, slotLine, `,
            slotList.Push({num: p1, x: p2, y: p3})
        }
        ; Записываем слоты в файл карты и обновляем MapCoords
        SaveMapSlots(mapName, slotList)
        LoadMapCoordsOne(mapName)
    }
    ; ---- 7. Обновляем UI ----
    ReloadMapList()
    LoadAllMapCoords()
    RefreshMapDropdown()
    UpdateCoordsHTML()
    UpdateCalibStatus()
    AddLog("Пресет """ PresetName """ загружен (координаты + настройки + слоты карт применены и записаны на диск)")
return

BtnPresetDelete:
    ; PresetName задаётся модальным окном (из JS-моста).
    if (PresetName = "") {
        AddLog("Удаление пресета отменено: имя не указано", "warn")
        return
    }
    if (DeletePresetSection(PresetName))
        AddLog("Пресет """ PresetName """ удалён")
    else
        AddLog("Не удалось удалить пресет """ PresetName """", "error")
return

; ===================== КАЛИБРОВКА (отдельное окно) =====================

; ===================== НАСТРОЙКИ АВТОПРОКАЧКИ =====================
AutoUpgradeToggle:
    ; AutoUpgradeEnabled уже обновлён через ProcessJSCmd ("toggle-autoupgrade")
return

BtnOpenAutoUpgradeSettings:
    OpenModalWindow("upgrade", "Auto Upgrade", 360, 320)
return

BtnCaptureAutoUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "AutoUpgrade"
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи кнопку AutoUpgrade. Отпусти — шаблон сохранится как AutoUpgrade.bmp.")
return

; ===================== ФАРМ ТОЛЬКО ЧЕРЕЗ AUTOPLAY =====================
; Для надёжности используются два отдельных шаблона кнопки:
; AutoPlayOff.bmp и AutoPlayOn.bmp. Снимай только кнопку, без большого фона.
BtnCaptureAutoPlayOff:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "AutoPlayOff"
    MarkList := []
    OpenMarkGui("Обведи кнопку AutoPlay в выключенном состоянии. Отпусти — шаблон сохранится как AutoPlayOff.bmp.")
return

BtnCaptureAutoPlayOn:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "AutoPlayOn"
    MarkList := []
    OpenMarkGui("Обведи кнопку AutoPlay во включенном состоянии. Отпусти — шаблон сохранится как AutoPlayOn.bmp.")
return

BtnTestAutoPlayOff:
    full := AutoPlayTemplateFile("off")
    if !FileExist(full) {
        AddLog("AutoPlayOff-шаблон отсутствует в images\\ — сначала сними выключенную кнопку.", "warn")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("AutoPlayOff-шаблон слишком большой — сними только кнопку или её текст.", "warn")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: выключенный AutoPlay найден в (" bx "," by ")")
    else
        AddLog("Проверка: выключенный AutoPlay не найден на текущем экране", "warn")
return

BtnTestAutoPlayOn:
    full := AutoPlayTemplateFile("on")
    if !FileExist(full) {
        AddLog("AutoPlayOn-шаблон отсутствует в images\\ — сначала сними включённую кнопку.", "warn")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("AutoPlayOn-шаблон слишком большой — сними только кнопку или её текст.", "warn")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: включённый AutoPlay найден в (" bx "," by ")")
    else
        AddLog("Проверка: включённый AutoPlay не найден на текущем экране", "warn")
return

BtnTestAutoUpgrade:
    global ImagesDir
    full := ImagesDir . "\AutoUpgrade.bmp"
    if !FileExist(full)
        full := ImagesDir . "\AutoUpgrade.png"
    if !FileExist(full) {
        AddLog("AutoUpgrade-шаблон отсутствует в images\ — сначала сними его.")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("AutoUpgrade-шаблон слишком большой — ImageSearch не найдёт. Сними шаблон поменьше.")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: AutoUpgrade найден на экране в (" bx "," by ") — детект будет работать!")
    else
        AddLog("Проверка: AutoUpgrade НЕ найден. Открой экран где видна кнопка AutoUpgrade.")
return

; ===================== СНЯТИЕ ШАБЛОНА ЭКРАНА DISCONNECTED =====================
; Тот же механизм, что и Start Game — заранее заданное имя (Disconnected),
; без запроса имени. Потом этот шаблон ищет DetectDisconnected() в WatchNextStage,
; чтобы 100% ловить именно диалог "Disconnected / Error Code: 277", а не полагаться
; только на исчезновение окна (диалог показывается ВНУТРИ ещё живого окна Roblox).
BtnCaptureDisconnected:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "Disconnected"
    MarkList := []
    OpenMarkGui("Дождись экрана ""Disconnected"" (Error Code: 277) и обведи слово Disconnected или Reconnect, БЕЗ лишнего фона. Отпусти — шаблон сохранится как Disconnected.bmp.")
return

BtnTestDisconnected:
    global ImagesDir
    full := ImagesDir . "\Disconnected.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Disconnected.png"
    if !FileExist(full) {
        AddLog("Проверка: Disconnected-шаблон отсутствует в images\ — сначала сними его кнопкой «Capture Disconnected Screen».")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("Проверка: Disconnected-шаблон слишком большой — ImageSearch его не найдёт. Сними шаблон поменьше.")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: экран Disconnected найден на экране в (" bx "," by ") — детект будет работать!")
    else
        AddLog("Проверка: экран Disconnected НЕ найден. Открой в игре диалог Disconnected и попробуй снова.")
return

; ===================== СТАРТ / СТОП ФАРМА =====================
BtnStartStop:
FarmHotkeyAction:
    if (FarmMode != "autoplay") {
        if (SelectedMapCtl = "") {
            Gosub, MapDetectNow
        }
        if (SelectedMapCtl = "") {
            AddLog("Карта не определена автоматически. Дождись экрана Travelling to... и попробуй снова", "warn")
            WBH_CallJS("ahkUpdateStatus('Map not detected', 'error')")
            return
        }
        if (!MapCoords.HasKey(SelectedMapCtl)) {
            AddLog("Нельзя запустить: """ SelectedMapCtl """ не размечена", "warn")
            WBH_CallJS("ahkUpdateStatus('Map not marked', 'error')")
            return
        }
    }
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена", "warn")
        WBH_CallJS("ahkUpdateStatus('Game not found', 'error')")
        return
    }
    Running := !Running
    if (Running) {
        FarmRunCount := 0
        StartZoomApplied := false
        PendingMapChange := ""
        WBH_CallJS("ahkUpdateFarm(true)")
        PushFarmRunCount()
        WriteBotState()
        if (FarmMode = "autoplay") {
            AutoPlayLastClickTick := 0
            AutoPlayLastStartClickTick := 0
            AutoPlayStartPending := false
            AutoPlayStartPendingSince := 0
            AutoPlayLastStageClickTick := 0
            AutoPlayLastHeartbeatTick := 0
            AutoPlayMissingTemplateWarned := false
            AutoPlayLastDetectionState := ""
            AddLog("Старт фарма AutoPlay: карта и расстановка не используются")
            WBH_CallJS("ahkUpdateStatus('Watching AutoPlay...', 'running')")
            SetTimer, AutoPlayWatch, 250
            ; Не ставим здесь отрицательный период: в AHK он заменяет
            ; периодический таймер одноразовым запуском.
            Gosub, AutoPlayWatch
            ; Резервный наблюдатель использует тот же таймер, что и обычный
            ; режим больше не нужен: AutoPlayWatch сам является постоянным
            ; наблюдателем и запускается каждые 250 мс.
        } else {
            AddLog("Старт фарма: " SelectedMapCtl)
            SetTimer, RunPlacementSequence, -100
        }
    } else {
        WBH_CallJS("ahkUpdateFarm(false)")
        WBH_CallJS("ahkUpdateStatus('Idle', '')")
        AddLog("Фарм остановлен")
        SetTimer, AutoPlayWatch, Off
        SetTimer, WatchNextStage, Off
        WriteBotState()
    }
return

; ---- Плавное наведение мыши (без клика) ----
; Равномерное движение: 30 мелких шагов, скорость регулируется только
; паузой между шагами (MouseSpeed 0-100). Без рывков при любой скорости.
SmoothMove(x, y) {
    global MouseSpeed, MouseSpeedEnabled
    if (!MouseSpeedEnabled) {
        MouseMove, %x%, %y%, 0
        return
    }
    MouseGetPos, curX, curY
    steps := 30
    ; Пауза между шагами: 30 мс при скорости 10 (медленно),
    ; 1 мс при скорости 100 (быстро). MouseMove всегда мгновенный (0).
    stepSleep := 32 - MouseSpeed / 3
    if (stepSleep < 1)
        stepSleep := 1
    Loop, %steps% {
        t := A_Index / steps
        tx := curX + (x - curX) * t
        ty := curY + (y - curY) * t
        MouseMove, %tx%, %ty%, 0
        Sleep, %stepSleep%
    }
    MouseMove, %x%, %y%, 0
}

; ---- Начальный зум камеры перед расстановкой юнитов ----
; ZoomScrolls > 0 — приближение (WheelUp), < 0 — отдаление (WheelDown).
ApplyStartZoom(force := false, overrideScrolls := "") {
    global ZoomEnabled, ZoomScrolls, Running
    if (!force && !ZoomEnabled)
        return
    scrolls := (overrideScrolls != "") ? (overrideScrolls + 0) : (ZoomScrolls + 0)
    if (scrolls = 0)
        return
    direction := (scrolls > 0) ? "WheelUp" : "WheelDown"
    count := Abs(scrolls)
    AddLog("Камера: " (scrolls > 0 ? "приближение" : "отдаление") " на " count " дел.")
    Loop, %count% {
        if (!force && !Running)
            return
        SendInput, % "{" . direction . "}"
        Sleep, 45
    }
    Sleep, 200
}

; ---- Верхний ракурс камеры перед обычным зумом ----
; Сначала активируем Roblox, прокручиваем вперёд на один шаг, затем
; удерживаем ПКМ и смещаем мышь вниз. Обе точки драга всегда остаются
; внутри игрового окна: относительный сдвиг из центра мог увести курсор
; за его нижнюю границу и Roblox переставал получать движение камеры.
ApplyTopCamera(force := false) {
    global TopCameraEnabled, Running, GameAreaW, GameAreaH, TS_X, TS_Y, WinTitle
    if (!force && !TopCameraEnabled)
        return
    if (!force && !Running)
        return
    if !WinExist(WinTitle) {
        AddLog("Камера: Roblox не найден, верхний ракурс не применён", "warn")
        return
    }
    ; При запуске из Settings фокус остаётся на модальном окне, поэтому
    ; активируем Roblox и здесь, а не только в обработчике кнопки Preview.
    WinActivate, %WinTitle%
    WinWaitActive, %WinTitle%,, 2
    if !WinActive(WinTitle) {
        AddLog("Камера: не удалось активировать Roblox для верхнего ракурса", "warn")
        return
    }
    ; Начинаем выше центра, чтобы после движения вниз курсор не вышел
    ; за пределы клиентской области Roblox (высота по умолчанию — 720).
    dragStartX := GameAreaW // 2
    dragStartY := GameAreaH // 3
    dragEndY := dragStartY + 280
    if (dragEndY > GameAreaH - 60)
        dragEndY := GameAreaH - 60
    ToScreen(dragStartX, dragStartY)
    MouseMove, %TS_X%, %TS_Y%, 0
    Sleep, 150
    SendInput, {WheelUp}
    Sleep, 150
    Click, Right Down
    Sleep, 120
    ToScreen(dragStartX, dragEndY)
    MouseMove, %TS_X%, %TS_Y%, 12
    Sleep, 120
    Click, Right Up
    Sleep, 300
    AddLog("Камера: установлен верхний ракурс")
}

; ---- Плавный клик: наводит мышь и кликает ----
; Некоторые кнопки в игре не срабатывают при телепортации курсора
; (Click, X, Y двигает мгновенно). Нужно реальное наведение мыши.
SmoothClick(x, y, hoverMs := 150) {
    SmoothMove(x, y)
    Sleep, %hoverMs%
    Click
    Sleep, 20
}

; ---- Плавный клик с несколькими нажатиями ----
; Наводится, ждёт, нажимает 2-3 раза с паузой между кликами.
; Используется для кнопок Start Game / Repeat Stage — надёжнее.
SmoothClickMulti(x, y, count := 2, hoverMs := 200, betweenMs := 300) {
    SmoothMove(x, y)
    Sleep, %hoverMs%
    Loop, %count% {
        Click
        Sleep, %betweenMs%
    }
    Sleep, 20
}

; ---- Проверка: совпадает ли цвет с допуском (по каналам RGB) ----
IsColorMatch(col, target, var) {
    r1 := col >> 16 & 0xFF
    g1 := col >> 8 & 0xFF
    b1 := col & 0xFF
    r2 := target >> 16 & 0xFF
    g2 := target >> 8 & 0xFF
    b2 := target & 0xFF
    return (Abs(r1-r2) <= var && Abs(g1-g2) <= var && Abs(b1-b2) <= var)
}

; ---- Уводит мышь в сторону (сброс hover) ----
; Перед повторной попыткой клика уводим курсор в нейтральную точку
; (левый нижний угол GameArea), чтобы кнопка «отпустила» hover.
MoveMouseAway() {
    global GameAreaW, GameAreaH, TS_X, TS_Y
    ToScreen(30, GameAreaH - 30)
    MouseMove, % TS_X, % TS_Y, 0
    Sleep, 400
}

; ---- Клик Start Game с повторными попытками ----
; Приоритет: 1) ImageSearch по шаблону StartGame.bmp (как Defeat/Victory);
; 2) калиброванные координаты + проверка цвета; 3) поиск по цвету (fallback).
ClickStartGameRetry() {
    global StartGameX, StartGameY, StartGameColor, StartGameColorVar, TS_X, TS_Y
    global Running, ImagesDir
    attempts := 3
    Loop, %attempts% {
        if (!Running)
            return
        clicked := false
        ; 1) ImageSearch по шаблону StartGame.bmp / StartGame.png (приоритет)
        full := ImagesDir . "\StartGame.bmp"
        if !FileExist(full)
            full := ImagesDir . "\StartGame.png"
        if (FileExist(full) && !IsTemplateTooBig(full)) {
            if (FindGameButton(full, btnX, btnY)) {
                SmoothClickMulti(btnX, btnY, 2, 200, 500)
                AddLog("Start Game: клик по шаблону (" btnX "," btnY "), попытка " A_Index "/" attempts)
                clicked := true
                Sleep, 1500
                ; Проверяем: кнопка исчезла? (шаблон больше не на экране)
                if (FindGameButton(full, bx, by)) {
                    AddLog("Start Game: кнопка ещё на экране (по шаблону), увожу мышь и повторяю...")
                } else {
                    AddLog("Start Game нажата: кнопка исчезла с экрана")
                    return
                }
            }
        }
        ; 2) Калиброванные координаты + проверка цвета (если шаблон не найден)
        if (!clicked && StartGameX > 0 && StartGameY > 0) {
            ToScreen(StartGameX, StartGameY)
            SmoothClickMulti(TS_X, TS_Y, 2, 200, 500)
            AddLog("Start Game: клик по координатам (" StartGameX "," StartGameY ") -> screen(" TS_X "," TS_Y "), попытка " A_Index "/" attempts)
            clicked := true
            Sleep, 1500
            PixelGetColor, col, %TS_X%, %TS_Y%, RGB
            if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
                if (!IsColorMatch(col, StartGameColor, StartGameColorVar + 30)) {
                    AddLog("Start Game нажата: кнопка исчезла с экрана")
                    return
                }
                AddLog("Start Game: кнопка ещё на экране (цвет " col "), увожу мышь и повторяю...")
            } else {
                ; Цвет не настроен — считаем, что клик прошёл
                return
            }
        }
        ; 3) Fallback: поиск по цвету (координат и шаблона нет)
        if (!clicked && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
            if (FindGameButtonByColor(StartGameColor, StartGameColorVar, btnX, btnY)) {
                SmoothClickMulti(btnX, btnY, 2, 200, 500)
                AddLog("Start Game: клик по цвету (fallback) (" btnX "," btnY "), попытка " A_Index "/" attempts)
                clicked := true
                Sleep, 1500
                ; Цветной fallback без проверки — считаем успешным
                return
            }
        }
        if (!clicked) {
            AddLog("Start Game: кнопка не найдена (попытка " A_Index "/" attempts ")")
            return
        }
        ; Не нажалось — уводим мышь в сторону, чтобы сбросить hover
        MoveMouseAway()
    }
    AddLog("ВНИМАНИЕ: Start Game не нажалась за " attempts " попыток — пробую снова")
}

; ---- Разовая расстановка всех юнитов по размеченным слотам ----
BeginFarmRun() {
    global FarmRunCount
    FarmRunCount += 1
    PushFarmRunCount()
    WriteBotState()
    AddLog("Ран #" FarmRunCount " начат")
}

RunPlacementSequence:
    ; Останавливаемся, если карта потеряла разметку (удалён *_slots.ini или
    ; switched map): без этого slots.Length() падал бы на пустом значении.
    if (!MapCoords.HasKey(SelectedMapCtl)) {
        AddLog("Расстановка остановлена: карта """ SelectedMapCtl """ не размечена", "warn")
        WBH_CallJS("ahkUpdateStatus('Map not marked', 'error')")
        Running := false
        SetTimer, WatchNextStage, Off
        SetTimer, AutoPlayWatch, Off
        WBH_CallJS("ahkUpdateFarm(false)")
        WriteBotState()
        return
    }
    runHasStarted := false
    slots := MapCoords[SelectedMapCtl]
    AddLog("Слотов загружено: " slots.Length() " для """ SelectedMapCtl """")
    ; Фокусируем игру без клика по миру: центральный клик мог случайно
    ; взаимодействовать с игрой ещё до выбора первого юнита.
    ToScreen(640, 360)
    MouseMove, %TS_X%, %TS_Y%, 0
    WinActivate, %WinTitle%
    WinWaitActive, %WinTitle%,, 2
    Sleep, 200
    ; Верхний ракурс выполняется до первого юнита каждого этапа.
    ApplyTopCamera()
    ; Обычный зум применяется только перед первой расстановкой после старта фарма.
    if (!StartZoomApplied) {
        ; Если зум включён, считаем ран с него; иначе — перед первой поставкой.
        if (Running && ZoomEnabled && (ZoomScrolls + 0) != 0) {
            BeginFarmRun()
            runHasStarted := true
        }
        ApplyStartZoom()
        if (Running)
            StartZoomApplied := true
    }
    if (Running && !runHasStarted)
        BeginFarmRun()
    for i, s in slots {
        if (!Running)
            break
        ; Порядок: сначала наводимся на место, ждём КД, потом выбираем юнита, потом ставим
        ToScreen(s.x, s.y)
        AddLog("Слот " i ": юнит " s.num " client(" s.x "," s.y ") -> screen(" TS_X "," TS_Y ")")
        SmoothMove(TS_X, TS_Y)
        Sleep, %HoverDelay%
        Send, % s.num
        Sleep, %ClickDelay%
        Click
        Sleep, %SlotClickDelay%
        AddLog("Юнит " s.num " поставлен (слот " i ")")
        Sleep, %UnitSleepDelay%
    }
    ; ---- Автопрокачка: после расстановки, если включена ----
    if (AutoUpgradeEnabled && Running) {
        AddLog("Автопрокачка: начинаю прокачку юнитов...")
        for i, s in slots {
            if (!Running)
                break
            priority := AutoUpgradePriority[s.num]
            if (priority <= 0)
                continue
            ; Кликаем чуть выше юнита чтобы выбрать его
            ToScreen(s.x, s.y - AutoUpgradeUnitOffsetY)
            SmoothClick(TS_X, TS_Y, 200)
            Sleep, 200
            ; Кликаем по кнопке AutoUpgrade priority раз
            Loop, %priority% {
                if (!Running)
                    break
                Gosub, DoAutoUpgradeClick
                Sleep, %AutoClickDelay%
            }
            AddLog("Автопрокачка: слот " i " (юнит " s.num ") — " priority " клик(ов)")
        }
        AddLog("Автопрокачка завершена")
    }
    if (Running) {
        WBH_CallJS("ahkUpdateStatus('Starting game...', 'running')")
        AddLog("Расстановка завершена, нажимаю Start Game...")
        ClickStartGameRetry()
        WBH_CallJS("ahkUpdateStatus('Watching...', 'running')")
        SetTimer, WatchNextStage, 1000
    }
return

; ---- Клик по кнопке AutoUpgrade (вызывается через Gosub) ----
DoAutoUpgradeClick:
    fullAU := ImagesDir . "\AutoUpgrade.bmp"
    if !FileExist(fullAU)
        fullAU := ImagesDir . "\AutoUpgrade.png"
    if (FileExist(fullAU) && !IsTemplateTooBig(fullAU)) {
        if (FindGameButton(fullAU, btnX, btnY)) {
            ; Клик по ЦЕНТРУ шаблона: читаем размеры BMP
            FileGetSize, tplSize, %fullAU%
            tplW := 0, tplH := 0
            if (tplSize > 26) {
                tplFile := FileOpen(fullAU, "r")
                if (tplFile) {
                    tplFile.Seek(18)
                    tplW := tplFile.ReadUInt()
                    tplFile.Seek(22)
                    tplH := tplFile.ReadUInt()
                    if (tplH > 0x7FFFFFFF)
                        tplH := 0x100000000 - tplH
                    tplFile.Close()
                }
            }
            if (tplW > 0 && tplH > 0)
                SmoothClick(btnX + tplW//2, btnY + tplH*2//5, 150)
            else
                SmoothClick(btnX, btnY, 150)
            return
        }
    }
    if (AutoX > 0 && AutoY > 0) {
        ToScreen(AutoX, AutoY)
        SmoothClick(TS_X, TS_Y, 150)
    }
return

; ---- Таймер записи Post-Rejoin действий (опрос состояния мыши) ----
RejoinRecordTimer:
    if (!RejoinRecordActive && !BotMapRecordActive)
        return
    MouseGetPos, mx, my
    lDown := GetKeyState("LButton", "P")
    if (BotMapRecordActive) {
        if (lDown && !BotMapRecordPending) {
            BotMapRecordPending := true
            BotMapRecordLastX := mx
            BotMapRecordLastY := my
        }
        if (!lDown && BotMapRecordPending) {
            BotMapRecordPending := false
            delayMs := 0
            if (BotMapRecordLastTime > 0)
                delayMs := A_TickCount - BotMapRecordLastTime
            gx := mx
            gy := my
            if (WinExist(WinTitle)) {
                robloxHwnd := WinExist(WinTitle)
                VarSetCapacity(pt, 8, 0)
                NumPut(0, pt, 0, "Int"), NumPut(0, pt, 4, "Int")
                DllCall("ClientToScreen", "ptr", robloxHwnd, "ptr", &pt)
                gx := mx - NumGet(pt, 0, "Int")
                gy := my - NumGet(pt, 4, "Int")
            }
            BotMapRecordActions.Push({x: gx, y: gy, delay: delayMs})
            BotMapRecordLastTime := A_TickCount
            AddLog("Discord bot: записан клик " gx "," gy)
        }
        return
    }
    if (lDown && !RejoinRecordPending) {
        ; Нажатие — запоминаем позицию, ждём отпускания
        RejoinRecordPending := true
        RejoinRecordLastX := mx
        RejoinRecordLastY := my
    }
    if (!lDown && RejoinRecordPending) {
        ; Отпускание — фиксируем клик (в игровых координатах!)
        RejoinRecordPending := false
        delayMs := 0
        if (RejoinRecordLastTime > 0)
            delayMs := A_TickCount - RejoinRecordLastTime
        ; Всегда берём origin ОКНА ROBLOX, а не сайдбара
        gx := mx
        gy := my
        if (WinExist(WinTitle)) {
            robloxHwnd := WinExist(WinTitle)
            VarSetCapacity(pt, 8, 0)
            NumPut(0, pt, 0, "Int"), NumPut(0, pt, 4, "Int")
            DllCall("ClientToScreen", "ptr", robloxHwnd, "ptr", &pt)
            gx := mx - NumGet(pt, 0, "Int")
            gy := my - NumGet(pt, 4, "Int")
        }
        RejoinActions.Push({x: gx, y: gy, delay: delayMs})
        RejoinRecordLastTime := A_TickCount
        AddLog("RejoinAction записан: клик " gx "," gy " (задержка " delayMs " мс)")
        PushRejoinActionCount()
    }
return

; ---- Колёсико мыши (горячие клавиши, включаются при записи) ----
RejoinWheelUp:
    if (!RejoinRecordActive && !BotMapRecordActive)
        return
    delayMs := 0
    if (BotMapRecordActive && BotMapRecordLastTime > 0)
        delayMs := A_TickCount - BotMapRecordLastTime
    else if (RejoinRecordLastTime > 0)
        delayMs := A_TickCount - RejoinRecordLastTime
    if (BotMapRecordActive) {
        BotMapRecordActions.Push({isWheel: true, delta: 120, delay: delayMs})
        BotMapRecordLastTime := A_TickCount
        AddLog("Discord bot: записано колесо вверх")
    } else {
        RejoinActions.Push({isWheel: true, delta: 120, delay: delayMs})
        RejoinRecordLastTime := A_TickCount
        AddLog("RejoinAction записан: колесо вверх (задержка " delayMs " мс)")
        PushRejoinActionCount()
    }
return

RejoinWheelDown:
    if (!RejoinRecordActive && !BotMapRecordActive)
        return
    delayMs := 0
    if (BotMapRecordActive && BotMapRecordLastTime > 0)
        delayMs := A_TickCount - BotMapRecordLastTime
    else if (RejoinRecordLastTime > 0)
        delayMs := A_TickCount - RejoinRecordLastTime
    if (BotMapRecordActive) {
        BotMapRecordActions.Push({isWheel: true, delta: -120, delay: delayMs})
        BotMapRecordLastTime := A_TickCount
        AddLog("Discord bot: записано колесо вниз")
    } else {
        RejoinActions.Push({isWheel: true, delta: -120, delay: delayMs})
        RejoinRecordLastTime := A_TickCount
        AddLog("RejoinAction записан: колесо вниз (задержка " delayMs " мс)")
        PushRejoinActionCount()
    }
return

; ---- Воспроизведение записанных Post-Rejoin действий ----
PlayRejoinActions(mapName) {
    global RejoinActions, Running, WinTitle, TS_X, TS_Y
    LoadRejoinActions(mapName)
    count := RejoinActions.Length()
    if (count < 1) {
        AddLog("RejoinActions: для карты """ mapName """ нет записанных действий")
        return
    }
    AddLog("RejoinActions: воспроизвожу " count " действи(я) для """ mapName """...")
    Loop, %count% {
        if (!Running)
            return
        a := RejoinActions[A_Index]
        if (a.delay > 0)
            Sleep, % a.delay
        if (!Running)
            return
        if (a.isWheel) {
            notches := Abs(a.delta) // 120
            Loop, %notches% {
                if (a.delta > 0)
                    MouseClick, WheelUp
                else
                    MouseClick, WheelDown
                Sleep, 30
            }
            AddLog("RejoinAction: колесо " (a.delta > 0 ? "вверх" : "вниз") " x" notches)
        } else {
            ; Конвертируем игровые координаты в экранные и кликаем
            ToScreen(a.x, a.y)
            AddLog("RejoinAction: клик game(" a.x "," a.y ") → screen(" TS_X "," TS_Y ")")
            SmoothClick(TS_X, TS_Y, 80)
        }
    }
    AddLog("RejoinActions: воспроизведение завершено")
}

; ---- Отправка количества записанных действий в UI модалки ----
PushRejoinActionCount() {
    global RejoinActions, WB_Modal
    count := RejoinActions.Length()
    try {
        WB_Modal.Document.parentWindow.execScript("ahkRejoinActionCount(" count ")")
    }
}

; ---- Отправка количества выполненных ранов в основную панель ----
PushFarmRunCount() {
    global FarmRunCount
    WBH_CallJS("ahkUpdateRunCount(" . FarmRunCount . ")")
}

; ---- Старт / стоп записи Post-Rejoin действий ----
ToggleRejoinRecord:
    global RejoinRecordActive, RejoinActions, RejoinRecordLastTime, RejoinRecordPending, SelectedMapCtl, WinTitle
    if (SelectedMapCtl = "") {
        AddLog("RejoinRecord: сначала выбери карту!", "warn")
        return
    }
    if (RejoinRecordActive) {
        ; Стоп записи
        RejoinRecordActive := false
        RejoinRecordPending := false
        SetTimer, RejoinRecordTimer, Off
        ; Отключаем wheel-хоткеи
        Hotkey, ~WheelUp, Off
        Hotkey, ~WheelDown, Off
        SaveRejoinActions(SelectedMapCtl)
        count := RejoinActions.Length()
        AddLog("RejoinRecord: запись остановлена, сохранено " count " действий для """ SelectedMapCtl """")
        PushRejoinActionCount()
        try {
            WB_Modal.Document.parentWindow.execScript("ahkRejoinRecordState(false)")
        }
    } else {
        ; Старт записи
        LoadRejoinActions(SelectedMapCtl)
        RejoinRecordActive := true
        RejoinRecordPending := false
        RejoinRecordLastTime := A_TickCount
        SetTimer, RejoinRecordTimer, 50
        ; Включаем wheel-хоткеи
        Hotkey, ~WheelUp, On
        Hotkey, ~WheelDown, On
        ; Активируем окно Roblox чтобы сразу кликать
        if (WinExist(WinTitle)) {
            WinActivate, %WinTitle%
            WinWaitActive, %WinTitle%,, 2
        }
        AddLog("RejoinRecord: запись начата для """ SelectedMapCtl """ — кликай/крути в Roblox (" RejoinRecordHotkey " = стоп)")
        try {
            WB_Modal.Document.parentWindow.execScript("ahkRejoinRecordState(true)")
        }
    }
return

; ---- Горячая клавиша — старт/стоп записи Post-Rejoin действий ----
RejoinRecordHotkeyAction:
RejoinF1:
    global RejoinRecordActive, SelectedMapCtl
    if (RejoinRecordActive) {
        GoSub, ToggleRejoinRecord
    } else {
        ; Проверяем что выбрана карта и роблокс на месте
        if (SelectedMapCtl = "") {
            AddLog("RejoinRecord: сначала выбери карту в сайдбаре!", "warn")
            return
        }
        if (!WinExist(WinTitle)) {
            AddLog("RejoinRecord: окно Roblox не найдено!", "warn")
            return
        }
        GoSub, ToggleRejoinRecord
    }
return

; ---- Горячая клавиша — запись действий входа на выбранную карту ----
; Карта берётся из текущего выбора в сайдбаре. Эти действия выполняются
; после победы/поражения, когда карта была поставлена через Discord.
MapDetectHotkeyAction:
    GoSub, MapDetectNow
return

MapChangeRecordHotkeyAction:
MapChangeF2:
    global BotMapRecordActive, RejoinRecordActive, SelectedMapCtl
    if (BotMapRecordActive) {
        StopBotMapRecord()
        return
    }
    if (RejoinRecordActive) {
        AddLog("MapRecord: сначала остановите запись Post-Rejoin!", "warn")
        return
    }
    if (SelectedMapCtl = "") {
        AddLog("MapRecord: сначала выбери карту в сайдбаре!", "warn")
        return
    }
    if (!WinExist(WinTitle)) {
        AddLog("MapRecord: окно Roblox не найдено!", "warn")
        return
    }
    StartBotMapRecord(SelectedMapCtl)
return

; ---- Тестовое воспроизведение Post-Rejoin действий ----
TestRejoinActions:
    global SelectedMapCtl
    if (SelectedMapCtl = "") {
        AddLog("RejoinTest: сначала выбери карту!", "warn")
        return
    }
    AddLog("RejoinTest: воспроизвожу действия для """ SelectedMapCtl """...")
    PlayRejoinActions(SelectedMapCtl)
return

; ---- Очистка Post-Rejoin действий для текущей карты ----
ClearRejoinActions:
    global SelectedMapCtl, RejoinActions
    if (SelectedMapCtl = "") {
        AddLog("RejoinClear: сначала выбери карту!", "warn")
        return
    }
    RejoinActions := []
    SaveRejoinActions(SelectedMapCtl)
    AddLog("RejoinClear: действия для """ SelectedMapCtl """ удалены")
    PushRejoinActionCount()
return

; ---- Наблюдение за окончанием волны / победы / поражения ----
AutoPlayTemplateFile(state) {
    global ImagesDir
    name := (state = "on") ? "AutoPlayOn" : "AutoPlayOff"
    full := ImagesDir . "\" . name . ".bmp"
    if !FileExist(full)
        full := ImagesDir . "\" . name . ".png"
    return full
}

GetTemplateSize(imageFile, ByRef tplW, ByRef tplH) {
    tplW := 0
    tplH := 0
    if !FileExist(imageFile)
        return false
    file := FileOpen(imageFile, "r")
    if !file
        return false
    file.Seek(0)
    b0 := file.ReadUChar()
    b1 := file.ReadUChar()
    if (b0 = 0x42 && b1 = 0x4D) {
        file.Seek(18)
        tplW := file.ReadUInt()
        file.Seek(22)
        rawH := file.ReadUInt()
        tplH := rawH
        if (tplH > 0x7FFFFFFF)
            tplH := 0x100000000 - tplH
        file.Close()
        return (tplW > 0 && tplH > 0)
    }
    if (b0 = 0x89 && b1 = 0x50) {
        file.Seek(16)
        tplW := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Seek(20)
        tplH := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Close()
        return (tplW > 0 && tplH > 0)
    }
    file.Close()
    return false
}

ClickAutoPlayTemplate(imageFile, foundX, foundY) {
    FocusEmbeddedGame()
    if (!GetTemplateSize(imageFile, tplW, tplH))
        return false
    ; Кликаем по центру выделенной кнопки, а не по левому верхнему углу ImageSearch.
    SmoothClick(foundX + tplW//2, foundY + tplH//2, 120)
    return true
}

; Ищет Start Game заново и нажимает только после свежего ImageSearch/PixelSearch.
; Возвращает true, если клик действительно выполнен.
AutoPlayClickStartGame(startFile := "") {
    global ImagesDir, StartGameColor, StartGameColorVar, StartGameX, StartGameY, TS_X, TS_Y
    global AutoPlayLastStartClickTick
    if (A_TickCount - AutoPlayLastStartClickTick < 2200)
        return false
    if (startFile = "") {
        startFile := ImagesDir . "\StartGame.bmp"
        if !FileExist(startFile)
            startFile := ImagesDir . "\StartGame.png"
    }
    ; Сначала определяем наличие кнопки по её шаблону/тексту. Важно: текущий
    ; StartGame.bmp может содержать заголовок «Start Game?», поэтому сам клик
    ; выполняем не по найденному заголовку, а по сохранённой точке кнопки.
    visible := false
    if (FileExist(startFile) && !IsTemplateTooBig(startFile))
        visible := FindGameButton(startFile, foundX, foundY)
    if (!visible && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "")
        visible := FindStartGameByColor(StartGameColor, StartGameColorVar, foundX, foundY)
    if (!visible)
        return false

    FocusEmbeddedGame()
    if (StartGameX > 0 && StartGameY > 0) {
        ToScreen(StartGameX, StartGameY)
        SmoothClickMulti(TS_X, TS_Y, 2, 200, 400)
        AddLog("AutoPlay: Start Game нажата по калиброванной точке (" StartGameX "," StartGameY ")")
    } else if (FileExist(startFile) && GetTemplateSize(startFile, tplW, tplH)) {
        SmoothClickMulti(foundX + tplW//2, foundY + tplH//2, 2, 200, 400)
        AddLog("AutoPlay: Start Game нажата по центру шаблона")
    } else {
        return false
    }
    MoveMouseAway()
    AutoPlayLastStartClickTick := A_TickCount
    return true
}

; ---- Постоянный наблюдатель режима AutoPlay ----
; В каждом цикле отдельно проверяются OFF, ON и Start Game. Если OFF найден,
; AutoPlay включается; при совпадении обоих шаблонов приоритет у ON.
AutoPlayWatch:
    if (!Running || FarmMode != "autoplay")
        return
    if !WinExist(WinTitle)
        return
    if (A_TickCount - AutoPlayLastHeartbeatTick >= 10000) {
        AutoPlayLastHeartbeatTick := A_TickCount
        AddLog("AutoPlay: постоянная проверка активна")
    }

    ; В AutoPlay-режиме обычный WatchNextStage не запускается, поэтому
    ; победу/поражение проверяем здесь же, тем же постоянным таймером.
    if (A_TickCount - AutoPlayLastStageClickTick >= 2500) {
        stageEnd := ""
        if (DetectDefeat())
            stageEnd := "Defeat"
        else if (DetectVictory())
            stageEnd := "Victory"
        if (stageEnd != "") {
            FocusEmbeddedGame()
            AddLog("AutoPlay: обнаружен экран " stageEnd ", нажимаю Repeat Stage")
            WBH_CallJS("ahkUpdateStatus('" . stageEnd . ", repeating...', 'running')")
            AutoPlayLastStageClickTick := A_TickCount
            AutoPlayStartPending := false
            AutoPlayStartPendingSince := 0
            ClickRepeatStage()
            MoveMouseAway()
            return
        }
    }
    offFile := AutoPlayTemplateFile("off")
    onFile := AutoPlayTemplateFile("on")
    if (!FileExist(offFile) || !FileExist(onFile)) {
        if (!AutoPlayMissingTemplateWarned) {
            AutoPlayMissingTemplateWarned := true
            AddLog("AutoPlay: шаблон OFF или ON отсутствует — продолжаю искать Start Game и экран окончания", "warn")
            WBH_CallJS("ahkUpdateStatus('Watching Start Game / result...', 'running')")
        }
    }
    if ((FileExist(offFile) && IsTemplateTooBig(offFile)) || (FileExist(onFile) && IsTemplateTooBig(onFile))) {
        if (!AutoPlayMissingTemplateWarned) {
            AutoPlayMissingTemplateWarned := true
            AddLog("AutoPlay: шаблон слишком большой — сними только кнопку или её текст", "warn")
            WBH_CallJS("ahkUpdateStatus('Watching Start Game / result...', 'running')")
        }
    }
    ; Каждый цикл отдельно ищем OFF, ON и Start Game. OFF нельзя проверять
    ; только в ветке «ON не найден»: после перезапуска состояния могут быстро
    ; меняться, поэтому все три поиска выполняются постоянно.
    offFound := FileExist(offFile) && !IsTemplateTooBig(offFile) && FindGameButton(offFile, offX, offY)
    onFound := FileExist(onFile) && !IsTemplateTooBig(onFile) && FindGameButton(onFile, onX, onY)
    AutoPlayMissingTemplateWarned := false

    startFile := ImagesDir . "\StartGame.bmp"
    if !FileExist(startFile)
        startFile := ImagesDir . "\StartGame.png"
    startFound := false
    if (FileExist(startFile) && !IsTemplateTooBig(startFile))
        startFound := FindGameButton(startFile, startX, startY)
    if (!startFound && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "")
        startFound := FindStartGameByColor(StartGameColor, StartGameColorVar, startX, startY)

    detectionState := (offFound ? "OFF " : "") . (onFound ? "ON " : "") . (startFound ? "START" : "")
    if (detectionState = "")
        detectionState := "none"
    if (detectionState != AutoPlayLastDetectionState) {
        AutoPlayLastDetectionState := detectionState
        AddLog("AutoPlay: найдено — " detectionState)
    }

    ; Если OFF найден, включаем AutoPlay. В следующем цикле Start Game
    ; проверится независимо от того, совпал ли ON-шаблон.
    if (offFound && !onFound) {
        if (A_TickCount - AutoPlayLastClickTick < 1600)
            return
        if (ClickAutoPlayTemplate(offFile, offX, offY)) {
            AutoPlayLastClickTick := A_TickCount
            AddLog("AutoPlay выключен — нажимаю кнопку включения")
            ; Убираем курсор с кнопки, иначе hover-состояние может помешать
            ; проверке нового состояния и поиску Start Game.
            MoveMouseAway()
            Sleep, 350
            WBH_CallJS("ahkUpdateStatus('AutoPlay enabled, checking Start Game...', 'running')")
        } else {
            AddLog("AutoPlay: клик по выключенной кнопке не выполнен", "warn")
        }
        return
    }
    ; Start Game проверяется всегда, даже если шаблон AutoPlay ON не найден.
    ; Это важно после перезапуска: ON может быть с другой подсветкой, а Start
    ; уже виден и должен быть нажат.
    if (AutoPlayClickStartGame(startFile))
        WBH_CallJS("ahkUpdateStatus('Start Game clicked', 'running')")
    if (onFound)
        WBH_CallJS("ahkUpdateStatus('AutoPlay ON, watching Start Game...', 'running')")
    else if (offFound)
        WBH_CallJS("ahkUpdateStatus('AutoPlay OFF, enabling...', 'running')")
    else
        WBH_CallJS("ahkUpdateStatus('Waiting for AutoPlay / Start Game...', 'running')")
return

WatchNextStage:
    if (FarmMode = "autoplay") {
        Gosub, AutoPlayWatch
        return
    }
    ; Диалог Disconnected ловим ОТДЕЛЬНО от WinExist: окно Roblox зачастую
    ; остаётся открытым, просто поверх игры висит попап с ошибкой соединения.
    disconnected := DetectDisconnected()
    if (disconnected || !WinExist(WinTitle)) {
        SetTimer, WatchNextStage, Off
        if (RejoinEnabled && RejoinShareLink != "" && Running) {
            reason := disconnected ? "обнаружен экран Disconnected" : "окно Roblox пропало"
            AddLog("Rejoin: " reason " — пробую автопереподключение...", "warn")
            WBH_CallJS("ahkUpdateStatus('Reconnecting...', 'warn')")
            if (AttemptRejoin(disconnected)) {
                AddLog("Переподключение успешно, продолжаю фарм")
                WBH_CallJS("ahkUpdateStatus('Reconnected, resuming...', 'running')")
                Sleep, % RejoinPostJoinDelay * 1000

                ; Если был вылет (окно пропало) и до этого роблокс был встроен —
                ; перевстраиваем новое окно автоматически
                if (!disconnected && Embedded) {
                    AddLog("Rejoin: перевстраиваю новое окно Roblox...")
                    Embedded := false   ; сбрасываем флаг, чтобы BtnEmbed сработал на встраивание
                    Gosub, BtnEmbed
                }

                ; Воспроизводим записанные Post-Rejoin действия для текущей карты
                if (SelectedMapCtl != "") {
                    PlayRejoinActions(SelectedMapCtl)
                    if (RejoinPostActionsDelay > 0) {
                        AddLog("Rejoin: жду " RejoinPostActionsDelay " сек после действий...")
                        Sleep, % RejoinPostActionsDelay * 1000
                    }
                }

                if (Running)
                    SetTimer, RunPlacementSequence, -100
                return
            }
            AddLog("Переподключение не удалось за " RejoinMaxAttempts " попыток(ки)", "error")
        }
        WBH_CallJS("ahkUpdateFarm(false)")
        WBH_CallJS("ahkUpdateStatus('Game lost', 'error')")
        AddLog(disconnected ? "Экран Disconnected обнаружен, остановка" : "Окно Roblox пропало, остановка")
        Running := false
        return
    }
    ; 1) Проверяем поражение/победу — ищем Defeat / Victory
    if (DetectDefeat()) {
        if (PendingMapChange != "") {
            HandlePendingMapChange("Defeat")
            return
        }
        AddLog("Обнаружено поражение! Кликаю Repeat Stage...")
        ClickRepeatStage()
        WBH_CallJS("ahkUpdateStatus('Defeat, restarting...', 'error')")
        Gosub, RestartFarmLoop
        return
    }
    if (DetectVictory()) {
        if (PendingMapChange != "") {
            HandlePendingMapChange("Victory")
            return
        }
        AddLog("Обнаружена победа! Кликаю Repeat Stage...")
        ClickRepeatStage()
        WBH_CallJS("ahkUpdateStatus('Victory, restarting...', 'running')")
        Gosub, RestartFarmLoop
        return
    }
    ; Next Stage — убран, автопрокачка работает вместо него
return

; ---- Бесконечный цикл: после победы/поражения всё заново ----
RestartFarmLoop:
    SetTimer, WatchNextStage, Off
    if (!Running)
        return
    WBH_CallJS("ahkUpdateStatus('Restarting stage...', 'running')")
    AddLog("Перезапуск этапа: жду загрузку, затем расстановка заново")
    Sleep, 4000
    if (Running)
        SetTimer, RunPlacementSequence, -100
return

; ---- Переподключение к VIP/приватному серверу через deeplink ----
; Два сценария, оба через roblox:// deeplink (browser-фолбэк если нет обработчика):
;   Disconnected: роблокс жив → просто deeplink (роблокс подхватит и перезайдёт)
;   Crash:        kill остатков → deeplink (запустит новый роблокс)
; Ждёт появления/восстановления окна до RejoinWaitTimeout сек, повторяет
; до RejoinMaxAttempts раз. Возвращает true при успехе.
AttemptRejoin(isDisconnected) {
    global WinTitle, RejoinShareLink, RejoinMaxAttempts, RejoinWaitTimeout, Running

    ; Строим deeplink (и фолбэк-ссылку) из share-ссылки пользователя
    links := BuildRejoinLinks(RejoinShareLink)
    if (links.deeplink = "" && links.browser = "") {
        AddLog("Rejoin: не удалось извлечь code из ссылки", "error")
        return false
    }

    ; Проверяем, зарегистрирован ли обработчик roblox:// в системе
    RegRead, robloxHandler, HKEY_CLASSES_ROOT, roblox\shell\open\command
    useDeeplink := (ErrorLevel = 0 && robloxHandler != "")
    launchURL := useDeeplink ? links.deeplink : links.browser
    AddLog("Rejoin: " (useDeeplink ? "deeplink" : "browser") " — " launchURL)

    if (isDisconnected) {
        ; Роблокс жив, висит Disconnected — просто шлём deeplink,
        ; живой роблокс подхватит и перезайдёт на сервер (как в RVL).
        AddLog("Rejoin: роблокс жив (Disconnected), запускаю deeplink...")
    } else {
        ; Вылет — гасим остатки процесса, если висят
        Process, Exist, RobloxPlayerBeta.exe
        if (ErrorLevel) {
            Process, Close, %ErrorLevel%
            Sleep, 2000
        }
        AddLog("Rejoin: процесс сброшен, запускаю " (useDeeplink ? "deeplink" : "браузер") "...")
    }

    attempts := RejoinMaxAttempts
    if (attempts < 1)
        attempts := 1

    Loop, %attempts% {
        if (!Running)
            return false
        AddLog("Rejoin попытка " A_Index "/" attempts "...")
        try {
            Run, % launchURL
        } catch e {
            AddLog("Rejoin: ошибка запуска — " e.Message, "error")
        }

        waitStart := A_TickCount
        timeoutMs := RejoinWaitTimeout * 1000
        while (A_TickCount - waitStart < timeoutMs) {
            if (!Running)
                return false
            ; Disconnected: ждём пока ИСЧЕЗНЕТ экран ошибки (роблокс жив, заходит)
            ; Crash:        ждём пока ПОЯВИТСЯ окно роблокса
            if (isDisconnected) {
                if (WinExist(WinTitle) && !DetectDisconnected()) {
                    AddLog("Rejoin: экран Disconnected пропал — игра загрузилась!")
                    WinWaitActive, %WinTitle%,, 5
                    return true
                }
            } else {
                if (WinExist(WinTitle)) {
                    WinWaitActive, %WinTitle%,, 5
                    return true
                }
            }
            Sleep, 500
        }
        AddLog("Rejoin попытка " A_Index ": не дождались за " RejoinWaitTimeout " сек")

        ; Если deeplink не сработал — пробуем браузерный фолбэк
        if (useDeeplink && links.browser != "" && A_Index = 1) {
            AddLog("Rejoin: deeplink не дал результата, пробую браузер...")
            launchURL := links.browser
            useDeeplink := false
        }
        Sleep, 1500
    }
    return false
}

; ---- Строим deeplink и браузерную ссылку из share-ссылки ----
; Вход:  https://www.roblox.com/share?code=ABC123&type=Server
; Выход: { deeplink: "roblox://navigation/share_links?code=ABC123&type=Server",
;           browser:  "https://www.roblox.com/share?code=ABC123&type=Server" }
BuildRejoinLinks(url) {
    result := { deeplink: "", browser: "" }

    ; Извлекаем полный code (включая &type=Server если есть)
    code := ""
    qPos := InStr(url, "?")
    if (qPos) {
        query := SubStr(url, qPos + 1)
        codePos := InStr(query, "code=")
        if (codePos) {
            code := SubStr(query, codePos + 5)  ; всё после "code="
        }
    }
    if (code = "") {
        ; Может быть пользователь вставил просто код (без URL)
        if (InStr(url, "&type=Server") || InStr(url, "&type=server"))
            code := url
        else if (RegExMatch(url, "^[A-Za-z0-9]{20,}$"))
            code := url . "&type=Server"
        else
            return result
    }

    ; Deeplink: roblox://navigation/share_links?code=КОД
    result.deeplink := "roblox://navigation/share_links?code=" . code

    ; Браузерный фолбэк
    if (InStr(url, "https://") = 1 || InStr(url, "http://") = 1)
        result.browser := url
    else
        result.browser := "https://www.roblox.com/share?code=" . code

    return result
}

; ---- Проверка: шаблон слишком большой для быстрого ImageSearch ----
; ImageSearch по шаблону > 300x300 в области 1280x720 занимает секунды
; и вешает GUI («не отвечает»). Такие шаблоны пропускаем.
IsTemplateTooBig(imageFile) {
    if !FileExist(imageFile)
        return false
    ; Читаем размеры из заголовка BMP/PNG
    file := FileOpen(imageFile, "r")
    if !file
        return false
    ; BMP: 'BM' + ... width @18, height @22
    file.Seek(0)
    b0 := file.ReadUChar()
    b1 := file.ReadUChar()
    if (b0 = 0x42 && b1 = 0x4D) {   ; 'BM'
        file.Seek(18)
        w := file.ReadUInt()
        file.Seek(22)
        hRaw := file.ReadUInt()
        h := hRaw
        if (h > 0x7FFFFFFF)   ; отрицательная высота = top-down
            h := 0x100000000 - hRaw
        file.Close()
        return (w > 300 || h > 300)
    }
    ; PNG: 89 50 4E 47 + width @16 (big-endian), height @20
    ; (без битовых сдвигов — в AHK v1 << 24 может дать знаковое число)
    if (b0 = 0x89 && b1 = 0x50) {
        file.Seek(16)
        w := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Seek(20)
        h := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Close()
        return (w > 300 || h > 300)
    }
    file.Close()
    return false
}

; ---- Детект поражения (Defeat) — ищет Defeat.png или Defeat.bmp ----
DetectDefeat() {
    global Embedded, ImagesDir, WinTitle
    if (!Embedded && !WinExist(WinTitle))
        return false
    full := ImagesDir . "\Defeat.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Defeat.png"
    if (FileExist(full)) {
        if (IsTemplateTooBig(full)) {
            global WarnedDefeat
            if (!WarnedDefeat) {
                WarnedDefeat := true
                AddLog("Defeat-шаблон слишком большой — ImageSearch вешает макрос. Сними маленький шаблон (Калибровка → Снять шаблон, имя Defeat).")
            }
            return false
        }
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Детект победы (Victory) — ищет Victory.png или Victory.bmp ----
DetectVictory() {
    global Embedded, ImagesDir, WinTitle
    if (!Embedded && !WinExist(WinTitle))
        return false
    full := ImagesDir . "\Victory.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Victory.png"
    if (FileExist(full)) {
        if (IsTemplateTooBig(full)) {
            global WarnedVictory
            if (!WarnedVictory) {
                WarnedVictory := true
                AddLog("Victory-шаблон слишком большой — ImageSearch вешает макрос. Сними маленький шаблон (Калибровка → Снять шаблон, имя Victory).")
            }
            return false
        }
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Детект диалога "Disconnected" (Error Code: 277 и т.п.) ----
; Использует шаблон Disconnected.bmp/png, снятый через "Capture Disconnected Screen".
; В отличие от WinExist(WinTitle) это ловит разрыв соединения даже если сам
; процесс/окно Roblox остаётся открытым (просто показывает диалог поверх игры).
DetectDisconnected() {
    global Embedded, ImagesDir, WinTitle
    if (!Embedded && !WinExist(WinTitle))
        return false
    full := ImagesDir . "\Disconnected.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Disconnected.png"
    if (FileExist(full)) {
        if (IsTemplateTooBig(full)) {
            global WarnedDisconnected
            if (!WarnedDisconnected) {
                WarnedDisconnected := true
                AddLog("Disconnected-шаблон слишком большой — ImageSearch вешает макрос. Сними шаблон поменьше.")
            }
            return false
        }
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Клик по кнопке Repeat Stage ----
; Кликает (координаты → изображение → цвет), ждёт и проверяет, исчез ли
; экран победы/поражения. Если нет — повторяет (до 3 попыток).
ClickRepeatStage() {
    global RepeatStageX, RepeatStageY, ImagesDir, ImgVariation, StartGameColor, StartGameColorVar
    global TS_X, TS_Y
    global Running
    FocusEmbeddedGame()
    attempts := 3
    Loop, %attempts% {
        if (!Running)
            return
        clicked := false
        ; 1) Калиброванные координаты — приоритет (быстро, без ImageSearch)
        if (RepeatStageX > 0 && RepeatStageY > 0) {
            ToScreen(RepeatStageX, RepeatStageY)
            SmoothClickMulti(TS_X, TS_Y, 2, 200, 400)
            AddLog("Repeat Stage: клик по экрану (" TS_X "," TS_Y "), попытка " A_Index)
            clicked := true
        }
        ; 2) ImageSearch по RepeatStage.bmp / RepeatStage.png
        if (!clicked) {
            full := ImagesDir . "\RepeatStage.bmp"
            if !FileExist(full)
                full := ImagesDir . "\RepeatStage.png"
            if (FileExist(full)) {
                if (FindGameButton(full, bx, by)) {
                    if (GetTemplateSize(full, repeatW, repeatH))
                        SmoothClickMulti(bx + repeatW//2, by + repeatH//2, 2, 200, 400)
                    else
                        SmoothClickMulti(bx, by, 2, 200, 400)
                    AddLog("Repeat Stage нажата по поиску изображения (" bx "," by "), попытка " A_Index)
                    clicked := true
                }
            }
        }
        ; 3) Fallback: ищем по цвету StartGame
        if (!clicked && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
            if (FindGameButtonByColor(StartGameColor, StartGameColorVar, bx, by)) {
                SmoothClickMulti(bx, by, 2, 200, 400)
                AddLog("Повторить по цвету StartGame (fallback), попытка " A_Index)
                clicked := true
            }
        }
        if (!clicked) {
            AddLog("Repeat Stage: кнопка не найдена (попытка " A_Index ")")
            return
        }
        ; Ждём и проверяем: экран победы/поражения исчез?
        Sleep, 2000
        if (!DetectVictory() && !DetectDefeat()) {
            AddLog("Repeat Stage нажата: экран закрыт")
            return
        }
        AddLog("Repeat Stage: экран ещё на месте, увожу мышь и повторяю...")
        ; Не нажалось — уводим мышь в сторону, чтобы сбросить hover
        MoveMouseAway()
	}
	AddLog("ВНИМАНИЕ: Repeat Stage не нажалась за " attempts " попыток")
}

; ===================== DISCORD BOT =====================

UpdateBotStatus(text, cls := "") {
    safeText := JsEscape(text)
    safeCls := JsEscape(cls)
    WBH_CallJS("ahkUpdateBotStatus('" . safeText . "','" . safeCls . "')")
    ModalCallJS("ahkUpdateBotStatus('" . safeText . "','" . safeCls . "')")
}

UpdateBotInstallButton(enabled) {
    js := "ahkSetBotInstallButton(" . (enabled ? "true" : "false") . ")"
    WBH_CallJS(js)
    ModalCallJS(js)
}

; ---- Установка Python-зависимостей Discord-бота ----
; Запускается из Settings отдельно от запуска бота. Ожидаем завершения pip,
; чтобы показать пользователю настоящий результат установки.
InstallBotDependencies:
    requirementsFile := BotDir . "\requirements.txt"
    if !FileExist(requirementsFile) {
        AddLog("Discord bot: requirements.txt не найден", "error")
        UpdateBotStatus("requirements.txt not found", "error")
        UpdateBotInstallButton(true)
        return
    }
    ; PowerShell-скрипт сам находит Python, а если его нет — устанавливает
    ; Python через winget. Поэтому кнопка работает на чистой системе тоже.
    safeRequirements := StrReplace(requirementsFile, "'", "''")
    safeLog := StrReplace(BotDepsLogFile, "'", "''")
    safeResult := StrReplace(BotRuntimeDir . "\pip_install_exit.txt", "'", "''")
    safePythonPath := StrReplace(BotPythonPathFile, "'", "''")
    psContent := "$ErrorActionPreference = 'Stop'`r`n"
    psContent .= "Add-Type -AssemblyName System.Windows.Forms`r`n"
    psContent .= "Add-Type -AssemblyName System.Drawing`r`n"
    psContent .= "$requirements = '" . safeRequirements . "'`r`n"
    psContent .= "$log = '" . safeLog . "'`r`n"
    psContent .= "$result = '" . safeResult . "'`r`n"
    psContent .= "$pythonPathFile = '" . safePythonPath . "'`r`n"
    psContent .= "$venv = Join-Path (Split-Path -Parent $requirements) 'runtime\.venv'`r`n"
    psContent .= "$venvPython = Join-Path $venv 'Scripts\python.exe'`r`n"
    psContent .= "$form = New-Object System.Windows.Forms.Form`r`n"
    psContent .= "$form.Text = 'Mmacro - Установка зависимостей'`r`n"
    psContent .= "$form.ClientSize = New-Object System.Drawing.Size(500, 280)`r`n"
    psContent .= "$form.StartPosition = 'CenterScreen'`r`n"
    psContent .= "$form.FormBorderStyle = 'None'`r`n"
    psContent .= "$form.ShowInTaskbar = $true`r`n"
    psContent .= "$form.TopMost = $true`r`n"
    psContent .= "$form.BackColor = [System.Drawing.Color]::FromArgb(18,18,18)`r`n"
    psContent .= "$accent = New-Object System.Windows.Forms.Panel`r`n"
    psContent .= "$accent.BackColor = [System.Drawing.Color]::FromArgb(59,130,246)`r`n"
    psContent .= "$accent.Location = New-Object System.Drawing.Point(0,0)`r`n"
    psContent .= "$accent.Size = New-Object System.Drawing.Size(500,2)`r`n"
    psContent .= "$form.Controls.Add($accent)`r`n"
    psContent .= "$brand = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$brand.Text = 'MMACRO  •  BOT'`r`n"
    psContent .= "$brand.AutoSize = $true`r`n"
    psContent .= "$brand.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)`r`n"
    psContent .= "$brand.ForeColor = [System.Drawing.Color]::FromArgb(150,150,150)`r`n"
    psContent .= "$brand.Location = New-Object System.Drawing.Point(22,22)`r`n"
    psContent .= "$form.Controls.Add($brand)`r`n"
    psContent .= "$title = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$title.Text = 'Установка зависимостей'`r`n"
    psContent .= "$title.AutoSize = $true`r`n"
    psContent .= "$title.Font = New-Object System.Drawing.Font('Segoe UI',14,[System.Drawing.FontStyle]::Bold)`r`n"
    psContent .= "$title.ForeColor = [System.Drawing.Color]::FromArgb(228,228,228)`r`n"
    psContent .= "$title.Location = New-Object System.Drawing.Point(22,48)`r`n"
    psContent .= "$form.Controls.Add($title)`r`n"
    psContent .= "$status = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$status.Text = 'Подготовка…'`r`n"
    psContent .= "$status.AutoSize = $true`r`n"
    psContent .= "$status.Font = New-Object System.Drawing.Font('Segoe UI',10)`r`n"
    psContent .= "$status.ForeColor = [System.Drawing.Color]::FromArgb(59,130,246)`r`n"
    psContent .= "$status.Location = New-Object System.Drawing.Point(22,94)`r`n"
    psContent .= "$form.Controls.Add($status)`r`n"
    psContent .= "$spinner = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$spinner.AutoSize = $false`r`n"
    psContent .= "$spinner.Size = New-Object System.Drawing.Size(32,32)`r`n"
    psContent .= "$spinner.TextAlign = 'MiddleCenter'`r`n"
    psContent .= "$spinner.Font = New-Object System.Drawing.Font('Segoe UI Symbol',16,[System.Drawing.FontStyle]::Regular)`r`n"
    psContent .= "$spinner.ForeColor = [System.Drawing.Color]::FromArgb(59,130,246)`r`n"
    psContent .= "$spinner.Location = New-Object System.Drawing.Point(444,86)`r`n"
    psContent .= "$form.Controls.Add($spinner)`r`n"
    psContent .= "$detail = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$detail.Text = 'Проверяем Python и pip'`r`n"
    psContent .= "$detail.AutoSize = $true`r`n"
    psContent .= "$detail.Font = New-Object System.Drawing.Font('Segoe UI',8)`r`n"
    psContent .= "$detail.ForeColor = [System.Drawing.Color]::FromArgb(120,120,120)`r`n"
    psContent .= "$detail.Location = New-Object System.Drawing.Point(22,120)`r`n"
    psContent .= "$form.Controls.Add($detail)`r`n"
    psContent .= "$progress = New-Object System.Windows.Forms.ProgressBar`r`n"
    psContent .= "$progress.Style = 'Marquee'`r`n"
    psContent .= "$progress.MarqueeAnimationSpeed = 22`r`n"
    psContent .= "$progress.Location = New-Object System.Drawing.Point(22,150)`r`n"
    psContent .= "$progress.Size = New-Object System.Drawing.Size(456,10)`r`n"
    psContent .= "$form.Controls.Add($progress)`r`n"
    psContent .= "$steps = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$steps.Text = '01  Python        02  pip        03  Пакеты        04  Готово'`r`n"
    psContent .= "$steps.AutoSize = $true`r`n"
    psContent .= "$steps.Font = New-Object System.Drawing.Font('Segoe UI',8)`r`n"
    psContent .= "$steps.ForeColor = [System.Drawing.Color]::FromArgb(100,100,100)`r`n"
    psContent .= "$steps.Location = New-Object System.Drawing.Point(22,200)`r`n"
    psContent .= "$form.Controls.Add($steps)`r`n"
    psContent .= "$hint = New-Object System.Windows.Forms.Label`r`n"
    psContent .= "$hint.Text = 'Не закрывайте окно — установка выполняется автоматически.'`r`n"
    psContent .= "$hint.AutoSize = $true`r`n"
    psContent .= "$hint.Font = New-Object System.Drawing.Font('Segoe UI',8)`r`n"
    psContent .= "$hint.ForeColor = [System.Drawing.Color]::FromArgb(90,90,90)`r`n"
    psContent .= "$hint.Location = New-Object System.Drawing.Point(22,230)`r`n"
    psContent .= "$form.Controls.Add($hint)`r`n"
    psContent .= "$form.Show()`r`n"
    psContent .= "[System.Windows.Forms.Application]::DoEvents()`r`n"
    psContent .= "$script:spinFrames = @([char]0x25D0, [char]0x25D3, [char]0x25D1, [char]0x25D2)`r`n"
    psContent .= "$script:spinIndex = 0`r`n"
    psContent .= "function Pump { $spinner.Text = $script:spinFrames[$script:spinIndex]; $script:spinIndex = ($script:spinIndex + 1) % $script:spinFrames.Count; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 80 }`r`n"
    psContent .= "$errorLog = $log + '.err'`r`n"
    psContent .= "Remove-Item -LiteralPath $errorLog -Force -ErrorAction SilentlyContinue`r`n"
    psContent .= "function Run-Step($caption, $executable, $arguments) {`r`n"
    psContent .= "  $status.Text = $caption`r`n"
    psContent .= "  $detail.Text = 'Выполняется, пожалуйста подождите…'`r`n"
    psContent .= "  [System.Windows.Forms.Application]::DoEvents()`r`n"
    psContent .= "  $process = Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $requirements) -RedirectStandardOutput $log -RedirectStandardError $errorLog -WindowStyle Hidden -PassThru`r`n"
    psContent .= "  while (-not $process.HasExited) { Pump }`r`n"
    psContent .= "  $process.WaitForExit()`r`n"
    psContent .= "  $process.Refresh()`r`n"
    psContent .= "  $exitCode = $process.ExitCode`r`n"
    psContent .= "  if ($null -eq $exitCode) { $exitCode = 0 }`r`n"
    psContent .= "  if (Test-Path -LiteralPath $errorLog) { Get-Content -LiteralPath $errorLog | Add-Content -LiteralPath $log }`r`n"
    psContent .= "  if ($exitCode -ne 0) { throw ($caption + ' завершился с ошибкой (код ' + $exitCode + ')') }`r`n"
    psContent .= "}`r`n"
    psContent .= "Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue`r`n"
    psContent .= "Remove-Item -LiteralPath $pythonPathFile -Force -ErrorAction SilentlyContinue`r`n"
    psContent .= "function Find-Python {`r`n"
    psContent .= "  $found = @()`r`n"
    psContent .= "  $cmd = Get-Command python.exe -ErrorAction SilentlyContinue`r`n"
    psContent .= "  if ($cmd -and $cmd.Source -notlike '*\\WindowsApps\\*') { $found += $cmd.Source }`r`n"
    psContent .= "  $roots = @((Join-Path $env:USERPROFILE 'AppData\\Local\\Programs\\Python'), (Join-Path $env:LocalAppData 'Programs\\Python'))`r`n"
    psContent .= "  if ($env:ProgramFiles) { $roots += @((Join-Path $env:ProgramFiles 'Python'), $env:ProgramFiles) }`r`n"
    psContent .= "  if (${env:ProgramFiles(x86)}) { $roots += @((Join-Path ${env:ProgramFiles(x86)} 'Python'), ${env:ProgramFiles(x86)}) }`r`n"
    psContent .= "  foreach ($root in $roots) {`r`n"
    psContent .= "    if ($root -and (Test-Path -LiteralPath $root)) {`r`n"
    psContent .= "      $found += @(Get-ChildItem -LiteralPath $root -Filter python.exe -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })`r`n"
    psContent .= "      $found += @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $candidate = Join-Path $_.FullName 'python.exe'; if (Test-Path -LiteralPath $candidate) { $candidate } })`r`n"
    psContent .= "    }`r`n"
    psContent .= "  }`r`n"
    psContent .= "  foreach ($launcher in @((Get-Command py.exe -ErrorAction SilentlyContinue).Source, (Join-Path $env:LocalAppData 'Programs\\Python\\Launcher\\py.exe'))) {`r`n"
    psContent .= "    if ($launcher -and (Test-Path -LiteralPath $launcher)) { try { $resolved = (& $launcher -3 -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1).Trim(); if ($resolved -and (Test-Path -LiteralPath $resolved)) { $found += $resolved } } catch {} }`r`n"
    psContent .= "  }`r`n"
    psContent .= "  foreach ($candidate in $found | Select-Object -Unique) { if ((Test-Path -LiteralPath $candidate) -and (Is-SupportedPython $candidate)) { return $candidate } }`r`n"
    psContent .= "  return $null`r`n"
    psContent .= "}`r`n"
    psContent .= "function Is-SupportedPython($candidate) {`r`n"
    psContent .= "  try { & $candidate -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)' 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }`r`n"
    psContent .= "}`r`n"
    ; Не используем старую или системную установку Python, которая может не
    ; поддерживать актуальные версии Pillow/mss. Python 3.10+ достаточен для
    ; всех зависимостей бота и не требует установки от имени администратора.
    psContent .= "try {`r`n"
    psContent .= "  $status.Text = 'Поиск Python'`r`n"
    psContent .= "  $detail.Text = 'Проверяем стандартные папки и Python Launcher…'`r`n"
    psContent .= "  Pump`r`n"
    psContent .= "  $python = Find-Python`r`n"
    psContent .= "  if (-not $python) {`r`n"
    psContent .= "    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue`r`n"
    psContent .= "    if (-not $winget) { throw 'Python не найден, а winget недоступен. Установите Python с python.org и повторите попытку.' }`r`n"
    psContent .= "    Add-Content -LiteralPath $log -Value 'Python не найден. Устанавливаем Python через winget...'`r`n"
    psContent .= "    $status.Text = 'Установка Python'`r`n"
    psContent .= "    $detail.Text = 'Скачиваем Python через winget…'`r`n"
    psContent .= "    $install = Start-Process -FilePath $winget.Source -ArgumentList @('install','--id','Python.Python.3.13','--scope','user','--silent','--accept-package-agreements','--accept-source-agreements') -PassThru -WindowStyle Hidden`r`n"
    psContent .= "    while (-not $install.HasExited) { Pump }`r`n"
    psContent .= "    if ($install.ExitCode -ne 0) { throw ('Не удалось установить Python через winget (код ' + $install.ExitCode + ')') }`r`n"
    psContent .= "    $python = Find-Python`r`n"
    psContent .= "  }`r`n"
    psContent .= "  if (-not $python) { throw 'Python установлен, но его исполняемый файл не найден. Перезапустите макрос и повторите попытку.' }`r`n"
    psContent .= "  Set-Content -LiteralPath $log -Value ('Python: ' + $python)`r`n"
    psContent .= "  $venvReady = $false`r`n"
    psContent .= "  if (Test-Path -LiteralPath $venvPython) { $venvReady = Is-SupportedPython $venvPython }`r`n"
    psContent .= "  if (-not $venvReady) {`r`n"
    psContent .= "    if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }`r`n"
    psContent .= "    $status.Text = 'Создание окружения'`r`n"
    psContent .= "    $detail.Text = 'Создаём отдельное окружение бота…'`r`n"
    psContent .= "    Run-Step 'Создание окружения' $python @('-m','venv',$venv)`r`n"
    psContent .= "  }`r`n"
    psContent .= "  if (-not (Test-Path -LiteralPath $venvPython)) { throw 'Не удалось создать виртуальное окружение Python' }`r`n"
    psContent .= "  Set-Content -LiteralPath $pythonPathFile -Value $venvPython`r`n"
    psContent .= "  $status.Text = 'Подготовка pip'`r`n"
    psContent .= "  $detail.Text = 'Включаем встроенный установщик пакетов…'`r`n"
    psContent .= "  Run-Step 'Подготовка pip' $venvPython @('-m','ensurepip','--upgrade')`r`n"
    psContent .= "  $status.Text = 'Обновление pip'`r`n"
    psContent .= "  $detail.Text = 'Проверяем менеджер пакетов…'`r`n"
    psContent .= "  Run-Step 'Обновление pip' $venvPython @('-m','pip','install','--upgrade','pip','--disable-pip-version-check','--no-input')`r`n"
    psContent .= "  $status.Text = 'Установка пакетов'`r`n"
    psContent .= "  $detail.Text = 'Устанавливаем discord.py, Pillow и mss…'`r`n"
    psContent .= "  Run-Step 'Установка пакетов' $venvPython @('-m','pip','install','-r',$requirements,'--disable-pip-version-check','--no-input','--prefer-binary')`r`n"
    psContent .= "  Run-Step 'Проверка пакетов' $venvPython @('-c','import discord, PIL, mss')`r`n"
    psContent .= "  $progress.Style = 'Continuous'`r`n"
    psContent .= "  $progress.Value = 100`r`n"
    psContent .= "  $status.Text = 'Готово'`r`n"
    psContent .= "  $detail.Text = 'Все зависимости установлены'`r`n"
    psContent .= "  $spinner.Text = [char]0x2713`r`n"
    psContent .= "  $spinner.ForeColor = [System.Drawing.Color]::FromArgb(34,197,94)`r`n"
    psContent .= "  [System.Windows.Forms.Application]::DoEvents()`r`n"
    psContent .= "  [System.IO.File]::WriteAllText($result, '0')`r`n"
    psContent .= "  Start-Sleep -Milliseconds 800`r`n"
    psContent .= "} catch {`r`n"
    psContent .= "  Add-Content -LiteralPath $log -Value ($_.Exception.Message)`r`n"
    psContent .= "  $status.Text = 'Ошибка установки'`r`n"
    psContent .= "  $detail.Text = $_.Exception.Message`r`n"
    psContent .= "  $status.ForeColor = [System.Drawing.Color]::FromArgb(239,68,68)`r`n"
    psContent .= "  $spinner.Text = '!'`r`n"
    psContent .= "  $spinner.ForeColor = [System.Drawing.Color]::FromArgb(239,68,68)`r`n"
    psContent .= "  $progress.Style = 'Continuous'`r`n"
    psContent .= "  $progress.Value = 0`r`n"
    psContent .= "  [System.Windows.Forms.Application]::DoEvents()`r`n"
    psContent .= "  [System.IO.File]::WriteAllText($result, '1')`r`n"
    psContent .= "  [System.Windows.Forms.Application]::DoEvents()`r`n"
    psContent .= "  $form.Close()`r`n"
    psContent .= "  Start-Sleep -Seconds 3`r`n"
    psContent .= "  exit 1`r`n"
    psContent .= "}`r`n"
    psContent .= "$form.Close()`r`n"
    FileDelete, %BotDepsScriptFile%
    f := FileOpen(BotDepsScriptFile, "w", "UTF-8")
    if (f) {
        f.Write(psContent)
        f.Close()
    }
    if !FileExist(BotDepsScriptFile) {
        AddLog("Discord bot: не удалось создать установщик", "error")
        UpdateBotStatus("Install failed", "error")
        UpdateBotInstallButton(true)
        return
    }
    UpdateBotStatus("Installing dependencies...", "running")
    UpdateBotInstallButton(false)
    AddLog("Discord bot: установка Python и зависимостей запущена", "success")
    q := Chr(34)
    RunWait, % "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " . q . BotDepsScriptFile . q, %BotDir%, Hide
    exitCode := 1
    resultFile := BotRuntimeDir . "\pip_install_exit.txt"
    if FileExist(resultFile) {
        FileRead, resultText, %resultFile%
        exitCode := Trim(resultText) + 0
    } else if (ErrorLevel != 0) {
        exitCode := ErrorLevel
    }
    if (exitCode = 0) {
        AddLog("Discord bot: зависимости установлены", "success")
        UpdateBotStatus("Dependencies installed", "success")
    } else {
        AddLog("Discord bot: установка завершилась с ошибкой (код " . exitCode . "), лог: " . BotDepsLogFile . " | причина: " . ReadBotInstallError(), "error")
        UpdateBotStatus("Install failed", "error")
    }
    if (exitCode = 0)
        FileDelete, %BotDepsScriptFile%
    UpdateBotInstallButton(true)
return

ReadBotInstallError() {
    global BotDepsLogFile
    if !FileExist(BotDepsLogFile)
        return "лог не создан"
    FileRead, logText, %BotDepsLogFile%
    logText := Trim(logText)
    if (StrLen(logText) > 300)
        logText := SubStr(logText, StrLen(logText) - 299)
    return StrReplace(StrReplace(logText, "`r", " "), "`n", " | ")
}

StartDiscordBot:
    if (BotRunning)
        return
    if (BotToken = "") {
        AddLog("Discord bot: токен не задан", "warn")
        UpdateBotStatus("Token is empty", "error")
        return
    }
    botScript := BotDir . "\bot.py"
    if !FileExist(botScript) {
        AddLog("Discord bot: файл bot.py не найден", "error")
        UpdateBotStatus("bot.py not found", "error")
        return
    }
    botPythonExe := ResolveBotPython()
    if (botPythonExe = "") {
        AddLog("Discord bot: Python не найден. Сначала установите зависимости", "error")
        UpdateBotStatus("Python not found", "error")
        return
    }
    BotPython := botPythonExe
    AddLog("Discord bot: найден Python " . botPythonExe)
    botLogFile := BotRuntimeDir . "\bot.log"
    ; Прямой запуск Python надёжнее промежуточного PowerShell-скрипта.
    Run, % """" . botPythonExe . """ -u """ . botScript . """", %BotDir%, Hide, BotProcessPid
    if (ErrorLevel || !BotProcessPid) {
        AddLog("Discord bot: не удалось создать процесс Python (" . botPythonExe . ")", "error")
        UpdateBotStatus("Bot start failed", "error")
        return
    }
    Goto, BotProcessStarted

    ; Старый fallback оставлен ниже для совместимости со сборками, где прямой
    ; запуск запрещён политикой Windows.
    FileDelete, %BotLaunchOutputFile%
    FileDelete, %BotLaunchErrorFile%
    safePython := StrReplace(botPythonExe, "'", "''")
    safeScript := StrReplace(botScript, "'", "''")
    safeWorkDir := StrReplace(BotDir, "'", "''")
    safeBotLog := StrReplace(botLogFile, "'", "''")
    safeLaunchError := StrReplace(BotLaunchErrorFile, "'", "''")
    safeLaunchOutput := StrReplace(BotLaunchOutputFile, "'", "''")
    launchScript := "$ErrorActionPreference = 'Stop'`r`n"
    launchScript .= "$python = '" . safePython . "'`r`n"
    launchScript .= "$script = '" . safeScript . "'`r`n"
    launchScript .= "$work = '" . safeWorkDir . "'`r`n"
    launchScript .= "$log = '" . safeBotLog . "'`r`n"
    launchScript .= "$err = '" . safeLaunchError . "'`r`n"
    launchScript .= "$out = '" . safeLaunchOutput . "'`r`n"
    launchScript .= "try {`r`n"
    launchScript .= "  if (-not (Test-Path -LiteralPath $python)) { throw ('Python not found: ' + $python) }`r`n"
    launchScript .= "  if (-not (Test-Path -LiteralPath $script)) { throw ('bot.py not found: ' + $script) }`r`n"
    launchScript .= "  $probe = @(& $python '-c' 'import discord; print(discord.__version__)' 2>&1)`r`n"
    launchScript .= "  if ($LASTEXITCODE -ne 0) { throw ('Не удалось загрузить discord.py: ' + ($probe -join ' ')) }`r`n"
    launchScript .= "  Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue`r`n"
    launchScript .= "  $p = Start-Process -FilePath $python -ArgumentList @('-u', $script) -WorkingDirectory $work -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru`r`n"
    launchScript .= "  if (-not $p) { throw 'Не удалось создать процесс Python' }`r`n"
    launchScript .= "  Set-Content -LiteralPath (Join-Path $work 'runtime\\bot_pid.txt') -Value $p.Id`r`n"
    launchScript .= "} catch { Set-Content -LiteralPath $err -Value ($_.Exception | Out-String); exit 1 }`r`n"
    FileDelete, %BotLaunchScriptFile%
    launchFile := FileOpen(BotLaunchScriptFile, "w", "UTF-8")
    if (launchFile) {
        launchFile.Write(launchScript)
        launchFile.Close()
    }
    RunWait, % "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . BotLaunchScriptFile . """", %BotDir%, Hide
    if (FileExist(BotLaunchErrorFile)) {
        FileRead, launchError, %BotLaunchErrorFile%
        launchError := Trim(launchError)
        if (launchError != "") {
            AddLog("Discord bot: ошибка запуска — " . launchError, "error")
            UpdateBotStatus("Bot start failed", "error")
            return
        }
    }
    pidFile := BotRuntimeDir . "\bot_pid.txt"
    if FileExist(pidFile) {
        FileRead, pidText, %pidFile%
        BotProcessPid := Trim(pidText) + 0
    }
BotProcessStarted:
    if (!BotProcessPid) {
        AddLog("Discord bot: процесс не был создан", "error")
        UpdateBotStatus("Bot start failed", "error")
        return
    }
    ; Даём Python время пройти импорт и проверить токен. Если процесс сразу
    ; завершился, показываем реальную причину из stderr/stdout, а не «запуск».
    Sleep, 900
    Process, Exist, %BotProcessPid%
    if (!ErrorLevel) {
        launchError := ""
        if FileExist(BotLaunchErrorFile) {
            FileRead, launchError, %BotLaunchErrorFile%
            launchError := Trim(launchError)
        }
        if (launchError = "" && FileExist(BotLaunchOutputFile)) {
            FileRead, launchError, %BotLaunchOutputFile%
            launchError := Trim(launchError)
        }
        if (launchError = "" && FileExist(BotRuntimeDir . "\bot.log")) {
            FileRead, launchError, % BotRuntimeDir . "\bot.log"
            launchError := Trim(launchError)
            if (StrLen(launchError) > 280)
                launchError := SubStr(launchError, StrLen(launchError) - 279)
        }
        if (launchError = "")
            launchError := "Python завершился до подключения к Discord"
        if (StrLen(launchError) > 220)
            launchError := SubStr(launchError, 1, 220) . "…"
        AddLog("Discord bot: процесс завершился — " . launchError, "error")
        UpdateBotStatus("Bot stopped", "error")
        BotProcessPid := 0
        return
    }
    ; Process, Exist возвращает PID найденного процесса в ErrorLevel.
    ; Ненулевое значение здесь означает успешный запуск, а не ошибку.
    BotRunning := true
    AddLog("Discord bot: запуск запрошен (лог: " . BotDir . "\runtime\bot.log)", "success")
    UpdateBotStatus("Running", "running")
return

ResolveBotPython() {
    global BotPython, BotPythonPathFile, BotVenvPythonFile
    ; Всегда предпочитаем окружение, созданное кнопкой установки. Это
    ; исключает запуск на другом Python после обновления или переустановки.
    if FileExist(BotVenvPythonFile)
        return BotVenvPythonFile
    if (InStr(BotPython, "\") && FileExist(BotPython))
        return BotPython
    if FileExist(BotPythonPathFile) {
        FileRead, savedPython, %BotPythonPathFile%
        savedPython := Trim(StrReplace(StrReplace(savedPython, "`r", ""), "`n", ""))
        if (savedPython != "" && FileExist(savedPython))
            return savedPython
    }

    ; Python Launcher знает фактическую установку даже если Python не добавлен
    ; в PATH (частый случай после установки через winget).
    pyProbe := A_Temp . "\mmacro_python_path.txt"
    FileDelete, %pyProbe%
    pyCommand := A_ComSpec . " /c py.exe -3 -c ""import sys; print(sys.executable)"" > """ . pyProbe . """ 2>nul"
    RunWait, %pyCommand%, , Hide
    if FileExist(pyProbe) {
        FileRead, pyResolved, %pyProbe%
        pyResolved := Trim(StrReplace(StrReplace(pyResolved, "`r", ""), "`n", ""))
        FileDelete, %pyProbe%
        if (pyResolved != "" && FileExist(pyResolved))
            return pyResolved
    }

    ; Официальный установщик также записывает путь в реестр.
    for _, version in ["3.13", "3.12", "3.11", "3.10", "3.9"] {
        RegRead, installPath, HKCU, Software\Python\PythonCore\%version%\InstallPath,
        if (ErrorLevel)
            RegRead, installPath, HKLM, Software\Python\PythonCore\%version%\InstallPath,
        if (!ErrorLevel && installPath != "") {
            candidate := RTrim(installPath, "\") . "\pythonw.exe"
            if FileExist(candidate)
                return candidate
            candidate := RTrim(installPath, "\") . "\python.exe"
            if FileExist(candidate)
                return candidate
        }
    }

    EnvGet, pathValue, PATH
    Loop, Parse, pathValue, `;
    {
        dir := Trim(A_LoopField)
        if (dir = "" || InStr(dir, "\WindowsApps\"))
            continue
        candidate := dir . "\pythonw.exe"
        if FileExist(candidate)
            return candidate
        candidate := dir . "\python.exe"
        if FileExist(candidate)
            return candidate
    }

    EnvGet, botLocalAppData, LOCALAPPDATA
    EnvGet, botUserProfile, USERPROFILE
    EnvGet, botPfRoot, ProgramFiles
    EnvGet, botPf86Root, ProgramFiles(x86)
    roots := []
    if (botLocalAppData != "")
        roots.Push(botLocalAppData . "\Programs\Python")
    if (botUserProfile != "")
        roots.Push(botUserProfile . "\AppData\Local\Programs\Python")
    if (botPfRoot != "")
        roots.Push(botPfRoot . "\Python")
    if (botPf86Root != "")
        roots.Push(botPf86Root . "\Python")

    for _, root in roots {
        candidate := root . "\pythonw.exe"
        if FileExist(candidate)
            return candidate
        candidate := root . "\python.exe"
        if FileExist(candidate)
            return candidate
        pattern := root . "\Python*\pythonw.exe"
        Loop, Files, %pattern%, F
            return A_LoopFileFullPath
        pattern := root . "\Python*\python.exe"
        Loop, Files, %pattern%, F
            return A_LoopFileFullPath
    }
    return ""
}

StopDiscordBot:
    if (BotProcessPid) {
        Process, Close, %BotProcessPid%
        BotProcessPid := 0
    }
    BotRunning := false
    AddLog("Discord bot: остановлен")
    UpdateBotStatus("Stopped", "")
return

RestartDiscordBot:
    Gosub, StopDiscordBot
    Sleep, 200
    Gosub, StartDiscordBot
return

PublishBotState:
    WriteBotState()
return

PollBotCommands:
    if !FileExist(BotCommandsDir)
        return
    Loop, Files, %BotCommandsDir%\*.cmd, F
    {
        commandFile := A_LoopFileFullPath
        FileRead, rawCommand, %commandFile%
        FileDelete, %commandFile%
        requestId := ""
        botAction := ""
        botArgument := ""
        Loop, Parse, rawCommand, `n, `r
        {
            line := A_LoopField
            equalPos := InStr(line, "=")
            if (!equalPos)
                continue
            key := SubStr(line, 1, equalPos - 1)
            value := SubStr(line, equalPos + 1)
            if (key = "id")
                requestId := value
            else if (key = "action")
                botAction := value
            else if (key = "arg")
                botArgument := UriDecode(value)
        }
        if (requestId != "" && botAction != "")
            ProcessBotCommand(requestId, botAction, botArgument)
        break
    }
return

ProcessBotCommand(requestId, action, argument) {
    global BotScreenshotFile, PendingMapChange, Running, MapCoords, SelectedMapCtl, LastCaptureX, LastCaptureY, LastCaptureW, LastCaptureH, WinTitle, GameAreaW, GameAreaH
    if (action = "screenshot") {
        ; Захват выполняет Python-бот: он умеет поднять Roblox, получить
        ; изображение через mss и использовать desktop fallback. AHK только
        ; быстро передаёт актуальную область, поэтому команда не блокирует
        ; макрос на WinWaitActive/BitBlt/PrintWindow.
        if (GameAreaOrigin(captureX, captureY)) {
            LastCaptureX := captureX
            LastCaptureY := captureY
            LastCaptureW := GameAreaW
            LastCaptureH := GameAreaH
            BotWriteResponse(requestId, true, "Область для снимка передана боту", "", LastCaptureX . "," . LastCaptureY . "," . LastCaptureW . "," . LastCaptureH)
        } else {
            BotWriteResponse(requestId, true, "Игровая область не найдена; бот попробует снять рабочий стол")
        }
        return
    }
    if (action = "state") {
        BotWriteResponse(requestId, true, BotStateText())
        return
    }
    if (action = "switch-map") {
        if (argument = "") {
            BotWriteResponse(requestId, false, "Имя карты не указано")
            return
        }
        if (!MapCoords.HasKey(argument)) {
            BotWriteResponse(requestId, false, "Карта не найдена или не размечена: " argument)
            return
        }
        if (Running) {
            PendingMapChange := argument
            AddLog("Discord bot: смена карты поставлена в очередь — " argument, "warn")
            BotWriteResponse(requestId, true, "Карта " argument " будет запущена после текущего раунда")
        } else {
            SelectedMapCtl := argument
            LoadRejoinActions(argument)
            RefreshMapDropdown()
            AddLog("Discord bot: выбрана карта " argument)
            BotWriteResponse(requestId, true, "Карта переключена: " argument)
        }
        WriteBotState()
        return
    }
    BotWriteResponse(requestId, false, "Неизвестная команда: " action)
}

BotWriteResponse(requestId, ok, message, path := "", region := "") {
    global BotResponsesDir
    responseFile := BotResponsesDir . "\" . requestId . ".result"
    content := "ok=" . (ok ? 1 : 0) . "`n"
    content .= "message=" . UriEncode(message) . "`n"
    if (path != "")
        content .= "path=" . UriEncode(path) . "`n"
    if (region != "")
        content .= "region=" . UriEncode(region) . "`n"
    ; Сначала полностью записываем ответ во временный файл, затем заменяем
    ; итоговый. Иначе Python может прочитать response в середине записи и
    ; получить path без строки ok.
    temporary := responseFile . ".tmp"
    FileDelete, %temporary%
    FileAppend, %content%, %temporary%, UTF-8
    FileMove, %temporary%, %responseFile%, 1
}

WriteBotState() {
    global BotStateFile, Running, SelectedMapCtl, FarmRunCount, PendingMapChange, MapList, BotRunning, BotMapRecordActive, BotMapRecordMap, GameMode
    content := "running=" . (Running ? 1 : 0) . "`n"
    content .= "game_mode=" . UriEncode(GameMode) . "`n"
    content .= "selected_map=" . UriEncode(SelectedMapCtl) . "`n"
    content .= "pending_map=" . UriEncode(PendingMapChange) . "`n"
    content .= "runs=" . FarmRunCount . "`n"
    content .= "bot_running=" . (BotRunning ? 1 : 0) . "`n"
    content .= "map_recording=" . (BotMapRecordActive ? 1 : 0) . "`n"
    content .= "map_record_map=" . UriEncode(BotMapRecordMap) . "`n"
    for i, mapName in MapList
        content .= "map_" . i . "=" . UriEncode(mapName) . "`n"
    temporary := BotStateFile . ".tmp"
    FileDelete, %temporary%
    FileAppend, %content%, %temporary%, UTF-8
    FileMove, %temporary%, %BotStateFile%, 1
}

BotStateText() {
    global Running, SelectedMapCtl, PendingMapChange, FarmRunCount, BotMapRecordActive, BotMapRecordMap, GameMode
    return "Режим: " GameModeLabel(GameMode) " | Фарм: " (Running ? "запущен" : "остановлен") " | карта: " (SelectedMapCtl != "" ? SelectedMapCtl : "не выбрана") " | ранов: " FarmRunCount (PendingMapChange != "" ? " | ожидает: " PendingMapChange : "") (BotMapRecordActive ? " | запись: " BotMapRecordMap : "")
}

UriEncode(str) {
    result := ""
    Loop, Parse, str
    {
        c := A_LoopField
        if (c ~= "[A-Za-z0-9_.~-]")
            result .= c
        else {
            code := Asc(c)
            if (code < 256)
                result .= "%" . Format("{:02X}", code)
            else
                result .= c
        }
    }
    return result
}

BotMapActionsFile(mapName) {
    global BotActionsDir
    ; Действия входа хранятся по режиму: actions\<режим>\<карта>.ini.
    dir := BotActionsDir . "\" . GameMode
    if !InStr(FileExist(dir), "D")
        FileCreateDir, %dir%
    return dir . "\" . MapFileBase(mapName) . ".ini"
}

LoadBotMapActions(mapName) {
    global BotMapActions
    BotMapActions := []
    f := BotMapActionsFile(mapName)
    if !FileExist(f)
        return
    IniRead, count, %f%, Actions, Count, 0
    Loop, %count% {
        IniRead, raw, %f%, Actions, %A_Index%, -
        if (raw = "-")
            continue
        if (InStr(raw, "wheel,") = 1) {
            rest := SubStr(raw, 7)
            StringSplit, wheelParts, rest, `,
            if (wheelParts0 >= 2)
                BotMapActions.Push({isWheel: true, delta: wheelParts1, delay: wheelParts2})
        } else {
            StringSplit, parts, raw, `,
            if (parts0 >= 3)
                BotMapActions.Push({x: parts1, y: parts2, delay: parts3})
        }
    }
}

SaveBotMapActions(mapName) {
    global BotMapRecordActions
    f := BotMapActionsFile(mapName)
    FileDelete, %f%
    count := BotMapRecordActions.Length()
    IniWrite, %count%, %f%, Actions, Count
    Loop, %count% {
        a := BotMapRecordActions[A_Index]
        if (a.isWheel)
            IniWrite, % "wheel," . a.delta . "," . a.delay, %f%, Actions, %A_Index%
        else
            IniWrite, % a.x . "," . a.y . "," . a.delay, %f%, Actions, %A_Index%
    }
}

ClearBotMapActions(mapName, requestId := "") {
    if (mapName = "")
        mapName := "_invalid_"
    f := BotMapActionsFile(mapName)
    if FileExist(f)
        FileDelete, %f%
    if (requestId != "")
        BotWriteResponse(requestId, true, "Запись действий для " mapName " очищена")
}

PushBotMapRecordState() {
    global BotMapRecordActive, BotMapRecordMap, BotMapRecordActions
    mapJS := JsEscape(BotMapRecordMap)
    count := BotMapRecordActions.Length()
    WBH_CallJS("ahkMapRecordState(" . (BotMapRecordActive ? "true" : "false") . ",'" . mapJS . "'," . count . ")")
    ModalCallJS("ahkMapRecordState(" . (BotMapRecordActive ? "true" : "false") . ",'" . mapJS . "'," . count . ")")
}

StartBotMapRecord(mapName, requestId := "") {
    global BotMapRecordActive, BotMapRecordMap, BotMapRecordActions, BotMapRecordLastTime, BotMapRecordPending, RejoinRecordActive
    if (mapName = "") {
        if (requestId != "")
            BotWriteResponse(requestId, false, "Имя карты не указано")
        return
    }
    if (RejoinRecordActive) {
        if (requestId != "")
            BotWriteResponse(requestId, false, "Сначала остановите обычную запись Rejoin")
        return
    }
    BotMapRecordMap := mapName
    BotMapRecordActions := []
    BotMapRecordLastTime := A_TickCount
    BotMapRecordPending := false
    BotMapRecordActive := true
    Hotkey, ~WheelUp, On
    Hotkey, ~WheelDown, On
    SetTimer, RejoinRecordTimer, 50
    AddLog("Discord bot: запись входа на карту начата — " mapName, "success")
    WriteBotState()
    PushBotMapRecordState()
    if (requestId != "")
        BotWriteResponse(requestId, true, "Запись начата для " mapName)
}

StopBotMapRecord(requestId := "") {
    global BotMapRecordActive, BotMapRecordMap, BotMapRecordActions, BotMapRecordPending, RejoinRecordActive
    if (!BotMapRecordActive) {
        if (requestId != "")
            BotWriteResponse(requestId, false, "Запись сейчас не запущена")
        return
    }
    BotMapRecordActive := false
    BotMapRecordPending := false
    SaveBotMapActions(BotMapRecordMap)
    if (!RejoinRecordActive) {
        SetTimer, RejoinRecordTimer, Off
        Hotkey, ~WheelUp, Off
        Hotkey, ~WheelDown, Off
    }
    count := BotMapRecordActions.Length()
    AddLog("Discord bot: запись сохранена для " BotMapRecordMap " (" count " действий)")
    WriteBotState()
    PushBotMapRecordState()
    if (requestId != "")
        BotWriteResponse(requestId, true, "Запись сохранена: " count " действий")
}

PlayBotMapActions(mapName) {
    global BotMapActions
    LoadBotMapActions(mapName)
    count := BotMapActions.Length()
    if (count < 1) {
        AddLog("Discord bot: для карты " mapName " нет записанных действий", "warn")
        return false
    }
    AddLog("Discord bot: выполняю " count " действий входа на карту " mapName)
    return PlayActionList(BotMapActions, "Discord bot")
}

PlayActionList(actions, source := "Actions") {
    global Running, TS_X, TS_Y, WinTitle
    ; Колесо через SendInput получает Roblox только у активного окна.
    if (WinExist(WinTitle)) {
        WinActivate, %WinTitle%
        WinWaitActive, %WinTitle%,, 2
    }
    for i, a in actions {
        if (!Running)
            return false
        if (a.delay > 0)
            Sleep, % a.delay
        if (!Running)
            return false
        if (a.isWheel) {
            notches := Abs(a.delta) // 120
            Loop, %notches% {
                if (a.delta > 0)
                    SendInput, {WheelUp}
                else
                    SendInput, {WheelDown}
                Sleep, 30
            }
        } else {
            ToScreen(a.x, a.y)
            SmoothClick(TS_X, TS_Y, 80)
        }
    }
    AddLog(source ": действия завершены")
    return true
}

HandlePendingMapChange(resultName) {
    global PendingMapChange, SelectedMapCtl, Running, MapCoords, BotMapPostActionsDelay
    target := PendingMapChange
    PendingMapChange := ""
    if (target = "" || !MapCoords.HasKey(target))
        return false
    SetTimer, WatchNextStage, Off
    SelectedMapCtl := target
    LoadRejoinActions(target)
    RefreshMapDropdown()
    WBH_CallJS("ahkUpdateStatus('Changing map...', 'running')")
    AddLog("Discord bot: " resultName " — переключаюсь на карту " target)
    actionsPlayed := PlayBotMapActions(target)
    if (Running && actionsPlayed && BotMapPostActionsDelay > 0) {
        AddLog("Discord bot: жду " BotMapPostActionsDelay " сек после действий входа на карту")
        Sleep, % BotMapPostActionsDelay * 1000
    }
    if (Running)
        SetTimer, RunPlacementSequence, -100
    WriteBotState()
    return true
}

; ===================== HTML ↔ AHK BRIDGE =====================

; ---- Выполнить JavaScript в HTML-панели ----
WBH_CallJS(js) {
    global WB
    if (!WB || WB.ReadyState != 4)
        return
    try {
        WB.Document.parentWindow.execScript(js)
    } catch e {
        AddLog("JS bridge error: " . e.Message . " | call: " . SubStr(js, 1, 80), "error")
        ; HTML-панель может быть не готова
    }
}

; ---- Таймер: опрос команд от JS (каждые 150 мс) ----
PollJSCmd:
    if (!WB || WB.ReadyState != 4)
        return
    cmd := ""
    try {
        cmd := WB.Document.parentWindow.ahkCmd
        if (cmd && cmd != "")
            WB.Document.parentWindow.ahkCmd := ""
    } catch e {
        return
    }
    if (cmd && cmd != "")
        ProcessJSCmd(cmd)
return

; ---- Обработка команд, пришедших из HTML ----
ProcessJSCmd(cmd) {
    global SelectedMapCtl, AutoUpgradeEnabled, Running, WB, FarmMode, PresetName
    ; Переменные ручного драга окна: без global они стали бы локальными в этой
    ; функции, и ManualDragLoop (метка, глобальная область) читал бы нули →
    ; сайдбар прыгал к курсору, а Roblox уезжал за левый край экрана.
    global WinDragStartMX, WinDragStartMY, WinDragStartWX, WinDragStartWY, WinDragLastMouseX, WinDragLastMouseY, WinDragLastTargetX, WinDragLastTargetY, WinDragMonitor, WinDragWorkLeft, WinDragWorkTop, WinDragWorkRight, WinDragWorkBottom, WinDragActive, MainGuiHwnd, GameHwnd, Embedded, GameAreaW, SidebarW
    
    ; Разбираем команду: "command" или "command/arg"
    slashPos := InStr(cmd, "/")
    if (slashPos) {
        action := SubStr(cmd, 1, slashPos - 1)
        arg := SubStr(cmd, slashPos + 1)
    } else {
        action := cmd
        arg := ""
    }
    
    if (action = "embed") {
        Gosub, BtnEmbed
        return
    }
    if (action = "start-farm") {
        Gosub, BtnStartStop
        return
    }
    if (action = "farm-mode") {
        if (Running) {
            WBH_CallJS("ahkSetFarmMode('" . JsEscape(FarmMode) . "')")
            AddLog("Сначала останови фарм, чтобы сменить режим", "warn")
            return
        }
        FarmMode := (arg = "autoplay") ? "autoplay" : "units"
        SaveSettings()
        WBH_CallJS("ahkSetFarmMode('" . JsEscape(FarmMode) . "')")
        AddLog("Режим фарма: " . (FarmMode = "autoplay" ? "AutoPlay" : "расстановка юнитов"))
        return
    }
    if (action = "bot-start") {
        Gosub, StartDiscordBot
        return
    }
    if (action = "bot-stop") {
        Gosub, StopDiscordBot
        return
    }
    if (action = "bot-install-deps") {
        Gosub, InstallBotDependencies
        return
    }
    if (action = "select-map") {
        if (Running) {
            ; Смена карты на ходу: расстановка продолжила бы работать со слотами
            ; прежней карты, поэтому отказываем и возвращаем выбор в панели.
            AddLog("Сначала останови фарм, чтобы сменить карту", "warn")
            if (SelectedMapCtl != "")
                WBH_CallJS("ahkUpdateMap('" . StrReplace(SelectedMapCtl, "'", "\\'") . "')")
            else
                WBH_CallJS("ahkUpdateMap('')")
            return
        }
        if (arg = "__none__")
            SelectedMapCtl := ""
        else
            SelectedMapCtl := arg
        Gosub, MapChanged
        return
    }
    if (action = "select-mode") {
        SelectGameMode(arg)
        return
    }
    if (action = "detect-map") {
        Gosub, MapDetectNow
        return
    }
    if (action = "capture-title") {
        Gosub, MapCaptureTitle
        return
    }
    if (action = "snapshot") {
        Gosub, BtnCaptureMap
        return
    }
    if (action = "mark-slots") {
        Gosub, BtnMarkSlots
        return
    }
    if (action = "clear-map") {
        Gosub, BtnClearMap
        return
    }
    if (action = "toggle-autoupgrade") {
        AutoUpgradeEnabled := !AutoUpgradeEnabled
        WBH_CallJS("document.getElementById('chkAutoUpgrade').checked = " . (AutoUpgradeEnabled ? "true" : "false") . ";")
        if (AutoUpgradeEnabled)
            AddLog("Auto Upgrade: ON")
        else
            AddLog("Auto Upgrade: OFF")
        return
    }
    if (action = "settings") {
        OpenModalWindow("settings", "Settings", 480, 660)
        return
    }
    if (action = "presets") {
        OpenModalWindow("presets", "Presets", 440, 370)
        return
    }
    if (action = "check-update") {
        GoSub, CheckForUpdate
        return
    }
    if (action = "confirm-update") {
        global PendingUpdateURL
        if (PendingUpdateURL != "") {
            AddLog("Update: скачиваю " . PendingUpdateURL . "...")
            RunUpdateScript(PendingUpdateURL)
        }
        return
    }
    if (action = "cancel-update") {
        AddLog("Update: отложено пользователем")
        return
    }
    if (action = "debug-log") {
        AddLog("JS debug: " . arg)
        return
    }
    if (action = "calibrate") {
        OpenModalWindow("calibrate", "Calibration", 460, 550)
        return
    }
    if (action = "upgrade-cfg") {
        OpenModalWindow("upgrade", "Auto Upgrade", 360, 320)
        return
    }
    if (action = "clear-log") {
        WBH_CallJS("ahkClearLog()")
        return
    }
    if (action = "minimize-main") {
        Gui, Minimize
        return
    }
    if (action = "close-main") {
        Gosub, GuiClose
        return
    }
    if (InStr(cmd, "drag-start-main/")) {
        params := SubStr(cmd, 17)
        slashPos := InStr(params, "/")
        if (slashPos && GetKeyState("LButton", "P")) {
            sx := SubStr(params, 1, slashPos - 1)
            sy := SubStr(params, slashPos + 1)
            WinDragStartMX := sx, WinDragStartMY := sy
            WinDragLastMouseX := "", WinDragLastMouseY := ""
            WinDragLastTargetX := "", WinDragLastTargetY := ""
            WinDragMonitor := 0
            ; WinGetPos: OutX, OutY, OutWidth, OutHeight, WinTitle, ...
            ; Раньше здесь было «WinGetPos, X, Y, ahk_id %MainGuiHwnd%» — без
            ; пустых OutWidth/OutHeight заголовок окна попадал в поле ширины,
            ; и AHK пытался создать переменную с именем «ahk_id 0x...» (нелегальный
            ; символ — пробел), что убивало поток и драг не стартовал.
            WinGetPos, WinDragStartWX, WinDragStartWY, , , ahk_id %MainGuiHwnd%
            WinDragActive := true
            SetTimer, SyncDockPosition, Off
            SetTimer, PollJSCmd, 5
            SetTimer, ManualDragLoop, 10
        }
        return
    }
    if (InStr(cmd, "drag-end-main")) {
        EndManualDrag(false)
        return
    }
    if (InStr(cmd, "drag-start-modal/")) {
        params := SubStr(cmd, 18)
        slashPos := InStr(params, "/")
        if (slashPos) {
            sx := SubStr(params, 1, slashPos - 1)
            sy := SubStr(params, slashPos + 1)
            DoNativeDragModal(sx, sy)
        }
        return
    }
}

; ---- Отправка начального состояния в HTML ----
PushStateToHTML:
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    global Embedded, Running, FarmRunCount, AutoUpgradeEnabled, MapList, SelectedMapCtl, AppLanguage, FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    
    ; Сообщаем JS что мы в AHK-режиме (не standalone браузер)
    WBH_CallJS("ahkSetMode()")
    WBH_CallJS("ahkSetLanguage('" . AppLanguage . "')")
    farmHotkeyJS := JsEscape(FarmHotkey)
    rejoinHotkeyJS := JsEscape(RejoinRecordHotkey)
    mapChangeHotkeyJS := JsEscape(MapChangeRecordHotkey)
    mapDetectHotkeyJS := JsEscape(MapDetectHotkey)
    WBH_CallJS("ahkSetHotkeys('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
    WBH_CallJS("ahkUpdateVersion('" . CURRENT_VERSION . "', false)")
    WBH_CallJS("ahkUpdateEmbed(" . (Embedded ? "true" : "false") . ")")
    WBH_CallJS("ahkUpdateFarm(" . (Running ? "true" : "false") . ")")
    WBH_CallJS("ahkUpdateRunCount(" . FarmRunCount . ")")
    WBH_CallJS("ahkUpdateAutoUpgrade(" . (AutoUpgradeEnabled ? "true" : "false") . ")")
    WBH_CallJS("ahkSetFarmMode('" . JsEscape(FarmMode) . "')")
    WBH_CallJS("ahkSetGameMode('" . GameMode . "')")
    if (Running)
        WBH_CallJS("ahkUpdateStatus('Watching...', 'running')")
    else
        WBH_CallJS("ahkUpdateStatus('Idle', '')")
    
    ; Карты
    if (MapList.Length() > 0) {
        mapOpts := ""
        for i, m in MapList
            mapOpts .= (i > 1 ? "|" : "") . m
        WBH_CallJS("ahkSetMapOptions(""" . mapOpts . """)")
    }
    else
        WBH_CallJS("ahkSetMapOptions("""")")
    PushMapDetectResult(LastDetectedMap, LastDetectScore)
    
    ; Координаты
    upStr := "Up(" . UpgradeX . "," . UpgradeY . ")"
    stStr := "Start(" . StartGameX . "," . StartGameY . ")"
    rpStr := "Repeat(" . RepeatStageX . "," . RepeatStageY . ")"
    auStr := "Auto(" . AutoX . "," . AutoY . ")"
    WBH_CallJS("ahkUpdateCoords(""" . upStr . """,""" . stStr . """,""" . rpStr . """,""" . auStr . """)")
    if (SelectedMapCtl != "")
        WBH_CallJS("ahkUpdateMap('" . StrReplace(SelectedMapCtl, "'", "\\'") . "')")
    else
        WBH_CallJS("ahkUpdateMap('')")
    
    ; Автопрокачка
    if (AutoUpgradeEnabled)
        WBH_CallJS("document.getElementById('chkAutoUpgrade').checked = true;")
    
    AddLog("HTML sidebar loaded — bridge active", "success")
return

; ---- Обновление координат в HTML (вызывается после калибровки) ----
UpdateCoordsHTML() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    upStr := "Up(" . UpgradeX . "," . UpgradeY . ")"
    stStr := "Start(" . StartGameX . "," . StartGameY . ")"
    rpStr := "Repeat(" . RepeatStageX . "," . RepeatStageY . ")"
    auStr := "Auto(" . AutoX . "," . AutoY . ")"
    WBH_CallJS("ahkUpdateCoords(""" . upStr . """,""" . stStr . """,""" . rpStr . """,""" . auStr . """)")
}

; ---- Обновление списка карт в HTML ----
UpdateMapListHTML() {
    global MapList
    if (MapList.Length() > 0) {
        mapOpts := ""
        for i, m in MapList
            mapOpts .= (i > 1 ? "|" : "") . m
        WBH_CallJS("ahkSetMapOptions(""" . mapOpts . """)")
    }
    else
        WBH_CallJS("ahkSetMapOptions("""")")
}

; ===================== MODAL WINDOWS (HTML sub-windows) =====================

; ---- Открыть модальное окно с HTML-дизайном ----
; name: "settings" / "presets" / "calibrate" / "upgrade"
; title: заголовок окна
; w, h: размеры окна
OpenModalWindow(name, title, w, h) {
    global htmlURL, WB_Modal, ModalHwnd, MainGuiHwnd, AppLanguage
    ; Пока открыты настройки, назначаемые комбинации не должны запускать макрос.
    EnableConfiguredHotkeys()
    if (name = "settings")
        DisableConfiguredHotkeys()
    
    ; Закрываем предыдущее модальное окно если открыто
    Gui, Modal:Destroy
    SetTimer, PollModalClose, Off
    
    ; Создаём окно без стандартного title bar (кастомный хотбар в HTML)
    ; В dock-режиме Roblox может находиться выше owner-окна. Модалка
    ; временно AlwaysOnTop, чтобы Settings/Presets всегда были доступны.
    Gui, Modal:New, +HwndModalHwnd +AlwaysOnTop -Caption, %title%
    ; Модалка принадлежит главному окну AHK. Она будет выше связки
    ; Roblox+панель, но не станет глобальным AlwaysOnTop для всех программ.
    SetWindowLongPtr(ModalHwnd, -8, MainGuiHwnd) ; GWLP_HWNDPARENT = owner
    Gui, Modal:Color, 0x121212
    Gui, Modal:Add, ActiveX, x0 y0 w%w% h%h% vWB_Modal, Shell.Explorer
    WB_Modal.Silent := true
    navURL := htmlURL . "?_=" . A_TickCount . "#" . name
    WB_Modal.Navigate(navURL, 12)
    
    ; Ждём загрузки
    waitStart := A_TickCount
    while (WB_Modal.ReadyState != 4 && A_TickCount - waitStart < 10000)
        Sleep, 80
    
    ; Сначала применяем язык ко всей модалке, затем пушим её данные.
    ModalCallJS("ahkSetLanguage('" . AppLanguage . "')")
    ; Пушим данные в модалку (текущие настройки / список пресетов / координаты)
    PushModalData(name)
    
    ; Центрируем окно на экране
    SysGet, Mon, MonitorWorkArea
    cx := (MonRight - MonLeft - w) // 2
    cy := (MonTop - MonTop + MonBottom - MonTop - h) // 2
    if (cx < 0)
        cx := 100
    if (cy < 0)
        cy := 100
    
    Gui, Modal:Show, x%cx% y%cy% w%w% h%h%, %title%
    WinActivate, ahk_id %ModalHwnd%
    
    ; Trident (Shell.Explorer) не всегда перерисовывает DOM после показа окна —
    ; из-за этого модалка (особенно пресеты) видна «пустой», пока курсор не наведут
    ; на поле. Принудительный reflow + отложенный пустой execScript заставляют
    ; движок отрисовать содержимое сразу после Show.
    ModalCallJS("try{var _p=document.querySelector('.modal.show .modal-panel')||document.querySelector('.modal-panel');if(_p){var _r=_p.offsetHeight;}}catch(e){}")
    ModalCallJS("0")

    ; Повторный пуш данных на случай, если при первом PushModalData JS-обработчики
    ; (window.ahkLoadSettings и т.п.) ещё не были готовы — такое бывает, когда
    ; document.readyState уже "complete", а скрипты в самом низу страницы
    ; выполнились на пару кадров позже. Без этого повторного пуша поля в
    ; модалке выглядят как "сброшенные" на дефолт.
    PushModalData(name)
    
    ; Таймер для опроса JS-команд (закрыть, свернуть, драг)
    SetTimer, PollModalClose, 20
}

; ---- Нативная запись горячей клавиши ----
; HTML-кнопка открывает настоящий AHK Hotkey-контрол. Он корректно
; распознаёт F-клавиши и комбинации даже во встроенном Shell.Explorer.
ShowHotkeyCapture(target) {
    global HotkeyCaptureTarget, HotkeyCaptureHwnd, HotkeyCaptureValue, HotkeyCaptureLastValue, FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    HotkeyCaptureTarget := (target = "rejoin") ? "rejoin" : ((target = "map-change") ? "map-change" : ((target = "map-detect") ? "map-detect" : "farm"))
    DisableConfiguredHotkeys()
    initial := (HotkeyCaptureTarget = "rejoin") ? RejoinRecordHotkey : ((HotkeyCaptureTarget = "map-change") ? MapChangeRecordHotkey : ((HotkeyCaptureTarget = "map-detect") ? MapDetectHotkey : FarmHotkey))
    HotkeyCaptureLastValue := initial

    Gui, HotkeyCapture:Destroy
    ; Само окно невидимое и нужно только как нативный источник ввода.
    ; Визуальная часть назначения теперь полностью рисуется в HTML-overlay.
    Gui, HotkeyCapture:New, +ToolWindow -Caption +HwndHotkeyCaptureHwnd
    Gui, HotkeyCapture:Add, Hotkey, x0 y0 w240 h40 vHotkeyCaptureValue, %initial%
    Gui, HotkeyCapture:Show, x0 y0 w240 h40
    WinSet, Transparent, 0, ahk_id %HotkeyCaptureHwnd%
    WinActivate, ahk_id %HotkeyCaptureHwnd%
    GuiControl, HotkeyCapture:Focus, HotkeyCaptureValue
    SetTimer, PollHotkeyCapture, 20
    ModalCallJS("ahkOpenHotkeyCapture('" . HotkeyCaptureTarget . "','" . JsEscape(initial) . "')")
}

; ---- Таймер: проверяем команды от JS (закрыть, свернуть, переместить) ----
PollHotkeyCapture:
    global HotkeyCaptureHwnd, HotkeyCaptureValue, HotkeyCaptureLastValue
    if (!HotkeyCaptureHwnd || !WinExist("ahk_id " . HotkeyCaptureHwnd))
        return
    Gui, HotkeyCapture:Submit, NoHide
    if (HotkeyCaptureValue != "" && HotkeyCaptureValue != HotkeyCaptureLastValue) {
        HotkeyCaptureLastValue := HotkeyCaptureValue
        ModalCallJS("ahkSetHotkeyCapture('" . JsEscape(HotkeyCaptureValue) . "')")
    }
return

PollModalClose:
    if (!WB_Modal || WB_Modal.ReadyState != 4)
        return
    cmd := ""
    try {
        cmd := WB_Modal.Document.parentWindow.ahkCmd
        if (cmd && cmd != "")
            WB_Modal.Document.parentWindow.ahkCmd := ""
    } catch e {
        return
    }
    if (cmd = "")
        return
    
    ; Разбор команды: "action" или "action/arg"
    slashPos := InStr(cmd, "/")
    if (slashPos) {
        action := SubStr(cmd, 1, slashPos - 1)
        arg := SubStr(cmd, slashPos + 1)
    } else {
        action := cmd
        arg := ""
    }
    
    ; Возвращаем хоткеи для любой команды, кроме начала захвата клавиши.
    if (action != "hotkey-capture-start")
        EnableConfiguredHotkeys()

    if (cmd = "close-modal") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
    }
    else if (cmd = "minimize-modal") {
        Gui, Modal:Minimize
    }
    else if (action = "record-hotkey") {
        ShowHotkeyCapture(arg)
    }
    else if (action = "record-hotkey-save") {
        GoSub, HotkeyCaptureSave
    }
    else if (action = "record-hotkey-cancel") {
        GoSub, HotkeyCaptureCancel
    }
    else if (action = "hotkey-capture-start") {
        ; F1/F9 и другие назначенные сочетания не должны перехватываться
        ; макросом, пока пользователь выбирает новую клавишу в поле.
        DisableConfiguredHotkeys()
    }
    else if (action = "hotkey-capture-stop") {
        EnableConfiguredHotkeys()
    }
    else if (InStr(cmd, "drag-start-modal/")) {
        params := SubStr(cmd, 18)
        slashPos := InStr(params, "/")
        if (slashPos) {
            DoNativeDragModal(SubStr(params, 1, slashPos - 1), SubStr(params, slashPos + 1))
        }
    }
    
    ; ---- Новые команды от модалок ----
    else if (action = "confirm-update") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        if (PendingUpdateURL != "") {
            AddLog("Update: скачиваю " . PendingUpdateURL . "...")
            RunUpdateScript(PendingUpdateURL)
        }
    }
    else if (action = "cancel-update") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        AddLog("Update: отложено пользователем")
    }
    else if (action = "settings-save") {
        GoSub, ModalSaveSettings
    }
    else if (action = "bot-start") {
        GoSub, StartDiscordBot
    }
    else if (action = "bot-stop") {
        GoSub, StopDiscordBot
    }
    else if (action = "bot-install-deps") {
        GoSub, InstallBotDependencies
    }
    else if (action = "preview-top-camera") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        if !WinExist(WinTitle) {
            AddLog("Проверка верхнего ракурса: игра не найдена", "warn")
            return
        }
        if (Embedded)
            FocusEmbeddedGame()
        else {
            WinActivate, %WinTitle%
            WinWaitActive, %WinTitle%, , 2
        }
        Sleep, 300
        ApplyTopCamera(true)
    }
    else if (action = "preview-zoom" || action = "preview-zoom-snapshot") {
        ; Закрываем Settings и применяем ту же последовательность, что и
        ; перед фармом: верхний ракурс (если он включён в форме), затем зум.
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        if !WinExist(WinTitle) {
            AddLog("Проверка зума: игра не найдена", "warn")
            return
        }
        WinActivate, %WinTitle%
        WinWaitActive, %WinTitle%, , 2
        Sleep, 300
        StringSplit, preview, arg, /
        previewScrolls := preview1
        previewTopEnabled := (preview2 = "1" || preview2 = "true") ? true : false
        if (previewTopEnabled)
            ApplyTopCamera(true)
        ApplyStartZoom(true, previewScrolls)
        if (action = "preview-zoom-snapshot") {
            Sleep, 250
            CaptureGameArea(TempShot)
            AddLog("Снимок после тестового зума сделан, открываю превью...")
            ShowSnapshotPreview()
        }
    }
    else if (action = "preset-save") {
        PresetName := arg
        GoSub, BtnPresetSave
        PushModalData("presets")
    }
    else if (action = "preset-load") {
        PresetName := arg
        GoSub, BtnPresetLoad
        PushModalData("presets")
    }
    else if (action = "preset-delete-confirm") {
        ; Подтверждение рисуется внутри той же HTML-модалки. Нативный MsgBox
        ; мог оказаться позади окна ActiveX и не поддерживал дизайн приложения.
        PresetName := arg
        ModalCallJS("ahkShowPresetDeleteConfirm('" . JsEscape(arg) . "')")
    }
    else if (action = "preset-delete-cancel") {
        ModalCallJS("ahkHidePresetDeleteConfirm()")
    }
    else if (action = "preset-delete-confirmed") {
        GoSub, BtnPresetDelete
        PushModalData("presets")
    }
    else if (action = "preset-delete") {
        PresetName := arg
        GoSub, BtnPresetDelete
        PushModalData("presets")
    }
    else if (action = "calibrate-upgrade") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateUpgrade
    }
    else if (action = "calibrate-startgame") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateStartGame
    }
    else if (action = "calibrate-repeatstage") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateRepeatStage
    }
    else if (action = "calibrate-autoupgrade") {
        ; Калибровка кнопки AutoUpgrade: снимаем шаблон (как Upgrade/StartGame)
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureAutoUpgrade
    }
    else if (action = "capture-template") {
        ; Снятие шаблона Defeat/Victory (имя спросит после выделения)
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureTemplate
    }
    else if (action = "test-detection") {
        ; Проверка детекта Defeat/Victory на текущем экране (модалку не закрываем)
        GoSub, BtnTestDetection
    }
    else if (action = "capture-startgame") {
        ; Снятие шаблона кнопки Start Game
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureStartGame
    }
    else if (action = "test-startgame") {
        ; Проверка детекта Start Game (модалку не закрываем)
        GoSub, BtnTestStartGame
    }
    else if (action = "capture-autoupgrade") {
        ; Снятие шаблона кнопки AutoUpgrade (альтернативный путь из карточки)
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureAutoUpgrade
    }
    else if (action = "capture-disconnected") {
        ; Снятие шаблона экрана Disconnected (для авто-реконнекта)
        AddLog("Команда: Capture Disconnected получена")
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureDisconnected
    }
    else if (action = "test-disconnected") {
        ; Проверка детекта экрана Disconnected (модалку не закрываем)
        AddLog("Команда: Test Disconnected получена")
        GoSub, BtnTestDisconnected
    }
    else if (action = "record-rejoin") {
        ; Старт/стоп записи Post-Rejoin действий
        GoSub, ToggleRejoinRecord
    }
    else if (action = "record-map-entry") {
        ; Старт/стоп записи входа на выбранную карту
        GoSub, MapChangeRecordHotkeyAction
    }
    else if (action = "test-rejoin") {
        ; Тестовое воспроизведение записанных действий
        GoSub, TestRejoinActions
    }
    else if (action = "clear-rejoin") {
        ; Очистка записанных действий для текущей карты
        GoSub, ClearRejoinActions
    }
    else if (action = "test-autoupgrade") {
        ; Проверка детекта AutoUpgrade (модалку не закрываем)
        GoSub, BtnTestAutoUpgrade
    }
    else if (action = "capture-autoplay-off") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureAutoPlayOff
    }
    else if (action = "test-autoplay-off") {
        GoSub, BtnTestAutoPlayOff
    }
    else if (action = "capture-autoplay-on") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCaptureAutoPlayOn
    }
    else if (action = "test-autoplay-on") {
        GoSub, BtnTestAutoPlayOn
    }
    else if (action = "upgrade-save") {
        GoSub, ModalSaveUpgrade
    }
    ; ---- Распознавание карты: карточка «Map detection» в настройках ----
    else if (action = "detect-map") {
        GoSub, MapDetectNow
    }
    else if (action = "capture-title") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, MapCaptureTitle
    }
    ; ---- Команды mark-* (модалка разметки) ----
    else if (action = "mark-click") {
        GoSub, MarkClick
    }
    else if (action = "mark-region") {
        ; arg = x1/y1/x2/y2 — обведённая область (шаблоны Defeat/Victory/StartGame/AutoUpgrade/заголовок карты)
        StringSplit, rp, arg, /
        SaveTemplateRegion(rp1, rp2, rp3, rp4)
        MarkMode := ""
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        if (ModalHwnd && DllCall("IsWindow", "ptr", ModalHwnd))
            DllCall("ShowWindow", "ptr", ModalHwnd, "int", 5)
        UpdateCalibStatus()
    }
    else if (action = "mark-undo") {
        GoSub, MarkUndo
    }
    else if (action = "mark-unit-num") {
        ; arg = x/y/n — добавление слота с номером юнита (из HTML-попапа)
        GoSub, MarkUnitNum
    }
    else if (action = "mark-done") {
        GoSub, MarkDone
    }
    ; ---- Команды snap-* (превью снимка) ----
    else if (action = "snap-confirm") {
        ; arg = имя карты (URL-encoded)
        SnapName := UriDecode(arg)
        GoSub, SnapConfirm
    }
    else if (action = "snap-cancel") {
        GoSub, SnapCancel
    }
return

HotkeyCaptureSave:
    global HotkeyCaptureTarget, HotkeyCaptureValue, FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    Gui, HotkeyCapture:Submit, NoHide
    captured := HotkeyCaptureValue
    if (captured = "") {
        AddLog("Горячая клавиша не выбрана", "warn")
        return
    }
    if (HotkeyCaptureTarget = "farm" && (captured = RejoinRecordHotkey || captured = MapChangeRecordHotkey || captured = MapDetectHotkey)) {
        AddLog("Эта комбинация уже используется другой горячей клавишей", "warn")
        return
    }
    if (HotkeyCaptureTarget = "rejoin" && (captured = FarmHotkey || captured = MapChangeRecordHotkey || captured = MapDetectHotkey)) {
        AddLog("Эта комбинация уже используется другой горячей клавишей", "warn")
        return
    }
    if (HotkeyCaptureTarget = "map-change" && (captured = FarmHotkey || captured = RejoinRecordHotkey || captured = MapDetectHotkey)) {
        AddLog("Эта комбинация уже используется другой горячей клавишей", "warn")
        return
    }
    if (HotkeyCaptureTarget = "map-detect" && (captured = FarmHotkey || captured = RejoinRecordHotkey || captured = MapChangeRecordHotkey)) {
        AddLog("Эта комбинация уже используется другой горячей клавишей", "warn")
        return
    }
    SetTimer, PollHotkeyCapture, Off
    if (HotkeyCaptureTarget = "rejoin")
        SetHotkeySettings(FarmHotkey, captured, MapChangeRecordHotkey, MapDetectHotkey)
    else if (HotkeyCaptureTarget = "map-change")
        SetHotkeySettings(FarmHotkey, RejoinRecordHotkey, captured, MapDetectHotkey)
    else if (HotkeyCaptureTarget = "map-detect")
        SetHotkeySettings(FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, captured)
    else
        SetHotkeySettings(captured, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey)
    ApplyConfiguredHotkeys()
    SaveSettings()
    farmHotkeyJS := JsEscape(FarmHotkey)
    rejoinHotkeyJS := JsEscape(RejoinRecordHotkey)
    mapChangeHotkeyJS := JsEscape(MapChangeRecordHotkey)
    mapDetectHotkeyJS := JsEscape(MapDetectHotkey)
    WBH_CallJS("ahkHotkeyCaptureFinished('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
    ModalCallJS("ahkHotkeyCaptureFinished('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
    Gui, HotkeyCapture:Destroy
return

HotkeyCaptureCancel:
    SetTimer, PollHotkeyCapture, Off
    Gui, HotkeyCapture:Destroy
    EnableConfiguredHotkeys()
    ModalCallJS("ahkHotkeyCaptureCanceled()")
return

HotkeyCaptureDrag:
    PostMessage, 0xA1, 2,,, ahk_id %HotkeyCaptureHwnd%
return

HotkeyCaptureGuiClose:
    GoSub, HotkeyCaptureCancel
return

; ---- Закрытие модалки через ✕ (крестик окна) ----
ModalGuiClose:
    SetTimer, PollModalClose, Off
    SetTimer, PollHotkeyCapture, Off
    Gui, HotkeyCapture:Destroy
    EnableConfiguredHotkeys()
    Gui, Modal:Destroy
    ModalHwnd := 0
return

; ---- Вызов JS в модальном окне ----
ModalCallJS(js) {
    global WB_Modal
    if (!WB_Modal || WB_Modal.ReadyState != 4)
        return
    try {
        WB_Modal.Document.parentWindow.execScript(js)
    } catch e {
        AddLog("Modal JS error: " . e.Message)
    }
}

; ---- Пуш данных в модальное окно после загрузки ----
PushModalData(name) {
    global
    if (name = "update-confirm") {
        ModalCallJS("ahkSetUpdateInfo('" . PendingUpdateOldVer . "', '" . PendingUpdateNewVer . "')")
    }
    else if (name = "settings") {
        colorHex := SubStr(StartGameColor, 3)  ; убираем "0x"
        rjLink := StrReplace(RejoinShareLink, "\", "\\")
        rjLink := StrReplace(rjLink, "'", "\'")
        farmHotkeyJS := JsEscape(FarmHotkey)
        rejoinHotkeyJS := JsEscape(RejoinRecordHotkey)
        mapChangeHotkeyJS := JsEscape(MapChangeRecordHotkey)
        mapDetectHotkeyJS := JsEscape(MapDetectHotkey)
        botTokenJS := JsEscape(BotToken)
        botGuildJS := JsEscape(BotGuildId)
        botAllowedJS := JsEscape(BotAllowedUserIds)
        ModalCallJS("ahkLoadSettings("
            . ClickDelay . "," . SlotClickDelay . "," . UpgradeClickDelay . ","
            . AutoClickDelay . "," . UnitSleepDelay . "," . StartGameDelay . ","
            . HoverDelay . "," . MouseSpeed . "," . ImgVariation . ",'"
            . colorHex . "'," . StartGameColorVar . ","
            . StartGameCenterX . "," . StartGameCenterY . "," . StartGameRadius . ","
            . (RejoinEnabled ? 1 : 0) . ",'" . rjLink . "',"
            . RejoinMaxAttempts . "," . RejoinWaitTimeout . "," . RejoinPostJoinDelay . ","
            . RejoinPostActionsDelay . "," . (MouseSpeedEnabled ? 1 : 0) . "," . ZoomScrolls . "," . (ZoomEnabled ? 1 : 0) . "," . (TopCameraEnabled ? 1 : 0) . ",'" . AppLanguage . "','" . farmHotkeyJS . "','" . rejoinHotkeyJS . "',"
            . (BotEnabled ? 1 : 0) . "," . (BotAutoStart ? 1 : 0) . ",'" . botTokenJS . "','" . botGuildJS . "','" . botAllowedJS . "','" . mapChangeHotkeyJS . "'," . BotMapPostActionsDelay . ",'" . JsEscape(FarmMode) . "','" . mapDetectHotkeyJS . "')")
        ModalCallJS("ahkSetFarmMode('" . JsEscape(FarmMode) . "')")
        AddLog("Settings пушнуты в модалку (Rejoin: " (RejoinEnabled ? "on" : "off") ", link len=" StrLen(RejoinShareLink) ")")
        ; Также пушим количество записанных Post-Rejoin действий
        count := RejoinActions.Length()
        ModalCallJS("ahkRejoinActionCount(" count ")")
        ModalCallJS("ahkRejoinRecordState(" (RejoinRecordActive ? "true" : "false") ")")
        PushBotMapRecordState()
        ModalCallJS("ahkUpdateBotStatus('" . (BotRunning ? "Running" : "Stopped") . "','" . (BotRunning ? "running" : "") . "')")
        ; Карточка «Распознавание карты»: активный режим и последний результат
        ModalCallJS("ahkSetGameMode('" . GameMode . "')")
        ModalCallJS("ahkMapDetectResult('" . JsEscape(LastDetectedMap) . "'," . LastDetectScore . ")")
    }
    else if (name = "presets") {
        ; Собираем список пресетов из presets.ini
        presetsList := ""
        if (FileExist(PresetsIni)) {
            ; IniWrite/IniDelete в AHK сохраняют имена секций в системной
            ; кодировке. Читаем исходные байты и декодируем их как CP1251,
            ; иначе кириллица превращается в "��".
            FileRead, raw, *c %PresetsIni%
            content := StrGet(&raw, "CP1251")
            Loop, Parse, content, `n, `r
            {
                line := Trim(A_LoopField, " `t`r`n")
                if (line = "")
                    continue
                sectionMatch := ""
                if (RegExMatch(line, "^\[([^\]]+)\]$", sectionMatch)) {
                    presetSection := Trim(sectionMatch1)
                    if (presetSection = "" || presetSection = "Presets")
                        continue
                    if (presetsList != "")
                        presetsList .= "|"
                    presetsList .= presetSection
                }
            }
        }
        ; Имя может содержать апостроф или обратный слеш — экранируем его
        ; перед передачей в JS, иначе список перестанет обновляться после сохранения.
        ModalCallJS("ahkLoadPresets('" . JsEscape(presetsList) . "')")
    }
    else if (name = "calibrate") {
        ModalCallJS("ahkUpdateCalibCoords("
            . UpgradeX . "," . UpgradeY . ","
            . StartGameX . "," . StartGameY . ","
            . RepeatStageX . "," . RepeatStageY . ","
            . AutoX . "," . AutoY . ")")
    }
    else if (name = "upgrade") {
        prioStr := ""
        Loop, 6 {
            if (A_Index > 1)
                prioStr .= ","
            prioStr .= AutoUpgradePriority[A_Index]
        }
        ModalCallJS("ahkLoadUpgradeCfg('" . prioStr . "'," . AutoUpgradeUnitOffsetY . ")")
    }
    ; mark и snap: данные отправляются в OpenMarkGui / ShowSnapshotPreview,
    ; здесь дополнительно пушить нечего.
}

; ---- Сохранение настроек из модального окна Settings ----
ModalSaveSettings:
    ; Новые поля добавляются в конец, чтобы сохранить совместимость с прежним порядком.
    ; .../rejoinPostActionsDelay/mouseSpeedEnabled/zoomScrolls/zoomEnabled/topCameraEnabled
    StringSplit, vals, arg, /
    AddLog("Команда: Save Settings получена (полей: " vals0 ")")
    if (vals0 < 14)
        return
    ClickDelay        := vals1
    SlotClickDelay    := vals2
    UpgradeClickDelay := vals3
    AutoClickDelay    := vals4
    UnitSleepDelay    := vals5
    StartGameDelay    := vals6
    HoverDelay        := vals7
    MouseSpeed        := vals8
    ImgVariation      := vals9
    StartGameColor    := "0x" . vals10
    StartGameColorVar := vals11
    StartGameCenterX  := vals12
    StartGameCenterY  := vals13
    StartGameRadius   := vals14
    if (vals0 >= 19) {
        RejoinEnabled       := (vals15 = "1") ? true : false
        RejoinShareLink     := UriDecode(vals16)
        RejoinMaxAttempts   := vals17
        RejoinWaitTimeout   := vals18
        RejoinPostJoinDelay := vals19
    }
    if (vals0 >= 20) {
        RejoinPostActionsDelay := vals20
    }
    if (vals0 >= 21) {
        MouseSpeedEnabled := (vals21 = "1" || vals21 = "true") ? true : false
    }
    if (vals0 >= 22) {
        ZoomScrolls := vals22
        if (ZoomScrolls < -50 || ZoomScrolls > 50)
            ZoomScrolls := 0
    }
    if (vals0 >= 23) {
        ZoomEnabled := (vals23 = "1" || vals23 = "true") ? true : false
    }
    if (vals0 >= 24) {
        TopCameraEnabled := (vals24 = "1" || vals24 = "true") ? true : false
    }
    if (vals0 >= 25) {
        SetAppLanguage(vals25)
        WBH_CallJS("ahkSetLanguage('" . AppLanguage . "')")
    }
    if (vals0 >= 28) {
        SetHotkeySettings(vals26, vals27, vals28, MapDetectHotkey)
        ApplyConfiguredHotkeys()
        farmHotkeyJS := JsEscape(FarmHotkey)
        rejoinHotkeyJS := JsEscape(RejoinRecordHotkey)
        mapChangeHotkeyJS := JsEscape(MapChangeRecordHotkey)
        mapDetectHotkeyJS := JsEscape(MapDetectHotkey)
        WBH_CallJS("ahkSetHotkeys('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
        ModalCallJS("ahkSetHotkeys('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
    }
    if (vals0 >= 36) {
        SetHotkeySettings(FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, vals36)
        ApplyConfiguredHotkeys()
        SaveHotkeySettings()
        farmHotkeyJS := JsEscape(FarmHotkey)
        rejoinHotkeyJS := JsEscape(RejoinRecordHotkey)
        mapChangeHotkeyJS := JsEscape(MapChangeRecordHotkey)
        mapDetectHotkeyJS := JsEscape(MapDetectHotkey)
        WBH_CallJS("ahkSetHotkeys('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
        ModalCallJS("ahkSetHotkeys('" . farmHotkeyJS . "','" . rejoinHotkeyJS . "','" . mapChangeHotkeyJS . "','" . mapDetectHotkeyJS . "')")
    }
    if (vals0 >= 33) {
        BotEnabled := (vals29 = "1" || vals29 = "true") ? true : false
        BotAutoStart := (vals30 = "1" || vals30 = "true") ? true : false
        BotToken := UriDecode(vals31)
        BotGuildId := UriDecode(vals32)
        BotAllowedUserIds := UriDecode(vals33)
        if (BotToken = "__EMPTY__")
            BotToken := ""
        if (BotGuildId = "__EMPTY__")
            BotGuildId := ""
        if (BotAllowedUserIds = "__EMPTY__")
            BotAllowedUserIds := ""
    }
    if (vals0 >= 34) {
        BotMapPostActionsDelay := vals34
        if (BotMapPostActionsDelay < 0)
            BotMapPostActionsDelay := 0
    }
    if (vals0 >= 35)
        FarmMode := (vals35 = "autoplay") ? "autoplay" : "units"
    WBH_CallJS("ahkSetFarmMode('" . JsEscape(FarmMode) . "')")
    SaveSettings()
    AddLog("Settings saved from modal")
return

; ---- Сохранение настроек автопрокачки из модального окна ----
ModalSaveUpgrade:
    ; arg = p1,p2,p3,p4,p5,p6/offset
    secondSlash := InStr(arg, "/", , 0)
    if (!secondSlash)
        return
    prioPart := SubStr(arg, 1, secondSlash - 1)
    offsetPart := SubStr(arg, secondSlash + 1)
    StringSplit, prio, prioPart, `,
    Loop, 6 {
        val := prio%A_Index%
        if (val = "" || val < 0)
            val := 0
        if (val > 9)
            val := 9
        AutoUpgradePriority[A_Index] := val
    }
    AutoUpgradeUnitOffsetY := offsetPart
    AddLog("Auto Upgrade settings saved from modal")
return

EndManualDrag(notifyUI := false) {
    global WinDragActive, WinDragLastMouseX, WinDragLastMouseY, WinDragLastTargetX, WinDragLastTargetY, WinDragMonitor, WB
    wasActive := WinDragActive
    WinDragActive := false
    WinDragLastMouseX := "", WinDragLastMouseY := ""
    WinDragLastTargetX := "", WinDragLastTargetY := ""
    WinDragMonitor := 0
    SetTimer, ManualDragLoop, Off
    SetTimer, SyncDockPosition, Off
    SetTimer, PollJSCmd, 20
    if (notifyUI && wasActive && WB && WB.ReadyState = 4) {
        try WB.Document.parentWindow.ahkEndMainDrag()
    }
}

; ---- Нативный драг главного окна: ручной перенос через таймер ----
; SendMessage WM_NCLBUTTONDOWN/HTCAPTION не работает при -Caption.
; Вместо этого AHK сам двигает окно(а) по смещению мыши через таймер.
;
; ВАЖНО: используем DllCall(SetWindowPos/DeferWindowPos), а НЕ WinMove.
; WinMove подчиняется SetWinDelay (по умолчанию 100 мс) — два WinMove
; давали ~200 мс на каждую итерацию драга (≈5 fps), отсюда рывки.
; DllCall работает мгновенно, а DeferWindowPos двигает оба окна одной
; атомарной операцией — DWM перерисовывает их вместе, без разрыва.
;
; Перемещение выполняется одним пакетом DWM. Не вызываем RedrawWindow для
; рабочего стола: это заставляет фон соседнего приложения проступать между
; двумя окнами и создаёт белые полосы.
ManualDragLoop:
    ; ActiveX may lose mouseup when the cursor leaves the panel. Check the
    ; physical button before moving so the last timer tick cannot jump the window.
    if (!WinDragActive)
        return
    if (!GetKeyState("LButton", "P")) {
        EndManualDrag(true)
        return
    }
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    if (mx = WinDragLastMouseX && my = WinDragLastMouseY)
        return
    ; Вычисляем новую позицию сайдбара относительно стартовой точки зажатия
    newX := WinDragStartWX + mx - WinDragStartMX
    newY := WinDragStartWY + my - WinDragStartMY
    ; Keep the panel reachable. In dock mode, clamp the Roblox/panel pair as a
    ; unit; otherwise keep at least the title strip inside the work area.
    if (Embedded && GameHwnd && DllCall("IsWindow", "ptr", GameHwnd)) {
        if (!GetWorkAreaAtPoint(mx, my, WinDragMonitor, WinDragWorkLeft, WinDragWorkTop, WinDragWorkRight, WinDragWorkBottom)) {
            SysGet, WinDragWork, MonitorWorkArea
        }
        minX := WinDragWorkLeft + GameAreaW
        maxX := WinDragWorkRight - SidebarW
        if (newX < minX)
            newX := minX
        if (newX > maxX)
            newX := maxX
        if (newY < WinDragWorkTop)
            newY := WinDragWorkTop
        if (newY + GameAreaH > WinDragWorkBottom)
            newY := WinDragWorkBottom - GameAreaH
    } else {
        if (!GetWorkAreaAtPoint(mx, my, WinDragMonitor, WinDragWorkLeft, WinDragWorkTop, WinDragWorkRight, WinDragWorkBottom))
            SysGet, WinDragWork, MonitorWorkArea
        if (newX + 48 < WinDragWorkLeft)
            newX := WinDragWorkLeft - SidebarW + 48
        if (newX + SidebarW - 48 > WinDragWorkRight)
            newX := WinDragWorkRight - 48
        if (newY < WinDragWorkTop)
            newY := WinDragWorkTop
        if (newY > WinDragWorkBottom - 32)
            newY := WinDragWorkBottom - 32
    }
    WinDragLastMouseX := mx, WinDragLastMouseY := my
    if (newX = WinDragLastTargetX && newY = WinDragLastTargetY)
        return
    WinDragLastTargetX := newX, WinDragLastTargetY := newY
    ; Только перемещение: без resize / z-order / activate
    moveFlags := 0x0015  ; SWP_NOSIZE(0x1) | SWP_NOZORDER(0x4) | SWP_NOACTIVATE(0x10)
    if (Embedded && GameHwnd && DllCall("IsWindow", "ptr", GameHwnd)) {
        ; Roblox остаётся отдельным окном для нормального DirectX/raw input,
        ; но во время drag оба окна перемещаются одним defer-пакетом.
        gameX := newX - GameAreaW
        hDefer := DllCall("BeginDeferWindowPos", "int", 2, "ptr")
        if (hDefer) {
            hDefer := DllCall("DeferWindowPos", "ptr", hDefer, "ptr", GameHwnd, "ptr", 0
                , "int", gameX, "int", newY, "int", 0, "int", 0
                , "uint", moveFlags, "ptr")
            hDefer := DllCall("DeferWindowPos", "ptr", hDefer, "ptr", MainGuiHwnd, "ptr", 0
                , "int", newX, "int", newY, "int", 0, "int", 0
                , "uint", moveFlags, "ptr")
            if (hDefer)
                DllCall("EndDeferWindowPos", "ptr", hDefer)
        } else {
            DllCall("SetWindowPos", "ptr", GameHwnd, "ptr", 0
                , "int", gameX, "int", newY, "int", 0, "int", 0
                , "uint", moveFlags, "ptr")
            DllCall("SetWindowPos", "ptr", MainGuiHwnd, "ptr", 0
                , "int", newX, "int", newY, "int", 0, "int", 0
                , "uint", moveFlags, "ptr")
        }
    } else {
        ; Roblox не закреплён — двигаем только сайдбар.
        DllCall("SetWindowPos", "ptr", MainGuiHwnd, "ptr", 0
            , "int", newX, "int", newY, "int", 0, "int", 0, "uint", moveFlags, "ptr")
    }
return

DoNativeDragModal(startMX, startMY) {
    global ModalHwnd
    if (!ModalHwnd)
        return
    wid := ModalHwnd
    DllCall("ReleaseCapture")
    SendMessage, 0xA1, 2, 0,, ahk_id %wid%
    DllCall("ReleaseCapture")
}

; ---- Удаление секции пресета с поддержкой кириллицы ----
; IniDelete не всегда находит секции, которые были записаны AHK
; в системной кодировке внутри UTF-8 файла. Переписываем только список
; строк, удаляя нужную секцию, и сохраняем байты через CP1251.
DeletePresetSection(sectionName) {
    global PresetsIni
    if (!FileExist(PresetsIni))
        return false

    FileRead, raw, *c %PresetsIni%
    content := StrGet(&raw, "CP1251")
    result := ""
    skip := false
    found := false
    Loop, Parse, content, `n, `r
    {
        line := A_LoopField
        trimmed := Trim(line, " `t`r`n")
        sectionMatch := ""
        if (RegExMatch(trimmed, "^\[([^\]]+)\]$", sectionMatch)) {
            skip := (Trim(sectionMatch1) = sectionName)
            if (skip)
                found := true
        }
        if (!skip)
            result .= line . "`r`n"
    }
    if (!found)
        return false

    tempFile := PresetsIni . ".tmp"
    outFile := FileOpen(tempFile, "w", "CP1251")
    if (!IsObject(outFile))
        return false
    outFile.Write(result)
    outFile.Close()
    FileMove, %tempFile%, %PresetsIni%, 1
    return !ErrorLevel
}

; ---- Экранирование значения для JavaScript-строки ----
JsEscape(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, "'", "\'")
    return value
}

; ---- Простой URL-декодер (%XX → символ) ----
UriDecode(str) {
    result := ""
    i := 1
    while (i <= StrLen(str)) {
        c := SubStr(str, i, 1)
        if (c = "+") {
            result .= " "
            i++
        } else if (c = "%" && i+2 <= StrLen(str)) {
            hex := SubStr(str, i+1, 2)
            if RegExMatch(hex, "^[0-9A-Fa-f]{2}$") {
                result .= Chr("0x" . hex)
                i += 3
            } else {
                result .= c
                i++
            }
        } else {
            result .= c
            i++
        }
    }
    return result
}

; ---- Запуск PowerShell-скрипта обновления и выход ----
; Пишет самодостаточный .ps1 во временную папку и запускает его.
; Сам скрипт качает zip, распаковывает, копирует файлы и перезапускает AHK.
; Такой подход исключает любые COM/RunWait-проблемы внутри AHK.
RunUpdateScript(zipURL) {
    try {
        RunUpdateScript_Inner(zipURL)
    } catch e {
        AddLog("Update: сбой запуска обновления (не сеть) — " . e.Message . " | " . e.Extra . " (line " . e.Line . ")", "error")
        WBH_CallJS("ahkUpdateVersion('ERR', false)")
    }
}

RunUpdateScript_Inner(zipURL) {
    ; Используем уникальные имена: предыдущий updater может ещё удалять себя
    ; или быть заблокирован системой. Общий путь приводил к сбою на FileDelete.
    updateId := A_TickCount
    psPath := A_Temp . "\tdmacro_updater_" . updateId . ".ps1"
    zipPath := A_Temp . "\tdmacro_update_" . updateId . ".zip"
    extractPath := A_Temp . "\tdmacro_update_" . updateId
    progressPath := A_Temp . "\tdmacro_progress_" . updateId . ".txt"

    ; Экранирование: в PowerShell-строках внутри двойных кавычек
    ; одиночная кавычка безопасна, бэкслеши не являются escape-символами.
    safeURL    := StrReplace(zipURL, "'", "''")
    ; main.ahk находится в <project>\macro, а GitHub-архив содержит
    ; <project>\macro и <project>\UI. Копируем содержимое в корень проекта.
    installRoot := A_ScriptDir . "\.."
    safeTarget := StrReplace(installRoot, "'", "''")
    safeMain   := StrReplace(A_ScriptDir . "\main.ahk", "'", "''")
    safeZip    := StrReplace(zipPath, "'", "''")
    safeExtr   := StrReplace(extractPath, "'", "''")
    safeProgress := StrReplace(progressPath, "'", "''")

    ; Команда загрузчика должна попасть в дочерний PowerShell без раскрытия
    ; его переменных родительским процессом. Поэтому экранируем её как
    ; содержимое одинарной строки PowerShell перед записью updater-скрипта.
    workerCommand := "$ErrorActionPreference = 'Stop'; try { "
    workerCommand .= "$request = [System.Net.HttpWebRequest]::Create('" . safeURL . "'); "
    workerCommand .= "$request.UserAgent = 'TD-Macro-Updater'; $request.AllowAutoRedirect = $true; "
    workerCommand .= "$response = $request.GetResponse(); $total = $response.ContentLength; "
    workerCommand .= "$inputStream = $response.GetResponseStream(); $output = [System.IO.File]::Create('" . safeZip . "'); "
    workerCommand .= "$buffer = New-Object byte[] 65536; $downloaded = [int64]0; $count = 0; "
    workerCommand .= "while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) { "
    workerCommand .= "$output.Write($buffer, 0, $count); $downloaded += $count; "
    workerCommand .= "if ($total -gt 0) { [System.IO.File]::WriteAllText('" . safeProgress . "', [string][Math]::Min(100, [Math]::Floor($downloaded * 100 / $total))) } "
    workerCommand .= "else { [System.IO.File]::WriteAllText('" . safeProgress . "', '-1') } }; "
    workerCommand .= "$output.Close(); $inputStream.Close(); $response.Close(); "
    workerCommand .= "[System.IO.File]::WriteAllText('" . safeProgress . "', '100') } catch { exit 1 }"
    safeWorkerCommand := StrReplace(workerCommand, "'", "''")

    ; Пишем PowerShell-скрипт
    script := ""
    script .= "$ErrorActionPreference = 'Stop'`r`n"
    script .= "[System.Net.ServicePointManager]::SecurityProtocol = 3072  # TLS 1.2`r`n"
    script .= "Add-Type -AssemblyName System.Windows.Forms`r`n"
    script .= "Add-Type -AssemblyName System.Drawing`r`n"
    script .= "`r`n"
    script .= "$form = New-Object System.Windows.Forms.Form`r`n"
    script .= "$form.Text = 'Mmacro — Обновление'`r`n"
    script .= "$form.ClientSize = New-Object System.Drawing.Size(420, 250)`r`n"
    script .= "$form.StartPosition = 'CenterScreen'`r`n"
    script .= "$form.FormBorderStyle = 'None'`r`n"
    script .= "$form.ShowInTaskbar = $true`r`n"
    script .= "$form.TopMost = $true`r`n"
    ; Палитра и плотность такие же, как у основной панели Mmacro:
    ; #121212 / #0f0f0f / #252525 и синий акцент #3b82f6.
    script .= "$form.BackColor = [System.Drawing.Color]::FromArgb(37, 37, 37)`r`n"
    script .= "$card = New-Object System.Windows.Forms.Panel`r`n"
    script .= "$card.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)`r`n"
    script .= "$card.Location = New-Object System.Drawing.Point(1, 1)`r`n"
    script .= "$card.Size = New-Object System.Drawing.Size(418, 248)`r`n"
    script .= "$form.Controls.Add($card)`r`n"
    script .= "$accent = New-Object System.Windows.Forms.Panel`r`n"
    script .= "$accent.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$accent.Location = New-Object System.Drawing.Point(0, 0)`r`n"
    script .= "$accent.Size = New-Object System.Drawing.Size(418, 2)`r`n"
    script .= "$card.Controls.Add($accent)`r`n"
    script .= "$icon = New-Object System.Windows.Forms.Label`r`n"
    script .= "$icon.AutoSize = $false`r`n"
    script .= "$icon.Size = New-Object System.Drawing.Size(30, 30)`r`n"
    script .= "$icon.Text = [char]0x2193`r`n"
    script .= "$icon.TextAlign = 'MiddleCenter'`r`n"
    script .= "$icon.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 15, [System.Drawing.FontStyle]::Bold)`r`n"
    script .= "$icon.ForeColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$icon.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 26)`r`n"
    script .= "$icon.Location = New-Object System.Drawing.Point(16, 15)`r`n"
    script .= "$card.Controls.Add($icon)`r`n"
    script .= "$brand = New-Object System.Windows.Forms.Label`r`n"
    script .= "$brand.AutoSize = $true`r`n"
    script .= "$brand.Text = 'MMACRO'`r`n"
    script .= "$brand.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)`r`n"
    script .= "$brand.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 228)`r`n"
    script .= "$brand.Location = New-Object System.Drawing.Point(54, 16)`r`n"
    script .= "$card.Controls.Add($brand)`r`n"
    script .= "$title = New-Object System.Windows.Forms.Label`r`n"
    script .= "$title.AutoSize = $true`r`n"
    script .= "$title.Text = 'Установка обновления'`r`n"
    script .= "$title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)`r`n"
    script .= "$title.ForeColor = [System.Drawing.Color]::FromArgb(228, 228, 228)`r`n"
    script .= "$title.Location = New-Object System.Drawing.Point(16, 57)`r`n"
    script .= "$card.Controls.Add($title)`r`n"
    script .= "$state = New-Object System.Windows.Forms.Label`r`n"
    script .= "$state.AutoSize = $false`r`n"
    script .= "$state.Size = New-Object System.Drawing.Size(86, 22)`r`n"
    script .= "$state.Text = 'ЗАГРУЗКА'`r`n"
    script .= "$state.TextAlign = 'MiddleCenter'`r`n"
    script .= "$state.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)`r`n"
    script .= "$state.ForeColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$state.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 26)`r`n"
    script .= "$state.Location = New-Object System.Drawing.Point(316, 19)`r`n"
    script .= "$card.Controls.Add($state)`r`n"
    script .= "$label = New-Object System.Windows.Forms.Label`r`n"
    script .= "$label.AutoSize = $true`r`n"
    script .= "$label.Text = 'Подготавливаем загрузку…'`r`n"
    script .= "$label.Font = New-Object System.Drawing.Font('Segoe UI', 9)`r`n"
    script .= "$label.ForeColor = [System.Drawing.Color]::FromArgb(181, 195, 216)`r`n"
    script .= "$label.Location = New-Object System.Drawing.Point(16, 101)`r`n"
    script .= "$card.Controls.Add($label)`r`n"
    script .= "$percent = New-Object System.Windows.Forms.Label`r`n"
    script .= "$percent.AutoSize = $false`r`n"
    script .= "$percent.Size = New-Object System.Drawing.Size(70, 22)`r`n"
    script .= "$percent.Text = '0%'`r`n"
    script .= "$percent.TextAlign = 'MiddleRight'`r`n"
    script .= "$percent.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)`r`n"
    script .= "$percent.ForeColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$percent.Location = New-Object System.Drawing.Point(318, 97)`r`n"
    script .= "$card.Controls.Add($percent)`r`n"
    script .= "$track = New-Object System.Windows.Forms.Panel`r`n"
    script .= "$track.BackColor = [System.Drawing.Color]::FromArgb(37, 37, 37)`r`n"
    script .= "$track.Location = New-Object System.Drawing.Point(16, 132)`r`n"
    script .= "$track.Size = New-Object System.Drawing.Size(386, 8)`r`n"
    script .= "$card.Controls.Add($track)`r`n"
    script .= "$fill = New-Object System.Windows.Forms.Panel`r`n"
    script .= "$fill.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$fill.Location = New-Object System.Drawing.Point(16, 132)`r`n"
    script .= "$fill.Size = New-Object System.Drawing.Size(2, 8)`r`n"
    script .= "$card.Controls.Add($fill)`r`n"
    script .= "$spinner = New-Object System.Windows.Forms.Label`r`n"
    script .= "$spinner.AutoSize = $true`r`n"
    script .= "$spinner.Text = [char]0x25D0`r`n"
    script .= "$spinner.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 10)`r`n"
    script .= "$spinner.ForeColor = [System.Drawing.Color]::FromArgb(59, 130, 246)`r`n"
    script .= "$spinner.Location = New-Object System.Drawing.Point(16, 155)`r`n"
    script .= "$card.Controls.Add($spinner)`r`n"
    script .= "$hint = New-Object System.Windows.Forms.Label`r`n"
    script .= "$hint.AutoSize = $true`r`n"
    script .= "$hint.Text = 'Не закрывайте окно — Mmacro перезапустится автоматически.'`r`n"
    script .= "$hint.Font = New-Object System.Drawing.Font('Segoe UI', 8)`r`n"
    script .= "$hint.ForeColor = [System.Drawing.Color]::FromArgb(117, 137, 165)`r`n"
    script .= "$hint.Location = New-Object System.Drawing.Point(38, 158)`r`n"
    script .= "$card.Controls.Add($hint)`r`n"
    script .= "$stage = New-Object System.Windows.Forms.Label`r`n"
    script .= "$stage.AutoSize = $true`r`n"
    script .= "$stage.Text = '01  Скачать        02  Установить        03  Перезапустить'`r`n"
    script .= "$stage.Font = New-Object System.Drawing.Font('Segoe UI', 8)`r`n"
    script .= "$stage.ForeColor = [System.Drawing.Color]::FromArgb(137, 162, 198)`r`n"
    script .= "$stage.Location = New-Object System.Drawing.Point(16, 206)`r`n"
    script .= "$card.Controls.Add($stage)`r`n"
    script .= "$form.Show()`r`n"
    script .= "[System.Windows.Forms.Application]::DoEvents()`r`n"
    script .= "`r`n"
    script .= "try {`r`n"
    script .= "    Write-Host 'Downloading update...'`r`n"
    script .= "    [System.IO.File]::WriteAllText('" . safeProgress . "', '0')`r`n"
    script .= "    $downloadCommand = '" . safeWorkerCommand . "'`r`n"
    script .= "    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($downloadCommand))`r`n"
    script .= "    $worker = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $encodedCommand) -WindowStyle Hidden -PassThru`r`n"
    script .= "    $phase = 0`r`n"
    script .= "    $spinIndex = 0`r`n"
    script .= "    $spinFrames = @([char]0x25D0, [char]0x25D3, [char]0x25D1, [char]0x25D2)`r`n"
    script .= "    while (-not $worker.HasExited) {`r`n"
    script .= "        $worker.Refresh()`r`n"
    script .= "        $progressValue = -1`r`n"
    script .= "        if (Test-Path -LiteralPath '" . safeProgress . "') {`r`n"
    script .= "            $progressText = Get-Content -LiteralPath '" . safeProgress . "' -Raw -ErrorAction SilentlyContinue`r`n"
    script .= "            $parsedProgress = 0`r`n"
    script .= "            if ($progressText -and [int]::TryParse($progressText.Trim(), [ref]$parsedProgress)) { $progressValue = $parsedProgress }`r`n"
    script .= "        }`r`n"
    script .= "        $spinnerChar = $spinFrames[$spinIndex]`r`n"
    script .= "        $spinIndex = ($spinIndex + 1) % 4`r`n"
    script .= "        if ($progressValue -ge 0) {`r`n"
    script .= "            $label.Text = 'Скачиваем файлы обновления…'`r`n"
    script .= "            $state.Text = 'ЗАГРУЗКА'`r`n"
    script .= "            $percent.Text = ('{0}%' -f $progressValue)`r`n"
    script .= "            $spinner.Text = $spinnerChar`r`n"
    script .= "            $fill.Left = 16`r`n"
    script .= "            $fill.Width = [int][Math]::Max(2, [Math]::Min(386, [Math]::Round(386 * $progressValue / 100)))`r`n"
    script .= "        } else {`r`n"
    script .= "            $label.Text = 'Подключаемся к GitHub…'`r`n"
    script .= "            $state.Text = 'СОЕДИНЕНИЕ'`r`n"
    script .= "            $percent.Text = '...'`r`n"
    script .= "            $spinner.Text = $spinnerChar`r`n"
    script .= "            $fill.Left = 16 + $phase`r`n"
    script .= "            $fill.Width = 90`r`n"
    script .= "            $phase += 10`r`n"
    script .= "            if ($phase -gt 290) { $phase = 0 }`r`n"
    script .= "        }`r`n"
    script .= "        [System.Windows.Forms.Application]::DoEvents()`r`n"
    script .= "        Start-Sleep -Milliseconds 40`r`n"
    script .= "    }`r`n"
    script .= "    $worker.Refresh()`r`n"
    script .= "    if ($worker.ExitCode -ne 0) { throw 'Не удалось скачать обновление. Проверьте подключение к интернету.' }`r`n"
    script .= "    if (-not (Test-Path '" . safeZip . "')) { throw 'Файл обновления не был создан' }`r`n"
    script .= "    $label.Text = 'Распаковываем и устанавливаем обновление…'`r`n"
    script .= "    $state.Text = 'УСТАНОВКА'`r`n"
    script .= "    $percent.Text = '100%'`r`n"
    script .= "    $stage.Text = '01  Скачать        02  Устанавливаем        03  Перезапустить'`r`n"
    script .= "    $fill.Left = 16`r`n"
    script .= "    $fill.Width = 386`r`n"
    script .= "    [System.Windows.Forms.Application]::DoEvents()`r`n"
    script .= "    Expand-Archive -Path '" . safeZip . "' -DestinationPath '" . safeExtr . "' -Force`r`n"
    script .= "    $srcDir = Get-ChildItem -Path '" . safeExtr . "' -Directory | Select-Object -First 1`r`n"
    script .= "    if (-not $srcDir) { $srcDir = '" . safeExtr . "' } else { $srcDir = $srcDir.FullName }`r`n"
    script .= "    $target = '" . safeTarget . "'`r`n"
    ; Пользовательские данные не копируем из архива релиза. Код обновляется,
    ; а локальные настройки, токены, карты, пресеты и действия бота остаются
    ; такими, какими их создал пользователь.
    script .= "    $protectedUpdatePaths = @(`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\maps')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\config.ini')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\ahk\\settings.ini')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\ahk\\presets.ini')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\ahk\\token.ini')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'macro\\ahk\\secrets.ini')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'bot\\actions')),`r`n"
    script .= "        [System.IO.Path]::GetFullPath((Join-Path $srcDir 'bot\\runtime'))`r`n"
    script .= "    )`r`n"
    script .= "    function Copy-UpdateItem($item, $destination) {`r`n"
    script .= "        $sourcePath = [System.IO.Path]::GetFullPath($item.FullName)`r`n"
    script .= "        if ($protectedUpdatePaths -contains $sourcePath) { return }`r`n"
    script .= "        $destinationPath = Join-Path $destination $item.Name`r`n"
    script .= "        if ($item.PSIsContainer) {`r`n"
    script .= "            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null`r`n"
    script .= "            Get-ChildItem -LiteralPath $item.FullName -Force | ForEach-Object { Copy-UpdateItem $_ $destinationPath }`r`n"
    script .= "        } else {`r`n"
    script .= "            Copy-Item -LiteralPath $item.FullName -Destination $destinationPath -Force`r`n"
    script .= "        }`r`n"
    script .= "    }`r`n"
    script .= "    Get-ChildItem -LiteralPath $srcDir -Force | ForEach-Object { Copy-UpdateItem $_ $target }`r`n"
    script .= "    $label.Text = 'Готово. Перезапускаем Mmacro…'`r`n"
    script .= "    $state.Text = 'ГОТОВО'`r`n"
    script .= "    $stage.Text = '01  Скачать        02  Установить        03  Перезапускаем'`r`n"
    script .= "    [System.Windows.Forms.Application]::DoEvents()`r`n"
    script .= "    Start-Sleep -Milliseconds 500`r`n"
    script .= "} catch {`r`n"
    script .= "    Write-Host ('Update error: ' + $_.Exception.Message)`r`n"
    script .= "    $title.Text = 'Не удалось обновить приложение'`r`n"
    script .= "    $label.Text = 'Обновление не было установлено'`r`n"
    script .= "    $state.Text = 'ОШИБКА'`r`n"
    script .= "    $percent.Text = '!'`r`n"
    script .= "    $stage.Text = 'Проверьте подключение и повторите попытку позже'`r`n"
    script .= "    $hint.Text = $_.Exception.Message`r`n"
    script .= "    $label.ForeColor = [System.Drawing.Color]::FromArgb(255, 160, 160)`r`n"
    script .= "    $state.ForeColor = [System.Drawing.Color]::FromArgb(255, 190, 190)`r`n"
    script .= "    $state.BackColor = [System.Drawing.Color]::FromArgb(101, 38, 48)`r`n"
    script .= "    $accent.BackColor = [System.Drawing.Color]::FromArgb(234, 89, 103)`r`n"
    script .= "    $fill.BackColor = [System.Drawing.Color]::FromArgb(234, 89, 103)`r`n"
    script .= "    $fill.Left = 16`r`n"
    script .= "    $fill.Width = 386`r`n"
    script .= "    [System.Windows.Forms.Application]::DoEvents()`r`n"
    script .= "    Start-Sleep -Seconds 8`r`n"
    script .= "    $form.Close()`r`n"
    script .= "    Remove-Item -LiteralPath '" . safeProgress . "' -Force -ErrorAction SilentlyContinue`r`n"
    script .= "    exit 1`r`n"
    script .= "}`r`n"
    script .= "`r`n"
    script .= "$form.Close()`r`n"
    script .= "Remove-Item -LiteralPath '" . safeProgress . "' -Force -ErrorAction SilentlyContinue`r`n"
    script .= "Start-Process -FilePath '" . safeMain . "'`r`n"
    script .= "`r`n"
    script .= "# Самоудаление скрипта`r`n"
    script .= "Start-Sleep -Seconds 2`r`n"
    script .= "Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue`r`n"

    f := FileOpen(psPath, "w", "UTF-8")
    if (!f) {
        throw Exception("Не удалось создать " . psPath . " (A_LastError=" . A_LastError . ")")
    }
    f.Write(script)
    f.Close()

    if (!FileExist(psPath)) {
        throw Exception("Файл обновления не создан: " . psPath)
    }

    AddLog("Update: запускаю обновление и выхожу...")
    Run, % "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ . psPath . """"
    Sleep, 500
    ExitApp
}

GuiClose:
    Gosub, StopDiscordBot
    if (Embedded)
        UnembedGameWindow()
    ExitApp