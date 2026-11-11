# PathDetect.ps1
# Отделяет красную дорожку, заполняет внутренние дырки (стрелки), рисует сетку
# и проверяет точку по клику.
#
# В окне:
#   ЛКМ     - проверить точку
#   F5      - новый снимок
#   F6 / F7 - ослабить / усилить чувствительность к красному
#   S       - настройки
#   D       - скрыть/показать сетку
#   Esc     - выход

param(
    [double]$K = 3.0,
    [switch]$NoGui,
    [int]$AutoClose = 0,
    [string]$SourceFile = "",
    [int]$X = 0,
    [int]$Y = 0,
    [int]$Width = 0,
    [int]$Height = 0,
    [double]$TopMask = 0.18,
    [double]$BottomMask = 0.15,
    [double]$RightMask = 0.18
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:k = $K
$script:shot = $null
$script:overlay = $null
$script:maskBuf = $null
$script:maskStride = 0
$script:maskW = 0
$script:maskH = 0
$script:holesBuf = $null
$script:holesStride = 0
$script:holesW = 0
$script:holesH = 0
$script:nearBuf = $null
$script:nearStride = 0
$script:nearW = 0
$script:nearH = 0
$script:pathPercent = 0
$script:showGrid = $true

$script:gridStep = 20
$script:bigStep = 60
$script:smallR = 2
$script:bigR = 5
$script:nearPx = 8
$script:topMask = $TopMask
$script:bottomMask = $BottomMask
$script:rightMask = $RightMask

$SettingsFile = Join-Path $PSScriptRoot "PathDetect.settings.txt"

function Get-Setting([string]$name) {
    switch ($name) {
        'k' { return $script:k }
        'gridStep' { return $script:gridStep }
        'bigStep' { return $script:bigStep }
        'smallR' { return $script:smallR }
        'bigR' { return $script:bigR }
        'nearPx' { return $script:nearPx }
        'topMask' { return $script:topMask }
        'bottomMask' { return $script:bottomMask }
        'rightMask' { return $script:rightMask }
    }
    return 0
}

function Set-Setting([string]$name, $value) {
    switch ($name) {
        'k' { $script:k = [double]$value }
        'gridStep' { $script:gridStep = [int]$value }
        'bigStep' { $script:bigStep = [int]$value }
        'smallR' { $script:smallR = [int]$value }
        'bigR' { $script:bigR = [int]$value }
        'nearPx' { $script:nearPx = [int]$value }
        'topMask' { $script:topMask = [double]$value / 100.0 }
        'bottomMask' { $script:bottomMask = [double]$value / 100.0 }
        'rightMask' { $script:rightMask = [double]$value / 100.0 }
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $SettingsFile)) { return }
    foreach ($line in (Get-Content -LiteralPath $SettingsFile -ErrorAction SilentlyContinue)) {
        if (-not $line) { continue }
        $pos = $line.IndexOf('=')
        if ($pos -lt 0) { continue }
        $key = $line.Substring(0, $pos).Trim()
        $val = $line.Substring($pos + 1).Trim()
        try {
            switch ($key) {
                'k' { $script:k = [double]$val }
                'gridStep' { $script:gridStep = [int]$val }
                'bigStep' { $script:bigStep = [int]$val }
                'smallR' { $script:smallR = [int]$val }
                'bigR' { $script:bigR = [int]$val }
                'nearPx' { $script:nearPx = [int]$val }
                'topMask' { $script:topMask = [double]$val }
                'bottomMask' { $script:bottomMask = [double]$val }
                'rightMask' { $script:rightMask = [double]$val }
            }
        } catch { }
    }
}

function Save-Settings {
    $lines = @(
        "k=$($script:k)",
        "gridStep=$($script:gridStep)",
        "bigStep=$($script:bigStep)",
        "smallR=$($script:smallR)",
        "bigR=$($script:bigR)",
        "nearPx=$($script:nearPx)",
        "topMask=$($script:topMask)",
        "bottomMask=$($script:bottomMask)",
        "rightMask=$($script:rightMask)"
    )
    try {
        Set-Content -LiteralPath $SettingsFile -Value $lines -Encoding UTF8
    } catch { }
}

Load-Settings

function Get-ScreenShot {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $cx = $X
    $cy = $Y
    $cw = $Width
    $ch = $Height
    if ($cw -le 0 -or $ch -le 0) {
        $cx = $bounds.X
        $cy = $bounds.Y
        $cw = $bounds.Width
        $ch = $bounds.Height
    }
    $bmp = New-Object System.Drawing.Bitmap $cw, $ch, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($cx, $cy, 0, 0, $bmp.Size)
    } finally {
        $g.Dispose()
    }
    return $bmp
}

function New-ColorMatrix($rows) {
    $m = New-Object System.Drawing.Imaging.ColorMatrix
    for ($i = 0; $i -lt 5; $i++) {
        for ($j = 0; $j -lt 5; $j++) {
            $m."Matrix$i$j" = [float]$rows[$i][$j]
        }
    }
    return $m
}

function Apply-CMatrix($src, $rows, $format = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb) {
    $dst = New-Object System.Drawing.Bitmap $src.Width, $src.Height, $format
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $ia = New-Object System.Drawing.Imaging.ImageAttributes
    try {
        $ia.SetColorMatrix((New-ColorMatrix $rows))
        $rect = New-Object System.Drawing.Rectangle 0, 0, $src.Width, $src.Height
        $g.DrawImage($src, $rect, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    } finally {
        $ia.Dispose()
        $g.Dispose()
    }
    return $dst
}

function Make-Mask($src, [double]$k) {
    $rows = @(
        @($k, $k, $k, 0, 0),
        @(-$k, -$k, -$k, 0, 0),
        @(-$k, -$k, -$k, 0, 0),
        @(0, 0, 0, 1, 0),
        @(0, 0, 0, 0, 1)
    )
    return Apply-CMatrix $src $rows
}

function Make-GreenLayer($mask) {
    # белое -> зелёное (непрозрачное), чёрное -> прозрачное
    $rows = @(
        @(0, 1, 0, 1, 0),
        @(0, 1, 0, 1, 0),
        @(0, 1, 0, 1, 0),
        @(0, 0, 0, 0, 0),
        @(0, 0, 0, 0, 1)
    )
    return Apply-CMatrix $mask $rows ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Make-DimShot($src) {
    $rows = @(
        @(0.22, 0, 0, 0, 0),
        @(0, 0.22, 0, 0, 0),
        @(0, 0, 0.22, 0, 0),
        @(0, 0, 0, 1, 0),
        @(0, 0, 0, 0, 1)
    )
    return Apply-CMatrix $src $rows ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Expand-Bmp($src, [int]$r) {
    $w = $src.Width
    $h = $src.Height
    $dst = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    try {
        $g.Clear([System.Drawing.Color]::Black)
        for ($dy = -$r; $dy -le $r; $dy++) {
            for ($dx = -$r; $dx -le $r; $dx++) {
                $g.DrawImage($src, $dx, $dy, $w, $h)
            }
        }
    } finally {
        $g.Dispose()
    }
    return $dst
}

function Read-MaskBits($bmp) {
    $w = $bmp.Width
    $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $stride = $data.Stride
    $buf = [byte[]]::new($stride * $h)
    try {
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    } finally {
        $bmp.UnlockBits($data)
    }
    return @{ Buf = $buf; Stride = $stride; W = $w; H = $h }
}

function Test-MaskPixel([int]$x, [int]$y) {
    if (-not $script:maskBuf) { return $false }
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $script:maskW -or $y -ge $script:maskH) { return $false }
    $i = $y * $script:maskStride + $x * 3
    if ($script:maskBuf[$i] -gt 128) { return $true }
    if ($script:holesBuf -and $script:holesBuf[$i] -gt 128) { return $true }
    return $false
}

# Заливка внутренних дырок (стрелок): чёрное, недостижимое от краёв маски.
function Get-HolesBitmap($maskFull) {
    $w = $maskFull.Width
    $h = $maskFull.Height
    $sw = [Math]::Max(16, [int][Math]::Round($w * 0.25))
    $sh = [Math]::Max(16, [int][Math]::Round($h * 0.25))

    $small = New-Object System.Drawing.Bitmap $sw, $sh, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.DrawImage($maskFull, 0, 0, $sw, $sh)
    $g.Dispose()

    $rect = New-Object System.Drawing.Rectangle 0, 0, $sw, $sh
    $data = $small.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $stride = $data.Stride
    $buf = [byte[]]::new($stride * $sh)
    try {
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    } finally {
        $small.UnlockBits($data)
    }
    $small.Dispose()

    $black = [bool[]]::new($sw * $sh)
    for ($y = 0; $y -lt $sh; $y++) {
        $row = $y * $stride
        $base = $y * $sw
        for ($x = 0; $x -lt $sw; $x++) {
            $black[$base + $x] = ($buf[$row + $x * 3] -le 128)
        }
    }

    $vis = [bool[]]::new($sw * $sh)
    $q = New-Object 'System.Collections.Generic.Queue[int]'

    for ($x = 0; $x -lt $sw; $x++) {
        $i = $x
        if ($black[$i] -and -not $vis[$i]) { $vis[$i] = $true; $q.Enqueue($i) }
        $i = ($sh - 1) * $sw + $x
        if ($black[$i] -and -not $vis[$i]) { $vis[$i] = $true; $q.Enqueue($i) }
    }
    for ($y = 0; $y -lt $sh; $y++) {
        $i = $y * $sw
        if ($black[$i] -and -not $vis[$i]) { $vis[$i] = $true; $q.Enqueue($i) }
        $i = $y * $sw + ($sw - 1)
        if ($black[$i] -and -not $vis[$i]) { $vis[$i] = $true; $q.Enqueue($i) }
    }

    while ($q.Count -gt 0) {
        $i = $q.Dequeue()
        $x = $i % $sw
        $y = [int](($i - $x) / $sw)
        if ($x -gt 0) {
            $j = $i - 1
            if ($black[$j] -and -not $vis[$j]) { $vis[$j] = $true; $q.Enqueue($j) }
        }
        if ($x -lt ($sw - 1)) {
            $j = $i + 1
            if ($black[$j] -and -not $vis[$j]) { $vis[$j] = $true; $q.Enqueue($j) }
        }
        if ($y -gt 0) {
            $j = $i - $sw
            if ($black[$j] -and -not $vis[$j]) { $vis[$j] = $true; $q.Enqueue($j) }
        }
        if ($y -lt ($sh - 1)) {
            $j = $i + $sw
            if ($black[$j] -and -not $vis[$j]) { $vis[$j] = $true; $q.Enqueue($j) }
        }
    }

    $holes = New-Object System.Drawing.Bitmap $sw, $sh, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $hd = $holes.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $hstride = $hd.Stride
    $hbuf = [byte[]]::new($hstride * $sh)
    for ($y = 0; $y -lt $sh; $y++) {
        $row = $y * $hstride
        $base = $y * $sw
        for ($x = 0; $x -lt $sw; $x++) {
            $o = $row + $x * 3
            if ($black[$base + $x] -and -not $vis[$base + $x]) {
                $hbuf[$o] = 255; $hbuf[$o + 1] = 255; $hbuf[$o + 2] = 255
            } else {
                $hbuf[$o] = 0; $hbuf[$o + 1] = 0; $hbuf[$o + 2] = 0
            }
        }
    }
    try {
        [System.Runtime.InteropServices.Marshal]::Copy($hbuf, 0, $hd.Scan0, $hbuf.Length)
    } finally {
        $holes.UnlockBits($hd)
    }

    $full = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g2 = [System.Drawing.Graphics]::FromImage($full)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g2.DrawImage($holes, 0, 0, $w, $h)
    $g2.Dispose()
    $holes.Dispose()
    return $full
}

function Get-PathPercent {
    if (-not $script:maskBuf) { return 0 }
    $step = 16
    $yes = 0
    $total = 0
    $buf = $script:maskBuf
    $stride = $script:maskStride
    $w = $script:maskW
    $h = $script:maskH
    $y0 = [int]($h * $script:topMask)
    $y1 = [int]($h * (1 - $script:bottomMask))
    $x1 = [int]($w * (1 - $script:rightMask))
    for ($y = 0; $y -lt $h; $y += $step) {
        if ($y -lt $y0 -or $y -ge $y1) { continue }
        $row = $y * $stride
        for ($x = 0; $x -lt $x1; $x += $step) {
            $total++
            $i = $row + $x * 3
            if ($buf[$i] -gt 128 -or $script:holesBuf[$i] -gt 128) { $yes++ }
        }
    }
    if ($total -eq 0) { return 0 }
    return [Math]::Round($yes * 100.0 / $total, 1)
}

function Draw-Grid($bmp, $fw, $fh) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $green = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 255, 80))
    $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 60, 60))
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $buf = $script:maskBuf
        $stride = $script:maskStride
        $mw = $script:maskW
        $mh = $script:maskH
        $nbuf = $script:nearBuf
        $nstride = $script:nearStride
        $nw = $script:nearW
        $nh = $script:nearH
        for ($y = 10; $y -lt $fh; $y += $script:gridStep) {
            for ($x = 10; $x -lt $fw; $x += $script:gridStep) {
                if ($y -lt $script:mt -or $y -ge ($fh - $script:mb) -or $x -ge ($fw - $script:mr)) { continue }
                if ($x -ge $mw -or $y -ge $mh) { continue }
                $isBig = (((($x - 30) % $script:bigStep) -eq 0) -and ((($y - 30) % $script:bigStep) -eq 0))
                $r = $script:smallR
                if ($isBig) { $r = $script:bigR }
                $i = $y * $stride + $x * 3
                $blocked = (($buf[$i] -gt 128) -or ($script:holesBuf[$i] -gt 128))
                if (-not $blocked -and $nbuf) {
                    $nx = [int]($x * $nw / $mw)
                    $ny = [int]($y * $nh / $mh)
                    if ($nx -ge 0 -and $ny -ge 0 -and $nx -lt $nw -and $ny -lt $nh) {
                        $blocked = ($nbuf[$ny * $nstride + $nx * 3] -gt 128)
                    }
                }
                if ($blocked) { $br = $red } else { $br = $green }
                $g.FillEllipse($br, $x - $r, $y - $r, $r * 2, $r * 2)
            }
        }
    } finally {
        $green.Dispose()
        $red.Dispose()
        $g.Dispose()
    }
}

function Build-Preview {
    $shot = $script:shot
    $fw = $shot.Width
    $fh = $shot.Height
    $script:mt = [int]($fh * $script:topMask)
    $script:mb = [int]($fh * $script:bottomMask)
    $script:mr = [int]($fw * $script:rightMask)

    $mask = Make-Mask $shot $script:k
    $bits = Read-MaskBits $mask
    $script:maskBuf = $bits.Buf
    $script:maskStride = $bits.Stride
    $script:maskW = $bits.W
    $script:maskH = $bits.H

    $holes = Get-HolesBitmap $mask
    $hb = Read-MaskBits $holes
    $script:holesBuf = $hb.Buf
    $script:holesStride = $hb.Stride
    $script:holesW = $hb.W
    $script:holesH = $hb.H

    # маска "рядом с дорожкой"
    $halfW = [int][Math]::Max(16, [Math]::Round($fw * 0.5))
    $halfH = [int][Math]::Max(16, [Math]::Round($fh * 0.5))
    $half = New-Object System.Drawing.Bitmap $halfW, $halfH, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gh = [System.Drawing.Graphics]::FromImage($half)
    $gh.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $gh.DrawImage($mask, 0, 0, $halfW, $halfH)
    $gh.Dispose()
    $nh_r = [Math]::Max(1, [int][Math]::Round($script:nearPx / 2))
    $near = Expand-Bmp $half $nh_r
    $half.Dispose()
    $nb = Read-MaskBits $near
    $near.Dispose()
    $script:nearBuf = $nb.Buf
    $script:nearStride = $nb.Stride
    $script:nearW = $nb.W
    $script:nearH = $nb.H

    $overlay = Make-DimShot $shot
    $g1 = Make-GreenLayer $mask
    $g2 = Make-GreenLayer $holes
    $mask.Dispose()
    $holes.Dispose()

    $gr = [System.Drawing.Graphics]::FromImage($overlay)
    $gr.DrawImage($g1, 0, 0)
    $gr.DrawImage($g2, 0, 0)
    $gr.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $fw, $script:mt)
    $gr.FillRectangle([System.Drawing.Brushes]::Black, 0, $fh - $script:mb, $fw, $script:mb)
    $gr.FillRectangle([System.Drawing.Brushes]::Black, $fw - $script:mr, 0, $script:mr, $fh)
    $gr.Dispose()
    $g1.Dispose()
    $g2.Dispose()

    if ($script:showGrid) {
        Draw-Grid $overlay $fw $fh
    }

    $oldOverlay = $script:overlay
    $script:overlay = $overlay
    $script:pathPercent = Get-PathPercent
    if ($oldOverlay) { $oldOverlay.Dispose() }
}

function Show-Settings($owner) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Настройки точек"
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ClientSize = New-Object System.Drawing.Size 340, 440
    $dlg.TopMost = $true

    $rows = @(
        @{ Text = 'Порог K'; Key = 'k'; Min = 0.6; Max = 10; Dec = 1; Inc = 0.1; Mul = 1 },
        @{ Text = 'Шаг мелких точек'; Key = 'gridStep'; Min = 4; Max = 100; Dec = 0; Inc = 4; Mul = 1 },
        @{ Text = 'Шаг крупных точек'; Key = 'bigStep'; Min = 4; Max = 200; Dec = 0; Inc = 10; Mul = 1 },
        @{ Text = 'Радиус мелких'; Key = 'smallR'; Min = 1; Max = 12; Dec = 0; Inc = 1; Mul = 1 },
        @{ Text = 'Радиус крупных'; Key = 'bigR'; Min = 1; Max = 20; Dec = 0; Inc = 1; Mul = 1 },
        @{ Text = 'Красная кайма, px'; Key = 'nearPx'; Min = 0; Max = 40; Dec = 0; Inc = 2; Mul = 1 },
        @{ Text = 'Зона сверху, %'; Key = 'topMask'; Min = 0; Max = 45; Dec = 0; Inc = 2; Mul = 100 },
        @{ Text = 'Зона снизу, %'; Key = 'bottomMask'; Min = 0; Max = 45; Dec = 0; Inc = 2; Mul = 100 },
        @{ Text = 'Зона справа, %'; Key = 'rightMask'; Min = 0; Max = 45; Dec = 0; Inc = 2; Mul = 100 }
    )

    $controls = @{}
    $y = 10
    foreach ($r in $rows) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.SetBounds(12, ($y + 4), 180, 20)
        $lbl.Text = $r.Text
        $dlg.Controls.Add($lbl)

        $num = New-Object System.Windows.Forms.NumericUpDown
        $num.SetBounds(200, $y, 120, 24)
        $num.Minimum = [decimal]$r.Min
        $num.Maximum = [decimal]$r.Max
        $num.DecimalPlaces = $r.Dec
        $num.Increment = [decimal]$r.Inc
        $val = [double](Get-Setting $r.Key) * $r.Mul
        if ($val -lt [double]$r.Min) { $val = [double]$r.Min }
        if ($val -gt [double]$r.Max) { $val = [double]$r.Max }
        $num.Value = [decimal]$val
        $dlg.Controls.Add($num)
        $controls[$r.Key] = $num
        $y += 40
    }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Применить"
    $ok.SetBounds(120, ($y + 10), 100, 30)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Отмена"
    $cancel.SetBounds(226, ($y + 10), 100, 30)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancel)
    $dlg.CancelButton = $cancel

    if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($r in $rows) {
            Set-Setting $r.Key ([double]$controls[$r.Key].Value)
        }
        Save-Settings
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# Без окна
# ---------------------------------------------------------------------------
if ($NoGui) {
    if ($SourceFile) {
        $script:shot = New-Object System.Drawing.Bitmap $SourceFile
    } else {
        $script:shot = Get-ScreenShot
    }
    Build-Preview
    "k=$($script:k) size=$($script:shot.Width)x$($script:shot.Height) path=$($script:pathPercent)%"
    exit 0
}

# ---------------------------------------------------------------------------
# Окно
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Path detect - отделение дорожки"
$form.Width = 1600
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$capW = $scr.Width
$capH = $scr.Height
if ($Width -gt 0 -and $Height -gt 0) {
    $capW = $Width
    $capH = $Height
}
$form.Height = [Math]::Max(420, [int](1584 * $capH / $capW) + 85)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)

$status = New-Object System.Windows.Forms.StatusStrip
$status.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$lbl = New-Object System.Windows.Forms.ToolStripStatusLabel
$lbl.ForeColor = [System.Drawing.Color]::White
$status.Items.Add($lbl) | Out-Null

$pbOverlay = New-Object System.Windows.Forms.PictureBox
$pbOverlay.Dock = 'Fill'
$pbOverlay.SizeMode = 'Zoom'
$pbOverlay.BackColor = [System.Drawing.Color]::Black
$pbOverlay.BorderStyle = 'FixedSingle'
$pbOverlay.Cursor = [System.Windows.Forms.Cursors]::Cross

$form.Controls.Add($status)
$form.Controls.Add($pbOverlay)

function Status-Text {
    return ("K={0}  дорожка {1}%  |  ЛКМ - точка; S - настройки; D - сетка; F5 - снимок; F6/F7 - порог; Esc - выход" -f $script:k, $script:pathPercent)
}

function Update-Preview([bool]$recapture) {
    if ($recapture) {
        $form.Hide()
        Start-Sleep -Milliseconds 250
        $old = $script:shot
        if ($SourceFile) {
            $script:shot = New-Object System.Drawing.Bitmap $SourceFile
        } else {
            $script:shot = Get-ScreenShot
        }
        if ($old) { $old.Dispose() }
        $form.Show()
        $form.Activate()
    }
    Build-Preview
    $pbOverlay.Image = $script:overlay
    $lbl.Text = Status-Text
}

function Test-Point([int]$ix, [int]$iy) {
    if (-not $script:maskBuf) { return "нет данных" }
    $fw = $script:shot.Width
    $fh = $script:shot.Height
    if ($ix -lt 0 -or $iy -lt 0 -or $ix -ge $fw -or $iy -ge $fh) { return "вне области" }
    if ($iy -lt $script:mt -or $iy -ge ($fh - $script:mb) -or $ix -ge ($fw - $script:mr)) {
        return ("x={0} y={1}: зона HUD (не анализируется)" -f $ix, $iy)
    }
    $blocked = Test-MaskPixel $ix $iy
    if (-not $blocked -and $script:nearBuf) {
        $nx = [int]($ix * $script:nearW / $script:maskW)
        $ny = [int]($iy * $script:nearH / $script:maskH)
        if ($nx -ge 0 -and $ny -ge 0 -and $nx -lt $script:nearW -and $ny -lt $script:nearH) {
            $blocked = ($script:nearBuf[$ny * $script:nearStride + $nx * 3] -gt 128)
        }
    }
    if ($blocked) {
        return ("x={0} y={1}: ДОРОЖКА (ставить нельзя)" -f $ix, $iy)
    }
    return ("x={0} y={1}: свободно (можно ставить)" -f $ix, $iy)
}

$pbOverlay.Add_MouseDown({
    param($sender, $e)
    $iw = $script:shot.Width
    $ih = $script:shot.Height
    if ($iw -le 0 -or $ih -le 0) { return }
    $s = [Math]::Min($sender.Width / $iw, $sender.Height / $ih)
    $ox = ($sender.Width - $iw * $s) / 2
    $oy = ($sender.Height - $ih * $s) / 2
    $ix = [int](($e.X - $ox) / $s)
    $iy = [int](($e.Y - $oy) / $s)
    $lbl.Text = (Test-Point $ix $iy)
})

$form.Add_KeyDown({
    param($sender, $e)
    switch ($e.KeyCode) {
        'Escape' { $form.Close() }
        'F5' { Update-Preview $true }
        'F6' { $script:k = [Math]::Max(1.2, $script:k - 0.4); Update-Preview $false }
        'F7' { $script:k = [Math]::Min(6.0, $script:k + 0.4); Update-Preview $false }
        'D' { $script:showGrid = -not $script:showGrid; Update-Preview $false }
        'S' { if (Show-Settings $form) { Update-Preview $false } }
    }
})

$form.Add_Shown({
    Update-Preview $true
})

if ($AutoClose -gt 0) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $AutoClose * 1000
    $timer.Add_Tick({ $form.Close() })
    $timer.Start()
}

[System.Windows.Forms.Application]::Run($form)
