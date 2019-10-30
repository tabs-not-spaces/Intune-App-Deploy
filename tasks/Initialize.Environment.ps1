#region Config
$modules = @(
    "Powershell-Yaml",
    "AzureAD"
)
$win32CliUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
$binPath = "$PSScriptRoot\bin"
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
    #region Install cli tool
    if (!(Test-Path $binPath -ErrorAction SilentlyContinue)) {
        New-Item $binPath -ItemType Directory -Force | out-null
    }
    Start-BitsTransfer $win32CliUrl -Destination "$binPath\$(Split-Path $win32CliUrl -leaf)"
    if (!(Test-Path "$binPath\$(Split-Path $win32CliUrl -leaf)" -ErrorAction SilentlyContinue)) {
        throw "CLI tool not found after download.."
    }
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
