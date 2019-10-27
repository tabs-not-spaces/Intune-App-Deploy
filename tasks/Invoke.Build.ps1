param (
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ })]
    [System.IO.FileInfo]$appConfig,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Remote', 'Local')]
    $buildFrom = "Local"
)
#region load functions
. $PSScriptRoot\build.functions.ps1
#endregion
switch ($buildFrom) {
    "Remote" {
        #region remote build
        if (Test-Path $appConfig -ErrorAction SilentlyContinue) {
            Invoke-Build $appConfig
        }
        break
        #endregion
    }
    "Local" {
        #region local build
        if (Test-Path $appConfig -ErrorAction SilentlyContinue) {
            $appRoot = Split-Path $appConfig -Parent
            $config = get-content $appConfig -raw | ConvertFrom-Yaml
            $param = @{
                applicationName = $config.application.appName
                installFilePath = $appRoot
                setupFile       = $config.application.installFile
                outputDirectory = $appRoot
            }
            Push-Location $appRoot
            New-IntunePackage @param
            Pop-Location
        }
        break
        #endregion
    }
    "default" {
        throw "This aint it chief.."
    }
}