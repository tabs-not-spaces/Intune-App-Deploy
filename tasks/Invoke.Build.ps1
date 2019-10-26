param (
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ })]
    [System.IO.FileInfo]$appConfig,

    [Parameter(Mandatory = $false)]
    [ValidateSet('SCCM', 'Source')]
    $buildFrom = "Source"
)
#region load functions
. $PSScriptRoot\build.functions.ps1
#endregion
switch ($buildFrom) {
    "SCCM" {
        #region SCCM build
        if (Test-Path $appConfig -ErrorAction SilentlyContinue) {
            Invoke-Build $appConfig
        }
        break
        #endregion
    }
    "Source" {
        #region Source build
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