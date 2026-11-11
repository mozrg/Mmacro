$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime

$runtimeTypes = @(
    'Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime',
    'Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime',
    'Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime',
    'Windows.Media.Ocr.OcrEngine, Windows, ContentType=WindowsRuntime'
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

if ($args.Count -lt 3 -or !(Test-Path -LiteralPath $args[0])) {
    throw 'Expected screenshot, result, and error paths'
}
$resultPath = [IO.Path]::GetFullPath($args[1])
$errorPath = [IO.Path]::GetFullPath($args[2])

try {
    $storageFileType = [Type]::GetType('Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime')
    $decoderType = [Type]::GetType('Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime')
    $ocrType = [Type]::GetType('Windows.Media.Ocr.OcrEngine, Windows, ContentType=WindowsRuntime')

    $file = Wait-WinRtOperation ($storageFileType::GetFileFromPathAsync([IO.Path]::GetFullPath($args[0]))) $storageFileType
    $stream = Wait-WinRtOperation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Wait-WinRtOperation ($decoderType::CreateAsync($stream)) $decoderType
    $bitmap = Wait-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine = $ocrType::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) { throw 'No Windows OCR language pack is available' }
    $result = Wait-WinRtOperation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    [IO.File]::WriteAllText($resultPath, $result.Text, [Text.UTF8Encoding]::new($false))
} catch {
    [IO.File]::WriteAllText($errorPath, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    exit 1
}
