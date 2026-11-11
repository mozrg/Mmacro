; ============================================================
; Пользовательские горячие клавиши
; Значения хранятся в секции [Hotkeys] файла ahk\settings.ini.
; ============================================================

FarmHotkey := "F9"
RejoinRecordHotkey := "F1"
MapChangeRecordHotkey := "F2"
MapDetectHotkey := "F3"
AppliedFarmHotkey := ""
AppliedRejoinRecordHotkey := ""
AppliedMapChangeRecordHotkey := ""
AppliedMapDetectHotkey := ""

NormalizeHotkey(value, fallback) {
    value := Trim(value)
    if !IsSafeHotkey(value)
        return fallback
    return value
}

IsSafeHotkey(value) {
    ; Убираем AHK-модификаторы Ctrl/Alt/Shift/Win и проверяем базовую клавишу.
    base := RegExReplace(value, "^[\^\!\+\#]+")
    return RegExMatch(base, "i)^(F([1-9]|1[0-9]|2[0-4])|[A-Z0-9]|Backspace|CapsLock|Delete|Down|End|Enter|Esc|Home|Insert|Left|NumLock|Numpad(Add|Clear|Del|Div|Dot|Ins|Mult|Sub|Enter|[0-9])|PageDown|PageUp|Pause|PrintScreen|Right|ScrollLock|Space|Tab|Up|AppsKey)$")
}

LoadHotkeySettings() {
    global SettingsFile, FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    IniRead, value, %SettingsFile%, Hotkeys, Farm, %FarmHotkey%
    oldFarmHotkey := value
    FarmHotkey := NormalizeHotkey(value, "F9")
    IniRead, value, %SettingsFile%, Hotkeys, RejoinRecord, %RejoinRecordHotkey%
    oldRejoinRecordHotkey := value
    RejoinRecordHotkey := NormalizeHotkey(value, "F1")
    IniRead, value, %SettingsFile%, Hotkeys, MapChangeRecord, %MapChangeRecordHotkey%
    oldMapChangeRecordHotkey := value
    MapChangeRecordHotkey := NormalizeHotkey(value, "F2")
    IniRead, value, %SettingsFile%, Hotkeys, MapDetect, %MapDetectHotkey%
    oldMapDetectHotkey := value
    MapDetectHotkey := NormalizeHotkey(value, "F3")
    if (FarmHotkey = RejoinRecordHotkey)
        RejoinRecordHotkey := (FarmHotkey = "F1") ? "F9" : "F1"
    if (FarmHotkey = MapChangeRecordHotkey || RejoinRecordHotkey = MapChangeRecordHotkey)
        MapChangeRecordHotkey := FindFreeHotkey("F2", FarmHotkey, RejoinRecordHotkey, MapDetectHotkey)
    if (MapDetectHotkey = FarmHotkey || MapDetectHotkey = RejoinRecordHotkey || MapDetectHotkey = MapChangeRecordHotkey)
        MapDetectHotkey := FindFreeHotkey("F3", FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey)
    if (oldFarmHotkey != FarmHotkey || oldRejoinRecordHotkey != RejoinRecordHotkey || oldMapChangeRecordHotkey != MapChangeRecordHotkey || oldMapDetectHotkey != MapDetectHotkey)
        SaveHotkeySettings()
}

SetHotkeySettings(farmKey, rejoinKey, mapChangeKey := "F2", mapDetectKey := "F3") {
    global FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    farmKey := NormalizeHotkey(farmKey, "F9")
    rejoinKey := NormalizeHotkey(rejoinKey, "F1")
    mapChangeKey := NormalizeHotkey(mapChangeKey, "F2")
    mapDetectKey := NormalizeHotkey(mapDetectKey, "F3")
    if (farmKey = rejoinKey)
        rejoinKey := (farmKey = "F1") ? "F9" : "F1"
    if (farmKey = mapChangeKey || rejoinKey = mapChangeKey)
        mapChangeKey := FindFreeHotkey("F2", farmKey, rejoinKey, mapDetectKey)
    if (mapDetectKey = farmKey || mapDetectKey = rejoinKey || mapDetectKey = mapChangeKey)
        mapDetectKey := FindFreeHotkey("F3", farmKey, rejoinKey, mapChangeKey)
    FarmHotkey := farmKey
    RejoinRecordHotkey := rejoinKey
    MapChangeRecordHotkey := mapChangeKey
    MapDetectHotkey := mapDetectKey
}

SaveHotkeySettings() {
    global SettingsFile, FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    IniWrite, %FarmHotkey%, %SettingsFile%, Hotkeys, Farm
    IniWrite, %RejoinRecordHotkey%, %SettingsFile%, Hotkeys, RejoinRecord
    IniWrite, %MapChangeRecordHotkey%, %SettingsFile%, Hotkeys, MapChangeRecord
    IniWrite, %MapDetectHotkey%, %SettingsFile%, Hotkeys, MapDetect
}

FindFreeHotkey(preferred, first, second := "", third := "", fourth := "") {
    candidates := [preferred, "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
    for _, candidate in candidates {
        if (candidate != first && candidate != second && candidate != third && candidate != fourth)
            return candidate
    }
    return preferred
}

DisableConfiguredHotkeys() {
    global AppliedFarmHotkey, AppliedRejoinRecordHotkey, AppliedMapChangeRecordHotkey, AppliedMapDetectHotkey
    if (AppliedFarmHotkey != "")
        Hotkey, %AppliedFarmHotkey%, FarmHotkeyAction, Off
    if (AppliedRejoinRecordHotkey != "")
        Hotkey, %AppliedRejoinRecordHotkey%, RejoinRecordHotkeyAction, Off
    if (AppliedMapChangeRecordHotkey != "")
        Hotkey, %AppliedMapChangeRecordHotkey%, MapChangeRecordHotkeyAction, Off
    if (AppliedMapDetectHotkey != "")
        Hotkey, %AppliedMapDetectHotkey%, MapDetectHotkeyAction, Off
}

EnableConfiguredHotkeys() {
    global AppliedFarmHotkey, AppliedRejoinRecordHotkey, AppliedMapChangeRecordHotkey, AppliedMapDetectHotkey
    if (AppliedFarmHotkey != "")
        Hotkey, %AppliedFarmHotkey%, FarmHotkeyAction, On
    if (AppliedRejoinRecordHotkey != "")
        Hotkey, %AppliedRejoinRecordHotkey%, RejoinRecordHotkeyAction, On
    if (AppliedMapChangeRecordHotkey != "")
        Hotkey, %AppliedMapChangeRecordHotkey%, MapChangeRecordHotkeyAction, On
    if (AppliedMapDetectHotkey != "")
        Hotkey, %AppliedMapDetectHotkey%, MapDetectHotkeyAction, On
}

ApplyConfiguredHotkeys() {
    global FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey, MapDetectHotkey
    global AppliedFarmHotkey, AppliedRejoinRecordHotkey, AppliedMapChangeRecordHotkey, AppliedMapDetectHotkey

    ; Защита от старых/повреждённых значений в settings.ini.
    FarmHotkey := NormalizeHotkey(FarmHotkey, "F9")
    RejoinRecordHotkey := NormalizeHotkey(RejoinRecordHotkey, "F1")
    MapChangeRecordHotkey := NormalizeHotkey(MapChangeRecordHotkey, "F2")
    MapDetectHotkey := NormalizeHotkey(MapDetectHotkey, "F3")
    if (FarmHotkey = RejoinRecordHotkey)
        RejoinRecordHotkey := (FarmHotkey = "F1") ? "F9" : "F1"
    if (FarmHotkey = MapChangeRecordHotkey || RejoinRecordHotkey = MapChangeRecordHotkey)
        MapChangeRecordHotkey := FindFreeHotkey("F2", FarmHotkey, RejoinRecordHotkey, MapDetectHotkey)
    if (MapDetectHotkey = FarmHotkey || MapDetectHotkey = RejoinRecordHotkey || MapDetectHotkey = MapChangeRecordHotkey)
        MapDetectHotkey := FindFreeHotkey("F3", FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey)

    ; Снимаем старые пользовательские сочетания перед регистрацией новых.
    DisableConfiguredHotkeys()

    Hotkey, %FarmHotkey%, FarmHotkeyAction, On
    if (ErrorLevel) {
        FarmHotkey := "F9"
        Hotkey, F9, FarmHotkeyAction, On
    }
    AppliedFarmHotkey := FarmHotkey

    Hotkey, %RejoinRecordHotkey%, RejoinRecordHotkeyAction, On
    if (ErrorLevel) {
        RejoinRecordHotkey := "F1"
        Hotkey, F1, RejoinRecordHotkeyAction, On
    }
    AppliedRejoinRecordHotkey := RejoinRecordHotkey

    Hotkey, %MapChangeRecordHotkey%, MapChangeRecordHotkeyAction, On
    if (ErrorLevel) {
        MapChangeRecordHotkey := FindFreeHotkey("F2", FarmHotkey, RejoinRecordHotkey, MapDetectHotkey)
        Hotkey, %MapChangeRecordHotkey%, MapChangeRecordHotkeyAction, On
    }
    AppliedMapChangeRecordHotkey := MapChangeRecordHotkey

    Hotkey, %MapDetectHotkey%, MapDetectHotkeyAction, On
    if (ErrorLevel) {
        MapDetectHotkey := FindFreeHotkey("F3", FarmHotkey, RejoinRecordHotkey, MapChangeRecordHotkey)
        Hotkey, %MapDetectHotkey%, MapDetectHotkeyAction, On
    }
    AppliedMapDetectHotkey := MapDetectHotkey
}
