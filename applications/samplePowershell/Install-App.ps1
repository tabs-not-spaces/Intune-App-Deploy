#region Config
$appName = "Sample-App"
$logFile = "$env:temp\$appName`.log"
#endregion
#region Logging
Start-Transcript -Path $logFile -Force
#endregion

#region Process
try {
    Write-Host "Let's throw a file in the temp folder and verify it's there.."
    Get-Date | Out-File "$env:temp\$appName`.txt" -Encoding ascii -NoNewline -Force
    if (Test-Path "$env:temp\$appName`.txt" -ErrorAction SilentlyContinue) {
        Write-Host "Found the file - as expected.."
    } 
    else {
        Throw "Sample file not found.."
    }
}
catch {
    $errorMsg = $_.Exception.Message
}
finally {
    if ($errorMsg) {
        Write-Host $errorMsg
        Stop-Transcript
        throw $errorMsg
    }
    else {
        Write-Host "Script completed successfully.."
        Stop-Transcript
    }
}
#endregion