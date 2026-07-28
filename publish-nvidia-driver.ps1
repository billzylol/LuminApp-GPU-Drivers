#Requires -Version 5.1
param(
    [switch]$Yes
)

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $ScriptDir "publish-nvidia-driver-common.ps1")

$config = @{
    ScriptDir            = $ScriptDir
    Vendor               = "NVIDIA"
    Version              = "595.79"
    AssetName            = "NVCleanstall_NVIDIA_595.79_x64_dch_Desktop_Setup.exe"
    ReleaseTag           = "nvidia-595.79"
    ReleaseTitle         = "Lumin NVIDIA Driver 595.79 (Desktop)"
    ManifestDriverKey    = "nvidia"
    MissingFileMessage   = "Place NVCleanstall_NVIDIA_595.79_x64_dch_Desktop_Setup.exe inside the upload folder."
    CommitMessage        = "Update NVIDIA driver manifest to 595.79"
    ReleaseNotesHeading  = "Lumin NVIDIA Driver 595.79 (Desktop)"
    ConfirmationPrompt   = "Publish this NVIDIA desktop driver? Type YES to continue:"
    SuccessMessage       = "NVIDIA desktop driver published successfully."
    MarkAsLatest         = $true
    UseLatestDownloadUrl = $false
    RestoreLatestReleaseTag = $null
    StagePaths           = @(
        "driver-manifest.json"
        "publish-nvidia-driver.ps1"
        "publish-nvidia-driver-common.ps1"
        "Publish NVIDIA Driver.cmd"
        ".gitignore"
        "upload/.gitkeep"
    )
}

Publish-NvidiaDriverRelease -Config $config -Yes:$Yes
