param (
    $appConfig,
    $upn
)
#region load the functions
. $PSScriptRoot\deploy.functions.ps1
#endregion
#region Config
$script:baseUrl = "https://graph.microsoft.com/beta/deviceAppManagement/"
$script:logRequestUris = $true;
$script:logHeaders = $false;
$script:logContent = $true;
$script:azureStorageUploadChunkSizeInMb = 6l;
$script:sleep = 30
$config = Get-Content $appConfig -raw | ConvertFrom-Yaml
$appRoot = Split-Path $appConfig -Parent
#endregion

#region make sure modules are installed..
if (!(get-module Powershell-Yaml -ListAvailable)) {
    Write-Host "Installing Powershell-Yaml module to currentUser.."
    Install-Module -Name Powershell-Yaml -Scope CurrentUser -Force
}
#endregion

#region prep authentication and source file..
Test-AuthToken -user $upn
$sourceFile = "$appRoot\$($config.application.appName)`.intunewin"
$detectionXml = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"
#endregion

#region set up the detection method
switch ($config.detection.detectionType) {
    "file" {
        $dtParam = @{
            file                 = $true
            Path                 = $config.detection.file.path
            FileOrFolderName     = $config.detection.file.fileOrFolderName
            FileDetectionType    = $config.detection.file.fileDetectionType
            check32BitOn64System = $config.detection.file.check32BitRegOn64System
        }
        break
    }
    "registry" {
        $dtParam = @{
            registry                = $true
            registryKeyPath         = $config.detection.registry.registryKeyPath
            registryDetectionType   = $config.detection.registry.registryDetectionType
            check32BitRegOn64System = $config.detection.registry.check32BitRegOn64System
        }
        break
    }
    "msi" {
        $dtParam = @{
            msi            = $true
            msiProductCode = $config.detection.msi.msiProductCode
        }
        break
    }
    default {
        throw "incorrect detection type.."
        break
    }
}
$DetectionRule = New-DetectionRule @dtParam
$ReturnCodes = Get-DefaultReturnCodes
#endregion

#region Publish package
$publishParam = @{
    sourceFile        = $sourceFile
    displayName       = $config.application.appName
    publisher         = $config.application.publisher
    description       = $config.application.description
    minOSArch         = $config.requirements.minOSArch
    runAs32           = $config.requirements.runAs32
    detectionRules    = @($DetectionRule)
    returnCodes       = $ReturnCodes
    installCmdLine    = $config.application.installCmdLine
    uninstallCmdLine  = $config.application.uninstallCmdLine
    installExperience = "system"
}
Publish-Win32Lob @publishParam
#endregion