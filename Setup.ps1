param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
try {
    $steamRoots = @(
        (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    ) | Where-Object { $_ } | Select-Object -Unique
    $libraries = @($steamRoots)
    foreach ($root in $steamRoots) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    $games = @($libraries | Select-Object -Unique | ForEach-Object {
        $candidate = Join-Path $_ 'steamapps\common\Scrap Mechanic'
        if (Test-Path -LiteralPath (Join-Path $candidate 'Survival\Scripts\game\SurvivalGame.lua')) { $candidate }
    })
    if ($games.Count -eq 1) {
        $gamePath = $games[0]
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Select your Scrap Mechanic game folder'
        $picker.ShowNewFolderButton = $false
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
        $gamePath = $picker.SelectedPath
        $picker.Dispose()
    }
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'Survival\Scripts\game\SurvivalGame.lua'))) {
        throw 'That folder does not contain Scrap Mechanic Survival.'
    }
    Write-Host "Game folder: $gamePath"
    & (Join-Path $PSScriptRoot 'Install.ps1') -GamePath $gamePath -Uninstall:$Uninstall
    if (-not $Uninstall) { Write-Host 'Ready! Start the game and turn Seekerbot Radar ON in the logbook (L).' }
} catch {
    Write-Host "Could not finish: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
