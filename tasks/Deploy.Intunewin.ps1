param (
    $appConfig,
    $user
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
$script:user = $user
$script:azCopy = (Get-ChildItem "$PSScriptRoot\bin\azcopy_windows_amd64_*\azCopy.exe").FullName
$config = Get-Content $appConfig -raw | ConvertFrom-Yaml
$appRoot = Split-Path $appConfig -Parent
#endregion
#region ascii fun
$p = 'CiBfX19fX18gIF9fICBfXyAgIF9fX19fXyAgIF9fICAgICAgIF9fICAgX19fX19fICAgX18gIF9fICAgIAovXCAgPT0gXC9cIFwvXCBcIC9cICA9PSBcIC9cIFwgICAgIC9cIFwgL1wgIF9fX1wgL1wgXF9cIFwgICAKXCBcICBfLS9cIFwgXF9cIFxcIFwgIF9fPCBcIFwgXF9fX19cIFwgXFwgXF9fXyAgXFwgXCAgX18gXCAgCiBcIFxfXCAgIFwgXF9fX19fXFwgXF9fX19fXFwgXF9fX19fXFwgXF9cXC9cX19fX19cXCBcX1wgXF9cIAogIFwvXy8gICAgXC9fX19fXy8gXC9fX19fXy8gXC9fX19fXy8gXC9fLyBcL19fX19fLyBcL18vXC9fLyAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCg=='
Write-Host $([system.text.encoding]::UTF8.GetString([system.convert]::FromBase64String($p)))
#endregion
#region prep authentication and source file..
Test-AuthToken -user $script:user
$sourceFile = "$appRoot\$($config.application.appName)`.intunewin"
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