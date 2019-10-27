#region Functions
function Invoke-Build {
    param (
        $appConfig
    )
    $config = Get-Content $appConfig -Raw | ConvertFrom-Json
    $appRoot = Split-Path $((Get-ChildItem $appConfig).FullName) -Parent
    $binPath = "$appRoot\bin"
    if (!(Test-Path $binPath -ErrorAction SilentlyContinue)) {
        new-item $binPath -ItemType Directory -Force | Out-Null
    }
    Get-InstallMedia -url $config.appUrl -downloadPath "$env:temp\$($config.appFile)"
    if ($config.unpack) {
        Expand-Archive -Path "$env:temp\$($config.appFile)" -DestinationPath $binPath
        try {
            Rename-Item "$binPath\$($config.appFile -replace '.zip')"-NewName "$($config.appFile.Replace(' ','_') -replace '.zip')" -ErrorAction SilentlyContinue
        }
        catch {
            Write-Debug "Folder naming is good - no need to rename.."
        }
        $binPath = "$binPath\$($config.appFile.Replace(' ','_') -replace '.zip')"
    }
    else {
            
        Move-Item -Path "$env:temp\$($config.appFile)" -Destination $binPath
    }
    $param = @{
        applicationName = $config.appName
        installFilePath = $binPath
        setupFile       = $config.installFile
        outputDirectory = $appRoot
    }
    Push-Location $binPath
    New-IntunePackage @param
    Pop-Location
}
function Get-InstallMedia {
    param (
        $url,
        $downloadPath
    )
    try {
        Write-Host "Downloading Media.."
        Invoke-WebRequest $url -UseBasicParsing -OutFile $downloadPath
    }
    catch {
        write-host $_.exception.message
    }
}
function New-IntunePackage {
    param (
        [string]$applicationName,
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ })]
        [string]$installFilePath,
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path $_ })]
        [System.IO.FileInfo]$setupFile,
        [Parameter(Mandatory = $true)]
        [string]$outputDirectory
    )
    try {
        $exePath = "$PSScriptRoot\bin\IntuneWinAppUtil.exe"
        $intunewinFileName = $setupFile.BaseName
        if (!(Test-Path $exePath)) {
            throw "IntuneWinAppUtil.exe not found at expected location.."
        }
        if (!($outputDirectory)) {
            New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
        }
        if (!($applicationName)) {
            $applicationName = "NewApplication_$(get-date -Format yyyyMMddhhmmss)"
            Write-Host "No application name given..`nGenerated name: $applicationName" -ForegroundColor Black -BackgroundColor Green
        }
        if (Test-Path -Path $installFilePath) {
            Write-Host "Creating installation media.." -ForegroundColor Black -BackgroundColor Green
            $proc = Start-Process -FilePath $exePath -ArgumentList "-c `"$installFilePath`" -s `"$setupFile`" -o `"$outputDirectory`" -q" -Wait -PassThru -WindowStyle Hidden
            while (Get-Process -id $proc.Id -ErrorAction SilentlyContinue) {
                Start-Sleep -Seconds 2
            }
            if (Test-Path "$outputDirectory\$intunewinFileName.intunewin") {
                Get-ChildItem -Path "$outputDirectory\$intunewinFileName.intunewin" | Rename-Item -NewName "$applicationName.intunewin" -Force
                return $(Get-ChildItem -Path "$outputDirectory\$applicationName.intunewin")
            }
            else {
                throw "*.intunewin file not found where it should be. something bad happened."
            }
        }
    }
    catch {
        Write-Warning $_.exception.message
    }
}
#endregion