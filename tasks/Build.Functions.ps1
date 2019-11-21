#region Functions
function Add-PaddFile {
    <#
    .SYNOPSIS
    This function is used to create an uncompressable padding file to address a file uplaod issu with azcopy and graph
    .DESCRIPTION
    Creates a file of SizeInBytes (max 9.1mb) at Path. If path is a folder the fill will be named dummy.dat
    .EXAMPLE
    Get-AutToken -Path c:\git\Intune-App-Deploy\Application\SamplePowerShell  -SizeInBytes 9.1MB
    #>    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $Path,
        [Parameter(Mandatory = $false)]
        $SizeInBytes
    )  
    $bytes = $SizeInBytes
    if ($bytes > 9.1mb)
    {
        $bytes = 9.1MB
    }
    if (Test-Path -PathType Container -Path $Path)
    {
        $path = Join-Path -Path $Path -ChildPath 'dummy.dat'
    }
    [System.Security.Cryptography.RNGCryptoServiceProvider] $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rndbytes = New-Object byte[] $bytes
    $rng.GetBytes($rndbytes)
    [System.IO.File]::WriteAllBytes($Path, $rndbytes)
}

function Invoke-Build {
    param (
        $appConfig
    )
    $config = Get-Content $appConfig -Raw | ConvertFrom-Yaml
    $appRoot = Split-Path $((Get-ChildItem $appConfig).FullName) -Parent
    $binPath = "$appRoot\bin"
    try {
        if (Test-Path $binPath -ErrorAction SilentlyContinue)
        {
            Remove-Item $binPath -Force -Recurse
        }
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
        get-childitem $appRoot -Exclude $appConfig.name, *.intunewin, bin | Copy-Item -Destination $binPath -Force -Verbose
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
            $proc = Start-Process -FilePath $script:cliTool -ArgumentList "-c `"$installFilePath`" -s `"$setupFile`" -o `"$outputDirectory`" -q" -Wait -PassThru -WindowStyle Hidden
            while (Get-Process -id $proc.Id -ErrorAction SilentlyContinue) {
                Start-Sleep -Seconds 2
            }
            if (Test-Path "$outputDirectory\$applicationName.intunewin")
            {
                Remove-Item "$outputDirectory\$applicationName.intunewin"
            }
           
            if (Test-Path "$outputDirectory\$intunewinFileName.intunewin") {
                Get-ChildItem -Path "$outputDirectory\$intunewinFileName.intunewin" | Rename-Item -NewName "$applicationName.intunewin" -Force
            }
            else {
                throw "*.intunewin file not found where it should be. something bad happened."
            }
        }
        else{
            throw "$installFilePath not found something bad happened."
        }
        $DetectionXML = Get-IntuneWinXML "$outputDirectory\$applicationName.intunewin" -fileName "detection.xml" -removeItem
        [int]$cSize = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        Write-Warning $cSize
        if ($cSize -lt 9.1mb)
        {
            Write-Host "File size to small adding some padding" -ForegroundColor Yellow
            Add-PaddFile -Path $outputDirectory\dummy.dat -SizeInBytes (9.2MB - $cSize)
            if (-not (Test-Path $outputDirectory\dummy.dat)) { Throw Failed to create padding file. }
            New-IntunePackage -applicationName $applicationName -installFilePath $installFilePath -setupFile $setupFile -outputDirectory $outputDirectory
        }
    }
    catch {
        Write-Warning $_.exception.message
    }
    return $(Get-ChildItem -Path "$outputDirectory\$applicationName.intunewin")
}
#endregion
