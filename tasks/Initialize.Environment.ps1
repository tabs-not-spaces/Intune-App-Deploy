#region Config
$modules = @(
    "Powershell-Yaml",
    "AzureAD"
)
$win32CliUri = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
$azCopyUri = "https://aka.ms/downloadazcopy-v10-windows"
$binPath = "$PSScriptRoot\bin"
#endregion
#region Functions
function Get-PreReq {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.Uri]$uri,

        [parameter(Mandatory = $true)]
        [string]$fileName,

        [parameter(Mandatory = $true)]
        [System.IO.FileInfo]$outputPath,

        [parameter(Mandatory = $false)]
        [switch]$extract
    )
    try {
        if (!(Test-Path -Path "$outputPath\$fileName" -ErrorAction SilentlyContinue)) {
            Start-BitsTransfer $uri -Destination "$outputPath\$fileName"
            if (!(Test-Path -Path "$outputPath\$fileName" -ErrorAction SilentlyContinue)) {
                throw "Couldn't find media after download.."
            }
            else {
                if ($extract) {
                    Expand-Archive -Path "$outputPath\$fileName" -DestinationPath $outputPath -Force
                    Remove-Item -Path "$outputPath\$fileName" -Force | Out-Null
                }
            }
        }
    }
    catch {
        Write-Warning $_.exception.message
    }
}
#endregion
#region Install missing modules
try {
    foreach ($m in $modules) {
        if (!(get-module "$m*" -ListAvailable)) {
            Write-Host "Installing $m module to currentUser.."
            Install-Module -Name $m -Scope CurrentUser -Force
        }
    }
    #endregion
    #region Verify bin path
    if (!(Test-Path $binPath -ErrorAction SilentlyContinue)) {
        New-Item $binPath -ItemType Directory -Force | out-null
    }
    #endregion
    #region Install pre-reqs
    Get-PreReq -uri $win32CliUri -fileName $(split-path $win32CliUri -Leaf) -outputPath "$PSScriptRoot\bin"
    Get-PreReq -uri $azCopyUri -fileName "azCopy.zip" -outputPath "$PSSCriptRoot\bin" -extract
    #endregion
}
catch {
    $errorMsg = $_.exception.message
}
finally {
    if ($errorMsg) {
        Write-Warning $errorMsg
        throw $errorMsg
    }
    else {
        Write-Host "Environment configured successfully!"
    }
}
