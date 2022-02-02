﻿@{

# Script module or binary module file associated with this manifest.
RootModule = 'TemplateHelpDSC.psm1'

DscResourcesToExport = @(
    'InstallADK',
    'InstallSSMS',
    'InstallDotNet4',
    'InstallAndConfigWSUS',
    'InstallAZCopy',
    'WriteEvent',
    'WaitForEvent',
    'DelegateControl',
    'AddBuiltinPermission',
    'AddNtfsPermissions',
    'InstallSCCM',
    'InstallDP',
    'InstallMP',
    'WaitForDomainReady',
    'VerifyComputerJoinDomain',
    'SetDNS',
    'WriteStatus',
    'WriteFileOnce',
    'WaitForFileToExist',
    'ChangeSqlInstancePort',
    'ChangeSQLServicesAccount',
    'RegisterTaskScheduler',
    'DownloadSCCM',
    'DownloadFile',
    'WaitForExtendSchemaFile',
    'SetAutomaticManagedPageFile',
    'InitializeDisks',
    'ChangeServices',
    'AddUserToLocalAdminGroup',
    'JoinDomain',
    'OpenFirewallPortForSCCM',
    'InstallFeatureForSCCM',
    'SetCustomPagingFile',
    'SetupDomain',
    'FileReadAccessShare',
    'InstallCA',
    'FileACLPermission',
    'ModuleAdd',
    'ActiveDirectorySPN'
)

# Version number of this module.
ModuleVersion = '1.0'

# ID used to uniquely identify this module
GUID = 'dade476b-0e1f-4c41-91c6-8b39ea182f40'

# Author of this module
Author = 'Microsoft Corporation'

# Company or vendor of this module
CompanyName = 'Microsoft Corporation'

# Copyright statement for this module
Copyright = '(c) 2014 Microsoft. All rights reserved.'

# Description of the functionality provided by this module
# Description = ''

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''
}