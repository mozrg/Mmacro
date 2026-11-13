;=============================================================
;  PathDetect - управление просмотрщиком дорожки
;
;  F4  - выделить область (снимать только её)
;  F8  - расставить юнитов по углам квадрата у центра окна игры
;  F3  - то же, но у второй точки (ниже центра);
;        обе клавиши переназначаются в настройках
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
PlaceClickKey := "3"   ; клавиша, которая жмётся перед каждым кликом
PlaceDiv := 3          ; радиус окружности = шаг крупных точек / PlaceDiv
PlaceMoveDelay := 100  ; пауза после наведения на угол, перед кликом
PlaceSpeed := 10       ; скорость переноса мыши: 0 = мгновенно, 100 = медленно
PlaceDelay := 100      ; пауза после клика, мс
PlaceClicks := 4       ; сколько углов квадрата жать (1-4)
PlaceHide := 1         ; прятать окно детектора на время кликов
Place2Offset := 0     ; вторая точка: на сколько крупных точек ниже первой (0 = вокруг центральной)
SlotCounts := [0, 0, 0, 0, 0, 0]   ; итог: сколько кликов каждым слотом
SlotOn := [1, 1, 1, 1, 1, 1]
SlotUnits := [0, 0, 0, 0, 0, 0]
SlotPrio := [1, 1, 1, 1, 1, 1]
SlotUpg := [1, 1, 1, 1, 1, 1]
SlotUntil := [1, 1, 1, 1, 1, 1]
SlotHill := [0, 0, 0, 0, 0, 0]
Untils := "Max|1|2|3|5"
PlaceHotkey1 := "F8"  ; клавиша 1-й точки
PlaceHotkey2 := "F3"  ; клавиша 2-й точки
HkReg1 := ""
HkReg2 := ""
MapFile := A_ScriptDir . "\PathDetect.map.txt"
UsedPts := []


LoadRegion()
LoadPlaceSettings()

Menu, Tray, NoStandard
Menu, Tray, Add, Выделить область (F4), DoSelect
Menu, Tray, Add, Запустить (F9), DoStart
Menu, Tray, Add, Остановить (F10), DoStop
Menu, Tray, Add, Перезапустить (F11), DoRestart
Menu, Tray, Add
Menu, Tray, Add, Расставить юнитов, DoPlaceMenu
Menu, Tray, Add, Слоты (плейсменты), DoSlots
Menu, Tray, Add, Настройки расстановки, DoPlaceSettings
Menu, Tray, Add
Menu, Tray, Add, Выход (F12), DoExit
Menu, Tray, Default, Запустить (F9)
Menu, Tray, Tip, PathDetect

RegisterPlaceHotkeys()

return

F4::SelectRegion()
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

return

DoPlaceHotkey1:
    DoPlace()
return

return


DoSlots:
    ShowSlotSettings()
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
    global PlaceKey, UsedPts

    LoadPlaceSettings()
    UsedPts := []

    ; сначала уводим курсор и жмём клавишу — только потом снимок экрана
    hwnd := GetGameHwnd()
    if hwnd {
        WinActivate, ahk_id %hwnd%
        Sleep, 150

        CoordMode, Mouse, Screen
        WinGetPos, gx, gy, gw, gh, ahk_id %hwnd%
        MouseMove, gx + 1, gy + 31, 0
        Sleep, 120

        Send, %PlaceKey%
        Sleep, 60
    }

    StartDetector()
}

;=============================================================
;  F8: расстановка юнитов
;
;  Центр = ближайшая КРУПНАЯ точка сетки к центру окна Roblox.
;  Вокруг центра рисуется окружность радиусом (шаг крупных точек / PlaceDiv),
;  в неё вписывается квадрат — юниты ставятся в его 4 угла.
;  Перед каждым кликом жмётся клавиша выбора юнита.
;=============================================================
DoPlace() {
    global PlaceDiv, PlaceMoveDelay, PlaceSpeed, PlaceDelay, PlaceHide, RegX, RegY, SlotOn, SlotUnits

    LoadPlaceSettings()

    bigStep := GetBigStep()
    gridStep := GetGridStep()
    g := GCD(bigStep, gridStep)
    if (g > 0)
        L := bigStep * (gridStep / g)
    else
        L := bigStep
    if (L < 10)
        L := bigStep

    div := PlaceDiv
    if (div <= 0)
        div := 1
    radius := bigStep / div
    if (radius < 1)
        radius := 1
    k := radius / 1.41421356237

    CoordMode, Mouse, Screen

    hwnd := GetGameHwnd()
    if hwnd {
        WinActivate, ahk_id %hwnd%
        Sleep, 120
        WinGetPos, gx, gy, gw, gh, ahk_id %hwnd%
    } else {
        gx := 0, gy := 0
        gw := A_ScreenWidth, gh := A_ScreenHeight
    }

    ; центральная крупная точка
    pcx := RegX + NearestBigDot((gx + gw / 2) - RegX, bigStep, gridStep)
    pcy := RegY + NearestBigDot((gy + gh / 2) - RegY, bigStep, gridStep)

    all := LoadMapAll()
    freeAll := []
    for idx, p in all {
        if (p[3] = 0)
            freeAll.Push([p[1], p[2]])
    }
    if (freeAll.MaxIndex() != "") {
        q := PickFreePoint(freeAll, pcx - RegX, pcy - RegY)
        if (q) {
            pcx := RegX + q[1]
            pcy := RegY + q[2]
        }
    }

    ; спираль: центр -> выше -> правее -> ниже -> левее -> следующий радиус
    spiral := []
    spiral.Push([pcx, pcy])
    rr := 1
    while (rr <= 12) {
        ringOffs := [[0, -rr], [rr, 0], [0, rr], [-rr, 0]]
        for idx, o in ringOffs {
            x := pcx + o[1] * L
            y := pcy + o[2] * L
            mp := FindMapPoint(all, x - RegX, y - RegY)
            if (mp != "" && mp[3] = 0 && !IsUsedPt(x, y)) {
                sx := RegX + mp[1]
                sy := RegY + mp[2]
                if (!InPicked(spiral, sx, sy))
                    spiral.Push([sx, sy])
            }
        }
        rr += 1
    }

    ; дальние точки (через одну и дальше) для слотов 5-6
    farPts := []
    dist := 2
    while (dist <= 5) {
        ringOffs := [[0, -dist], [dist, 0], [0, dist], [-dist, 0], [dist, -dist], [dist, dist], [-dist, dist], [-dist, -dist]]
        for idx, o in ringOffs {
            x := pcx + o[1] * L
            y := pcy + o[2] * L
            mp := FindMapPoint(all, x - RegX, y - RegY)
            if (mp != "" && mp[3] = 0 && !IsUsedPt(x, y)) {
                sx := RegX + mp[1]
                sy := RegY + mp[2]
                if (!InPicked(farPts, sx, sy))
                    farPts.Push([sx, sy])
            }
        }
        dist += 1
    }

    ord := SortByPrio([1, 2, 3, 4, 5, 6])
    corners := [[-k, -k], [k, -k], [k, k], [-k, k]]

    jobCount := 0
    for oi, slot in ord {
        if (SlotOn[slot] && SlotUnits[slot] > 0)
            jobCount += 1
    }
    if (jobCount = 0) {
        TrayTip, PathDetect, Слоты пустые — поставь Units, 3
        return
    }

    MarkUsed(pcx, pcy)

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

    CircleShow(pcx, pcy, L, spiral)

    si := 1
    fi := 1
    tasks := []
    pts := []

    for oi, slot in ord {
        if (!SlotOn[slot] || SlotUnits[slot] <= 0)
            continue

        n := SlotUnits[slot]
        if (n > 4)
            n := 4

        q := ""
        if (slot <= 4) {
            if (si <= spiral.MaxIndex()) {
                q := spiral[si]
                si += 1
            }
        } else {
            if (fi <= farPts.MaxIndex()) {
                q := farPts[fi]
                fi += 1
            }
        }
        if (q = "")
            continue

        if (n = 1) {
            tasks.Push({key: slot, x: q[1], y: q[2], n: 1})
            pts.Push([q[1], q[2]])
        } else {
            ci := 1
            while (ci <= n) {
                off := corners[ci]
                tasks.Push({key: slot, x: q[1] + off[1], y: q[2] + off[2], n: 1})
                pts.Push([q[1] + off[1], q[2] + off[2]])
                ci += 1
            }
        }
    }

    for idx, t in tasks {
        j := 0
        while (j < t.n) {
            Send, % t.key
            MoveSlow(t.x, t.y, PlaceSpeed)
            Sleep, %PlaceMoveDelay%
            Click
            Sleep, %PlaceDelay%
            j += 1
        }
    }

    Sleep, 250
    CircleHide()
    if (hidden) {
        if det
            WinShow, ahk_id %det%
    }

    cnt := tasks.MaxIndex()
    TrayTip, PathDetect, Готово: %cnt% кликов, 2
}

FindMapPoint(all, x, y) {
    for idx, p in all {
        if (Abs(p[1] - x) <= 2 && Abs(p[2] - y) <= 2)
            return p
    }
    return ""
}
SortByPrio(list) {
    global SlotPrio

    n := list.MaxIndex()
    i := 2
    while (i <= n) {
        v := list[i]
        j := i - 1
        while (j >= 1) {
            a := list[j]
            if (SlotPrio[a] < SlotPrio[v] || (SlotPrio[a] = SlotPrio[v] && a < v))
                break
            list[j + 1] := list[j]
            j -= 1
        }
        list[j + 1] := v
        i += 1
    }
    return list
}
LoadMapAll() {
    global MapFile

    pts := []
    if !FileExist(MapFile)
        return pts

    Loop, Read, %MapFile%
    {
        line := A_LoopReadLine
        if (line = "" || SubStr(line, 1, 1) = "#")
            continue
        StringSplit, f, line, %A_Space%
        if (f0 < 3)
            continue
        pts.Push([f1 + 0, f2 + 0, f3 + 0])
    }
    return pts
}

IsBlockedAt(all, x, y, L) {
    bestD := 1.0e12
    blk := 0
    for idx, p in all {
        dx := p[1] - x
        dy := p[2] - y
        d := dx * dx + dy * dy
        if (d < bestD) {
            bestD := d
            blk := p[3]
        }
    }
    if (bestD > (L * 0.75) * (L * 0.75))
        return 0
    return blk
}

InPicked(res, x, y) {
    for idx, p in res {
        if (p[1] = x && p[2] = y)
            return 1
    }
    return 0
}

FarPoints(all, cx, cy, L) {
    res := []
    loop 2 {
        best := ""
        bestD := 1.0e12
        for idx, p in all {
            if (p[3] != 0)
                continue
            if (IsUsedPt(p[1], p[2]))
                continue
            if (InPicked(res, p[1], p[2]))
                continue
            dx := p[1] - cx
            dy := p[2] - cy
            d2 := dx * dx + dy * dy
            if (d2 < (1.5 * L) * (1.5 * L))
                continue
            if (d2 > (3.2 * L) * (3.2 * L))
                continue
            if (d2 < bestD) {
                bestD := d2
                best := [p[1], p[2]]
            }
        }
        if (best = "")
            break
        res.Push(best)
    }
    return res
}

;=============================================================
;  Окружность с углами квадрата (клики проходят сквозь окно)
;=============================================================
PlacementOffsets(clicks, r, k) {
    if (clicks >= 4)
        return [[-k, -k], [k, -k], [k, k], [-k, k]]
    if (clicks = 3)
        return [[0, -r], [Round(r * 0.866), Round(r * 0.5)], [-Round(r * 0.866), Round(r * 0.5)]]
    if (clicks = 2)
        return [[r, 0], [-r, 0]]
    return [[0, -r]]
}

CircleShow(cx, cy, r, pts) {
    d2 := Ceil(r * 2)
    size := d2 + 12
    x := Round(cx - r - 6)
    y := Round(cy - r - 6)

    Gui, Circ:Destroy
    Gui, Circ:+AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound
    Gui, Circ:Color, 010203
    Gui, Circ:Show, x%x% y%y% w%size% h%size% NoActivate
    WinSet, TransColor, 010203
    hwnd := WinExist()

    hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 2, "UInt", 0x0000FF00, "Ptr")
    dot := DllCall("gdi32\CreateSolidBrush", "UInt", 0x0000FFFF, "Ptr")
    nullBrush := DllCall("gdi32\GetStockObject", "Int", 5, "Ptr")

    oldPen := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
    oldBrush := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", nullBrush, "Ptr")
    DllCall("gdi32\Ellipse", "Ptr", hdc, "Int", 6, "Int", 6, "Int", 6 + d2, "Int", 6 + d2)

    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", dot, "Ptr")
    mx := 6 + r
    my := 6 + r
    for idx, pt in pts {
        ex := mx + (pt[1] - cx)
        ey := my + (pt[2] - cy)
        DllCall("gdi32\Ellipse", "Ptr", hdc, "Int", Round(ex - 2), "Int", Round(ey - 2), "Int", Round(ex + 2), "Int", Round(ey + 2))
    }
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldPen)
    DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldBrush)
    DllCall("gdi32\DeleteObject", "Ptr", pen)
    DllCall("gdi32\DeleteObject", "Ptr", dot)
    DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
}

CircleHide() {
    Gui, Circ:Destroy
}


;=============================================================
;  Слоты (карточки): вкл, Units, Priority, Upgrade, Until, Hill
;=============================================================

ShowSlotSettings() {
    global  ; все переменные функции — глобальные (иначе виртуальные vEn1 и т.п. не работают)

    LoadPlaceSettings()

    Gui, Slot:Destroy
    Gui, Slot:New, +AlwaysOnTop -MaximizeBox, Слоты
    Gui, Slot:Font, s9, Segoe UI

    i := 1
    while (i <= 6) {
        col := Mod(i - 1, 3)
        row := (i - 1) // 3
        x := 12 + col * 182
        y := 10 + row * 180

        Gui, Slot:Add, GroupBox, x%x% y%y% w174 h170, Slot %i%

        cx := x + 112
        cy := y + 14
        vOn := SlotOn[i]
        Gui, Slot:Add, Checkbox, x%cx% y%cy% vEn%i% Checked%vOn%, вкл

        tx := x + 12
        uy0 := y + 38
        Gui, Slot:Add, Text, x%tx% y%uy0% w55, Units:
        ex := x + 70
        ey := y + 36
        Gui, Slot:Add, Edit, x%ex% y%ey% w45 vUn%i% number, % SlotUnits[i]
        ux := ex + 47
        Gui, Slot:Add, UpDown, x%ux% y%ey% w18 Range0-60, % SlotUnits[i]

        py0 := y + 66
        Gui, Slot:Add, Text, x%tx% y%py0% w55, Priority:
        py := y + 64
        Gui, Slot:Add, Edit, x%ex% y%py% w45 vPr%i% number, % SlotPrio[i]
        Gui, Slot:Add, UpDown, x%ux% y%py% w18 Range1-9, % SlotPrio[i]

        uy := y + 92
        vUp := SlotUpg[i]
        Gui, Slot:Add, Checkbox, x%tx% y%uy% vUp%i% Checked%vUp%, Upgrade

        Gy := y + 120
        Gui, Slot:Add, Text, x%tx% y%Gy% w45, Until:
        dx := x + 60
        dy := y + 118
        vUnt := SlotUntil[i]
        Gui, Slot:Add, DropDownList, x%dx% y%dy% w100 vUt%i% Choose%vUnt%, %Untils%

        hy := y + 144
        vHl := SlotHill[i]
        Gui, Slot:Add, Checkbox, x%tx% y%hy% vHl%i% Checked%vHl%, Hill unit

        i += 1
    }

    by := 10 + 2 * 180 + 4
    Gui, Slot:Add, Button, x160 y%by% w110 h30 gSlotSave Default, Сохранить
    Gui, Slot:Add, Button, x290 y%by% w110 h30 gSlotCancel, Отмена

    hh := by + 46
    Gui, Slot:Show, w560 h%hh%, Слоты
}

SlotSave:
    global SlotOn, SlotUnits, SlotPrio, SlotUpg, SlotUntil, SlotHill
    Gui, Slot:Submit, NoHide
    i := 1
    while (i <= 6) {
        vOn := En%i% + 0
        vUn := Un%i% + 0
        vPr := Pr%i% + 0
        vUp := (Up%i% + 0) ? 1 : 0
        vUt := Ut%i%
        vHl := (Hl%i% + 0) ? 1 : 0
        vUt := IndexOfUntil(vUt)
        IniWrite, %vOn%, %IniFile%, Place, Slot%i%On
        IniWrite, %vUn%, %IniFile%, Place, Slot%i%Units
        IniWrite, %vPr%, %IniFile%, Place, Slot%i%Prio
        IniWrite, %vUp%, %IniFile%, Place, Slot%i%Upg
        IniWrite, %vUt%, %IniFile%, Place, Slot%i%Until
        IniWrite, %vHl%, %IniFile%, Place, Slot%i%Hill
        i += 1
    }
    LoadPlaceSettings()
    Gui, Slot:Destroy
    TrayTip, PathDetect, Слоты сохранены, 3
return

SlotCancel:
    Gui, Slot:Destroy
return

IndexOfUntil(v) {
    if (v = "Max")
        return 1
    if (v = "1")
        return 2
    if (v = "2")
        return 3
    if (v = "3")
        return 4
    return 5
}

LoadPlaceSettings() {
    global IniFile, PlaceKey, PlaceClickKey, PlaceDiv, PlaceMoveDelay, PlaceSpeed, PlaceDelay, PlaceClicks, PlaceHide, Place2Offset, PlaceHotkey1, PlaceHotkey2, SlotCounts, SlotOn, SlotUnits, SlotPrio, SlotUpg, SlotUntil, SlotHill

    IniRead, PlaceKey, %IniFile%, Place, Key, 6
    IniRead, PlaceClickKey, %IniFile%, Place, ClickKey, 3
    IniRead, PlaceDiv, %IniFile%, Place, Div, 3
    IniRead, PlaceMoveDelay, %IniFile%, Place, MoveDelay, 100
    IniRead, PlaceSpeed, %IniFile%, Place, Speed, 10
    IniRead, PlaceDelay, %IniFile%, Place, Delay, 100
    IniRead, PlaceClicks, %IniFile%, Place, Clicks, 4
    IniRead, PlaceHide, %IniFile%, Place, Hide, 1
    IniRead, Place2Offset, %IniFile%, Place, Dots2, 0
    IniRead, PlaceHotkey1, %IniFile%, Place, Key1, F8
    IniRead, PlaceHotkey2, %IniFile%, Place, Key2, F3
    si := 1
    while (si <= 6) {
        IniRead, vv, %IniFile%, Place, Slot%si%On, 1
        SlotOn[si] := vv + 0
        IniRead, vv, %IniFile%, Place, Slot%si%Units, 0
        SlotUnits[si] := vv + 0
        IniRead, vv, %IniFile%, Place, Slot%si%Prio, 1
        SlotPrio[si] := vv + 0
        IniRead, vv, %IniFile%, Place, Slot%si%Upg, 1
        SlotUpg[si] := vv + 0
        IniRead, vv, %IniFile%, Place, Slot%si%Until, 1
        SlotUntil[si] := vv + 0
        IniRead, vv, %IniFile%, Place, Slot%si%Hill, 0
        SlotHill[si] := vv + 0
        si += 1
    }

    PlaceDiv += 0
    PlaceMoveDelay += 0
    PlaceSpeed += 0
    PlaceDelay += 0
    PlaceClicks += 0
    PlaceHide += 0
    Place2Offset += 0

    if (PlaceKey = "" || PlaceKey = "ERROR")
        PlaceKey := "6"
    if (PlaceClickKey = "" || PlaceClickKey = "ERROR")
        PlaceClickKey := "3"
    if (PlaceDiv <= 0)
        PlaceDiv := 1
    if (PlaceSpeed < 0)
        PlaceSpeed := 0
    if (PlaceSpeed > 100)
        PlaceSpeed := 100
    if (PlaceMoveDelay < 0)
        PlaceMoveDelay := 0
    if (PlaceDelay < 0)
        PlaceDelay := 0
    if (PlaceClicks < 1)
        PlaceClicks := 1
    if (PlaceClicks > 4)
        PlaceClicks := 4
    if (Place2Offset < 0)
        Place2Offset := 0
    if (Place2Offset > 50)
        Place2Offset := 50
    if (!IsKeyName(PlaceHotkey1))
        PlaceHotkey1 := "F8"
    si := 1
    while (si <= 6) {
        SlotCounts[si] := SlotOn[si] ? SlotUnits[si] : 0
        si += 1
    }

    if (!IsKeyName(PlaceHotkey2))
        PlaceHotkey2 := "F3"
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

; Плавный перенос курсора: скорость 0-100 -> 0-600 мс, движение шагами
; (обычный MouseMove со speed на коротких переходах летит мгновенно).
MoveSlow(x2, y2, speed) {
    if (speed <= 0) {
        MouseMove, %x2%, %y2%, 0
        return
    }
    MouseGetPos, x1, y1
    dx := x2 - x1
    dy := y2 - y1
    if (dx = 0 && dy = 0)
        return

    dur := speed * 6
    steps := Round(dur / 15)
    if (steps < 2)
        steps := 2
    if (steps > 40)
        steps := 40

    sx := dx / steps
    sy := dy / steps
    i := 1
    while (i <= steps) {
        MouseMove, % Round(x1 + sx * i), % Round(y1 + sy * i), 0
        Sleep, 15
        i += 1
    }
    MouseMove, %x2%, %y2%, 0
}

FormatNum(v) {
    s := Format("{:.3f}", v)
    s := RTrim(s, "0")
    s := RTrim(s, ".")
    if (s = "")
        s := "0"
    return s
}

GetBigStep() {
    global SettingsFile
    step := 60
    if FileExist(SettingsFile) {
        Loop, Read, %SettingsFile%
        {
            if (SubStr(A_LoopReadLine, 1, 8) = "bigStep=") {
                v := SubStr(A_LoopReadLine, 9) + 0
                if (v >= 2)
                    step := v
            }
        }
    }
    return step
}

; Ближайшая КРУПНАЯ точка сетки к координате target (в координатах снимка).
; Точки стоят в 10 + i*gridStep, крупные — там, где (x-30) % bigStep = 0.
NearestBigDot(target, bigStep, gridStep) {
    g := GCD(bigStep, gridStep)
    if (g = 0 || Mod(20, g) != 0)
        return 30

    i0 := -1
    i := 0
    while (i < 200) {
        if (Mod(20 + bigStep * i, gridStep) = 0) {
            i0 := i
            break
        }
        i += 1
    }
    if (i0 < 0)
        return 30

    L := bigStep * (gridStep / g)
    base := 30 + bigStep * i0
    k := Round((target - base) / L)
    x := base + k * L
    while (x < 10)
        x += L
    return x
}

GCD(a, b) {
    while (b) {
        t := Mod(a, b)
        a := b
        b := t
    }
    return a
}
; Свободные крупные точки из карты детектора (координаты снимка)
LoadFreeMap() {
    global MapFile

    pts := []
    if !FileExist(MapFile)
        return pts

    Loop, Read, %MapFile%
    {
        line := A_LoopReadLine
        if (line = "" || SubStr(line, 1, 1) = "#")
            continue
        StringSplit, f, line, %A_Space%
        if (f0 < 3)
            continue
        if (f3 = "0")
            pts.Push([f1 + 0, f2 + 0])
    }
    return pts
}

; Ближайшая к (tx, ty) свободная точка, которую ещё не использовали
PickFreePoint(pts, tx, ty) {
    best := ""
    bestD := 1.0e12
    for idx, p in pts {
        dx := p[1] - tx
        dy := p[2] - ty
        d := dx * dx + dy * dy
        if (d < bestD) {
            bestD := d
            best := p
        }
    }
    return best
}

IsUsedPt(x, y) {
    global UsedPts

    for idx, p in UsedPts {
        if (p[1] = x && p[2] = y)
            return true
    }
    return false
}

MarkUsed(x, y) {
    global UsedPts, RegX, RegY

    UsedPts.Push([x - RegX, y - RegY])
}

; Переназначаемые клавиши точек
RegisterPlaceHotkeys() {
    global PlaceHotkey1, HkReg1

    if (HkReg1 != "")
        Hotkey, %HkReg1%, DoPlaceHotkey1, Off
    HkReg1 := ""

    k1 := PlaceHotkey1
    if (!IsKeyName(k1) || IsReservedKey(k1))
        k1 := "F8"

    Hotkey, %k1%, DoPlaceHotkey1, On
    if ErrorLevel
        HkReg1 := ""
    else
        HkReg1 := k1
}

IsKeyName(k) {
    if (k = "")
        return false
    return RegExMatch(k, "i)^([!^+#]+)?([a-z]|[0-9]|f[0-9]{1,2}|space|enter|esc|escape|tab|home|end|pgup|pgdn|up|down|left|right|insert|delete|backspace|numpad[0-9])$")
}

IsReservedKey(k) {
    return (k = "F4" || k = "F9" || k = "F10" || k = "F11" || k = "F12")
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
    global PlaceKey, PlaceClickKey, PlaceDiv, PlaceMoveDelay, PlaceDelay, PlaceHide, PlaceSpeed, PlaceHotkey1

    LoadPlaceSettings()

    Gui, Place:Destroy
    Gui, Place:New, +AlwaysOnTop -MaximizeBox, Настройки расстановки
    Gui, Place:Font, s9, Segoe UI

    Gui, Place:Add, Text, x12 y14 w230, Клавиша поставки:
    Gui, Place:Add, Edit, x250 y12 w90 vHotkey1, %PlaceHotkey1%
    Gui, Place:Add, Text, x350 y14 w140 cGray, (одна на всё)

    Gui, Place:Add, Text, x12 y44 w230, Клавиша выбора юнита (после F9):
    Gui, Place:Add, Edit, x250 y42 w90 vKey, %PlaceKey%
    Gui, Place:Add, Text, x350 y44 w140 cGray, (напр. 6)

    Gui, Place:Add, Text, x12 y74 w230, Клавиша перед каждым кликом:
    Gui, Place:Add, Edit, x250 y72 w90 vClickKey, %PlaceClickKey%
    Gui, Place:Add, Text, x350 y74 w140 cGray, (если слоты пустые)

    Gui, Place:Add, Text, x12 y104 w230, Пауза перед кликом, мс:
    Gui, Place:Add, Edit, x250 y102 w90 vMoveDelay number, %PlaceMoveDelay%
    Gui, Place:Add, Text, x350 y104 w140 cGray, (после наведения)

    Gui, Place:Add, Text, x12 y134 w230, Скорость переноса мыши (0-100):
    Gui, Place:Add, Edit, x250 y132 w90 vSpeed number, %PlaceSpeed%
    Gui, Place:Add, Text, x350 y134 w140 cGray, (0 = мгновенно)

    Gui, Place:Add, Text, x12 y164 w230, Радиус кружка = шаг крупных / N:
    divText := FormatNum(PlaceDiv)
    Gui, Place:Add, Edit, x250 y162 w90 vDiv, %divText%
    Gui, Place:Add, Text, x350 y164 w150 cGray, (можно дробное: 2.5)

    Gui, Place:Add, Text, x12 y194 w230, Пауза после клика, мс:
    Gui, Place:Add, Edit, x250 y192 w90 vDelay number, %PlaceDelay%

    Gui, Place:Add, Checkbox, x250 y222 vHide Checked%PlaceHide%, Прятать окно детектора

    Gui, Place:Add, Text, x12 y252 w470 cGray, Центр — ближайшая КРУПНАЯ точка к центру окна Roblox.`nСлоты 1-4 ставят на точки, ближайшие к дорожке (красные пропускаются),`nслоты 5-6 — через одну (дальние, для ферм).`nUnits = сколько юнитов слота ставить у точки (1 — центр, 2-4 — углы).

    Gui, Place:Add, Button, x180 y330 w100 h30 gPlaceSave Default, Сохранить
    Gui, Place:Add, Button, x290 y330 w100 h30 gPlaceCancel, Отмена

    Gui, Place:Show, w500 h375, Настройки расстановки
}

PlaceSave:
    Gui, Place:Submit, NoHide
    if (Key = "")
        Key := "6"
    if (ClickKey = "")
        ClickKey := "3"
    if (Hotkey1 = "")
        Hotkey1 := "F8"
    Div := Div + 0.0
    if (Div <= 0)
        Div := 1
    MoveDelay += 0
    if (MoveDelay < 0)
        MoveDelay := 0
    Speed += 0
    if (Speed < 0)
        Speed := 0
    if (Speed > 100)
        Speed := 100
    Delay += 0
    if (Delay < 0)
        Delay := 0

    IniWrite, %Key%, %IniFile%, Place, Key
    IniWrite, %ClickKey%, %IniFile%, Place, ClickKey
    IniWrite, % FormatNum(Div), %IniFile%, Place, Div
    IniWrite, %MoveDelay%, %IniFile%, Place, MoveDelay
    IniWrite, %Speed%, %IniFile%, Place, Speed
    IniWrite, %Delay%, %IniFile%, Place, Delay
    IniWrite, %Hotkey1%, %IniFile%, Place, Key1
    IniWrite, %Hide%, %IniFile%, Place, Hide

    LoadPlaceSettings()
    RegisterPlaceHotkeys()
    Gui, Place:Destroy
    TrayTip, PathDetect, Настройки сохранены, 3
return
PlaceCancel:
    Gui, Place:Destroy
return
