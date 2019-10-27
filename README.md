# Intune-App-Deploy

A fast, reliable way to package your win32 applications and deploy them to Intune from any source - including SCCM, using Powershell & VS Code tasks!

## Whats this all about?

Think of this as streamlining your application packaging workflow - If most or all of your application packaging dev work is done in VS Code, why not build and publish locally as well?!

This repo can be used as a scaffold to very easily build and deploy win32 applications from any machine that you clone it to.

## OK, how do I get started?

- Clone the repo to your development environment
- Open the repo folder in VS Code
- Start preparing your applications in the **applications folder** (One app per folder..)
- Open the command palette (ctrl+shift+p // F1) and type **Run Task**

## Right, what tasks have we got?

### Initialize Environment

To set up your development space (Installing PowerShell modules Yaml-Powershell & AzureAD, downloading the Win32 Content Prep Tool.), select the **Initialize Environment** task.

### Build

To compile your application package into the require *.intunewin file, while in a file within the application you wish to build, select the **Build** task.

### Publish

To publish your compiled application package, while in a file within the application you wish to publish, select the **Publish** task.

You will be asked to enter Credentials to authenticate to your Azure Tenant - make sure you have correct permissions to access Intune.

### Build & Publish

Build & publish tasks in one streamlined package - for the confident amongst us.

## How do I need to set up my applications?

If you are building an application package locally, just place all your binaries / scripts within a folder inside the **applications** folder.

If you are building an application from media stored remotely, make a note of the location of the media and we will put it in the..


## App.Yaml - the secret sauce.

Once you are ready to build and deploy your package, create a file within the root of the folder named **app.yaml** and configure as you would in Intune / SCCM.

Below is a sample to use as a reference point.

``` yaml
application:
  appName: "NameOfApplication"
  publisher: "Powers-Hell"
  description: 'Description goes here'
  appUrl: "" # URL of your application package (storage blob, dropbox, whatever)
  appFile: "" # whats the file name inclusing extension
  unpack: false # true / false (if you need to unpack the remote media set to true, otherwise set to false)
  installFile: "InstallerGoesHere.exe" # what's the first file that will trigger the install (setup.exe, setup.msi, setup.ps1 etc)
  installCmdLine: "InstallerGoesHere.exe -installArgs"
  uninstallCmdLine: "InstallerGoesHere.exe -uninstallArgs"

requirements:
  runAs32: false # true / false
  minOSArch: "v10_1809" # set this to your minimum allowed win10 build

detection:
  detectionType: "file" # file / msi / registry - what you pick here is what detection method will be bundled into your application.
  file: # File or folder detection.
    path: "C:/path/to/application"
    fileOrFolderName: "filename.ext"
    fileDetectionType: "exists"
    check32BitRegOn64System: false # true / false
  
  registry: # Registry detection
    registryKeyPath: "HKLM:/software/path/application"
    registryDetectionType: "exists"
    check32BitRegOn64System: false # true / false
  
  msi: # MSI installation detection (application GUID)
    msiProductCode: "{F16BDC7C-960E-4F21-A44A-41E996D5356C}"
```