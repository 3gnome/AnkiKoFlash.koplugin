# Create a GitHub release zip for AnkiKoFlash and publish with gh.
#
# First-time setup (once per machine):
#   gh auth login
#
# Usage:
#   .\release.ps1                     # bump patch, commit, tag, push, publish
#   .\release.ps1 -Version 1.0.4      # release a specific version
#   .\release.ps1 -PublishOnly          # publish zip for current _meta.lua version (tag must exist)
#   .\release.ps1 -DryRun               # show planned steps without changing anything
#   .\release.ps1 -NotesFile notes.md  # custom release notes body

param(
    [string]$Version = "",
    [switch]$PublishOnly,
    [switch]$DryRun,
    [switch]$SkipPush,
    [string]$NotesFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MetaFile = Join-Path $RepoRoot "_meta.lua"
$PluginFolder = "AnkiKoFlash.koplugin"
$ZipDir = Split-Path -Parent $RepoRoot

# Refresh PATH so gh is found in terminals opened before winget install.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    $ghDir = "C:\Program Files\GitHub CLI"
    if (Test-Path (Join-Path $ghDir "gh.exe")) {
        $env:Path = "$ghDir;$env:Path"
    }
}

function Write-Step([string]$Message) {
    Write-Host "==> $Message"
}

function Get-MetaVersion {
    $content = Get-Content -LiteralPath $MetaFile -Raw
    if ($content -match 'version\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    throw "Could not read version from _meta.lua"
}

function Set-MetaVersion([string]$NewVersion) {
    $content = Get-Content -LiteralPath $MetaFile -Raw
    $updated = [regex]::Replace(
        $content,
        '(version\s*=\s*")[^"]+(")',
        '${1}' + $NewVersion + '${2}',
        1
    )
    if ($updated -eq $content) {
        throw "Could not update version in _meta.lua"
    }
    Set-Content -LiteralPath $MetaFile -Value $updated -NoNewline
}

function Bump-Patch([string]$Current) {
    $parts = $Current.Split(".")
    if ($parts.Count -lt 3) {
        throw "Version must be semver-like (e.g. 1.0.3), got: $Current"
    }
    $patch = [int]$parts[-1] + 1
    $parts[-1] = [string]$patch
    return ($parts -join ".")
}

function Ensure-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Install: winget install GitHub.cli"
    }
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "gh is not authenticated. Run once: gh auth login"
    }
}

function Get-DefaultNotes([string]$Ver) {
    @"
## Install
Download ``AnkiKoFlash-v$Ver.zip``, unzip, and copy the ``AnkiKoFlash.koplugin`` folder into your KOReader ``plugins/`` directory.

See [Getting started](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/docs/getting-started.md) for setup.
"@
}

Push-Location $RepoRoot
try {
    $current = Get-MetaVersion

    if ($PublishOnly) {
        $Version = $current
        Write-Step "Publish-only mode for v$Version"
    } elseif ($Version -eq "") {
        $Version = Bump-Patch $current
        Write-Step "Bumping version $current -> $Version"
        if (-not $DryRun) {
            Set-MetaVersion $Version
            git add _meta.lua
            git commit -m "Bump version to $Version"
        }
    } else {
        Write-Step "Using version $Version"
        if ($Version -ne $current) {
            if (-not $DryRun) {
                Set-MetaVersion $Version
                git add _meta.lua
                git commit -m "Bump version to $Version"
            }
        }
    }

    $tag = "v$Version"
    $zipName = "AnkiKoFlash-v$Version.zip"
    $zipPath = Join-Path $ZipDir $zipName

    Write-Step "Building $zipName"
    if (-not $DryRun) {
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
        }
        git archive --format=zip --prefix="$PluginFolder/" -o $zipPath HEAD
        if (-not (Test-Path -LiteralPath $zipPath)) {
            throw "Zip was not created: $zipPath"
        }
    }

    $tagExists = $false
    if (-not $DryRun) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        git rev-parse "refs/tags/$tag" 2>$null | Out-Null
        $tagExists = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prevEap
    }

    if (-not $PublishOnly -and -not $tagExists) {
        Write-Step "Creating tag $tag"
        if (-not $DryRun) {
            git tag -a $tag -m "$tag"
        }
    }

    if (-not $SkipPush -and -not $PublishOnly -and -not $DryRun) {
        Write-Step "Pushing main"
        git push origin main
        if (-not $tagExists) {
            Write-Step "Pushing tag $tag"
            git push origin $tag
        }
    }

    Ensure-Gh

    $notes = if ($NotesFile -ne "" -and (Test-Path -LiteralPath $NotesFile)) {
        Get-Content -LiteralPath $NotesFile -Raw
    } else {
        Get-DefaultNotes $Version
    }

    Write-Step "Publishing GitHub release $tag"
    if ($DryRun) {
        Write-Host "Dry run complete. Would publish $zipPath as $tag"
        exit 0
    }

    $releaseExists = $false
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    gh release view $tag 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $releaseExists = $true }
    $ErrorActionPreference = $prevEap

    if ($releaseExists) {
        Write-Step "Release exists; uploading asset"
        gh release upload $tag $zipPath --clobber
    } else {
        gh release create $tag $zipPath `
            --title "$tag" `
            --notes $notes
    }

    Write-Step "Done: https://github.com/3gnome/AnkiKoFlash.koplugin/releases/tag/$tag"
    Write-Host "Zip: $zipPath"
}
finally {
    Pop-Location
}
