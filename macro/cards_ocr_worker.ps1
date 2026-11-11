# Долгоживущий OCR-воркер карточек Summer Event.
# Один раз инициализирует System.Drawing, WinRT и OcrEngine, затем обрабатывает
# запросы из файла requestPath. AHK пишет туда путь к BMP, воркер пишет ответ
# в resultPath в том же формате, что и cards_ocr.ps1:
#   CARD1<TAB>...
#   CARD2<TAB>...
#   CARD3<TAB>...
#   VOTE<TAB>text<TAB>x<TAB>y
# При ошибке первая строка ответа: ERROR<TAB>...
#
# Аргументы: requestPath resultPath readyPath stopPath parentPid

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$requestPath = [IO.Path]::GetFullPath($args[0])
$resultPath = [IO.Path]::GetFullPath($args[1])
$readyPath = [IO.Path]::GetFullPath($args[2])
$stopPath = [IO.Path]::GetFullPath($args[3])
$parentPid = [int]$args[4]

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
$compositePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "mmacro_cards_ocr_worker_$PID.bmp")

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

$storageFileType = [Type]::GetType('Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime')
$decoderType = [Type]::GetType('Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime')
$ocrType = [Type]::GetType('Windows.Media.Ocr.OcrEngine, Windows, ContentType=WindowsRuntime')
$languageType = [Type]::GetType('Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime')

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

function Convert-Region($region, $scaleX, $scaleY, $source) {
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

function Process-CardImage($screenshotPath) {
    $source = $null
    $canvas = $null
    $graphics = $null
    $stream = $null
    $bitmap = $null
    try {
        $source = [System.Drawing.Bitmap]::FromFile($screenshotPath)
        $scaleX = $source.Width / $baseWidth
        $scaleY = $source.Height / $baseHeight

        $bands = @()
        $top = $pad
        $maxWidth = 0
        $cardIndex = 0
        foreach ($region in $cardRegions) {
            $r = Convert-Region $region $scaleX $scaleY $source
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
        $rVote = Convert-Region $voteRegion $scaleX $scaleY $source
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
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
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
        $graphics = $null
        $canvas.Save($compositePath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $canvas.Dispose()
        $canvas = $null

        $file = Wait-WinRtOperation ($storageFileType::GetFileFromPathAsync($compositePath)) $storageFileType
        $stream = Wait-WinRtOperation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Wait-WinRtOperation ($decoderType::CreateAsync($stream)) $decoderType
        $bitmap = Wait-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
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

        return @(
            "CARD1`t$($cardTexts[0])",
            "CARD2`t$($cardTexts[1])",
            "CARD3`t$($cardTexts[2])",
            "VOTE`t$voteText`t$voteX`t$voteY"
        ) -join "`r`n"
    } finally {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $canvas) { $canvas.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
        if (Test-Path -LiteralPath $compositePath) {
            Remove-Item -LiteralPath $compositePath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Прогрев пайплайна: первый вызов Process-CardImage в новом процессе заметно
# медленнее (JIT, GDI+, декодер, OCR). Готовим синтетический кадр 1280x720 и
# полностью прогоняем его через тот же путь.
$warmPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "mmacro_cards_ocr_warm_$PID.bmp")
try {
    $warmBmp = [System.Drawing.Bitmap]::new(1280, 720)
    $warmG = [System.Drawing.Graphics]::FromImage($warmBmp)
    $warmG.Clear([System.Drawing.Color]::White)
    $warmFont = [System.Drawing.Font]::new('Arial', 22)
    $warmG.DrawString('CARD1 TEST', $warmFont, [System.Drawing.Brushes]::Black, 330, 250)
    $warmG.DrawString('CARD2 TEST', $warmFont, [System.Drawing.Brushes]::Black, 550, 250)
    $warmG.DrawString('CARD3 TEST', $warmFont, [System.Drawing.Brushes]::Black, 770, 250)
    $warmG.Dispose()
    $warmFont.Dispose()
    $warmBmp.Save($warmPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $warmBmp.Dispose()
    $null = Process-CardImage $warmPath
} catch {
} finally {
    if (Test-Path -LiteralPath $warmPath) {
        Remove-Item -LiteralPath $warmPath -Force -ErrorAction SilentlyContinue
    }
}
# Готовность сообщаем только после инициализации OCR-движка.
[IO.File]::WriteAllText($readyPath, [string]$PID, [Text.UTF8Encoding]::new($false))

$parentCheck = 0
while ($true) {
    if (Test-Path -LiteralPath $stopPath) {
        Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
        break
    }
    $parentCheck += 1
    if ($parentCheck -ge 100) {
        $parentCheck = 0
        if (-not (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) { break }
    }
    if (Test-Path -LiteralPath $requestPath) {
        $imagePath = ''
        try {
            $imagePath = (Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8).Trim()
            Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
            if ($imagePath -eq '') { throw 'Empty OCR request' }
            $resultText = Process-CardImage $imagePath
        } catch {
            $resultText = "ERROR`t" + $_.Exception.Message
        }
        $tmpResult = $resultPath + '.tmp'
        [IO.File]::WriteAllText($tmpResult, ($resultText + "`r`n"), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmpResult -Destination $resultPath -Force
    }
    Start-Sleep -Milliseconds 15
}

Remove-Item -LiteralPath $readyPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
