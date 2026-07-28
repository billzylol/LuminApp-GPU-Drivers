#Requires -Version 5.1
param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Vendor = "NVIDIA"
$Version = "595.79"
$AssetName = "NVCleanstall_NVIDIA_595.79_x64_dch_Desktop_Setup.exe"
$ReleaseTag = "nvidia-595.79"
$ReleaseTitle = "Lumin NVIDIA Driver 595.79"
$MaxFileSizeBytes = [int64]2147483648

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

Set-Location -LiteralPath $ScriptDir

$DriverPath = Join-Path $ScriptDir ("upload\{0}" -f $AssetName)
$ManifestPath = Join-Path $ScriptDir "driver-manifest.json"

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Get-RepositorySlugFromRemote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl
    )

    $trimmedUrl = $RemoteUrl.Trim()

    if ($trimmedUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
        return "{0}/{1}" -f $Matches.owner, $Matches.repo
    }

    throw "Unable to parse GitHub repository from remote URL: $RemoteUrl"
}

function Format-HumanReadableSize {
    param(
        [Parameter(Mandatory = $true)]
        [int64]$Bytes
    )

    $units = @("B", "KiB", "MiB", "GiB")
    $size = [double]$Bytes
    $unitIndex = 0

    while ($size -ge 1024 -and $unitIndex -lt ($units.Length - 1)) {
        $size /= 1024
        $unitIndex++
    }

    if ($unitIndex -eq 0) {
        return "{0:N0} {1}" -f $size, $units[$unitIndex]
    }

    return "{0:N2} {1}" -f $size, $units[$unitIndex]
}

function Get-UtcIso8601Timestamp {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss'Z'")
}

function New-ReleaseNotes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HumanReadableSize,
        [Parameter(Mandatory = $true)]
        [string]$Sha256,
        [Parameter(Mandatory = $true)]
        [string]$PublishedAt
    )

    return @"
# Lumin NVIDIA Driver $Version

NVIDIA GPU driver package distributed for use by LuminApp.

- Vendor: $Vendor
- Version: $Version
- File: $AssetName
- Size: $HumanReadableSize
- SHA-256: ``$Sha256``
- Published: $PublishedAt

LuminApp must verify the SHA-256 hash before executing this file.
"@
}

function ConvertTo-HashtableRecursive {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Array]) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ConvertTo-HashtableRecursive -InputObject $item
        }
        return $items
    }

    if ($InputObject -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-HashtableRecursive -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

function Update-DriverManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositorySlug,
        [Parameter(Mandatory = $true)]
        [string]$Sha256,
        [Parameter(Mandatory = $true)]
        [int64]$SizeBytes,
        [Parameter(Mandatory = $true)]
        [string]$PublishedAt
    )

    $manifest = [ordered]@{
        schemaVersion = 1
        updatedAt     = $PublishedAt
        drivers       = [ordered]@{}
    }

    if (Test-Path -LiteralPath $ManifestPath) {
        $existingRaw = Get-Content -LiteralPath $ManifestPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
            $existing = ConvertFrom-Json -InputObject $existingRaw
            $existingHashtable = ConvertTo-HashtableRecursive -InputObject $existing

            if ($existingHashtable.Contains("schemaVersion")) {
                $manifest.schemaVersion = $existingHashtable.schemaVersion
            }

            foreach ($propertyName in $existingHashtable.Keys) {
                if ($propertyName -notin @("schemaVersion", "updatedAt", "drivers")) {
                    $manifest[$propertyName] = $existingHashtable[$propertyName]
                }
            }

            if ($existingHashtable.Contains("drivers") -and $null -ne $existingHashtable.drivers) {
                foreach ($driverName in $existingHashtable.drivers.Keys) {
                    if ($driverName -ne "nvidia") {
                        $manifest.drivers[$driverName] = $existingHashtable.drivers[$driverName]
                    }
                }
            }
        }
    }

    $manifest.updatedAt = $PublishedAt
    $manifest.drivers.nvidia = [ordered]@{
        version              = $Version
        tag                  = $ReleaseTag
        assetName            = $AssetName
        downloadUrl          = "https://github.com/$RepositorySlug/releases/latest/download/$AssetName"
        versionedDownloadUrl = "https://github.com/$RepositorySlug/releases/download/$ReleaseTag/$AssetName"
        sha256               = $Sha256
        sizeBytes            = $SizeBytes
        publishedAt          = $PublishedAt
    }

    $json = ($manifest | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($ManifestPath, "$json`n", [System.Text.UTF8Encoding]::new($false))
}

function Test-GitHubReleaseExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositorySlug
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        gh release view $ReleaseTag --repo $RepositorySlug *> $null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

if (-not (Test-CommandExists -Name "git")) {
    Write-Host "Git is not installed or not available on PATH."
    Write-Host "Install Git from: https://git-scm.com/downloads"
    exit 1
}

if (-not (Test-CommandExists -Name "gh")) {
    Write-Host "GitHub CLI (gh) is not installed."
    Write-Host "Install GitHub CLI from: https://cli.github.com/"
    exit 1
}

gh auth status --hostname github.com 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub CLI is installed, but you are not authenticated."
    Write-Host "Run the following command to authenticate:"
    Write-Host ""
    Write-Host "  gh auth login"
    Write-Host ""
    exit 1
}

$remoteUrl = git remote get-url origin
Assert-LastExitCode -FailureMessage "Unable to read git remote 'origin'. Run this script inside the repository."

$repositorySlug = Get-RepositorySlugFromRemote -RemoteUrl $remoteUrl

gh repo view $repositorySlug 1>$null
Assert-LastExitCode -FailureMessage "Unable to access GitHub repository: $repositorySlug"

$isPrivate = gh repo view $repositorySlug --json isPrivate --jq .isPrivate
Assert-LastExitCode -FailureMessage "Unable to determine repository visibility for: $repositorySlug"

if ($isPrivate -eq "true") {
    Write-Warning "Repository $repositorySlug is private. Normal LuminApp users will not be able to download the file without GitHub authentication."
}

if (-not (Test-Path -LiteralPath $DriverPath)) {
    Write-Host "Place NVCleanstall_NVIDIA_595.79_x64_dch_Desktop_Setup.exe inside the upload folder."
    exit 1
}

$driverFile = Get-Item -LiteralPath $DriverPath
$sizeBytes = $driverFile.Length

if ($sizeBytes -eq 0) {
    throw "Driver file is empty: $AssetName"
}

if ($sizeBytes -ge $MaxFileSizeBytes) {
    throw "Driver file exceeds the 2 GiB GitHub release asset limit."
}

$humanReadableSize = Format-HumanReadableSize -Bytes $sizeBytes
$sha256 = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host ""
Write-Host "Repository: $repositorySlug"
Write-Host "Vendor: $Vendor"
Write-Host "Version: $Version"
Write-Host "Tag: $ReleaseTag"
Write-Host "File: $AssetName"
Write-Host "Size: $humanReadableSize"
Write-Host "SHA-256: $sha256"
Write-Host ""

if (-not $Yes) {
    $confirmation = Read-Host "Publish this NVIDIA driver? Type YES to continue:"
    if ($confirmation -ne "YES") {
        Write-Host "Publishing cancelled."
        exit 0
    }
}

$publishedAt = Get-UtcIso8601Timestamp
$releaseNotes = New-ReleaseNotes -HumanReadableSize $humanReadableSize -Sha256 $sha256 -PublishedAt $publishedAt
$releaseNotesPath = Join-Path $ScriptDir ("release-notes-{0}.md" -f $ReleaseTag)

try {
    [System.IO.File]::WriteAllText($releaseNotesPath, $releaseNotes, [System.Text.UTF8Encoding]::new($false))

    $releaseExists = Test-GitHubReleaseExists -RepositorySlug $repositorySlug

    if (-not $releaseExists) {
        gh release create $ReleaseTag `
            --title $ReleaseTitle `
            --notes-file $releaseNotesPath `
            --latest `
            --repo $repositorySlug `
            $DriverPath
        Assert-LastExitCode -FailureMessage "Failed to create GitHub release $ReleaseTag."
    }
    else {
        gh release upload $ReleaseTag `
            --clobber `
            --repo $repositorySlug `
            $DriverPath
        Assert-LastExitCode -FailureMessage "Failed to upload release asset to $ReleaseTag."

        gh release edit $ReleaseTag `
            --title $ReleaseTitle `
            --notes-file $releaseNotesPath `
            --latest `
            --repo $repositorySlug
        Assert-LastExitCode -FailureMessage "Failed to update GitHub release $ReleaseTag."
    }

    Update-DriverManifest -RepositorySlug $repositorySlug -Sha256 $sha256 -SizeBytes $sizeBytes -PublishedAt $publishedAt

    $manifestCommitSucceeded = $false
    $manifestPushSucceeded = $false

    try {
        git add -- "driver-manifest.json" "publish-nvidia-driver.ps1" "Publish NVIDIA Driver.cmd" ".gitignore" "upload/.gitkeep"
        Assert-LastExitCode -FailureMessage "Failed to stage manifest or publishing files."

        $stagedChanges = git diff --cached --name-only
        Assert-LastExitCode -FailureMessage "Failed to inspect staged changes."

        if ($stagedChanges) {
            git commit -m "Update NVIDIA driver manifest to 595.79"
            Assert-LastExitCode -FailureMessage "Failed to commit driver manifest."

            $manifestCommitSucceeded = $true

            git push
            Assert-LastExitCode -FailureMessage "Failed to push driver manifest commit."

            $manifestPushSucceeded = $true
        }
    }
    catch {
        Write-Host ""
        Write-Host "WARNING: The NVIDIA driver release was uploaded successfully,"
        Write-Host "but the manifest commit or push failed."
        Write-Host ""
        Write-Host $_.Exception.Message
        Write-Host ""
        exit 1
    }

    $releaseUrl = "https://github.com/$repositorySlug/releases/tag/$ReleaseTag"
    $latestDownloadUrl = "https://github.com/$repositorySlug/releases/latest/download/$AssetName"
    $versionedDownloadUrl = "https://github.com/$repositorySlug/releases/download/$ReleaseTag/$AssetName"

    Write-Host ""
    Write-Host "NVIDIA driver published successfully."
    Write-Host ""
    Write-Host "Repository:"
    Write-Host $repositorySlug
    Write-Host ""
    Write-Host "Release:"
    Write-Host $releaseUrl
    Write-Host ""
    Write-Host "Latest download:"
    Write-Host $latestDownloadUrl
    Write-Host ""
    Write-Host "Version-specific download:"
    Write-Host $versionedDownloadUrl
    Write-Host ""
    Write-Host "SHA-256:"
    Write-Host $sha256
    Write-Host ""

    try {
        Set-Clipboard -Value $latestDownloadUrl
    }
    catch {
        # Clipboard failure must not fail publishing.
    }

    exit 0
}
finally {
    if (Test-Path -LiteralPath $releaseNotesPath) {
        Remove-Item -LiteralPath $releaseNotesPath -Force -ErrorAction SilentlyContinue
    }
}
