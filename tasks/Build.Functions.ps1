#region Functions
function Invoke-Build {
    param (
        $appConfig
    )
    $config = Get-Content $appConfig -Raw | ConvertFrom-Yaml
    $appRoot = Split-Path $((Get-ChildItem $appConfig).FullName) -Parent
    $binPath = "$appRoot\bin"
    try {
        if (!(Test-Path $binPath -ErrorAction SilentlyContinue)) {
            new-item $binPath -ItemType Directory -Force | Out-Null
        }
        if (Test-Path -Path $env:temp\$($config.application.appFile) -ErrorAction SilentlyContinue) {
            Write-Host "Found install media locally - will not download.."
        }
        else {
            Get-InstallMedia -url $config.application.appUrl -downloadPath "$env:temp\$($config.application.appFile)"
        }
        if ($config.application.unpack) {
            Expand-Archive -Path "$env:temp\$($config.application.appFile)" -DestinationPath $binPath
            try {
                Rename-Item "$binPath\$($config.application.appFile -replace '.zip')"-NewName "$($config.application.appFile.Replace(' ','_') -replace '.zip')" -ErrorAction SilentlyContinue
            }
            catch {
                Write-Debug "Folder naming is good - no need to rename.."
            }
            $binPath = "$binPath\$($config.application.appFile.Replace(' ','_') -replace '.zip')"
        }
        else {

            Move-Item -Path "$env:temp\$($config.application.appFile)" -Destination $binPath
        }
        $param = @{
            applicationName = $config.application.appName
            installFilePath = $binPath
            setupFile       = $config.application.installFile
            outputDirectory = $appRoot
        }
        Push-Location $binPath
        New-IntunePackage @param
        Pop-Location
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}
function Get-InstallMedia {
    param (
        $url,
        $downloadPath
    )
    try {
        Write-Host "Downloading Media.."
        Start-BitsTransfer $url -Destination $downloadPath
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
        $intunewinFileName = $setupFile.BaseName
        if (!(Test-Path $script:cliTool)) {
            throw "IntuneWinAppUtil.exe not found at expected location.."
        }
        if (!($outputDirectory)) {
            New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
        }
        if (!($applicationName)) {
            $applicationName = "NewApplication_$(get-date -Format yyyyMMddhhmmss)"
            Write-Host "No application name given..`nGenerated name: $applicationName" -ForegroundColor Yellow
        }
        if (Test-Path -Path $installFilePath) {
            Write-Host "Creating installation media.." -ForegroundColor Yellow
            $proc = Start-Process -FilePath $script:cliTool -ArgumentList "-c `"$installFilePath`" -s `"$setupFile`" -o `"$outputDirectory`"" -Wait -PassThru -WindowStyle Normal
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