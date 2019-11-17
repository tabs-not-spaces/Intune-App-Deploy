param (
    [Parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path $_ })]
    [System.IO.FileInfo]$appConfig,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Remote', 'Local')]
    $buildFrom = "Local"
)
#region load functions
$script:cliTool = "$PSScriptRoot\bin\IntuneWinAppUtil.exe"
. $PSScriptRoot\build.functions.ps1
#endregion
#region ascii fun
$b = "IF9fX19fXyAgIF9fICBfXyAgIF9fICAgX18gICAgICAgX19fX18gICAKL1wgID09IFwgL1wgXC9cIFwgL1wgXCAvXCBcICAgICAvXCAgX18tLiAKXCBcICBfXzwgXCBcIFxfXCBcXCBcIFxcIFwgXF9fX19cIFwgXC9cIFwKIFwgXF9fX19fXFwgXF9fX19fXFwgXF9cXCBcX19fX19cXCBcX19fXy0KICBcL19fX19fLyBcL19fX19fLyBcL18vIFwvX19fX18vIFwvX19fXy8K"
Write-Host $([system.text.encoding]::UTF8.GetString([system.convert]::FromBase64String($b)))
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