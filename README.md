# AutomatedTemplates
Process to automated VMware template creation
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
#    - VMware Horizon Agent
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
