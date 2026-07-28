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
    AssetName            = "NVCleanstall_NVIDIA_595.79_x64_dch_Notebook_Setup.exe"
    ReleaseTag           = "nvidia-595.79-notebook"
    ReleaseTitle         = "Lumin NVIDIA Driver 595.79 (Notebook)"
    ManifestDriverKey    = "nvidia-notebook"
    MissingFileMessage   = "Place NVCleanstall_NVIDIA_595.79_x64_dch_Notebook_Setup.exe inside the upload folder."
    CommitMessage        = "Update NVIDIA notebook driver manifest to 595.79"
    ReleaseNotesHeading  = "Lumin NVIDIA Driver 595.79 (Notebook)"
    ConfirmationPrompt   = "Publish this NVIDIA notebook driver? Type YES to continue:"
    SuccessMessage       = "NVIDIA notebook driver published successfully."
    MarkAsLatest         = $false
    UseLatestDownloadUrl = $false
    StagePaths           = @(
        "driver-manifest.json"
        "publish-nvidia-notebook-driver.ps1"
        "publish-nvidia-driver-common.ps1"
        "Publish NVIDIA Notebook Driver.cmd"
        ".gitignore"
        "upload/.gitkeep"
    )
}

Publish-NvidiaDriverRelease -Config $config -Yes:$Yes
