#
# Author: Dominic Chan (dominic.chan@tataoui.com)
# Date: 2020-11-11
# Last Update: 2020-11-28
#
# Description:
# Windows / Linux OS unattended installation with VMware tools and post installation tasks.
# - tested on Windows 2016, 2019, 10, and CentOS 8.2 (server)
# 
# Powershell environment prerequisites:
# 1. Powershell version: 5.1.14393.3866
# 2. PowerCLI Version: 12.1.0.16997582
# 3. ImportExcel: 7.1.0
#    Install-Module -Name ImportExcel -RequiredVersion 7.1.0
#
# Prerequisites:
# 1. Windows ADK installed in the default installation path. (Only need to pick Deployment Tools during install)
#    https://developer.microsoft.com/en-us/windows/hardware/windows-assessment-deployment-kit
# 2. mkisofs-md5 download and available on the system
#    https://sourceforge.net/projects/mkisofs-md5/ and http://www.thecomputermanual.com/iso-file-or-iso-image/
# 3. Obtain Windows ISOs (Server and/or desktop)
#    Determine your current build - (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ReleaseId).ReleaseId
#    https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016/
#    https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019
# 4. Obtain Linux ISOs (RHEL and/or CentOS)
#    http://isoredirect.centos.org/centos/8/isos/x86_64/
# 5. Identify the URL of the VMware tools ISO matching the version to be installed in Windows.
#    https://packages.vmware.com/tools/esx/index.html
#
# 5b. Identify the URL of the VMware tools ISO matching the version to be installed in Linux.
#    https://packages.vmware.com/tools/esx/index.html
#
# 6. Working vCenter with an availability Content Library to host the custom ISO and template
# 7. Available datastore storage to host your VM during the build
#
# 8. In addition, the following binaries would be required based on your deployment use case
#    - VMware OS Optimization Tool
#    - VMware Dynamic Environment Agent
#    - VMware App Volume Agent
#
# Note: All Windows VMs are deploy using UEFI, while Linux VMs are deploy with BIOS
#
# Todo:
# 1. CentOS desktop deployment, currently only supporting server
# 2. Include Ubuntu option
# 3. NSX-T integration
#
# Customize the section below based on your environment
#
$DataSourcePath = "G:\Transfer\VMware.xlsx" # Path to Excel Worksheet as the data sources
# Import-Excel -Path $Path -WorksheetName 'VM Templates' -StartRow 1 | Out-GridView
# Get-VM | Export-Excel -Path $Path -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -ClearSheet -WorksheetName 'Deploy VM'
$InfraParameters = Import-Excel -Path $DataSourcePath -WorksheetName 'Infra'
$EmailParameters = Import-Excel -Path $DataSourcePath -WorksheetName 'Email'
$VMParameters = Import-Excel -Path $DataSourcePath -WorksheetName 'VM Templates'

$DataSource = Read-Host -Prompt 'Using static preset inputs or import from Excel? (S/E)'

if ($DataSource -eq 'S') {
    $VCSAIPAddress = '192.168.10.223'
    $VCSASSODomainName = 'vsphere.local'
    $VCSASSOPassword = 'VMware1!'
    $strESXHost = 'esx01.tataoui.com'

    $strO365Username = 'dominic.chan@tataoui.com' # Office 365 username
    $strO365Password = 'Mayflower#0322' # Office 365 Password ##########################
    $strSMTPServer = 'smtp.office365.com' # SMTP Server
    $intSMTPPort = 587 # SMTP Server Port
    $strSendTo = 'dwchan69@gmail.com' # Email Recipient

    $strUseCase = 'Horizon' # Horizon (toggle installation of agents - Windows only)
    $strOSVersion = 'Win10' # Win10 / Win2016 / Win2019 / CentOS / RHEL
    $strVMName = 'win10' # Name of the Virtual Machine that will become the template
    $strVMPassword = '$vbe#26r' # Local admin password of the virtual machine
    $intVMCPU = 1 # Allocate number of vCPU for the VM
    $intVMMemory = 4 # Allocate memory size for the VM
    $intVMDisksize = 20 # Allocate disk space for the VM
    $strVMNetwork = 'VM Network' # Allocate network porgroup for the VM
    $strVMDataStore = 'SSD_VM' # Template Datastore name for the VM
    $ConLibName = 'Repo' # Content Libray Repository for the custom OS image (iso)
    $BuildPath = 'G:\CustomizedISO' # Local staging area for the custom OS image (iso)
    $strStarterApp = $false # Installed some common standard Apps
    $TemplateToCL = $false
} else {
    $VCSAIPAddress = $InfraParameters.'vCenter IP'
    $VCSASSODomainName = $InfraParameters.'VCSA SSO Domain'
    $VCSASSOPassword = $InfraParameters.'VCSA SSO Password'
    $strESXHost = $InfraParameters.'ESX Host'

    $strO365Username = $EmailParameters.'SMTP Username'
    $strO365Password = $EmailParameters.'SMTP Password'
    $strSMTPServer = $EmailParameters.'SMTP Server'
    $intSMTPPort = $EmailParameters.'SMTP Port'
    $strSendTo = $EmailParameters.'Recipient'

    $strUseCase = $VMParameters.'Use Case'
    $strOSVersion = $VMParameters.OS
    $strVMName = $VMParameters.'VM Name'
    $strVMPassword = $VMParameters.'VM Password'
    $intVMCPU = $VMParameters.'VM CPU'
    $intVMMemory = $VMParameters.'VM Memory'
    $intVMDisksize = $VMParameters.'VM Disk Size'
    $strVMNetwork = $VMParameters.'VM Network'
    $strVMDataStore = $VMParameters.'VM Datastore'
    $ConLibName = $VMParameters.'Content Library'
    $BuildPath = $VMParameters.'Build Path'
    $strStarterApp = $VMParameters.'Starter App'
    $TemplateToCL = $VMParameters.'Template to CL'
}

$strO365Password = ConvertTo-SecureString -string $strO365Password -AsPlainText -Force
$oOffice365credential = New-Object System.Management.Automation.PSCredential -argumentlist $strO365Username, $strO365Password
$strEmailSubject = "VMware Automated Virtual Machine Creation Deployment Log - $strOSVersion"

# Update source parameters
$VMwareOSOT = 'D:\Windows\VMware_OSOT'
$VMwareHorizonAgent = 'D:\Windows\VMware_HAgent'
$VMwareDEM = 'D:\Windows\VMware_DEM'
$VMwareAppVol = 'D:\Windows\VMware_AppVol'
$STDApps = 'D:\Windows\Apps'
$VMDomainCert = 'D:\Windows\Certs'
$VMwareToolsIsoUrl = 'https://packages.vmware.com/tools/esx/6.7u3/windows/VMware-tools-windows-10.3.10-12406962.iso'
# $AppVolServer = 'AppVol.tataoui.com'

$SourceRHELIsoPath = 'D:\LabSources\ISOs\rhel-8.1-x86_64-dvd.iso'
$SourceCentOSIsoPath = 'D:\LabSources\ISOs\CentOS-8.2.2004-x86_64-dvd1.iso'
$Linuxkscfg = 'D:\Linux\Kickstart\ks.cfg'
$Linuxisolinuxcfg = 'D:\Linux\Kickstart\isolinux.cfg'
$SourceWin2016isoPath = 'D:\LabSources\ISOs\Windows_Server_2016_Datacenter_EVAL_en-us_14393_refresh.iso'
$SourceWin2019isoPath = 'D:\LabSources\ISOs\17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso'
$SourceWin10isoPath = 'D:\LabSources\ISOs\Win10_en-us.iso'
$Win2016nattendXmlPath = 'D:\Windows\UnattendXML\Win2016unattend.xml'
$Win10UnattendXmlPath = 'D:\Windows\UnattendXML\Win10unattend.xml'
$Win2019UnattendXmlPath = 'D:\Windows\UnattendXML\Win2019unattend.xml'

# DO NOT EDIT BEYOND HERE ############################################
$LogVersion = Get-Date -UFormat "%Y-%m-%d_%H-%M"
$verboseLogFile = "VMware-Automated-Virtual-Machine-Creation-Deployment-$LogVersion.log"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$StartTime = Get-Date
$vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue
$oVMDataStore = Get-Datastore -Name $strVMDataStore

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

My-Logger "Begin Virtual Machine Template Creation process ..."

if (!(Test-Path $BuildPath)) {
    New-Item -ItemType Directory -Path $BuildPath
    New-Item -ItemType Directory -Path $BuildPath\FinalISO
    New-Item -ItemType Directory -Path $BuildPath\UnattendXML
}

if ($strOSVersion -eq 'Win10') {
    $SourceISOPath = $SourceWin10isoPath
    $AutoUnattendXmlPath = $Win10UnattendXmlPath
    $strVMGuestID = 'windows9_64Guest'
    } elseif ($strOSVersion -eq 'Win2019') {
    $SourceISOPath = $SourceWin2019isoPath
    $AutoUnattendXmlPath = $Win2019UnattendXmlPath
    $strVMGuestID = 'windows9Server64Guest'
    # windows2019srv_64Guest
    } elseif ($strOSVersion -eq 'Win2016') {
    $SourceISOPath = $SourceWin2016isoPath
    $AutoUnattendXmlPath = $Win2016nattendXmlPath
    $strVMGuestID = 'windows9Server64Guest'
    } else {
    $SourceISOPath = $SourceCentOSIsoPath
    $strVMGuestID = 'centos8_64Guest'
    #guestOS = "ubuntu-64" - BIOS
}

#Clean DISM mount point if any. Linked to the PVSCSI drivers injection.
Clear-WindowsCorruptMountPoint
if (Test-Path $BuildPath\Temp) {
    Dismount-WindowsImage -path $BuildPath\Temp\MountDISM -discard
    #The Temp folder is only needed during the creation of one ISO.
    Remove-Item -Recurse -Force $BuildPath\Temp
}

My-Logger "Creating local staging area..."
New-Item -ItemType Directory -Path $BuildPath\Temp
New-Item -ItemType Directory -Path $BuildPath\Temp\WorkingFolder
New-Item -ItemType Directory -Path $BuildPath\Temp\VMwareTools
New-Item -ItemType Directory -Path $BuildPath\Temp\MountDISM

My-Logger "Prepare path for the Windows/Linux ISO destination file..."
$SourceISOFullName = $SourceISOPath.split("\")[-1]
$DestinationISOPath = $BuildPath + '\FinalISO\' +  ($SourceISOFullName -replace ".iso","") + '-custom.iso'
$DestinationISO = ($SourceISOFullName -replace ".iso","") + '-custom'

if ($DestinationISOPath.Length -gt 80){
    Write-Host "The source ISO name is longer than 80 characters.."
    Exit
}

My-Logger "Mount source OS ISO..."
$MountSourceISO= mount-diskimage -imagepath $SourceISOPath -passthru
# Obtain the drive letter assigned to Linux source ISO.
$DriveSourceISO = ($MountSourceISO| get-volume).driveletter + ':'

My-Logger "Copy the content of the source OS ISO to a stage area..."
copy-item $DriveSourceISO\* -Destination $BuildPath\Temp\WorkingFolder -force -recurse

# Remove the read-only attribtue from the extracted OS files
Get-ChildItem $BuildPath\Temp\WorkingFolder -recurse | %{ if (! $_.psiscontainer) { $_.isreadonly = $false } }

if ($strOSVersion -eq 'CentOS') {
    My-Logger "Copy Linux pckages into a staging area..."
#   Only a test for now
    My-Logger "Copy VMware Horizon Agent into a staging area - custom folder..."
    copy-item $VMwareHorizonAgent -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse
    } else {

    My-Logger "Download VMware Tools ISO from VMware..."
    $VMwareToolsIsoFullName = $VMwareToolsIsoUrl.split("/")[-1]
    $VMwareToolsIsoPath =  $BuildPath + '\Temp\VMwareTools\' + $VMwareToolsIsoFullName 
    (New-Object System.Net.WebClient).DownloadFile($VMwareToolsIsoUrl, $VMwareToolsIsoPath)

    My-Logger "Mount VMware Tools ISO..."
    $MountVMwareToolsIso = mount-diskimage -imagepath $VMwareToolsIsoPath -passthru
    $VMTools = 1
    # Obtain the drive letter assigned to VMware Tools ISO.
    $DriveVMwareToolsIso = ($MountVMwareToolsIso  | get-volume).driveletter + ':'

    My-Logger "Copy VMware Tools exe to staging area for custom ISO..."
    New-Item -ItemType Directory -Path $BuildPath\Temp\WorkingFolder\CustomFolder
    copy-item "$DriveVMwareToolsIso\setup64.exe" -Destination $BuildPath\Temp\WorkingFolder\CustomFolder
    # For 32 bits
    # copy-item "$DriveVMwareToolsIso\setup.exe" -Destination $BuildPath\TempWorkingFolder\CustomFolder

    My-Logger "Configure PVSCSI Drivers .inf to be injected into boot.wim and install.vim..."
    $pvcsciPath = $DriveVMwareToolsIso + '\Program Files\VMware\VMware Tools\Drivers\pvscsi\Win8\amd64\pvscsi.inf'
    # For 32 bits
    # $pvcsciPath = $DriveVMwareToolsIso + '\Program Files\VMware\VMware Tools\Drivers\pvscsi\Win8\i386\pvscsi.inf'

    My-Logger "Copy VMware OS Optimization Tool into a staging area - custom folder..."
    copy-item $VMwareOSOT -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse

    My-Logger "Copy VMware Horizon Agent into a staging area - custom folder..."
    copy-item $VMwareHorizonAgent -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse

    My-Logger "Copy VMware Dynamic Environment Manager Agent into a staging area - custom folder..."
    copy-item $VMwareDEM -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse

    My-Logger "Copy VMware App Volume Agent into a staging area - custom folder..."
    copy-item $VMwareAppVol -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse

    My-Logger "Copy Standard Apps for desktops into a staging area - custom folder..."
    copy-item $STDApps -Destination $BuildPath\Temp\WorkingFolder\CustomFolder -Recurse
}

if ($strOSVersion -eq 'CentOS') {
    My-Logger "Update kickstart (ks.cfg) with the appropriate hostname and administrator password..."
    Get-Content -Raw $Linuxkscfg | ForEach-Object { $_ `
            -replace '<!--REPLACE WITH MACHINENAME-->',$strVMName `
        } | Set-Content -NoNewline "$BuildPath\Temp\WorkingFolder\ks.cfg"

    copy-item "$Linuxisolinuxcfg" -Destination $BuildPath\Temp\WorkingFolder\isolinux -confirm:$false

    My-Logger "Create custom Linux ISO from staging area..."
    #D:\Linux\mkisofs\mkisofs.exe -R -J -V "RHEL-8.1Server.x86_64" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $BuildPath\FinalISO\redhat.iso $BuildPath\Temp\WorkingFolder
    D:\Linux\mkisofs\mkisofs.exe -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -o $DestinationISOPath $BuildPath\Temp\WorkingFolder
    } else {

#   Optional check all Image Index for boot.wim
#   Get-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\boot.wim
#
#   Modify all images in "boot.wim"
#   Example for windows 2016 iso:
#     - Microsoft Windows PE (x64)
#     - Microsoft Windows Setup (x64)

    My-Logger "Inject PVSCSI Drivers into boot.wim..."
    Get-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\boot.wim | foreach-object {
	    Mount-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\boot.wim -Index ($_.ImageIndex) -Path $BuildPath\Temp\MountDISM
	    Add-WindowsDriver -path $BuildPath\Temp\MountDISM -driver $pvcsciPath -ForceUnsigned
	    Dismount-WindowsImage -path $BuildPath\Temp\MountDISM -save
    }

#   Optional check all Image Index for install.wim
#   Get-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\install.wim
#
#   Modify all images in "install.wim"
#   Example for windows 2016 iso:
#     - Windows Server 2016 SERVERSTANDARDCORE
#     - Windows Server 2016 SERVERSTANDARD
#     - Windows Server 2016 SERVERDATACENTERCORE
#     - Windows Server 2016 SERVERDATACENTER

    My-Logger "Inject PVSCSI Drivers into install.wim..."
    Get-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\install.wim | foreach-object {
	    Mount-WindowsImage -ImagePath $BuildPath\Temp\WorkingFolder\sources\install.wim -Index ($_.ImageIndex) -Path $BuildPath\Temp\MountDISM
	    Add-WindowsDriver -path $BuildPath\Temp\MountDISM -driver $pvcsciPath -ForceUnsigned
	    Dismount-WindowsImage -path $BuildPath\Temp\MountDISM -save
    }
#################################pause
    My-Logger "Update autounattend xml with the appropriate hostname and administrator password..."
    Get-Content $AutoUnattendXmlPath | ForEach-Object { $_ `
            -replace '<!--REPLACE WITH MACHINENAME-->',$strVMName `
            -replace '<!--REPLACE WITH ADMINISTRATOR PASSWORD-->',$strVMPassword `
        } | Set-Content "$BuildPath\Temp\WorkingFolder\autounattend.xml"
    #copy-item $AutoUnattendXmlPath -Destination $BuildPath\Temp\WorkingFolder\autounattend.xml

# Future
# Adding patches to ISO with Add-WindowsPackage
# Add-WindowsPackage -Path "c:\offline" -PackagePath "c:\packages" -IgnoreCheck

    My-Logger "Create custom Windows ISO from staging area..."
    $OcsdimgPath = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
    $oscdimg  = "$OcsdimgPath\oscdimg.exe"
    $etfsboot = "$OcsdimgPath\etfsboot.com"
    $efisys_noprompt = "$OcsdimgPath\efisys_noprompt.bin"
    $efisys   = "$OcsdimgPath\efisys.bin" 
    $z = $BuildPath + '\Temp\WorkingFolder'
    $data = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys_noprompt  # Remove "Press Any Key to Continue" prompt
    start-process $oscdimg -args @("-bootdata:$data",'-u2','-udfver102', $z, $DestinationISOPath) -wait -nonewwindow
}

My-Logger "Un-mount ALL previously mounted ISO image..."
Dismount-DiskImage -ImagePath $SourceISOPath
if ($VMTools -eq 1){
    Dismount-DiskImage -ImagePath $VMwareToolsIsoPath
}

My-Logger "Upload newly created ISO to Content Library..."
$VMiso = Get-ContentLibraryItem -ContentLibrary $ConLibName -Name $DestinationISO
if ($VMiso -eq $null){
    New-ContentLibraryItem -ContentLibrary $ConLibName -Name $DestinationISO -ItemType iso -Files $DestinationISOPath
    } else {
    $VMiso | Remove-ContentLibraryItem -Confirm:$false
    New-ContentLibraryItem -ContentLibrary $ConLibName -Name $DestinationISO -ItemType iso -Files $DestinationISOPath
}
###################pause
My-Logger "Clean up local build environment..."
Remove-Item $BuildPath -Recurse -Force

My-Logger "Create new Virtual Machine hardware with mounted ISO..."
VMware.VimAutomation.Core\New-VM -Name $strVMName -VMHost $strESXHost -Datastore $strVMDataStore -DiskGB $intVMDisksize -DiskStorageFormat Thin -NumCpu $intVMCPU -MemoryGB $intVMMemory -NetworkName $strVMNetwork -GuestId $strVMGuestID
# [VMware.Vim.VirtualMachineGuestOsIdentifier].GetEnumValues()
$VMiso = Get-ContentLibraryItem -ContentLibrary $ConLibName -Name $DestinationISO
VMware.VimAutomation.Core\Get-VM -Name $strVMName | New-CDDrive -ContentLibraryIso $VMiso -Verbose

if ($strOSVersion -eq 'Win2016' -Or $strOSVersion -eq 'Win10'){
    My-Logger "Set HW BIOS to UEFI...(need for Win2016 and Win10)"
    $oVMName = VMware.VimAutomation.Core\Get-VM -Name $strVMName
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
    $oVMName.ExtensionData.ReconfigVM($spec)
}

if ($strOSVersion -eq 'CentOS'){
    My-Logger "Set HW UEFI to BIOS...(need for CentOS)"
    $oVMName = VMware.VimAutomation.Core\Get-VM -Name $strVMName
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::bios
    $oVMName.ExtensionData.ReconfigVM($spec)
}

if ($strUseCase -eq 'Horizon'){
    My-Logger "Disable the Ability to Add and Remove Virtual Hardware While the VM Is Running"
    $oVMName = VMware.VimAutomation.Core\Get-VM -Name $strVMName
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $extra = New-Object VMware.Vim.OptionValue
    $extra.Key = 'devices.hotplug'
    $extra.Value = 'false'
    $spec.ExtraConfig += $extra
    $oVMName.ExtensionData.ReconfigVM($spec)
}

# For Debug ONLY, Do not use
if ($Enforce -eq '1'){
My-Logger "Enforce Virtual Machine boot order..."
    $intBootDelay = '0'
    $BIOSSetup = $false
    $strBootNICDeviceName = 'Network adapter 1'
    $strBootHDiskDeviceName = 'Hard disk 1'
    $viewVM = Get-View -ViewType VirtualMachine -Property Name, Config.Hardware.Device -Filter @{"Name" = $strVMName}

    # Create Newtork Object from Virtual Network Card deviceID
    $intNICDeviceKey = ($viewVM.Config.Hardware.Device | ?{$_.DeviceInfo.Label -eq $strBootNICDeviceName}).Key
    $oBootableNIC = New-Object -TypeName VMware.Vim.VirtualMachineBootOptionsBootableEthernetDevice -Property @{"DeviceKey" = $intNICDeviceKey}
    # Create Disk Object from Virtual hard drive deviceID
    $intHDiskDeviceKey = ($viewVM.Config.Hardware.Device | ?{$_.DeviceInfo.Label -eq $strBootHDiskDeviceName}).Key
        $oBootableHDisk = New-Object -TypeName VMware.Vim.VirtualMachineBootOptionsBootableDiskDevice -Property @{"DeviceKey" = $intHDiskDeviceKey}
    # Create CDRom Object
    $oBootableCDRom = New-Object -Type VMware.Vim.VirtualMachineBootOptionsBootableCdromDevice
 
    # Create VM ConfigSpec to change the VM's boot order
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec -Property @{
        "BootOptions" = New-Object VMware.Vim.VirtualMachineBootOptions -Property @{
            BootOrder = $oBootableCDRom, $oBootableHDisk, $oBootableNIC
            BootDelay = $intootDelay
            EnterBIOSSetup = $BIOSSetup
        }
    }
    $viewVM.ReconfigVM_Task($spec)
}

My-Logger "Power on Virtual Machine $strVMName..."
VMware.VimAutomation.Core\Start-VM -VM $strVMName

My-Logger "Wait for OS installation to finish before continuing..."
while (-not $oVMName.ExtensionData.Guest.GuestOperationsReady)
    {
    Start-Sleep 2
    $oVMName.ExtensionData.UpdateViewData('Guest')
    }
Start-Sleep 30

if ($strOSVersion -eq 'CentOS') {
    My-Logger "Start Post Linux OS installation...(if any)"
    $LinuxUser = 'root'
    $LinuxPWord = ConvertTo-SecureString -String 'VMware1!' -AsPlainText -Force
    $LinuxCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LinuxUser, $LinuxPWord

#   For example only
#       My-Logger "Initiate VMware Update Mangager Download Service Installation..."
#       Get-Item "D:\Linux\UMDS\" | Copy-VMGuestFile -Force -Destination /root -VM $strVMName -LocalToGuest -GuestCredential $LinuxCredential -Verbose
#       $ConfigureUMDS = 'cd UMDS
#                       chmod +x umds_install.sh
#                       ./umds_install.sh'
#       Invoke-VMScript -ScriptText $ConfigureUMDS -VM $strVMName -GuestCredential $LinuxCredential -ScriptType Bash

    } else {

    My-Logger "Start Post OS installation..."
    $DCLocalUser = "$strVMName\homer"
    $DCLocalPWord = ConvertTo-SecureString -String 'VMware1!' -AsPlainText -Force
    $DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord

    My-Logger "Initiate Windows Update Service..."
    $ConfigureOSPatching = 'Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value "1" -Type DWord;
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value "1" -Type DWord;
                    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine;
                    Install-PackageProvider -Name Nuget -MinimumVersion 2.8.5.201 -Force;
                    Install-Module PowerShellGet -Force;
                    Install-Module PSWindowsUpdate -Confirm:$false -Force;

                    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot'
    Invoke-VMScript -ScriptText $ConfigureOSPatching -VM $strVMName -GuestCredential $DCLocalCredential
  #                     Add-WUServiceManager -MicrosoftUpdate -Confirm:$false;

    My-Logger "Initiate Windows Update reboot..."
    Restart-VM -VM $strVMName -Confirm:$false
    My-Logger "Wait for successful OS shutdown before continuing..."
    while ($oVMName.ExtensionData.Guest.GuestOperationsReady)
        {
        Start-Sleep 2
        $oVMName.ExtensionData.UpdateViewData('Guest')
        }
    My-Logger "Windows successfully shutdown..."
    while (-not $oVMName.ExtensionData.Guest.GuestOperationsReady)
        {
        Start-Sleep 2
        $oVMName.ExtensionData.UpdateViewData('Guest')
        }
    My-Logger "Wait for Windows bootup to finish before continuing..."
    Start-Sleep 30
                    
    if ($strStarterApp -eq $true) {
            $ConfigureStarterApp = 'Write-Verbose -Message "Configuring Standard Starter Apps..." -Verbose;
                    Start-Process msiexec "/q /I ""D:\CustomFolder\Apps\7z1900-x64.msi""" -PassThru -Wait;
                    Start-Process msiexec "/qn /norestart /i “"D:\CustomFolder\Apps\GoogleChromeStandaloneEnterprise64.msi”"" -PassThru -Wait;
                    Start-Process "D:\CustomFolder\Apps\vlc-3.0.11-win64.exe" -ArgumentList "/L=1033 /S /NCRC";
                    Start-Process "D:\CustomFolder\Apps\npp.7.8.8.Installer.x64.exe" -ArgumentList "/S";
                    Start-Process "D:\CustomFolder\Apps\jre-8u271-windows-x64.exe" -ArgumentList "/s"'
            Invoke-VMScript -ScriptText $ConfigureStarterApp -VM $strVMName -GuestCredential $DCLocalCredential
            Start-Sleep 10
    }

    if ($strUseCase -eq "Horizon") {

        if ($strOSVersion -eq 'Win10') {
            My-Logger "Update VMware Tools for Horizon..."
            $UpdateVMwareTools = 'Write-Verbose -Message "Update VMware Tools for Horizon..." -Verbose;
                    $VMwareTools = "setup64.exe";
                    $VMwareToolsConfig = "/s /v ""/qn REBOOT=ReallySuppress ADDLOCAL=ALL REMOVE=Hgfs,SVGA,VSS,AppDefense,NetworkIntrospection""";
                    Start-Process "D:\CustomFolder\$VMwareTools" -ArgumentList $VMwareToolsConfig -PassThru -Wait -ErrorAction Stop'
            Invoke-VMScript -ScriptText $UpdateVMwareTools -VM $strVMName -GuestCredential $DCLocalCredential
            Start-Sleep 10
        }

        if ($strOSVersion -eq 'Win10') {
            My-Logger "Optimize Windows 10 Features..."
            $ConfigureWindowsFeature = 'Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -NoRestart;
                    Disable-WindowsOptionalFeature -online -featurename "Printing-Foundation-Features"'
            Invoke-VMScript -ScriptText $ConfigureWindowsFeature -VM $strVMName -GuestCredential $DCLocalCredential
            Start-Sleep 10
        }

        My-Logger "Install and configure VMware Horizon Agent..."
        $ConfigureHorizonAgent = 'Write-Verbose -Message "Configuring VMware Horizon Agent" -Verbose;
                    $HorizonAgent = "VMware-Horizon-Agent-x86_64-7.13.0-16975066.exe";
                    $HorizonAgentConfig = "/s /v ""/qn REBOOT=ReallySuppress ADDLOCAL=Core,RTAV,ClientDriveRedirection,VmwVaudio""";
                    Start-Process "D:\CustomFolder\VMware_HAgent\$HorizonAgent" -ArgumentList $HorizonAgentConfig -PassThru -Wait -ErrorAction Stop'
        Invoke-VMScript -ScriptText $ConfigureHorizonAgent -VM $strVMName -GuestCredential $DCLocalCredential
        Start-Sleep 10

        My-Logger "Install and configure VMware Dynamic Environment Agent..."
        $ConfigureDEM = 'Write-Verbose -Message "Configuring VMware Dynamic Environment Agent" -Verbose;
                    $DEMAgent = "VMware Dynamic Environment Manager Enterprise 10.1 x64.msi";
                    $DEMLicense = "VMware-DEM-10.1.0-GA.lic";
                    $DEMConfig = "/i ""D:\CustomFolder\VMware_DEM\$DEMAgent"" /qn /norestart ADDLOCAL=FlexEngine LICENSEFILE=$DEMLicense";
                    Start-Process msiexec.exe -ArgumentList $DEMConfig -PassThru -Wait'
        Invoke-VMScript -ScriptText $ConfigureDEM -VM $strVMName -GuestCredential $DCLocalCredential
        Start-Sleep 10

#        My-Logger "Install and configure App Volume Agent..."
#        $ConfigureAppVol = 'Write-Verbose -Message "Configuring App Volume Agent" -Verbose;
#                    $AppVolAgent = "App Volumes Agent.msi";
#                    $AppVolServer = "AppVol.tataoui.com";
#                    $AppVolConfig = "/i ""D:\CustomFolder\VMware_AppVol\$AppVolAgent"" /qn REBOOT=ReallySuppress MANAGER_ADDR=$AppVolServer MANAGER_PORT=443";
#                    Start-Process msiexec.exe -ArgumentList $AppVolConfig -PassThru -Wait'
#        Invoke-VMScript -ScriptText $ConfigureAppVol -VM $strVMName -GuestCredential $DCLocalCredential
#        Start-Sleep 10
    }

# VMwareOSOptimizationTool.exe -o -background #000000 -VisualEffect Performance -StoreApp Remove-all -t "$OSOTtemplate" -r C:\Temp\ -reboot'
# VMwareOSOptimizationTool.exe -o -storeapp remove-all -visualeffect performance -background #000000
# VMwareOSOptimizationTool.exe -o -storeapp remove-all'
# VMwareOSOptimizationTool.exe -o -t "$OSOTtemplate" -r C:\Temp\ -reboot'
# VMwareOSOptimizationTool.exe -finalize 1 2 3 4 5 6'
    My-Logger "Execute VMware OS Optimization Tool with defined template..."
    $ConfigureOSOT = 'Write-Verbose -Message "Configuring VMware OSOT" -Verbose;
                    $OSOTtemplate = "VMware Templates\Windows 10 and Server 2016 or later";
                    $PostInstallFolders = "D:\CustomFolder";
                    $folder = "$PostInstallFolders\VMware_OSOT";
                    Set-Location -Path $folder;
                    .\VMwareOSOptimizationTool.exe -o -storeapp remove-all'
    Invoke-VMScript -ScriptText $ConfigureOSOT -VM $strVMName -GuestCredential $DCLocalCredential

#    try{
#        Invoke-VMScript -ScriptText $ConfigureOSOT -VM $strVMName -GuestCredential $DCLocalCredential
#    }
#    catch
#    {
#    Write-Host $error[0]
#    Sleep 10
#        Invoke-VMScript -ScriptText $ConfigureOSOT -VM $strVMName -GuestCredential $DCLocalCredential
#    }
}

My-Logger "Shutting down guest Virtual Machine..."
Shutdown-VMGuest -VM $strVMName -Confirm:$false
Start-Sleep 20
My-Logger "Dismount all media from Virtual Machine..."
Get-CDDrive -VM $strVMName | Set-CDDrive -NoMedia -Confirm:$false

My-Logger "Dismount all media and convert Virtual Machine to Template..."
if ($TemplateToCL -eq $false){
    $oVMName| Set-VM -ToTemplate -Confirm:$false    
    } else {
    Write-Host "To do list"
}
$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "VMware Virtual Machine Template Creation completed.."
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"

# Forward Deployment summary and log to receipent...
$verboseLogFilePath = Get-ChildItem Env:Userprofile
$AttachmentsPath = $verboseLogFilePath.Value+'\'+$verboseLogFile
$strEmailBody = @"
<h1>VMware Deployment Log attached</h1>
<table style="width:100%">
  <tr>
    <th>Start Time</th>
    <th>End Time</th> 
    <th>Duration</th>
  </tr>
  <tr>
    <td style='text-align:center'>$StartTime</td>
    <td style='text-align:center'>$EndTime</td> 
    <td style='text-align:center'>$duration minutes</td>
  </tr>
  <tr>
    <th>Operation System</th>
    <th>Use Case</th> 
    <th>Virtual Machine Name</th>
  </tr>
  <tr>
    <td style='text-align:center'>$strOSVersion</td>
    <td style='text-align:center'>$strUseCase</td> 
    <td style='text-align:center'>$strVMName</td>
  </tr>

</table>
"@
$sendMailParams = @{
    From = $strO365Username
    To = $strSendTo
    #Cc =
    #Bcc =
    Subject = $strEmailSubject
    Body = $strEmailBody
    BodyAsHtml = $true
    Attachments = $AttachmentsPath
    Priority = 'High'
    DeliveryNotificationOption = 'None' # 'OnSuccess, OnFailure'
    SMTPServer = $strSMTPServer
    Port = $intSMTPPort
    UseSsl = $true
    Credential = $oOffice365credential
}
Send-MailMessage @sendMailParams

# $SucceededEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationSucceeded" }
# $FailureEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationFailed" }

# Copy-DatastoreItem -Item $DestinationISOPath -Destination $oVMDataStore.DatastoreBrowserPath -Force
# e.g. vmstore:\192.168.10.223@443\DatacenterHQ\SSD_VM

# -Template Temp_W2k12 -OSCustomizationSpec Cust_W2012R2

