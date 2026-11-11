; Слой карт: папки режимов, имена файлов и распознавание карты по заголовку.
; Подключается из main.ahk. Глобальные переменные (MapsDir, GameMode, MapList,
; параметры Detect*) объявляются в main.ahk при старте.
;
; Пиксельные буферы передаются между функциями только адресами: в AHK v1
; бинарные данные нельзя передавать по значению или хранить в свойстве объекта —
; значение обрезается на первом нулевом байте.

ModeDir(mode := "") {
    global MapsDir, GameMode
    m := (mode = "") ? GameMode : mode
    return MapsDir . "\" . m
}

IsValidGameMode(mode) {
    global GameModes
    for _, m in GameModes
        if (m = mode)
            return true
    return false
}

MapFileBase(name) {
    n := Trim(name)
    n := RegExReplace(n, "[\\/:*?""<>|]", "_")
    n := RegExReplace(n, "[.\s]+$", "")
    return n
}

LegacyMapBase(name) {
    n := Trim(name)
    StringReplace, n, n, ', , All
    n := RegExReplace(n, "[\s\\/:*?""<>|]", "_")
    return n
}

MapSidecarFile(mapName, suffix) {
    canonical := ModeDir() . "\" . MapFileBase(mapName) . suffix
    if FileExist(canonical)
        return canonical
    legacy := ModeDir() . "\" . LegacyMapBase(mapName) . suffix
    if FileExist(legacy)
        return legacy
    return canonical
}

MapSlotsFile(mapName) {
    return MapSidecarFile(mapName, "_slots.ini")
}

RejoinActionsFile(mapName) {
    return MapSidecarFile(mapName, "_rejoin.ini")
}

MapTitlePath(mapName) {
    return ModeDir() . "\" . MapFileBase(mapName) . "_title.bmp"
}

MapTitleAnchorPath(mapName) {
    return ModeDir() . "\" . MapFileBase(mapName) . "_title.ini"
}

MapTitleTemplate(mapName) {
    f := MapTitlePath(mapName)
    if FileExist(f)
        return f
    png := ModeDir() . "\" . MapFileBase(mapName) . "_title.png"
    if FileExist(png)
        return png
    return ""
}

; Читает точные названия карт для одного режима из общего UTF-8 каталога.
; Пустые строки и комментарии с ; пропускаются.
LoadMapCatalog(mode, ByRef names) {
    global MapsDir
    names := []
    file := MapsDir . "\map_catalog.txt"
    if !FileExist(file)
        return false
    FileRead, text, *P65001 %file%
    if (ErrorLevel)
        return false
    section := ""
    for _, line in StrSplit(StrReplace(text, "`r"), "`n") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if (SubStr(line, 1, 1) = "[" && SubStr(line, 0) = "]") {
            section := SubStr(line, 2, StrLen(line) - 2)
            StringLower, section, section
            continue
        }
        if (section != mode)
            continue
        names.Push(line)
    }
    return true
}

InvalidateTitleTemplates() {
    global TitleTemplates, TitleTemplatesMode
    TitleTemplates := []
    TitleTemplatesMode := ""
}

; Читает 24-битный BMP в переменную вызывающего, приводя строки к порядку
; «сверху вниз». Возвращает false для любого другого формата.
LoadBmpPixels(file, ByRef buf, ByRef w, ByRef h, ByRef stride) {
    buf := ""
    w := 0, h := 0, stride := 0
    if !FileExist(file)
        return false
    f := FileOpen(file, "r")
    if !f
        return false
    f.Seek(10)
    dataOffset := f.ReadUInt()
    f.Seek(18)
    bw := f.ReadInt()
    f.Seek(22)
    bh := f.ReadInt()
    f.Seek(28)
    bpp := f.ReadUShort()
    if (bpp != 24 || bw < 1 || Abs(bh) < 1 || dataOffset < 54) {
        f.Close()
        return false
    }
    w := bw
    h := Abs(bh)
    stride := ((w * 3 + 3) // 4) * 4
    VarSetCapacity(buf, stride * h, 0)
    f.Seek(dataOffset)
    read := f.RawRead(&buf, stride * h)
    f.Close()
    if (read < stride * h) {
        buf := ""
        w := 0, h := 0, stride := 0
        return false
    }
    if (bh < 0)
        return true
    ; BMP снизу вверх: разворачиваем строки на месте, чтобы дальше всё читалось
    ; одинаково. Меняем местами половинки строк через один временный ряд.
    VarSetCapacity(rowTmp, stride, 0)
    half := h // 2
    Loop, %half% {
        top := (A_Index - 1) * stride
        bottom := (h - A_Index) * stride
        DllCall("RtlMoveMemory", "ptr", &rowTmp, "ptr", &buf + top, "ptr", stride)
        DllCall("RtlMoveMemory", "ptr", &buf + top, "ptr", &buf + bottom, "ptr", stride)
        DllCall("RtlMoveMemory", "ptr", &buf + bottom, "ptr", &rowTmp, "ptr", stride)
    }
    return true
}

; Светло-синий пиксель — из таких нарисован текст заголовка.
IsTitleTextPixel(addr, stride, w, h, x, y) {
    if (x < 0 || y < 0 || x >= w || y >= h)
        return false
    off := y * stride + x * 3
    b := NumGet(addr + off, 0, "UChar")
    g := NumGet(addr + off + 1, 0, "UChar")
    r := NumGet(addr + off + 2, 0, "UChar")
    return (b > 150 && b - r > 50 && g > 100)
}

; Точки заголовка для сравнения: пиксели текста, у которых рядом есть фон.
; Берём контуры букв — тогда результат не зависит от превью карты под текстом,
; а точек заметно меньше, чем пикселей во всём шаблоне.
CollectTitleSamples(addr, w, h, stride) {
    samples := []
    step := 2
    edgeDist := 3
    y := 0
    while (y < h) {
        x := 0
        while (x < w) {
            if (IsTitleTextPixel(addr, stride, w, h, x, y)) {
                if (!IsTitleTextPixel(addr, stride, w, h, x - edgeDist, y)
                    || !IsTitleTextPixel(addr, stride, w, h, x + edgeDist, y)
                    || !IsTitleTextPixel(addr, stride, w, h, x, y - edgeDist)
                    || !IsTitleTextPixel(addr, stride, w, h, x, y + edgeDist))
                    samples.Push({x: x, y: y})
            }
            x += step
        }
        y += step
    }
    return samples
}

; Загружает шаблоны заголовков активного режима в кэш.
BuildTitleTemplates(force := false) {
    global GameMode, MapList, TitleTemplates, TitleTemplatesMode, TitleTplPixels
    if (!force && TitleTemplatesMode = GameMode)
        return
    TitleTemplates := []
    TitleTemplatesMode := GameMode
    for _, mapName in MapList {
        tplFile := MapTitleTemplate(mapName)
        if (tplFile = "")
            continue
        if (!LoadBmpPixels(tplFile, TitleTplPixels, w, h, stride))
            continue
        ax := 0, ay := 0
        anchor := MapTitleAnchorPath(mapName)
        if FileExist(anchor) {
            IniRead, ax, %anchor%, Title, X, 0
            IniRead, ay, %anchor%, Title, Y, 0
        }
        samples := CollectTitleSamples(&TitleTplPixels, w, h, stride)
        if (samples.Length() < 20)
            continue
        ; Разреженная выборка для грубого перебора положения: в шесть раз меньше
        ; точек, но её хватает, чтобы отличить свою карту от чужой.
        coarse := []
        i := 1
        while (i <= samples.Length()) {
            coarse.Push(samples[i])
            i += 6
        }
        TitleTemplates.Push({name: mapName, file: tplFile, w: w, h: h, stride: stride
            , x: ax + 0, y: ay + 0, samples: samples, coarse: coarse})
    }
}

; Совпал ли пиксель полосы с пикселем шаблона (компоненты B,G,R по отдельности).
TitlePixelMatches(tplAddr, bandAddr, toff, boff, tol) {
    if (Abs(NumGet(tplAddr + toff, 0, "UChar") - NumGet(bandAddr + boff, 0, "UChar")) > tol)
        return false
    if (Abs(NumGet(tplAddr + toff + 1, 0, "UChar") - NumGet(bandAddr + boff + 1, 0, "UChar")) > tol)
        return false
    if (Abs(NumGet(tplAddr + toff + 2, 0, "UChar") - NumGet(bandAddr + boff + 2, 0, "UChar")) > tol)
        return false
    return true
}

; Доля точек шаблона, совпавших с полосой кадра при смещении (dx, dy), в %.
; neighbor=true дополнительно считает попаданием совпадение с соседним пикселем
; полосы — это гасит чувствительность к сдвигу на один пиксель.
ScoreTitleTemplate(tplAddr, tplStride, tplX, tplY, samples, dx, dy, neighbor := false) {
    global DetectBandBuf, DetectBandStride, DetectBandW, DetectBandH
    global DetectTitleX, DetectTitleY, DetectTitleTolerance
    bandAddr := &DetectBandBuf
    tol := DetectTitleTolerance
    total := 0, hits := 0
    for _, s in samples {
        bx := tplX + s.x + dx - DetectTitleX
        by := tplY + s.y + dy - DetectTitleY
        if (bx < 0 || by < 0 || bx >= DetectBandW || by >= DetectBandH)
            continue
        total += 1
        toff := s.y * tplStride + s.x * 3
        boff := by * DetectBandStride + bx * 3
        if (TitlePixelMatches(tplAddr, bandAddr, toff, boff, tol)) {
            hits += 1
            continue
        }
        if (!neighbor)
            continue
        ; Соседние пиксели полосы: сначала по сторонам, затем по диагоналям —
        ; так попадание засчитывается и при смещении на один пиксель в любую сторону.
        xOk := (bx + 1 < DetectBandW), xPrev := (bx > 0)
        yOk := (by + 1 < DetectBandH), yPrev := (by > 0)
        right := boff + 3, left := boff - 3
        down := boff + DetectBandStride, up := boff - DetectBandStride
        if ((xOk && TitlePixelMatches(tplAddr, bandAddr, toff, right, tol))
            || (xPrev && TitlePixelMatches(tplAddr, bandAddr, toff, left, tol))
            || (yOk && TitlePixelMatches(tplAddr, bandAddr, toff, down, tol))
            || (yPrev && TitlePixelMatches(tplAddr, bandAddr, toff, up, tol))
            || (xOk && yOk && TitlePixelMatches(tplAddr, bandAddr, toff, right + DetectBandStride, tol))
            || (xPrev && yPrev && TitlePixelMatches(tplAddr, bandAddr, toff, left - DetectBandStride, tol))
            || (xOk && yPrev && TitlePixelMatches(tplAddr, bandAddr, toff, right - DetectBandStride, tol))
            || (xPrev && yOk && TitlePixelMatches(tplAddr, bandAddr, toff, left + DetectBandStride, tol)))
            hits += 1
    }
    if (total = 0)
        return 0
    return Round(hits * 100 / total)
}

; Ищет положение заголовка вокруг сохранённой точки: грубый проход по всей
; области, затем уточнение на полной выборке. Возвращает [score, dx, dy].
SearchTitleOffset(tpl, ByRef outDx, ByRef outDy) {
    global TitleTplPixels, DetectTitleRoam, DetectTitleCoarseStep, DetectTitleFineRoam
    if (!LoadBmpPixels(tpl.file, TitleTplPixels, tw, th, tstride)) {
        outDx := 0, outDy := 0
        return 0
    }
    tplAddr := &TitleTplPixels
    best := -1, bestDx := 0, bestDy := 0
    dy := -DetectTitleRoam
    while (dy <= DetectTitleRoam) {
        dx := -DetectTitleRoam
        while (dx <= DetectTitleRoam) {
            score := ScoreTitleTemplate(tplAddr, tpl.stride, tpl.x, tpl.y, tpl.coarse, dx, dy)
            if (score > best) {
                best := score, bestDx := dx, bestDy := dy
            }
            dx += DetectTitleCoarseStep
        }
        dy += DetectTitleCoarseStep
    }
    ; Уточнение шагом 1 вокруг лучшей грубой позиции. Грубая сетка идёт с шагом
    ; 4, поэтому истинное смещение заведомо в пределах ±2 от её точки.
    coarseDx := bestDx, coarseDy := bestDy
    score := ScoreTitleTemplate(tplAddr, tpl.stride, tpl.x, tpl.y, tpl.samples, coarseDx, coarseDy, true)
    if (score >= DetectTitleThreshold) {
        outDx := coarseDx, outDy := coarseDy
        return score
    }
    if (score > best)
        best := score
    dy := coarseDy - DetectTitleFineRoam
    while (dy <= coarseDy + DetectTitleFineRoam) {
        dx := coarseDx - DetectTitleFineRoam
        while (dx <= coarseDx + DetectTitleFineRoam) {
            score := ScoreTitleTemplate(tplAddr, tpl.stride, tpl.x, tpl.y, tpl.samples, dx, dy, true)
            if (score > best) {
                best := score, bestDx := dx, bestDy := dy
            }
            dx += 1
        }
        dy += 1
    }
    outDx := bestDx, outDy := bestDy
    return best
}

; Распознаёт название OCR и проверяет его по каталогу; при недоступности OCR
; использует пиксельные шаблоны, созданные для отдельных карт.
DetectMapTitle(ByRef outMap, ByRef outScore, forceRebuild := false) {
    global WinTitle, DetectTitleThreshold, OcrCapturePath
    global DetectTitleX, DetectTitleY, DetectTitleW, DetectTitleH
    global DetectBandBuf, DetectBandStride, DetectBandW, DetectBandH
    global TitleTemplates, TitleTplPixels, DetectedOtherMode
    outMap := "", outScore := 0
    DetectedOtherMode := ""
    if !WinExist(WinTitle)
        return false
    if (!GameAreaOrigin(areaX, areaY))
        return false
    otherMode := ""
    CaptureScreenshot(areaX + DetectTitleX, areaY + DetectTitleY, DetectTitleW, DetectTitleH, OcrCapturePath)
    if (RecognizeTitleText(OcrCapturePath, ocrText)) {
        if (MatchCatalogMap(ocrText, outMap, "", otherMode)) {
            outScore := 100
            return true
        }
        if (otherMode != "") {
            DetectedOtherMode := otherMode
            outScore := 0
        }
        return false
    }

    ; Если Windows OCR недоступен, используем сохранённые шаблоны.
    BuildTitleTemplates(forceRebuild)
    if (TitleTemplates.Length() = 0)
        return false

    bandFile := A_Temp . "\mmacro_title_band.bmp"
    CaptureScreenshot(areaX + DetectTitleX, areaY + DetectTitleY, DetectTitleW, DetectTitleH, bandFile)
    if (!LoadBmpPixels(bandFile, DetectBandBuf, DetectBandW, DetectBandH, DetectBandStride))
        return false

    ; Первый проход — по сохранённой позиции: обычный случай, когда окно игры
    ; не меняло размер с момента снятия шаблона.
    best := 0, bestName := ""
    for _, tpl in TitleTemplates {
        if (!LoadBmpPixels(tpl.file, TitleTplPixels, tw, th, tstride))
            continue
        score := ScoreTitleTemplate(&TitleTplPixels, tpl.stride, tpl.x, tpl.y, tpl.samples, 0, 0, true)
        if (score > best) {
            best := score
            bestName := tpl.name
        }
    }
    if (best >= DetectTitleThreshold) {
        outMap := bestName, outScore := best
        return true
    }

    ; Позиция «поехала» (другое окно игры) — ищем её заново у двух лучших
    ; кандидатов. Перебирать так все карты слишком долго, а нужная карта почти
    ; всегда попадает в двойку лучших по первому проходу.
    candidates := []
    for _, tpl in TitleTemplates {
        if (!LoadBmpPixels(tpl.file, TitleTplPixels, tw, th, tstride))
            continue
        candidates.Push({tpl: tpl, score: ScoreTitleTemplate(&TitleTplPixels, tpl.stride, tpl.x, tpl.y, tpl.samples, 0, 0, true)})
    }
    loop, 2 {
        top := ""
        for _, c in candidates {
            if (c.used)
                continue
            if (top = "" || c.score > top.score)
                top := c
        }
        if (top = "")
            break
        top.used := true
        score := SearchTitleOffset(top.tpl, foundDx, foundDy)
        if (score > best) {
            best := score
            bestName := top.tpl.name
        }
    }
    outMap := bestName
    outScore := best
    return (best >= DetectTitleThreshold && bestName <> "")
}