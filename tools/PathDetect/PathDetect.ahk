;=============================================================
;  PathDetect - управление просмотрщиком дорожки
;
;  F4  - выделить область (снимать только её)
;  F8  - расставить юнитов (по углам квадрата вокруг курсора)
;  F9  - запустить просмотр, нажать 6 и увести курсор в угол
;  F10 - остановить
;  F11 - перезапустить
;  F12 - выход из контроллера
;=============================================================
#Requires AutoHotkey v1.1
#NoEnv
#SingleInstance Force
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%
DllCall("SetProcessDPIAware")

Ps1 := A_ScriptDir . "\PathDetect.ps1"
IniFile := A_ScriptDir . "\PathDetect.ini"
SettingsFile := A_ScriptDir . "\PathDetect.settings.txt"
Pid := 0
RegX := 0
RegY := 0
RegW := 0
RegH := 0

; --- расстановка юнитов ---
PlaceKey := "6"        ; клавиша выбора юнита (жмётся после F9)
PlaceDiv := 3          ; радиус квадрата = шаг сетки / PlaceDiv
PlaceDelay := 100      ; пауза между кликами, мс
PlaceClicks := 4       ; сколько углов квадрата жать (1-4)
PlaceHide := 1         ; прятать окно детектора на время кликов

LoadRegion()
LoadPlaceSettings()

Menu, Tray, NoStandard
Menu, Tray, Add, Выделить область (F4), DoSelect
Menu, Tray, Add, Запустить (F9), DoStart
Menu, Tray, Add, Остановить (F10), DoStop
Menu, Tray, Add, Перезапустить (F11), DoRestart
Menu, Tray, Add
Menu, Tray, Add, Расставить юнитов (F8), DoPlaceMenu
Menu, Tray, Add, Настройки расстановки, DoPlaceSettings
Menu, Tray, Add
Menu, Tray, Add, Выход (F12), DoExit
Menu, Tray, Default, Запустить (F9)
Menu, Tray, Tip, PathDetect

return

F4::SelectRegion()
F8::DoPlace()
F9::StartWithUnit()
F10::StopDetector()
F11::RestartDetector()
F12::ExitApp

DoSelect:
    SelectRegion()
return

DoStart:
    StartWithUnit()
return

DoStop:
    StopDetector()
return

DoRestart:
    RestartDetector()
return

DoPlaceMenu:
    DoPlace()
return

DoPlaceSettings:
    ShowPlaceSettings()
return

DoExit:
    ExitApp

;=============================================================
;  Область
;=============================================================
LoadRegion() {
    global IniFile, RegX, RegY, RegW, RegH

    IniRead, RegX, %IniFile%, Region, X, 0
    IniRead, RegY, %IniFile%, Region, Y, 0
    IniRead, RegW, %IniFile%, Region, W, 0
    IniRead, RegH, %IniFile%, Region, H, 0
    RegX += 0
    RegY += 0
    RegW += 0
    RegH += 0
}

SelectRegion() {
    global IniFile, RegX, RegY, RegW, RegH

    CoordMode, Mouse, Screen

    Gui, Overlay:New, +AlwaysOnTop -Caption +ToolWindow
    Gui, Overlay:Color, 000000
    Gui, Overlay:Show, x0 y0 w%A_ScreenWidth% h%A_ScreenHeight%
    WinSet, Transparent, 60
    ToolTip, Обведи игровое поле (без нижней панели).`nEsc - отмена.

    while !GetKeyState("LButton", "P") {
        if GetKeyState("Esc", "P") {
            Gui, Overlay:Destroy
            ToolTip
            return
        }
        Sleep, 10
    }

    MouseGetPos, sx, sy
    Gui, Overlay:Destroy
    ToolTip

    Gui, Rect:New, +AlwaysOnTop -Caption +ToolWindow
    Gui, Rect:Color, FFC800
    Gui, Rect:Show, x%sx% y%sy% w1 h1
    WinSet, Transparent, 100

    x := sx
    y := sy
    w := 1
    h := 1
    while GetKeyState("LButton", "P") {
        MouseGetPos, mx, my
        x := (sx < mx) ? sx : mx
        y := (sy < my) ? sy : my
        w := ((sx > mx) ? sx - mx : mx - sx) + 1
        h := ((sy > my) ? sy - my : my - sy) + 1
        Gui, Rect:Show, x%x% y%y% w%w% h%h%
        Sleep, 10
    }
    Gui, Rect:Destroy

    if (w < 50 || h < 50) {
        MsgBox, 48, PathDetect, Слишком маленькая область. Выдели ещё раз (F4).
        return
    }

    RegX := x
    RegY := y
    RegW := w
    RegH := h

    IniWrite, %RegX%, %IniFile%, Region, X
    IniWrite, %RegY%, %IniFile%, Region, Y
    IniWrite, %RegW%, %IniFile%, Region, W
    IniWrite, %RegH%, %IniFile%, Region, H

    TrayTip, PathDetect, Область: %w% x %h%. F9 - запуск, 4
}

;=============================================================
;  Запуск / остановка
;=============================================================
IsRunning() {
    global Pid
    if !Pid
        return false
    Process, Exist, %Pid%
    return (ErrorLevel != 0)
}

StartDetector() {
    global Ps1, Pid, RegX, RegY, RegW, RegH

    if IsRunning() {
        TrayTip, PathDetect, Уже запущен, 2
        return
    }

    if !FileExist(Ps1) {
        MsgBox, 16, PathDetect, Не найден файл:`n%Ps1%
        return
    }

    args := ""
    if (RegW >= 50 && RegH >= 50)
        args := " -X " . RegX . " -Y " . RegY . " -Width " . RegW . " -Height " . RegH

    Run, powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%Ps1%"%args%, , Hide, Pid

    Sleep, 1400
    if IsRunning()
        TrayTip, PathDetect, Запущен: F5 - снимок; F8 - расставить; Esc - выход, 4
    else
        MsgBox, 16, PathDetect, Не запустился.`nПроверь файл:`n%Ps1%
}

StopDetector() {
    global Pid

    if IsRunning() {
        Process, Close, %Pid%
        TrayTip, PathDetect, Остановлен, 2
    } else {
        TrayTip, PathDetect, Не запущен, 2
    }
    Pid := 0
}

RestartDetector() {
    StopDetector()
    Sleep, 400
    StartDetector()
}

;=============================================================
;  F9: запуск + выбор юнита + курсор в угол окна Roblox
;=============================================================
StartWithUnit() {
    global PlaceKey

    StartDetector()
    if !IsRunning()
        return

    LoadPlaceSettings()

    hwnd := GetGameHwnd()
    if !hwnd
        return

    WinActivate, ahk_id %hwnd%
    Sleep, 150

    CoordMode, Mouse, Screen
    WinGetPos, gx, gy, gw, gh, ahk_id %hwnd%
    MouseMove, gx + 1, gy + 1, 0
    Sleep, 60

    Send, %PlaceKey%
}

;=============================================================
;  F8: расстановка юнитов по углам квадрата
;
;  Курсор = левый верхний угол квадрата, сторона = радиус * sqrt(2),
;  радиус = шаг сетки / PlaceDiv (по умолчанию 1/3 шага).
;  Клики: левый верх, правый верх, правый низ, левый низ.
;=============================================================
DoPlace() {
    global PlaceDiv, PlaceDelay, PlaceClicks, PlaceHide

    LoadPlaceSettings()

    step := GetGridStep()
    div := PlaceDiv
    if (div < 1)
        div := 1
    radius := step / div
    side := radius * 1.41421356237

    clicks := PlaceClicks
    if (clicks < 1)
        clicks := 1
    if (clicks > 4)
        clicks := 4

    CoordMode, Mouse, Screen
    MouseGetPos, mx, my

    hwnd := GetGameHwnd()
    if hwnd {
        WinActivate, ahk_id %hwnd%
        Sleep, 120
    }

    hidden := 0
    det := 0
    if (PlaceHide) {
        det := GetDetectorHwnd()
        if det {
            WinHide, ahk_id %det%
            hidden := 1
            Sleep, 120
        }
    }

    x1 := mx
    y1 := my
    x2 := mx + side
    y2 := my + side

    i := 1
    while (i <= clicks) {
        if (i = 1) {
            px := x1, py := y1
        } else if (i = 2) {
            px := x2, py := y1
        } else if (i = 3) {
            px := x2, py := y2
        } else {
            px := x1, py := y2
        }
        MouseMove, %px%, %py%, 0
        Sleep, 20
        Click
        Sleep, %PlaceDelay%
        i += 1
    }

    if (hidden)
        WinShow, ahk_id %det%

    TrayTip, PathDetect, Расстановка: %clicks% точ.  шаг %step%  радиус %radius%, 2
}

;=============================================================
;  Настройки расстановки
;=============================================================
LoadPlaceSettings() {
    global IniFile, PlaceKey, PlaceDiv, PlaceDelay, PlaceClicks, PlaceHide

    IniRead, PlaceKey, %IniFile%, Place, Key, 6
    IniRead, PlaceDiv, %IniFile%, Place, Div, 3
    IniRead, PlaceDelay, %IniFile%, Place, Delay, 100
    IniRead, PlaceClicks, %IniFile%, Place, Clicks, 4
    IniRead, PlaceHide, %IniFile%, Place, Hide, 1

    PlaceDiv += 0
    PlaceDelay += 0
    PlaceClicks += 0
    PlaceHide += 0

    if (PlaceKey = "" || PlaceKey = "ERROR")
        PlaceKey := "6"
    if (PlaceDiv < 1)
        PlaceDiv := 1
    if (PlaceDelay < 0)
        PlaceDelay := 0
    if (PlaceClicks < 1)
        PlaceClicks := 1
    if (PlaceClicks > 4)
        PlaceClicks := 4
}

GetGridStep() {
    global SettingsFile

    step := 20
    if FileExist(SettingsFile) {
        Loop, Read, %SettingsFile%
        {
            if (SubStr(A_LoopReadLine, 1, 9) = "gridStep=") {
                v := SubStr(A_LoopReadLine, 10) + 0
                if (v >= 2)
                    step := v
            }
        }
    }
    return step
}

GetGameHwnd() {
    SetTitleMatchMode, 2
    hwnd := WinExist("ahk_exe RobloxPlayerBeta.exe")
    if !hwnd
        hwnd := WinExist("ahk_exe Windows10Universal.exe")
    if !hwnd
        hwnd := WinExist("Roblox")
    return hwnd
}

GetDetectorHwnd() {
    SetTitleMatchMode, 2
    return WinExist("Path detect")
}

ShowPlaceSettings() {
    global PlaceKey, PlaceDiv, PlaceDelay, PlaceClicks, PlaceHide

    LoadPlaceSettings()

    Gui, Place:Destroy
    Gui, Place:New, +AlwaysOnTop, Настройки расстановки
    Gui, Place:Font, s9, Segoe UI

    Gui, Place:Add, Text, x12 y14 w230, Клавиша выбора юнита (после F9):
    Gui, Place:Add, Edit, x250 y12 w90 vKey, %PlaceKey%

    Gui, Place:Add, Text, x12 y46 w230, Радиус = шаг сетки / N:
    Gui, Place:Add, Edit, x250 y44 w90 vDiv number, %PlaceDiv%
    Gui, Place:Add, Text, x350 y46 w120, (шаг / 3 = 1/3 шага)

    Gui, Place:Add, Text, x12 y78 w230, Пауза между кликами, мс:
    Gui, Place:Add, Edit, x250 y76 w90 vDelay number, %PlaceDelay%

    Gui, Place:Add, Text, x12 y110 w230, Сколько углов жать (1-4):
    Gui, Place:Add, Edit, x250 y108 w90 vClicks number, %PlaceClicks%

    Gui, Place:Add, Checkbox, x250 y140 vHide Checked%PlaceHide%, Прятать окно детектора

    Gui, Place:Add, Text, x12 y172 w460 cGray, Клик идёт в левый верхний угол квадрата,`nсторона = радиус * 1.41, обход по часовой.

    Gui, Place:Add, Button, x180 y220 w100 h30 gPlaceSave Default, Сохранить
    Gui, Place:Add, Button, x290 y220 w100 h30 gPlaceCancel, Отмена

    Gui, Place:Show, w470 h265, Настройки расстановки
}

PlaceSave:
    Gui, Place:Submit, NoHide
    if (Key = "")
        Key := "6"
    Div += 0
    if (Div < 1)
        Div := 1
    Delay += 0
    if (Delay < 0)
        Delay := 0
    Clicks += 0
    if (Clicks < 1)
        Clicks := 1
    if (Clicks > 4)
        Clicks := 4

    IniWrite, %Key%, %IniFile%, Place, Key
    IniWrite, %Div%, %IniFile%, Place, Div
    IniWrite, %Delay%, %IniFile%, Place, Delay
    IniWrite, %Clicks%, %IniFile%, Place, Clicks
    IniWrite, %Hide%, %IniFile%, Place, Hide

    LoadPlaceSettings()
    Gui, Place:Destroy
    TrayTip, PathDetect, Настройки расстановки сохранены, 2
return

PlaceCancel:
    Gui, Place:Destroy
return
