; OCR title recognition using the Windows.Media.Ocr API.
; Paths are passed as arguments; recognized lines are returned in a UTF-8 temp file.
RecognizeTitleText(imagePath, ByRef text) {
    global OcrScriptPath
    text := ""
    if !FileExist(OcrScriptPath) {
        AddLog("Windows OCR: не найден файл " . OcrScriptPath, "error")
        return false
    }
    processId := DllCall("GetCurrentProcessId")
    resultPath := A_Temp . "\mmacro_ocr_" . processId . ".txt"
    errorPath := A_Temp . "\mmacro_ocr_" . processId . ".err"
    FileDelete, %resultPath%
    FileDelete, %errorPath%
    command := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " . Chr(34) . OcrScriptPath . Chr(34)
        . " " . Chr(34) . imagePath . Chr(34) . " " . Chr(34) . resultPath . Chr(34) . " " . Chr(34) . errorPath . Chr(34)
    RunWait, %command%, , Hide UseErrorLevel
    if (ErrorLevel) {
        if FileExist(errorPath)
            FileDelete, %errorPath%
        AddLog("Windows OCR: не удалось запустить распознавание, см. результат проверки карты", "error")
        return false
    }
    if !FileExist(resultPath) {
        AddLog("Windows OCR: скрипт не создал результат", "error")
        return false
    }
    FileRead, text, *P65001 %resultPath%
    readError := ErrorLevel
    FileDelete, %resultPath%
    if FileExist(errorPath)
        FileDelete, %errorPath%
    if (readError) {
        AddLog("Windows OCR: не удалось прочитать результат распознавания", "error")
        return false
    }
    if (Trim(text) = "") {
        AddLog("Windows OCR: текст не найден в области названия карты", "warn")
        return true
    }
    return true
}

MatchCatalogMap(ocrText, ByRef matchedName, mode := "", ByRef otherMode := "") {
    global GameMode, GameModes
    matchedName := ""
    otherMode := ""
    selectedMode := (mode = "") ? GameMode : mode
    if !LoadMapCatalog(selectedMode, names)
        return false
    if (FindCatalogMap(ocrText, names, foundName)) {
        matchedName := foundName
        return true
    }

    for _, candidateMode in GameModes {
        if (candidateMode = selectedMode)
            continue
        if !LoadMapCatalog(candidateMode, candidateNames)
            continue
        if (FindCatalogMap(ocrText, candidateNames, foundName)) {
            matchedName := foundName
            otherMode := candidateMode
            AddLog("Распознана карта " . foundName . ", но она относится к режиму " . candidateMode . ". Выбери этот режим.", "warn")
            return false
        }
    }
    return false
}

FindCatalogMap(ocrText, names, ByRef matchedName) {
    matchedName := ""
    lines := StrSplit(StrReplace(ocrText, "`r"), "`n")
    combined := ""
    for _, line in lines {
        normalized := NormalizeMapOcrText(line)
        if (normalized = "")
            continue
        combined .= normalized
        for _, name in names {
            if (MapOcrTextMatches(normalized, NormalizeMapOcrText(name))) {
                matchedName := name
                return true
            }
        }
    }
    for _, name in names {
        if (MapOcrTextMatches(combined, NormalizeMapOcrText(name))) {
            matchedName := name
            return true
        }
    }
    return false
}

MapOcrTextMatches(ocrText, catalogText) {
    if (ocrText = catalogText)
        return true
    ; Windows OCR sometimes reads capital I as lowercase l in stylized titles.
    pos := 0
    while (pos := InStr(ocrText, "l", false, pos + 1)) {
        candidate := SubStr(ocrText, 1, pos - 1) . "i" . SubStr(ocrText, pos + 1)
        if (candidate = catalogText)
            return true
    }
    return false
}

NormalizeMapOcrText(text) {
    StringLower, text, text
    return RegExReplace(text, "[^a-z0-9]")
}
