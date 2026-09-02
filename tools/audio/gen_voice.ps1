<#
.SYNOPSIS
  Generate NPC voice lines with Windows SAPI (System.Speech) from tools/audio/phrases.json.

  Output: audio/voice/<ru|en>/<group>/<category>_NN.wav  (PCM 16-bit mono 22050 Hz)
  RU -> "Microsoft Irina Desktop"; EN -> Zira / David alternating per phrase.
  Rate +1 for calm lines, +2..+3 for yelling (has '!' or is mostly CAPS); vendor_dark whispers slower.
  Godot re-randomizes pitch at runtime (AudioBus.npc_shout), so we keep the raw TTS here.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/audio/gen_voice.ps1
  powershell -ExecutionPolicy Bypass -File tools/audio/gen_voice.ps1 -Group cop -Lang en
#>
param(
    [string]$Group = "",
    [string]$Lang = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$phrasesPath = Join-Path $PSScriptRoot "phrases.json"
$outRoot = Join-Path $root "audio\voice"

$json = Get-Content -Raw -Encoding UTF8 $phrasesPath | ConvertFrom-Json

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })

$preferred = @{
    ru = @("Microsoft Irina Desktop")
    en = @("Microsoft Zira Desktop", "Microsoft David Desktop")
}
$cultures = @{ ru = "ru-RU"; en = "en-US" }

$fallbacks = New-Object System.Collections.Generic.List[string]

function Resolve-Voices([string]$lang) {
    $names = @()
    foreach ($n in $preferred[$lang]) {
        if ($installed | Where-Object { $_.Name -eq $n }) { $names += $n }
        else { $script:fallbacks.Add("missing voice '$n' for $lang") }
    }
    if ($names.Count -eq 0) {
        $same = $installed | Where-Object { $_.Culture.Name -like ($cultures[$lang].Substring(0, 2) + "*") }
        if ($same) {
            $names = @($same | ForEach-Object { $_.Name })
            $script:fallbacks.Add("$lang -> using culture fallback: $($names -join ', ')")
        } else {
            $names = @($installed | Select-Object -First 1 | ForEach-Object { $_.Name })
            $script:fallbacks.Add("$lang -> NO voice for culture $($cultures[$lang]); using $($names -join ', ') (wrong accent!)")
        }
    }
    return $names
}

$voices = @{ ru = @(Resolve-Voices "ru"); en = @(Resolve-Voices "en") }

$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    22050,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)

function Get-Rate([string]$text, [string]$group) {
    if ($group -eq "vendor_dark") { return 0 }
    $letters = ($text.ToCharArray() | Where-Object { [char]::IsLetter($_) })
    $upper = ($letters | Where-Object { [char]::IsUpper($_) }).Count
    $caps = ($letters.Count -gt 0) -and ($upper / [double]$letters.Count -gt 0.6)
    $bangs = ([regex]::Matches($text, "!")).Count
    if ($caps -or $bangs -ge 2) { return 3 }
    if ($bangs -ge 1) { return 2 }
    return 1
}

$count = 0
$bytes = 0L
$groups = $json.PSObject.Properties.Name
if ($Group) { $groups = $groups | Where-Object { $_ -eq $Group } }
$langs = @("ru", "en")
if ($Lang) { $langs = @($Lang) }

foreach ($g in $groups) {
    $cats = $json.$g
    foreach ($lang in $langs) {
        $dir = Join-Path $outRoot "$lang\$g"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem -Path $dir -Filter "*.wav" -ErrorAction SilentlyContinue | Remove-Item -Force
        $voiceList = @($voices[$lang])
        $vi = 0
        foreach ($cat in $cats.PSObject.Properties.Name) {
            $lines = @($cats.$cat.$lang)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $text = [string]$lines[$i]
                $voiceName = $voiceList[$vi % $voiceList.Count]
                $vi++
                $file = Join-Path $dir ("{0}_{1:D2}.wav" -f $cat, ($i + 1))
                try { $synth.SelectVoice($voiceName) } catch { $fallbacks.Add("SelectVoice($voiceName) failed: $($_.Exception.Message)") }
                $synth.Rate = Get-Rate $text $g
                $synth.Volume = 100
                $synth.SetOutputToWaveFile($file, $format)
                $synth.Speak($text)
                $synth.SetOutputToNull()
                $count++
                $bytes += (Get-Item $file).Length
                if (-not $Quiet) { Write-Host ("  {0,-2} {1,-16} {2,-14} r{3} {4}" -f $lang, $g, (Split-Path $file -Leaf), $synth.Rate, $text) }
            }
        }
    }
}

$synth.Dispose()

Write-Host ("{0} voice files, {1:N2} MB raw -> {2}" -f $count, ($bytes / 1MB), $outRoot)
# trim SAPI's silence padding + normalize (pure-stdlib Python)
$py = Get-Command py -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
if ($py) { & $py.Source (Join-Path $PSScriptRoot "trim_voice.py") $outRoot }
else { Write-Host "python not found; skipped trim_voice.py (files are untrimmed but valid)" }
if ($fallbacks.Count -gt 0) {
    Write-Host "Voice fallbacks / notes:"
    $fallbacks | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "Voice fallbacks: none"
}
