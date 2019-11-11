function Get-AuthToken {
    <#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $user,

        [Parameter(Mandatory = $false)]
        [switch]$refreshSession
    )
    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $user
    $tenant = $userUpn.Host
    Write-Host "Checking for AzureAD module..."
    $aadModule = Get-Module -Name "AzureAD" -ListAvailable
    if ($aadModule -eq $null) {
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $aadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }
    if ($aadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }
    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version
    if ($aadModule.count -gt 1) {
        $Latest_Version = ($aadModule | Select-Object version | Sort-Object)[-1]
        $aadModule = $aadModule | Where-Object { $_.version -eq $Latest_Version.version }
        # Checking if there are multiple versions of the same module found
        if ($aadModule.count -gt 1) {
            $aadModule = $aadModule | Select-Object -Unique
        }
        $adal = Join-Path $aadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $aadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }
    else {
        $adal = Join-Path $aadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $aadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$Tenant"
    try {
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
        # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
        if ($refreshSession) {
            $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "RefreshSession"
            
        }
        else {
            $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
        }
        $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
        $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result
        # If the accesstoken is valid then create the authentication header
        if ($authResult.AccessToken) {
            # Creating header for Authorization token
            $authHeader = @{
                'Content-Type'  = 'application/json'
                'Authorization' = "Bearer " + $authResult.AccessToken
                'ExpiresOn'     = $authResult.ExpiresOn
            }
            return $authHeader
        }
        else {
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
        }
    }
    catch {
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    }
}
function Copy-Object {
    [cmdletbinding()]
    param (
        $object
    )
    $stream = New-Object IO.MemoryStream
    $formatter = New-Object Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $formatter.Serialize($stream, $object)
    $stream.Position = 0
    $formatter.Deserialize($stream)
}
function Write-Headers {
    [cmdletbinding()]
    param (
        $authToken
    )
    foreach ($header in $authToken.GetEnumerator()) {
        if ($header.Name.ToLower() -eq "authorization") {
            continue
        }
        Write-Host -ForegroundColor Gray "$($header.Name): $($header.Value)"
    }
}
function New-GetRequest {
    [cmdletbinding()]
    param (
        $collectionPath
    )
    $uri = "$baseUrl$collectionPath"
    $request = "GET $uri"
    if ($logRequestUris) { Write-Host $request; }
    if ($logHeaders) { Write-Headers $authToken; }
    try {
        Test-AuthToken
        $response = Invoke-RestMethod $uri -Method Get -Headers $authToken
        $response
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}
function New-PatchRequest {
    [cmdletbinding()]
    param (
        $collectionPath,
        $body
    )
    New-Request "PATCH" $collectionPath $body
}
function New-PostRequest {
    [cmdletbinding()]
    param (
        $collectionPath,
        $body
    )
    New-Request "POST" $collectionPath $body
}
function New-Request {
    [cmdletbinding()]
    param (
        $verb,
        $collectionPath,
        $body
    )
    $uri = "$baseUrl$collectionPath"
    $request = "$verb $uri"
    $clonedHeaders = Copy-Object $authToken
    $clonedHeaders["content-length"] = $body.Length
    $clonedHeaders["content-type"] = "application/json"
    if ($logRequestUris) { Write-Host $request; }
    if ($logHeaders) { Write-Headers $clonedHeaders; }
    if ($logContent) { Write-Host -ForegroundColor Gray $body; }
    try {
        Test-AuthToken
        $response = Invoke-RestMethod $uri -Method $verb -Headers $clonedHeaders -Body $body
        $response
    }
    catch {
        Write-Host -ForegroundColor Red $request
        Write-Host -ForegroundColor Red $_.Exception.Message
        throw
    }
}
function Send-FileToAzureStorage {
    [cmdletbinding()]
    param (
        $sasUri,
        $filePath
    )
    try {
        $azCopy = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
        . $azCopy /Source:$filePath /Dest:$sasUri
    }
    catch {
        write-warning $_
    }
    finally {
        "File upload completed.."
    }

}
function Wait-ForFileProcessing {
    [cmdletbinding()]
    param (
        $fileUri,
        $stage
    )
    $attempts = 600
    $waitTimeInSeconds = 10
    $successState = "$($stage)Success"
    $pendingState = "$($stage)Pending"
    $failedState = "$($stage)Failed"
    $timedOutState = "$($stage)TimedOut"
    $file = $null
    while ($attempts -gt 0) {
        $file = New-GetRequest $fileUri
        if ($file.uploadState -eq $successState) {
            break
        }
        elseif ($file.uploadState -ne $pendingState) {
            Write-Host -ForegroundColor Red $_.Exception.Message
            throw "File upload state is not success: $($file.uploadState)"
        }
        Start-Sleep $waitTimeInSeconds
        $attempts--
    }
    if ($file -eq $null -or $file.uploadState -ne $successState) {
        throw "File request did not complete in the allotted time."
    }
    $file
}
function Get-Win32AppBody {
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,

        [parameter(Mandatory = $true, ParameterSetName = "EXE", Position = 1)]
        [Switch]$EXE,

        [Parameter(Mandatory = $false, ParameterSetName = "PWSH", Position = 1)]
        [switch]$PowerShell,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,

        [parameter(Mandatory = $false)]
        [ValidateSet('system', 'user')]
        $installExperience = "system",

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $setupFileName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $minOSarch,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $runAs32,

        [parameter(Mandatory = $true, ParameterSetName = "PWSH")]
        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,

        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $msiPackageType,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $msiProductCode,

        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $msiProductName,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $msiProductVersion,

        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $msiPublisher,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $msiRequiresReboot,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $msiUpgradeCode
    )
    $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
    if ($msi) {
        $body.applicableArchitectures = "x64,x86"
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.fileName = $filename
        $body.installCommandLine = "msiexec /i `"$SetupFileName`""
        $body.installExperience = @{"runAsAccount" = "$installExperience" }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{$minOSArch = $true }
        $body.msiInformation = @{
            "packageType"    = "$msiPackageType"
            "productCode"    = "$msiProductCode"
            "productName"    = "$msiProductName"
            "productVersion" = "$msiProductVersion"
            "publisher"      = "$msiPublisher"
            "requiresReboot" = "$msiRequiresReboot"
            "upgradeCode"    = "$msiUpgradeCode"
        }
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = if ($runAs32) { $true } else { $false }
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "msiexec /x `"$msiProductCode`""
    }
    elseif ($EXE) {
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.fileName = $filename
        $body.installCommandLine = "$installCommandLine"
        $body.installExperience = @{"runAsAccount" = "$installExperience" }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{$minOSArch = $true }
        $body.msiInformation = $null
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = if ($runAs32) { $true } else { $false }
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "$uninstallCommandLine"
    }
    elseif ($PowerShell) {
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.fileName = $filename
        $body.installCommandLine = "Powershell.exe -executionPolicy bypass -file './$SetupFileName'"
        $body.installExperience = @{"runAsAccount" = "$installExperience" }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{$minOSArch = $true }
        $body.msiInformation = $null
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = if ($runAs32) { $true } else { $false }
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "$uninstallCommandLine"
    }
    return $body
}
function Get-AppFileBody {
    [cmdletbinding()]
    param (
        $name,
        $size,
        $sizeEncrypted,
        $manifest
    )
    $body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" }
    $body.name = $name
    $body.size = $size
    $body.sizeEncrypted = $sizeEncrypted
    $body.manifest = $manifest
    $body.isDependency = $false
    $body
}
function Get-AppCommitBody {
    [cmdletbinding()]
    param(
        $contentVersionId,
        $LobType
    )
    $body = @{ "@odata.type" = "#$LobType" }
    $body.committedContentVersion = $contentVersionId
    $body
}
function Test-SourceFile {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $sourceFile
    )
    try {
        if (!(test-path "$sourceFile")) {
            Write-Host
            Write-Host "Source File '$sourceFile' doesn't exist..." -ForegroundColor Red
            throw
        }
    }
    catch {
        Write-Host -ForegroundColor Red $_.Exception.Message
        Write-Host
        break
    }
}
function New-DetectionRule {
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell", Position = 1)]
        [Switch]$PowerShell,
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$msi,
        [parameter(Mandatory = $true, ParameterSetName = "File", Position = 1)]
        [Switch]$File,
        [parameter(Mandatory = $true, ParameterSetName = "Registry", Position = 1)]
        [Switch]$Registry,
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptFile,
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $enforceSignatureCheck,
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $runAs32Bit,
        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        [String]$msiProductCode,
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [String]$Path,
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [string]$FileOrFolderName,
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB")]
        [string]$FileDetectionType,
        [parameter(Mandatory = $false, ParameterSetName = "File")]
        $FileDetectionValue = $null,
        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("True", "False")]
        [string]$check32BitOn64System = "False",
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryKeyPath,
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("notConfigured", "exists", "doesNotExist", "string", "integer", "version")]
        [string]$RegistryDetectionType,
        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryValue,
        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("True", "False")]
        [string]$check32BitRegOn64System = "False"
    )
    if ($PowerShell) {
        if (!(Test-Path "$ScriptFile")) {
            Write-Host
            Write-Host "Could not find file '$ScriptFile'..." -ForegroundColor Red
            Write-Host "Script can't continue..." -ForegroundColor Red
            Write-Host
            break
        }
        $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection" }
        $DR.enforceSignatureCheck = $false
        $DR.runAs32Bit = $false
        $DR.scriptContent = "$ScriptContent"
    }
    elseif ($msi) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection" }
        $DR.productVersionOperator = "notConfigured"
        $DR.productCode = "$msiProductCode"
        $DR.productVersion = $null
    }
    elseif ($File) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection" }
        $DR.check32BitOn64System = "$check32BitOn64System"
        $DR.detectionType = "$FileDetectionType"
        $DR.detectionValue = $FileDetectionValue
        $DR.fileOrFolderName = "$FileOrFolderName"
        $DR.operator = "notConfigured"
        $DR.path = "$Path"
    }
    elseif ($Registry) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppRegistryDetection" }
        $DR.check32BitOn64System = "$check32BitRegOn64System"
        $DR.detectionType = "$RegistryDetectionType"
        $DR.detectionValue = ""
        $DR.keyPath = "$RegistryKeyPath"
        $DR.operator = "notConfigured"
        $DR.valueName = "$RegistryValue"
    }
    return $DR
}
function Get-DefaultReturnCodes {
    $returnCodes = @(
        @{
            "returnCode" = 0
            "type"       = "success" 
        },
        @{
            "returnCode" = 1707
            "type"       = "success" 
        }, 
        @{
            "returnCode" = 3010
            "type"       = "softReboot" 
        }, 
        @{
            "returnCode" = 1641
            "type"       = "hardReboot" 
        },
        @{
            "returnCode" = 1618
            "type"       = "retry" 
        }
    )
    return $returnCodes
}
function New-ReturnCode {
    param
    (
        [parameter(Mandatory = $true)]
        [int]$returnCode,
        [parameter(Mandatory = $true)]
        [ValidateSet('success', 'softReboot', 'hardReboot', 'retry')]
        $type
    )
    @{
        "returnCode" = $returnCode 
        "type"       = "$type"
    }
}
function Get-IntuneWinXML {
    param
    (
        [Parameter(Mandatory = $true)]
        $sourceFile,
        [Parameter(Mandatory = $true)]
        $fileName,
        [Parameter(Mandatory = $false)]
        [switch]$removeItem
    )
    Test-SourceFile "$sourceFile"
    $Directory = [System.IO.Path]::GetDirectoryName("$sourceFile")
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$sourceFile")
    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$filename", $true)
    }
    $zip.Dispose()
    [xml]$IntuneWinXML = Get-Content "$Directory\$filename"
    if ($removeItem) {
        remove-item "$Directory\$filename"
    }
    return $IntuneWinXML
}
function Get-IntuneWinFile {
    param
    (
        [Parameter(Mandatory = $true)]
        $sourceFile,

        [Parameter(Mandatory = $true)]
        $fileName,

        [Parameter(Mandatory = $false)]
        [string]$Folder = "win32"
    )
    $Directory = [System.IO.Path]::GetDirectoryName("$sourceFile")
    if (!(Test-Path "$Directory\$folder")) {
        New-Item -ItemType Directory -Path "$Directory" -Name "$folder" | Out-Null
    }
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$sourceFile")
    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$folder\$filename", $true)
    }
    $zip.Dispose()
    return "$Directory\$folder\$filename"
}
function Publish-Win32Lob {
    <#
    .SYNOPSIS
    This function is used to upload a Win32 Application to the Intune Service
    .DESCRIPTION
    This function is used to upload a Win32 Application to the Intune Service
    .EXAMPLE
    Upload-Win32Lob "C:\Packages\package.intunewin" -publisher "Microsoft" -description "Package"
    This example uses all parameters required to add an intunewin File into the Intune Service
    .NOTES
    NAME: Upload-Win32LOB
    #>
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$sourceFile,
        
        [parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,
        
        [parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,
        
        [parameter(Mandatory = $true, Position = 3)]
        [ValidateNotNullOrEmpty()]
        [string]$description,
        
        [parameter(Mandatory = $true, Position = 4)]
        [ValidateNotNullOrEmpty()]
        $detectionRules,
        
        [parameter(Mandatory = $true, Position = 5)]
        [ValidateNotNullOrEmpty()]
        $returnCodes,
        
        [parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullOrEmpty()]
        [string]$installCmdLine,
        
        [parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullOrEmpty()]
        [string]$uninstallCmdLine,

        [parameter(Mandatory = $false, Position = 8)]
        [ValidateNotNullOrEmpty()]
        [string]$minOSArch,

        [parameter(Mandatory = $false, Position = 9)]
        [ValidateNotNullOrEmpty()]
        [string]$runAs32,
        
        [parameter(Mandatory = $false, Position = 10)]
        [ValidateSet('system', 'user')]
        $installExperience = "system"
    )
    try	{
        $LOBType = "microsoft.graph.win32LobApp"
        Write-Host "Testing if SourceFile '$sourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$sourceFile"
        $Win32Path = "$sourceFile"
        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow
        # Funciton to read Win32LOB file
        $DetectionXML = Get-IntuneWinXML "$sourceFile" -fileName "detection.xml" -removeItem
        # If displayName input don't use Name from detection.xml file
        if ($displayName) { $DisplayName = $displayName }
        else { $DisplayName = $DetectionXML.ApplicationInfo.Name }
        $FileName = $DetectionXML.ApplicationInfo.FileName
        $SetupFileName = $DetectionXML.ApplicationInfo.SetupFile
        $Ext = [System.IO.Path]::GetExtension($SetupFileName)
        if ((($Ext).contains("msi") -or ($Ext).contains("Msi")) -and (!$installCmdLine -or !$uninstallCmdLine)) {
            # MSI
            $msiExecutionContext = $DetectionXML.ApplicationInfo.MsiInfo.MsiExecutionContext
            $msiPackageType = "DualPurpose"
            if ($msiExecutionContext -eq "System") { $msiPackageType = "PerMachine" }
            elseif ($msiExecutionContext -eq "User") { $msiPackageType = "PerUser" }
            $msiProductCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
            $msiProductVersion = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductVersion
            $msiPublisher = $DetectionXML.ApplicationInfo.MsiInfo.MsiPublisher
            $msiRequiresReboot = $DetectionXML.ApplicationInfo.MsiInfo.MsiRequiresReboot
            $msiUpgradeCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiUpgradeCode
            if ($msiRequiresReboot -eq "false") { $msiRequiresReboot = $false }
            elseif ($msiRequiresReboot -eq "true") { $msiRequiresReboot = $true }
            $mobileAppParams = @{
                MSI               = $true
                displayName       = "$DisplayName"
                publisher         = "$publisher"
                description       = $description
                filename          = $FileName
                SetupFileName     = "$SetupFileName"
                installExperience = $installExperience
                minOSArch         = $minOSArch
                runAs32           = $runAs32
                MsiPackageType    = $msiPackageType
                MsiProductCode    = $msiProductCode
                MsiProductName    = $displayName
                MsiProductVersion = $msiProductVersion
                MsiPublisher      = $msiPublisher
                MsiRequiresReboot = $msiRequiresReboot
                MsiUpgradeCode    = $msiUpgradeCode
            }
            $mobileAppBody = Get-Win32AppBody @mobileAppParams
        }
        else {
            $mobileAppParams = @{
                EXE                  = $true
                displayName          = $displayName
                publisher            = $publisher
                description          = $description
                filename             = $fileName
                setupFileName        = $SetupFileName
                installCommandLine   = $installCmdLine
                installExperience    = $installExperience
                uninstallCommandLine = $uninstallCmdLine
                minOSArch            = $minOSArch
                runAs32              = $runAs32
            }
            $mobileAppBody = Get-Win32AppBody @mobileAppParams
        }
        if ($DetectionRules.'@odata.type' -contains "#microsoft.graph.win32LobAppPowerShellScriptDetection" -and @($DetectionRules).'@odata.type'.Count -gt 1) {
            Write-Host
            Write-Warning "A Detection Rule can either be 'Manually configure detection rules' or 'Use a custom detection script'"
            Write-Warning "It can't include both..."
            Write-Host
            break
        }
        else {
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'detectionRules' -Value $detectionRules
        }
        #ReturnCodes
        if ($returnCodes) {
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'returnCodes' -Value @($returnCodes)
        }
        else {
            Write-Host
            Write-Warning "Intunewin file requires ReturnCodes to be specified"
            Write-Warning "If you want to use the default ReturnCode run 'Get-DefaultReturnCodes'"
            Write-Host
            break
        }
        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
        $mobileApp = New-PostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json)
        # Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
        $appId = $mobileApp.id
        $contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions"
        $contentVersion = New-PostRequest $contentVersionUri "{}"
        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Getting Encryption Information for '$sourceFile'..." -ForegroundColor Yellow
        $encryptionInfo = @{ }
        $encryptionInfo.encryptionKey = $DetectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
        $encryptionInfo.macKey = $DetectionXML.ApplicationInfo.EncryptionInfo.macKey
        $encryptionInfo.initializationVector = $DetectionXML.ApplicationInfo.EncryptionInfo.initializationVector
        $encryptionInfo.mac = $DetectionXML.ApplicationInfo.EncryptionInfo.mac
        $encryptionInfo.profileIdentifier = "ProfileVersion1"
        $encryptionInfo.fileDigest = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigest
        $encryptionInfo.fileDigestAlgorithm = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm
        $fileEncryptionInfo = @{ }
        $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo
        # Extracting encrypted file
        $IntuneWinFile = Get-IntuneWinFile "$sourceFile" -fileName "$filename"
        [int64]$Size = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        $EncrySize = (Get-Item "$IntuneWinFile").Length
        # Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
        $contentVersionId = $contentVersion.id
        $fileBody = Get-AppFileBody "$FileName" $Size $EncrySize $null
        $filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files"
        $file = New-PostRequest $filesUri ($fileBody | ConvertTo-Json)
        # Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
        $fileId = $file.id
        $fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId"
        $file = Wait-ForFileProcessing $fileUri "AzureStorageUriRequest"
        # Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage..." -f Yellow
        $sasUri = $file.azureStorageUri
        Send-FileToAzureStorage -sasUri $file.azureStorageUri -filePath "$IntuneWinFile"
        # Need to Add removal of IntuneWin file
        $IntuneWinFolder = [System.IO.Path]::GetDirectoryName("$IntuneWinFile")
        Remove-Item "$(split-path $IntuneWinFile -Parent)" -Recurse -Force
        #Remove-Item "$IntuneWinFile" -Force
        # Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
        $commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit"
        New-PostRequest $commitFileUri ($fileEncryptionInfo | ConvertTo-Json)
        # Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
        $file = Wait-ForFileProcessing $fileUri "CommitFile"
        # Commit the app.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
        $commitAppUri = "mobileApps/$appId"
        $commitAppBody = Get-AppCommitBody $contentVersionId $LOBType
        New-PatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json)
        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host
    }
    catch {
        Write-Host ""
        Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())"
    }
}
function Test-AuthToken {
    param (
        $user
    )
    # Checking if authToken exists before running authentication
    if ($global:authToken) {
        # Setting DateTime to Universal time to work in all timezones
        $DateTime = (Get-Date).ToUniversalTime()
        # If the authToken exists checking when it expires
        $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes
        if ($TokenExpires -le 0) {
            write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
            write-host
            # Defining Azure AD tenant name, this is the name of your Azure Active Directory (do not use the verified domain name)
            $global:authToken = Get-AuthToken -User $script:user
        }
    }
    else {
        # Getting the authorization token
        $global:authToken = Get-AuthToken -User $script:User
    }
}