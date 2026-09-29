[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GamePath = 'D:\SteamLibrary\steamapps\common\Scrap Mechanic',
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$target = Join-Path $GamePath 'Survival\Scripts\game\managers\ScannerbotManager.lua'
$source = Join-Path $PSScriptRoot 'SeekerbotRadar.lua'
$assetUpdates = @()
$assetChanged = $false
$equipmentEdits = @()
foreach ($patch in @(
    @{ File = 'SurvivalPlayer.lua'; Source = 'RadarEquipment.lua'; Marker = 'EQUIPMENT'; Class = 'SurvivalPlayer' },
    @{ File = 'tools\LogBook.lua'; Source = 'RadarLogbook.lua'; Marker = 'LOGBOOK'; Class = 'LogBook' }
)) {
    $patchTarget = Join-Path $GamePath ('Survival\Scripts\game\' + $patch.File)
    $patchText = [IO.File]::ReadAllText($patchTarget)
    $patchBegin = '-- BEGIN SEEKERBOT RADAR ' + $patch.Marker
    $patchEnd = '-- END SEEKERBOT RADAR ' + $patch.Marker
    $patchPattern = '(?s)\r?\n' + [regex]::Escape($patchBegin) + '\r?\n.*?\r?\n' + [regex]::Escape($patchEnd) + '\r?\n?'
    $patchMatches = [regex]::Matches($patchText, $patchPattern)
    if ($patchMatches.Count -gt 1 -or (($patchText.Contains($patchBegin) -or $patchText.Contains($patchEnd)) -and $patchMatches.Count -ne 1)) { throw "Invalid patch markers: $patchTarget" }
    $patchUpdated = [regex]::Replace($patchText, $patchPattern, '')
    if (-not $Uninstall) {
        if ($patchUpdated -notmatch ('function ' + $patch.Class + '\.client_onCreate\(')) { throw "Unsupported script: $patchTarget" }
        $patchUpdated += "`n$patchBegin`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot $patch.Source)).TrimEnd() + "`n$patchEnd`n"
    }
    if ($patchUpdated -ne $patchText) { $equipmentEdits += @{ Target = $patchTarget; Text = $patchUpdated } }
}
$commandTarget = Join-Path $GamePath 'Survival\Scripts\game\SurvivalGame.lua'
$commandText = [IO.File]::ReadAllText($commandTarget)
$commandPattern = '(?s)\r?\n-- BEGIN SEEKERBOT RADAR COMMANDS\r?\n.*?\r?\n-- END SEEKERBOT RADAR COMMANDS\r?\n?'
$commandMatches = [regex]::Matches($commandText, $commandPattern)
if ($commandMatches.Count -gt 1 -or (($commandText.Contains('-- BEGIN SEEKERBOT RADAR COMMANDS') -or $commandText.Contains('-- END SEEKERBOT RADAR COMMANDS')) -and $commandMatches.Count -ne 1)) {
    throw 'Invalid radar command block; refusing to edit.'
}
$commandUpdated = [regex]::Replace($commandText, $commandPattern, '')
if (-not $Uninstall) {
    if ($commandUpdated -notmatch 'function SurvivalGame.bindChatCommands\(' -or $commandUpdated -notmatch 'function SurvivalGame.cl_onChatCommand\(') { throw 'Unsupported SurvivalGame callbacks.' }
    $commandUpdated += "`n-- BEGIN SEEKERBOT RADAR COMMANDS`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RadarCommands.lua')).TrimEnd() + "`n-- END SEEKERBOT RADAR COMMANDS`n"
}
$commandChanged = $commandUpdated -ne $commandText
# Remove the obsolete custom font from the previous version, if present.
$fontTarget = Join-Path $GamePath 'Data\Gui\Language\English\Fonts.xml'
$fontText = [IO.File]::ReadAllText($fontTarget)
$fontPattern = '(?s)<!-- BEGIN SEEKERBOT RADAR FONT -->.*?<!-- END SEEKERBOT RADAR FONT -->\r?\n?'
$fontClean = [regex]::Replace($fontText, $fontPattern, '')
$fontUpdated = $fontClean
$null = [xml]$fontUpdated
$fontChanged = $fontUpdated -ne $fontText
if (-not $Uninstall) {
    foreach ($assetName in @('status-neutral.png', 'warning-text.png')) {
        $asset = Join-Path $PSScriptRoot ('assets\' + $assetName)
        $assetTarget = Join-Path $GamePath ('Survival\Gui\SeekerbotRadar\' + $assetName)
        if (-not (Test-Path -LiteralPath $asset)) { throw "Missing asset: $assetName" }
        $needsCopy = -not (Test-Path -LiteralPath $assetTarget)
        if (-not $needsCopy) {
            $needsCopy = (Get-FileHash -LiteralPath $asset).Hash -ne (Get-FileHash -LiteralPath $assetTarget).Hash
        }
        if ($needsCopy) { $assetUpdates += @{ Source = $asset; Target = $assetTarget } }
    }
    $assetChanged = $assetUpdates.Count -gt 0
}
$begin = '-- BEGIN SEEKERBOT RADAR v1'
$end = '-- END SEEKERBOT RADAR v1'
$text = [IO.File]::ReadAllText($target)
$pattern = '(?s)\r?\n' + [regex]::Escape($begin) + '\r?\n.*?\r?\n' + [regex]::Escape($end) + '\r?\n?'
$matchesFound = [regex]::Matches($text, $pattern)
if ($matchesFound.Count -gt 1) { throw 'Multiple radar blocks found; refusing to edit.' }
if (($text.Contains($begin) -or $text.Contains($end)) -and $matchesFound.Count -ne 1) {
    throw 'Incomplete radar block found; refusing to edit.'
}
$clean = [regex]::Replace($text, $pattern, '')
if ($Uninstall) {
    if ($matchesFound.Count -eq 0 -and -not $fontChanged -and -not $commandChanged -and $equipmentEdits.Count -eq 0) { Write-Output 'Seekerbot Radar is not installed.'; return }
    $updated = $clean
} else {
    foreach ($callback in @('client_onCreate', 'client_onUpdate', 'client_onClientDataUpdate')) {
        if ($clean -notmatch ('function ScannerbotManager\.' + $callback + '\(')) {
            throw "Unsupported manager: missing $callback."
        }
    }
    $updated = $clean + "`n$begin`n" + [IO.File]::ReadAllText($source).TrimEnd() + "`n$end`n"
}
if ($updated -eq $text -and -not $assetChanged -and -not $fontChanged -and -not $commandChanged -and $equipmentEdits.Count -eq 0) { Write-Output 'Seekerbot Radar is already up to date.'; return }
if (Get-Process -Name ScrapMechanic -ErrorAction SilentlyContinue) {
    throw 'Close Scrap Mechanic before installing or uninstalling.'
}
if ($PSCmdlet.ShouldProcess($target, $(if ($Uninstall) { 'Remove radar patch' } else { 'Install radar patch' }))) {
    foreach ($edit in $equipmentEdits) {
        Copy-Item -LiteralPath $edit.Target -Destination ($edit.Target + '.radar-backup-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($edit.Target, $edit.Text, [Text.UTF8Encoding]::new($false))
    }
    if ($commandChanged) {
        Copy-Item -LiteralPath $commandTarget -Destination ($commandTarget + '.radar-backup-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($commandTarget, $commandUpdated, [Text.UTF8Encoding]::new($false))
    }
    if ($fontChanged) {
        Copy-Item -LiteralPath $fontTarget -Destination ($fontTarget + '.radar-backup-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($fontTarget, $fontUpdated, [Text.UTF8Encoding]::new($false))
    }
    foreach ($assetUpdate in $assetUpdates) {
        $asset = $assetUpdate.Source
        $assetTarget = $assetUpdate.Target
        if (Test-Path -LiteralPath $assetTarget) {
            Copy-Item -LiteralPath $assetTarget -Destination ($assetTarget + '.backup-' + [guid]::NewGuid().ToString('N'))
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $assetTarget) -Force | Out-Null
        Copy-Item -LiteralPath $asset -Destination $assetTarget -Force
    }
    # Save an exact copy before each edit; uninstall removes only our marked block.
    $backup = $target + '.radar-backup-' + [guid]::NewGuid().ToString('N')
    Copy-Item -LiteralPath $target -Destination $backup
    [IO.File]::WriteAllText($target, $updated, [Text.UTF8Encoding]::new($false))
    # Rebuild cached scripts on the next launch, including after uninstall.
    $cacheTarget = Join-Path $GamePath 'Cache\Bundle\core_data.cbo'
    if (Test-Path -LiteralPath $cacheTarget -PathType Leaf) {
        $cacheBackupName = 'core_data.cbo.radar-backup-' + [guid]::NewGuid().ToString('N')
        Rename-Item -LiteralPath $cacheTarget -NewName $cacheBackupName
        Write-Output "Script cache backed up as $cacheBackupName; the game will rebuild it on launch."
    }
    Write-Output "Done. Backup: $backup"
}
