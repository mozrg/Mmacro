# OCR экрана выбора карточек Summer Event.
# Скрипт вырезает три заголовка карточек и подпись кнопки Vote, собирает их
# в одну картинку с увеличением (мелкий игровой шрифт иначе читается плохо)
# и распознаёт одним проходом Windows.Media.Ocr.
#
# Аргументы: <скриншот> <файл-результата> <файл-ошибки>
# Результат — UTF-8, по строке на элемент:
#   CARD1<TAB>текст заголовка первой карточки
#   CARD2<TAB>...
#   CARD3<TAB>...
#   VOTE<TAB>текст кнопки<TAB>x<TAB>y
# Координаты VOTE — в пикселях исходного скриншота (игровая область 1280x720).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

if ($args.Count -lt 3 -or !(Test-Path -LiteralPath $args[0])) {
    throw 'Expected screenshot, result, and error paths'
}

$screenshotPath = [IO.Path]::GetFullPath($args[0])
$resultPath = [IO.Path]::GetFullPath($args[1])
$errorPath = [IO.Path]::GetFullPath($args[2])

# Области в системе координат игровой области 1280x720. Заголовки взяты
# с запасом по ширине: название центрируется внутри карточки, а карточки
# бывают разной ширины.
$baseWidth = 1280.0
$baseHeight = 720.0
$cardRegions = @(
    @{ X = 312.0; Y = 246.0; W = 246.0; H = 52.0 },
    @{ X = 538.0; Y = 246.0; W = 226.0; H = 52.0 },
    @{ X = 750.0; Y = 246.0; W = 226.0; H = 52.0 }
)
$voteRegion = @{ X = 486.0; Y = 570.0; W = 190.0; H = 52.0 }
$cardScale = 3
$voteScale = 3
$pad = 16

try {
    $source = [System.Drawing.Bitmap]::FromFile($screenshotPath)
} catch {
    [IO.File]::WriteAllText($errorPath, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    exit 1
}

try {
    $scaleX = $source.Width / $baseWidth
    $scaleY = $source.Height / $baseHeight

    function Convert-Region($region) {
        $x = [int][Math]::Round($region.X * $scaleX)
        $y = [int][Math]::Round($region.Y * $scaleY)
        $w = [int][Math]::Round($region.W * $scaleX)
        $h = [int][Math]::Round($region.H * $scaleY)
        if ($x -lt 0) { $x = 0 }
        if ($y -lt 0) { $y = 0 }
        if ($x + $w -gt $source.Width) { $w = $source.Width - $x }
        if ($y + $h -gt $source.Height) { $h = $source.Height - $y }
        return @{ X = $x; Y = $y; W = $w; H = $h }
    }

    $bands = @()
    $top = $pad
    $maxWidth = 0
    $cardIndex = 0
    foreach ($region in $cardRegions) {
        $r = Convert-Region $region
        $drawW = $r.W * $cardScale
        $drawH = $r.H * $cardScale
        $bands += @{
            Type = 'card'
            Slot = $cardIndex
            Region = $r
            Scale = $cardScale
            Top = $top
            Height = $drawH
            DrawY = $top
        }
        if ($drawW -gt $maxWidth) { $maxWidth = $drawW }
        $top += $drawH + $pad
        $cardIndex += 1
    }
    $rVote = Convert-Region $voteRegion
    $voteDrawW = $rVote.W * $voteScale
    $voteDrawH = $rVote.H * $voteScale
    $bands += @{
        Type = 'vote'
        Slot = -1
        Region = $rVote
        Scale = $voteScale
        Top = $top
        Height = $voteDrawH
        DrawY = $top
    }
    if ($voteDrawW -gt $maxWidth) { $maxWidth = $voteDrawW }
    $top += $voteDrawH + $pad

    $canvasWidth = $maxWidth + 2 * $pad
    $canvasHeight = $top
    $canvas = [System.Drawing.Bitmap]::new($canvasWidth, $canvasHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::Bilinear
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

    foreach ($band in $bands) {
        $r = $band.Region
        if ($r.W -lt 2 -or $r.H -lt 2) { continue }
        $crop = $source.Clone(
            [System.Drawing.Rectangle]::new($r.X, $r.Y, $r.W, $r.H),
            $source.PixelFormat)
        $drawW = $r.W * $band.Scale
        $drawH = $r.H * $band.Scale
        $graphics.DrawImage($crop, $pad, $band.DrawY, $drawW, $drawH)
        $crop.Dispose()
    }
    $graphics.Dispose()

    $compositePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "mmacro_cards_ocr_$PID.bmp")
    $canvas.Save($compositePath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $canvas.Dispose()
} finally {
    $source.Dispose()
}

$runtimeTypes = @(
    'Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime',
    'Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime',
    'Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime',
    'Windows.Media.Ocr.OcrEngine, Windows, ContentType=WindowsRuntime',
    'Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime'
)
foreach ($typeName in $runtimeTypes) {
    $type = [Type]::GetType($typeName)
    if ($null -eq $type) { throw "Windows OCR type unavailable: $typeName" }
}

$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.ToString() -eq 'Windows.Foundation.IAsyncOperation`1[TResult]'
    } | Select-Object -First 1
if ($null -eq $asTask) { throw 'WinRT async bridge unavailable' }

function Wait-WinRtOperation($operation, [Type]$resultType) {
    $task = $script:asTask.MakeGenericMethod(@($resultType)).Invoke($null, @($operation))
    return $task.GetAwaiter().GetResult()
}

try {
    $storageFileType = [Type]::GetType('Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime')
    $decoderType = [Type]::GetType('Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime')
    $ocrType = [Type]::GetType('Windows.Media.Ocr.OcrEngine, Windows, ContentType=WindowsRuntime')
    $languageType = [Type]::GetType('Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime')

    $file = Wait-WinRtOperation ($storageFileType::GetFileFromPathAsync($compositePath)) $storageFileType
    $stream = Wait-WinRtOperation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Wait-WinRtOperation ($decoderType::CreateAsync($stream)) $decoderType
    $bitmap = Wait-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

    # Названия карточек английские, поэтому сначала просим en-US. Если
    # языкового пакета нет, откатываемся на языки профиля пользователя.
    $engine = $null
    try {
        $language = [Activator]::CreateInstance($languageType, @('en-US'))
        $engine = $ocrType::TryCreateFromLanguage($language)
    } catch {
        $engine = $null
    }
    if ($null -eq $engine) {
        $engine = $ocrType::TryCreateFromUserProfileLanguages()
    }
    if ($null -eq $engine) { throw 'No Windows OCR language pack is available' }

    $ocrResult = Wait-WinRtOperation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

    $cardTexts = @('', '', '')
    $voteText = ''
    $voteX = 0
    $voteY = 0

    foreach ($line in $ocrResult.Lines) {
        $words = @($line.Words)
        if ($words.Count -eq 0) { continue }
        $first = $words[0].BoundingRect
        $last = $words[$words.Count - 1].BoundingRect
        $centerX = $first.X + (($last.X + $last.Width - $first.X) / 2.0)
        $centerY = $first.Y + ($first.Height / 2.0)

        foreach ($band in $bands) {
            if ($centerY -lt $band.Top -or $centerY -gt ($band.Top + $band.Height)) { continue }
            $text = $line.Text.Trim()
            if ($text -eq '') { break }
            if ($band.Type -eq 'card') {
                $index = $band.Slot
                if ($index -ge 0 -and $index -lt 3) {
                    if ($cardTexts[$index] -ne '') { $cardTexts[$index] += ' ' }
                    $cardTexts[$index] += $text
                }
            } else {
                if ($text.ToLowerInvariant().Contains('vote')) {
                    $voteText = $text
                    $relativeX = ($centerX - $pad) / $band.Scale
                    $relativeY = ($centerY - $band.DrawY) / $band.Scale
                    $voteX = [int][Math]::Round($band.Region.X + $relativeX)
                    $voteY = [int][Math]::Round($band.Region.Y + $relativeY)
                }
            }
            break
        }
    }

    $lines = @(
        "CARD1`t$($cardTexts[0])",
        "CARD2`t$($cardTexts[1])",
        "CARD3`t$($cardTexts[2])",
        "VOTE`t$voteText`t$voteX`t$voteY"
    )
    [IO.File]::WriteAllText($resultPath, ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
} catch {
    [IO.File]::WriteAllText($errorPath, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $compositePath) { Remove-Item -LiteralPath $compositePath -Force -ErrorAction SilentlyContinue }
    exit 1
}

if (Test-Path -LiteralPath $compositePath) { Remove-Item -LiteralPath $compositePath -Force -ErrorAction SilentlyContinue }
