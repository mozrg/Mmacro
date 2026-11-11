;=============================================================
;  PathDetect - управление просмотрщиком дорожки
;
;  F4  - выделить область (снимать только её)
;  F9  - запустить просмотр
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
Pid := 0
RegX := 0
RegY := 0
RegW := 0
RegH := 0

LoadRegion()

Menu, Tray, NoStandard
Menu, Tray, Add, Выделить область (F4), DoSelect
Menu, Tray, Add, Запустить (F9), DoStart
Menu, Tray, Add, Остановить (F10), DoStop
Menu, Tray, Add, Перезапустить (F11), DoRestart
Menu, Tray, Add
Menu, Tray, Add, Выход (F12), DoExit
Menu, Tray, Default, Запустить (F9)
Menu, Tray, Tip, PathDetect

return

F4::SelectRegion()
F9::StartDetector()
F10::StopDetector()
F11::RestartDetector()
F12::ExitApp

DoSelect:
    SelectRegion()
return

DoStart:
    StartDetector()
return

DoStop:
    StopDetector()
return

DoRestart:
    RestartDetector()
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
        TrayTip, PathDetect, Запущен: F5 - снимок; F6/F7 - порог; Esc - выход, 4
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
