$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
function Export-LogoSize([string]$source, [string]$target, [int]$size, [double]$fraction, [bool]$white) {
    $original = [System.Drawing.Image]::FromFile($source)
    $canvas = New-Object System.Drawing.Bitmap($size, $size)
    $drawing = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $drawing.Clear($(if ($white) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Transparent }))
        $drawing.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $length = [int]($size * $fraction)
        $offset = [int](($size - $length) / 2)
        $drawing.DrawImage($original, $offset, $offset, $length, $length)
        $canvas.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $drawing.Dispose(); $canvas.Dispose(); $original.Dispose() }
}
foreach ($app in @('child', 'parent')) {
    $source = Join-Path $projectRoot "apps/$app/assets/branding/$app-logo.png"
    $resource = Join-Path $projectRoot "apps/$app/android/app/src/main/res"
    foreach ($entry in @{ 'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192 }.GetEnumerator()) {
        Export-LogoSize $source (Join-Path $resource "mipmap-$($entry.Key)/ic_launcher.png") $entry.Value 0.88 $true
    }
    # Adaptive icon foregrounds need a wide inset to survive all launcher masks.
    Export-LogoSize $source (Join-Path $resource 'drawable-nodpi/brand_launcher_foreground.png') 432 0.62 $false
}
