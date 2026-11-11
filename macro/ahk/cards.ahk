; Слой карточек Summer Event: каталог, приоритет, OCR и автоголосование.
; Подключается из main.ahk. Глобальные переменные объявляются здесь, чтобы
; настройки и интерфейс могли обращаться к ним до первого запуска проверки.
;
; Сценарий: игра показывает три карточки на выбор (тиры I/II/III). Макрос
; читает их названия через Windows OCR, отбрасывает номер тира, сверяет базу
; имени с card_catalog.txt, выбирает карточку с самым высоким приоритетом из
; card_priority.txt, кликает по ней и затем по Vote.

CardsDir := A_ScriptDir . "\cards"
CardCatalogFile := CardsDir . "\card_catalog.txt"
CardPriorityFile := CardsDir . "\card_priority.txt"
OcrCardsScriptPath := A_ScriptDir . "\cards_ocr.ps1"
OcrWorkerScriptPath := A_ScriptDir . "\cards_ocr_worker.ps1"
OcrWorkerId := DllCall("GetCurrentProcessId")
OcrWorkerRequestFile := A_Temp . "\mmacro_cards_ocr_req_" . OcrWorkerId . ".txt"
OcrWorkerResultFile := A_Temp . "\mmacro_cards_ocr_res_" . OcrWorkerId . ".txt"
OcrWorkerReadyFile := A_Temp . "\mmacro_cards_ocr_ready_" . OcrWorkerId . ".txt"
OcrWorkerStopFile := A_Temp . "\mmacro_cards_ocr_stop_" . OcrWorkerId . ".txt"
OcrWorkerPid := 0
OcrWorkerStarting := false
CardCaptureFile := A_Temp . "\mmacro_cards_capture_" . DllCall("GetCurrentProcessId") . ".bmp"
CardCatalogDefault := "Attack|Boss Damage|Double Attack|Enemy Health|Enemy Regen|Enemy Shield|Enemy Speed|Explosive Deaths|Plated Enemies|Random Blessings|Random Curses|Range|Resistant Enemies|Spellproof Enemies|Yen|Active Cooldown|Cooldown"
CardPriorityDefault := "Yen|Range|Attack|Double Attack|Boss Damage|Enemy Regen|Enemy Health|Enemy Shield|Enemy Speed|Explosive Deaths|Resistant Enemies|Spellproof Enemies|Plated Enemies|Random Blessings|Random Curses|Cooldown|Active Cooldown"

IfNotExist, %CardsDir%
    FileCreateDir, %CardsDir%

CardVoteEnabled := false
CardVoteBusy := false
CardVoteArmed := true
CardVoteRetry := false
CardVoteErrorLogged := false
CardVoteCooldownUntil := 0
CardLastDetectText := ""
CardCatalog := []
CardPriority := []

; Координаты в системе игровой области 1280x720.
CardSlotCount := 3
CardSlotClickX := {1: 435, 2: 643, 3: 858}
CardSlotClickY := 375
CardVoteGreenX := 540
CardVoteGreenY := 600
CardVoteRedX := 680
CardVoteRedY := 600
CardVoteFallbackX := 540
CardVoteFallbackY := 600

; ===================== КАТАЛОГ И ПРИОРИТЕТ =====================
; Всегда добавляет карточки каталога, которых пока нет в списке. Старые
; записи с тирами («Enemy Regen III») заменяются каноническим именем из
; каталога. Если в каталог добавили новую карточку, она появится в конце
; списка приоритета без ручного редактирования.
AddMissingToPriority() {
    global CardPriority, CardCatalog
    result := []
    for _, name in CardPriority {
        for _, c in CardCatalog {
            if (CardBaseName(c) = CardBaseName(name)) {
                already := false
                for _, r in result {
                    if (CardBaseName(r) = CardBaseName(c)) {
                        already := true
                        break
                    }
                }
                if (!already)
                    result.Push(c)
                break
            }
        }
    }
    for _, c in CardCatalog {
        already := false
        for _, r in result {
            if (CardBaseName(r) = CardBaseName(c)) {
                already := true
                break
            }
        }
        if (!already)
            result.Push(c)
    }
    CardPriority := result
}

LoadCardCatalog() {
    global CardCatalog, CardCatalogFile, CardCatalogDefault
    if !FileExist(CardCatalogFile) {
        ; Файла нет — используем встроенный список по умолчанию.
        CardCatalog := []
        for _, name in StrSplit(CardCatalogDefault, "|")
            CardCatalog.Push(name)
        return true
    }
    FileRead, text, *P65001 %CardCatalogFile%
    if (ErrorLevel)
        return false
    names := []
    for _, line in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        names.Push(line)
    }
    ; Заменяем кэш только после успешного чтения: если файл временно
    ; недоступен, уже загруженный каталог продолжит работать.
    if (names.Length() = 0) {
        CardCatalog := []
        for _, name in StrSplit(CardCatalogDefault, "|")
            CardCatalog.Push(name)
        AddMissingToPriority()
        return true
    }
    CardCatalog := names
    AddMissingToPriority()
    return true
}

LoadCardPriority() {
    global CardPriority, CardPriorityFile, CardCatalog, CardPriorityDefault
    if !FileExist(CardPriorityFile) {
        list := []
        for _, name in StrSplit(CardPriorityDefault, "|")
            list.Push(name)
        CardPriority := list
        AddMissingToPriority()
        return true
    }
    FileRead, text, *P65001 %CardPriorityFile%
    if (ErrorLevel) {
        if (CardPriority.Length() = 0) {
            list := []
            for _, name in StrSplit(CardPriorityDefault, "|")
                list.Push(name)
            CardPriority := list
            AddMissingToPriority()
        }
        return false
    }
    list := []
    for _, line in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        list.Push(line)
    }
    CardPriority := list
    AddMissingToPriority()
    return true
}

SaveCardPriority(list) {
    global CardPriorityFile, CardsDir
    if !InStr(FileExist(CardsDir), "D")
        FileCreateDir, %CardsDir%
    f := FileOpen(CardPriorityFile, "w", "UTF-8-RAW")
    if (!f) {
        AddLog("Карточки: не удалось записать " . CardPriorityFile, "error")
        return false
    }
    f.Write("; Приоритет карточек: сверху — самый высокий.`r`n")
    for _, name in list
        f.Write(name . "`r`n")
    f.Close()
    return true
}

; ===================== РАСПОЗНАВАНИЕ =====================
NormalizeBaseName(text) {
    StringLower, text, text
    return RegExReplace(text, "[^a-z\s]+", " ")
}

; Базовое имя карточки: только буквы, без знака +/-, процентов, цифр и тира
; I/II/III (в том числе OCR-вариантов Ill, IIl, lI и т.п.). Пробелы убираются,
; поэтому «+ Enemy Regen III» и «Enemy Regen» дают одно и то же «enemyregen».
CardBaseName(raw) {
    norm := NormalizeBaseName(raw)
    norm := RegExReplace(norm, "[il]{1,3}\s*$", "")
    norm := RegExReplace(norm, "^\s+|\s+$", "")
    return RegExReplace(norm, "\s+", "")
}

CardNamesEqual(a, b) {
    return (CardBaseName(a) = CardBaseName(b))
}

; Сопоставляет распознанный заголовок с каталогом по базовому имени.
; Возвращает название из каталога (без тира). Точное совпадение базы имеет
; приоритет; если точного нет, ищем ближайшее по расстоянию Левенштейна
; (погрешности OCR вроде Doubte/Double, Spettproof/Spellproof).
CardMatchCatalog(ocrText, ByRef matchedName) {
    global CardCatalog
    matchedName := ""
    ocrBase := CardBaseName(ocrText)
    if (ocrBase = "")
        return false

    ; Сначала ищем точное совпадение базы.
    for _, name in CardCatalog {
        if (CardBaseName(name) = ocrBase) {
            matchedName := name
            return true
        }
    }

    bestScore := 0, bestName := ""
    for _, name in CardCatalog {
        catBase := CardBaseName(name)
        if (catBase = "")
            continue
        dist := Levenshtein(ocrBase, catBase)
        maxLen := (StrLen(ocrBase) > StrLen(catBase)) ? StrLen(ocrBase) : StrLen(catBase)
        sim := (maxLen = 0) ? 100 : Round((maxLen - dist) * 100 / maxLen)
        if (dist > 2 || sim < 75)
            continue
        if (sim > bestScore) {
            bestScore := sim
            bestName := name
        }
    }
    if (bestScore >= 75 && bestName != "") {
        matchedName := bestName
        return true
    }
    return false
}

MinInt3(a, b, c) {
    m := a
    if (b < m)
        m := b
    if (c < m)
        m := c
    return m
}

; Расстояние Левенштейна для коротких строк.
Levenshtein(a, b) {
    la := StrLen(a)
    lb := StrLen(b)
    if (la = 0)
        return lb
    if (lb = 0)
        return la
    prev := []
    Loop, % lb + 1
        prev.Push(A_Index - 1)
    Loop, % la {
        i := A_Index
        ca := SubStr(a, i, 1)
        cur := [i]
        Loop, % lb {
            j := A_Index
            cb := SubStr(b, j, 1)
            cost := (ca = cb) ? 0 : 1
            del := prev[j + 1] + 1
            ins := cur[j] + 1
            sub := prev[j] + cost
            cur.Push(MinInt3(del, ins, sub))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; ===================== OCR СКРИПТ =====================
; Удаляет временный файл, даже если он остался с атрибутом ReadOnly.
; FileDelete в AHK v1 бросает исключение на read-only файле — из-за этого
; раньше падал RecognizeCardScreen ещё до запуска OCR.
SafeDeleteFile(path) {
    if (path = "")
        return
    if FileExist(path)
        FileSetAttrib, -R, %path%
    try {
        FileDelete, %path%
    } catch {
    }
}

; Запускает долгоживущий OCR-воркер (один раз на сессию). Он инициализирует
; WinRT/OCR при старте, а потом отвечает примерно за 0.4 с на кадр вместо
; повторного запуска PowerShell на каждый экран.
EnsureOcrWorker() {
    global OcrWorkerScriptPath, OcrWorkerRequestFile, OcrWorkerResultFile
    global OcrWorkerReadyFile, OcrWorkerStopFile, OcrWorkerPid, OcrWorkerStarting, OcrWorkerId
    if (OcrWorkerPid) {
        Process, Exist, %OcrWorkerPid%
        if (ErrorLevel) {
            if FileExist(OcrWorkerReadyFile)
                return true
        } else {
            OcrWorkerPid := 0
        }
    }
    if (OcrWorkerStarting) {
        Loop, 100 {
            if (OcrWorkerPid && FileExist(OcrWorkerReadyFile))
                return true
            Sleep, 50
        }
        return false
    }
    if !FileExist(OcrWorkerScriptPath)
        return false

    OcrWorkerStarting := true
    SafeDeleteFile(OcrWorkerRequestFile)
    SafeDeleteFile(OcrWorkerResultFile)
    SafeDeleteFile(OcrWorkerReadyFile)
    SafeDeleteFile(OcrWorkerStopFile)

    command := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " . Chr(34) . OcrWorkerScriptPath . Chr(34)
        . " " . Chr(34) . OcrWorkerRequestFile . Chr(34)
        . " " . Chr(34) . OcrWorkerResultFile . Chr(34)
        . " " . Chr(34) . OcrWorkerReadyFile . Chr(34)
        . " " . Chr(34) . OcrWorkerStopFile . Chr(34)
        . " " . OcrWorkerId
    Run, %command%, , Hide UseErrorLevel, workerPid
    if (ErrorLevel || !workerPid) {
        OcrWorkerStarting := false
        return false
    }
    OcrWorkerPid := workerPid
    Loop, 100 {
        if FileExist(OcrWorkerReadyFile) {
            OcrWorkerStarting := false
            return true
        }
        Process, Exist, %workerPid%
        if (!ErrorLevel)
            break
        Sleep, 50
    }
    Process, Close, %workerPid%
    OcrWorkerPid := 0
    OcrWorkerStarting := false
    return false
}

; Отправляет путь к BMP воркеру и ждёт текстовый результат.
RunOcrWorkerRequest(imagePath, ByRef text) {
    global OcrWorkerRequestFile, OcrWorkerResultFile, OcrWorkerPid
    text := ""
    if (!EnsureOcrWorker())
        return false

    SafeDeleteFile(OcrWorkerResultFile)
    tmpRequest := OcrWorkerRequestFile . ".tmp"
    SafeDeleteFile(tmpRequest)
    f := FileOpen(tmpRequest, "w", "UTF-8-RAW")
    if (!f)
        return false
    f.Write(imagePath)
    f.Close()
    FileMove, %tmpRequest%, %OcrWorkerRequestFile%, 1
    if (ErrorLevel) {
        SafeDeleteFile(tmpRequest)
        return false
    }

    Loop, 500 {
        if FileExist(OcrWorkerResultFile) {
            FileRead, text, *P65001 %OcrWorkerResultFile%
            readError := ErrorLevel
            SafeDeleteFile(OcrWorkerResultFile)
            if (readError) {
                text := ""
                return false
            }
            return true
        }
        Process, Exist, %OcrWorkerPid%
        if (!ErrorLevel) {
            OcrWorkerPid := 0
            return false
        }
        Sleep, 10
    }
    ; Воркер завис — убиваем, следующий вызов перезапустит его.
    Process, Close, %OcrWorkerPid%
    OcrWorkerPid := 0
    return false
}

ParseCardOcrText(text, ByRef cardTexts, ByRef voteX, ByRef voteY) {
    cardTexts := ["", "", ""]
    voteX := 0, voteY := 0
    if (SubStr(text, 1, 6) = "ERROR`t") {
        AddLog("Карточки OCR: " . SubStr(text, 7), "error")
        return false
    }
    for _, line in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(line)
        if (line = "")
            continue
        fields := StrSplit(line, "`t")
        key := fields[1]
        if (key = "CARD1" || key = "CARD2" || key = "CARD3") {
            idx := SubStr(key, 5, 1) + 0
            if (idx >= 1 && idx <= 3)
                cardTexts[idx] := (fields.Length() >= 2) ? fields[2] : ""
        } else if (key = "VOTE") {
            voteX := (fields.Length() >= 3) ? fields[3] + 0 : 0
            voteY := (fields.Length() >= 4) ? fields[4] + 0 : 0
        }
    }
    return true
}

; Запускает cards_ocr.ps1 и разбирает его результат. Скрипт сам вырезает
; заголовки трёх карточек и кнопку Vote, поэтому AHK передаёт только кадр.
RecognizeCardScreen(imagePath, ByRef cardTexts, ByRef voteX, ByRef voteY) {
    global OcrCardsScriptPath
    cardTexts := ["", "", ""]
    voteX := 0, voteY := 0
    processId := DllCall("GetCurrentProcessId")
    resultPath := A_Temp . "\mmacro_cards_ocr_" . processId . ".txt"
    errorPath := A_Temp . "\mmacro_cards_ocr_" . processId . ".err"
    SafeDeleteFile(resultPath)
    SafeDeleteFile(errorPath)

    ; Сначала быстрый постоянный воркер. Если он недоступен/упал — откат
    ; на одноразовый cards_ocr.ps1, чтобы функция не осталась без OCR.
    if (RunOcrWorkerRequest(imagePath, workerText)) {
        if (ParseCardOcrText(workerText, cardTexts, voteX, voteY))
            return true
    }

    if !FileExist(OcrCardsScriptPath) {
        AddLog("Карточки: не найден " . OcrCardsScriptPath, "error")
        return false
    }
    command := "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " . Chr(34) . OcrCardsScriptPath . Chr(34)
        . " " . Chr(34) . imagePath . Chr(34) . " " . Chr(34) . resultPath . Chr(34) . " " . Chr(34) . errorPath . Chr(34)
    RunWait, %command%, , Hide UseErrorLevel
    if (ErrorLevel) {
        errText := ""
        if FileExist(errorPath)
            FileRead, errText, *P65001 %errorPath%
        SafeDeleteFile(errorPath)
        if (Trim(errText) != "")
            AddLog("Карточки OCR: " . SubStr(Trim(errText), 1, 300), "error")
        else
            AddLog("Карточки OCR: не удалось запустить распознавание", "error")
        return false
    }
    if !FileExist(resultPath) {
        AddLog("Карточки OCR: скрипт не создал результат", "error")
        return false
    }
    FileRead, text, *P65001 %resultPath%
    readError := ErrorLevel
    SafeDeleteFile(resultPath)
    SafeDeleteFile(errorPath)
    if (readError) {
        AddLog("Карточки OCR: не удалось прочитать результат", "error")
        return false
    }
    return ParseCardOcrText(text, cardTexts, voteX, voteY)
}

CountCardTexts(cardTexts) {
    n := 0
    Loop, 3 {
        if (Trim(cardTexts[A_Index]) != "")
            n += 1
    }
    return n
}

; Снимает игровую область и возвращает три распознанных текста + совпавшие
; (базовые) названия из каталога.
ReadCardScreen(ByRef cardTexts, ByRef matched, ByRef voteX, ByRef voteY, ByRef errorText) {
    global WinTitle, CardCaptureFile, CardSlotCount
    cardTexts := ["", "", ""]
    matched := ["", "", ""]
    voteX := 0, voteY := 0
    errorText := ""
    if !WinExist(WinTitle) {
        errorText := "Окно Roblox не найдено"
        return false
    }
    ; Каталог и приоритет можно править вручную — подхватываем изменения
    ; без перезапуска макроса.
    LoadCardCatalog()
    LoadCardPriority()
    if (!CaptureForMarking(CardCaptureFile)) {
        errorText := "Не удалось снять игровую область (файл занят или Roblox не виден)"
        return false
    }
    ocrOk := RecognizeCardScreen(CardCaptureFile, cardTexts, voteX, voteY)
    SafeDeleteFile(CardCaptureFile)
    textCount := ocrOk ? CountCardTexts(cardTexts) : 0

    ; Иногда первый кадр попадает на переход/перерисовку и OCR возвращает
    ; пустые названия. Делаем один быстрый повтор, чтобы не терять экран
    ; целиком и не оставлять CardVoteArmed выключенным.
    if (!ocrOk || textCount < 2) {
        Sleep, 100
        if (CaptureForMarking(CardCaptureFile)) {
            ocrOk := RecognizeCardScreen(CardCaptureFile, cardTexts, voteX, voteY)
            SafeDeleteFile(CardCaptureFile)
            textCount := ocrOk ? CountCardTexts(cardTexts) : 0
        }
    }
    if (!ocrOk) {
        errorText := "Windows OCR не смог прочитать карточки"
        return false
    }
    if (textCount < 2) {
        errorText := "OCR не распознал названия карточек (пустой или частичный кадр)"
        return false
    }
    Loop, %CardSlotCount% {
        found := ""
        if (CardMatchCatalog(cardTexts[A_Index], found))
            matched[A_Index] := found
    }
    return true
}

ChooseCardByPriority(matched, ByRef chosenSlot, ByRef chosenName) {
    global CardPriority, CardSlotCount
    chosenSlot := 0
    chosenName := ""
    for _, priorityName in CardPriority {
        Loop, %CardSlotCount% {
            if (matched[A_Index] != "" && CardNamesEqual(matched[A_Index], priorityName)) {
                chosenSlot := A_Index
                chosenName := matched[A_Index]
                return true
            }
        }
    }
    return false
}

BuildCardDetectText(cardTexts, matched) {
    parts := []
    Loop, 3 {
        text := Trim(cardTexts[A_Index])
        name := matched[A_Index]
        if (text = "")
            text := "?"
        ; Показываем каноническое имя из каталога — без тира I/II/III.
        if (name != "")
            parts.Push(A_Index . ": " . name)
        else
            parts.Push(A_Index . ": " . text)
    }
    return JoinArr(parts, " | ")
}

PushCardDetectResult(text, cls := "") {
    global CardLastDetectText
    CardLastDetectText := text
    js := "ahkCardDetectResult('" . JsEscape(text) . "','" . JsEscape(cls) . "')"
    WBH_CallJS(js)
    ModalCallJS(js)
}

; ===================== ДЕЙСТВИЯ =====================
PrepareGameForClick() {
    global Embedded, WinTitle
    if (!WinExist(WinTitle))
        return false
    if (Embedded) {
        FocusEmbeddedGame()
    } else {
        WinActivate, %WinTitle%
        WinWaitActive, %WinTitle%, , 2
    }
    Sleep, 150
    if !WinActive(WinTitle) {
        AddLog("Карточки: не удалось активировать окно Roblox", "warn")
        return false
    }
    return true
}

IsVoteButtonColorAt(x, y) {
    if (!GameAreaOrigin(gx, gy))
        return false
    sx := gx + x
    sy := gy + y
    PixelGetColor, color, %sx%, %sy%, RGB
    if (ErrorLevel)
        return false
    r := (color >> 16) & 0xFF
    g := (color >> 8) & 0xFF
    b := color & 0xFF
    return (g > 150 && r < 140 && b < 120)
}

IsCancelButtonColorAt(x, y) {
    if (!GameAreaOrigin(gx, gy))
        return false
    sx := gx + x
    sy := gy + y
    PixelGetColor, color, %sx%, %sy%, RGB
    if (ErrorLevel)
        return false
    r := (color >> 16) & 0xFF
    g := (color >> 8) & 0xFF
    b := color & 0xFF
    return (r > 150 && g < 90 && b < 90)
}

IsSaturatedColorAt(x, y) {
    PixelGetColor, color, %x%, %y%, RGB
    if (ErrorLevel)
        return false
    r := (color >> 16) & 0xFF
    g := (color >> 8) & 0xFF
    b := color & 0xFF
    maxC := (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b)
    minC := (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b)
    return (maxC >= 90 && (maxC - minC) >= 40)
}

; Белая надпись «Choose a card...» — второй признак, который отсекает
; ложные срабатывания на обычной игре (рамки там иногда тоже colourful).
IsChooseBannerVisible() {
    if (!GameAreaOrigin(gx, gy))
        return false
    xs := [540, 560, 580, 600, 620, 640, 660, 680, 700, 720, 740]
    ys := [180, 186, 192, 198, 204]
    hits := 0
    for _, y in ys {
        sy := gy + y
        for _, x in xs {
            sx := gx + x
            PixelGetColor, color, %sx%, %sy%, RGB
            if (ErrorLevel)
                continue
            r := (color >> 16) & 0xFF
            g := (color >> 8) & 0xFF
            b := color & 0xFF
            if (r > 200 && g > 200 && b > 200) {
                hits += 1
                if (hits >= 4)
                    return true
            }
        }
    }
    return false
}

; До появления Vote экран выбора карточек не содержит кнопок Vote/Cancel,
; поэтому отдельно проверяем верхние рамки трёх карточек: три ряда
; насыщенных пикселей в фиксированных слотах. Это дешёвая проверка, чтобы
; не запускать PowerShell OCR на каждом тике во время обычной игры.
IsCardChooseScreenVisible() {
    if (!GameAreaOrigin(gx, gy))
        return false
    if (!IsChooseBannerVisible())
        return false
    cardXs := [[360, 435, 500], [570, 645, 720], [785, 860, 930]]
    ; Верхняя рамка карточек может смещаться на несколько пикселей из-за
    ; позиции окна и обрезки края экрана. Сканируем широкую полосу, а не
    ; одну фиксированную строку.
    for _, xs in cardXs {
        bestRow := 0
        Loop, 19 {
            y := 221 + A_Index  ; 222..240
            rowHits := 0
            for _, x in xs {
                if (IsSaturatedColorAt(gx + x, gy + y))
                    rowHits += 1
            }
            if (rowHits > bestRow)
                bestRow := rowHits
        }
        if (bestRow < 2)
            return false
    }
    return true
}

IsCardVoteScreenVisible() {
    global CardVoteGreenX, CardVoteGreenY, CardVoteRedX, CardVoteRedY
    ; Сначала экран выбора карточек (кнопок Vote/Cancel ещё нет), затем
    ; экран подтверждения: зелёная Vote и красная Cancel.
    if (IsCardChooseScreenVisible())
        return true
    return (IsVoteButtonColorAt(CardVoteGreenX, CardVoteGreenY)
        && IsCancelButtonColorAt(CardVoteRedX, CardVoteRedY))
}

; Проверка без голосования: показывает, что макрос видит на экране карточек.
RunCardDetectOnly() {
    global CardVoteRetry
    cardTexts := [], matched := []
    voteX := 0, voteY := 0
    errorText := ""
    CardVoteRetry := false
    if (!ReadCardScreen(cardTexts, matched, voteX, voteY, errorText)) {
        AddLog("Проверка карточек: " . errorText, "warn")
        PushCardDetectResult(errorText, "error")
        return
    }
    text := BuildCardDetectText(cardTexts, matched)
    chosenSlot := 0, chosenName := ""
    if (ChooseCardByPriority(matched, chosenSlot, chosenName))
        text .= "  =>  " . chosenName
    else
        text .= "  =>  нет карточки из приоритета"
    AddLog("Проверка карточек: " . text)
    PushCardDetectResult(text, (chosenSlot > 0) ? "success" : "warn")
}

; Основной проход: выбрать карточку по приоритету, кликнуть её и Vote.
RunCardVote() {
    global CardVoteRetry, CardVoteErrorLogged, CardVoteCooldownUntil
    global CardLastDetectText, CardVoteFallbackX, CardVoteFallbackY, TS_X, TS_Y
    global CardSlotClickX, CardSlotClickY
    cardTexts := [], matched := []
    voteX := 0, voteY := 0
    errorText := ""
    CardVoteRetry := false
    if (!ReadCardScreen(cardTexts, matched, voteX, voteY, errorText)) {
        CardVoteRetry := true
        if (!CardVoteErrorLogged) {
            AddLog("Карточки: " . errorText, "warn")
            CardVoteErrorLogged := true
        }
        return
    }
    CardVoteErrorLogged := false
    seenText := BuildCardDetectText(cardTexts, matched)
    matchedCount := 0
    Loop, 3 {
        if (matched[A_Index] != "")
            matchedCount += 1
    }
    ; Не кликаем по одному случайному совпадению: на обычной игре HUD тоже
    ; содержит слова вроде Cooldown. Нужен хотя бы два узнанных названия.
    if (matchedCount < 2) {
        CardVoteRetry := true
        if (!CardVoteErrorLogged) {
            AddLog("Карточки: распознано меньше двух карточек, повторяю", "warn")
            CardVoteErrorLogged := true
        }
        return
    }

    chosenSlot := 0, chosenName := ""
    if (!ChooseCardByPriority(matched, chosenSlot, chosenName)) {
        text := seenText . "  =>  нет карточки из приоритета"
        AddLog("Карточки: " . text, "warn")
        PushCardDetectResult(text, "warn")
        return
    }

    AddLog("Карточки: вижу " . seenText)
    text := seenText . "  =>  " . chosenName
    AddLog("Карточки: выбрана """ . chosenName . """ (слот " . chosenSlot . ")", "success")
    PushCardDetectResult(text, "success")

    if (!PrepareGameForClick()) {
        AddLog("Карточки: не удалось активировать Roblox", "warn")
        return
    }

    ToScreen(CardSlotClickX[chosenSlot], CardSlotClickY)
    SmoothClick(TS_X, TS_Y, 80)
    Sleep, 100

    ; После клика по карточке появляется подтверждение с Vote. Кнопки на
    ; исходном экране выбора ещё нет, поэтому ждём её появления до 2 секунд.
    if (voteX <= 0 || voteY <= 0) {
        voteFound := false
        Loop, 20 {
            if (IsVoteButtonColorAt(CardVoteFallbackX, CardVoteFallbackY)) {
                voteFound := true
                break
            }
            Sleep, 100
        }
        if (voteFound) {
            voteX := CardVoteFallbackX
            voteY := CardVoteFallbackY
            AddLog("Карточки: Vote найден по цвету")
        } else {
            AddLog("Карточки: кнопка Vote не найдена", "warn")
            return
        }
    }
    ToScreen(voteX, voteY)
    SmoothClick(TS_X, TS_Y, 80)
    Sleep, 100
    CardVoteCooldownUntil := A_TickCount + 3000
    AddLog("Карточки: Vote нажат", "success")
}

ToggleCardVote() {
    global CardVoteEnabled, CardVoteArmed, CardVoteHotkey, CardVoteErrorLogged, CardVoteCooldownUntil
    CardVoteEnabled := !CardVoteEnabled
    CardVoteArmed := true
    CardVoteCooldownUntil := 0
    CardVoteErrorLogged := false
    SaveSettings()
    UpdateCardVoteTimer()
    state := CardVoteEnabled ? "true" : "false"
    WBH_CallJS("ahkUpdateCardVote(" . state . ")")
    ModalCallJS("ahkUpdateCardVote(" . state . ")")
    if (CardVoteEnabled)
        AddLog("Проверка карточек включена (" . CardVoteHotkey . ")", "success")
    else
        AddLog("Проверка карточек выключена", "success")
}

UpdateCardVoteTimer() {
    global CardVoteEnabled
    if (CardVoteEnabled) {
        SetTimer, CardVoteWatch, 400
        ; Прогреваем OCR-воркер заранее, чтобы первый экран не ждал запуска.
        SetTimer, StartOcrWorker, -50
    } else {
        SetTimer, CardVoteWatch, Off
    }
}