﻿configuration DCConfiguration
{
    param
    (
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds
    )

    Import-DscResource -ModuleName 'TemplateHelpDSC'
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration', 'NetworkingDsc', 'xDhcpServer', 'DnsServerDsc', 'ComputerManagementDsc', 'ActiveDirectoryDsc'

    # Read config
    $deployConfig = Get-Content -Path $ConfigFilePath | ConvertFrom-Json
    $ThisMachineName = $deployConfig.thisParams.MachineName
    $ThisVM = $deployConfig.virtualMachines | Where-Object { $_.vmName -eq $ThisMachineName }
    $DomainName = $deployConfig.parameters.domainName
    $DomainAdminName = $deployConfig.vmOptions.adminName
    $PSName = $deployConfig.thisParams.PSName
    $CSName = $deployConfig.thisParams.CSName

    $DomainAccounts = $deployConfig.thisParams.DomainAccounts
    $DomainAccountsUPN = $deployConfig.thisParams.DomainAccountsUPN
    $DomainComputers = $deployConfig.thisParams.DomainComputers

    $network = $deployConfig.vmOptions.network.Substring(0, $deployConfig.vmOptions.network.LastIndexOf("."))
    $DHCP_DNSAddress = $network + ".1"
    $DHCP_DefaultGateway = $network + ".200"

    $setNetwork = $true
    if ($ThisVM.hidden) {
        $setNetwork = $false
    }

    # SQL AO
    $SQLAO = $deployConfig.thisParams.SQLAO
    $SQLAOGroupMembers = $deployConfig.thisParams.SQLAO.GroupMembers

    # AD Sites
    $adsites = $deployConfig.thisParams.sitesAndNetworks

    # Define log share
    $LogFolder = "DSC"
    $LogPath = "c:\staging\$LogFolder"

    # CM Files folder/share
    $CM = if ($deployConfig.cmOptions.version -eq "tech-preview") { "CMTP" } else { "CMCB" }

    # Servers for which permissions need to be added to systems management contaienr
    $waitOnDomainJoin = $deployConfig.thisParams.ServersToWaitOn

    # Domain creds
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node LOCALHOST
    {
        LocalConfigurationManager {
            ConfigurationMode  = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        WriteStatus NewName {
            Status = "Renaming the computer to $ThisMachineName"
        }

        Computer NewName {
            Name = $ThisMachineName
        }

        WriteStatus InitDisks {
            DependsOn = "[Computer]NewName"
            Status    = "Initializing disks"
        }

        InitializeDisks InitDisks {
            DependsOn = "[Computer]NewName"
            DummyKey  = "Dummy"
            VM        = $ThisVM | ConvertTo-Json
        }

        SetCustomPagingFile PagingSettings {
            DependsOn   = "[InitializeDisks]InitDisks"
            Drive       = 'C:'
            InitialSize = '8192'
            MaximumSize = '8192'
        }

        WriteStatus InstallFeature {
            DependsOn = "[SetCustomPagingFile]PagingSettings"
            Status    = "Installing required windows features"
        }

        InstallFeatureForSCCM InstallFeature {
            Name      = 'DC'
            Role      = 'DC'
            DependsOn = "[SetCustomPagingFile]PagingSettings"
        }

        WriteStatus FirstDS {
            DependsOn = "[InstallFeatureForSCCM]InstallFeature"
            Status    = "Configuring ADDS and setting up the domain. The computer will reboot a couple of times."
        }

        SetupDomain FirstDS {
            DependsOn                     = "[InstallFeatureForSCCM]InstallFeature"
            DomainFullName                = $DomainName
            SafemodeAdministratorPassword = $DomainCreds
        }

        $adObjectDependency = @()
        $i = 0
        foreach ($user in $DomainAccounts) {
            $i++
            ADUser "User$($i)" {
                Ensure               = 'Present'
                UserName             = $user
                Password             = $DomainCreds
                PasswordNeverResets  = $true
                PasswordNeverExpires = $true
                CannotChangePassword = $true
                DomainName           = $DomainName
                DependsOn            = "[WindowsFeature]ADPS"
            }
            $adObjectDependency += "[ADUser]User$($i)"
        }

        foreach ($userWithUPN in $DomainAccountsUPN) {
            $i++
            ADUser "User$($i)" {
                Ensure               = 'Present'
                UserPrincipalName    = $userWithUPN + '@' + $DomainName
                UserName             = $userWithUPN
                Password             = $DomainCreds
                PasswordNeverResets  = $true
                PasswordNeverExpires = $true
                CannotChangePassword = $true
                DomainName           = $DomainName
                DependsOn            = "[WindowsFeature]ADPS"
            }
            $adObjectDependency += "[ADUser]User$($i)"
        }

        $i = 0
        foreach ($computer in $DomainComputers) {
            $i++
            ADComputer "Computer$($i)" {
                ComputerName      = $computer
                EnabledOnCreation = $false
                Dependson         = '[WindowsFeature]ADPS'
            }
            $adObjectDependency += "[ADComputer]Computer$($i)"
        }

        ADGroup AddToAdmin {
            GroupName        = "Administrators"
            MembersToInclude = @($DomainAdminName)
            DependsOn        = $adObjectDependency
        }

        ADGroup AddToDomainAdmin {
            GroupName        = "Domain Admins"
            MembersToInclude = @($DomainAdminName, $Admincreds.UserName)
            DependsOn        = $adObjectDependency
        }

        ADGroup AddToSchemaAdmin {
            GroupName        = "Schema Admins"
            MembersToInclude = @($DomainAdminName)
            DependsOn        = $adObjectDependency
        }

        $adSiteDependency = @()
        $i = 0
        foreach ($site in $adsites) {
            $i++
            ADReplicationSite "ADSite$($i)" {
                Ensure    = 'Present'
                Name      = $site.SiteCode
                DependsOn = "[ADGroup]AddToSchemaAdmin"
            }

            ADReplicationSubnet "ADSubnet$($i)" {
                Name        = "$($site.Subnet)/24"
                Site        = $site.SiteCode
                Location    = $site.SiteCode
                Description = 'Created by vmbuild'
                DependsOn   = "[ADReplicationSite]ADSite$($i)"
            }

            $adSiteDependency += "[ADReplicationSubnet]ADSubnet$($i)"
        }

        AddNtfsPermissions AddNtfsPerms {
            Ensure    = "Present"
            DependsOn = $adSiteDependency
        }

        OpenFirewallPortForSCCM OpenFirewall {
            DependsOn = "[AddNtfsPermissions]AddNtfsPerms"
            Name      = "DC"
            Role      = "DC"
        }

        if ($setNetwork) {

            WriteStatus NetworkDNS {
                DependsOn = "[SetupDomain]FirstDS"
                Status    = "Setting Primary DNS, Default Gateway and DNS Forwarders"
            }

            IPAddress NewIPAddressDC {
                DependsOn      = "[SetupDomain]FirstDS"
                IPAddress      = $DHCP_DNSAddress
                InterfaceAlias = 'Ethernet'
                AddressFamily  = 'IPV4'
            }

            DefaultGatewayAddress SetDefaultGateway {
                DependsOn      = "[IPAddress]NewIPAddressDC"
                Address        = $DHCP_DefaultGateway
                InterfaceAlias = 'Ethernet'
                AddressFamily  = 'IPv4'
            }

            DnsServerForwarder DnsServerForwarder {
                DependsOn        = "[DefaultGatewayAddress]SetDefaultGateway"
                IsSingleInstance = 'Yes'
                IPAddresses      = @('1.1.1.1', '8.8.8.8', '9.9.9.9')
                UseRootHint      = $true
                EnableReordering = $true
            }

            WriteStatus ADCS {
                DependsOn = "[DnsServerForwarder]DnsServerForwarder"
                Status    = "Installing Certificate Authority"
            }
        }
        else {
            WriteStatus ADCS {
                DependsOn = "[SetupDomain]FirstDS"
                Status    = "Installing Certificate Authority"
            }
        }

        InstallCA InstallCA {
            DependsOn     = "[WriteStatus]ADCS"
            HashAlgorithm = "SHA256"
        }

        WriteStatus InstallDotNet {
            DependsOn = "[InstallCA]InstallCA"
            Status    = "Installing .NET 4.8"
        }

        InstallDotNet4 DotNet {
            DownloadUrl = "https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe"
            FileName    = "ndp48-x86-x64-allos-enu.exe"
            NetVersion  = "528040"
            Ensure      = "Present"
            DependsOn   = "[WriteStatus]InstallDotNet"
        }

        File ShareFolder {
            DestinationPath = $LogPath
            Type            = 'Directory'
            Ensure          = 'Present'
            DependsOn       = "[InstallDotNet4]DotNet"
        }

        FileReadAccessShare DomainSMBShare {
            Name      = $LogFolder
            Path      = $LogPath
            DependsOn = "[File]ShareFolder"
        }

        WriteStatus WaitDomainJoin {
            DependsOn = "[FileReadAccessShare]DomainSMBShare"
            Status    = "Waiting for $($waitOnDomainJoin -join ',') to join the domain"
        }

        $waitOnDependency = @()
        foreach ($server in $waitOnDomainJoin) {

            VerifyComputerJoinDomain "WaitFor$server" {
                ComputerName = $server
                Ensure       = "Present"
                DependsOn    = "[WriteStatus]WaitDomainJoin"
            }

            DelegateControl "Add$server" {
                Machine        = $server
                DomainFullName = $DomainName
                Ensure         = "Present"
                DependsOn      = "[VerifyComputerJoinDomain]WaitFor$server"
            }

            $waitOnDependency += "[DelegateControl]Add$server"
        }

        if ($SQLAO) {

            WriteStatus SQLAOGroup {
                DependsOn = $waitOnDependency
                Status    = "Creating AD Group and assigning SPN for SQL Availability Group"
            }

            ADGroup SQLAOGroup {
                Ensure      = 'Present'
                GroupName   = $deployConfig.thisParams.SQLAO.GroupName
                GroupScope  = "Global"
                Category    = "Security"
                Description = "$($deployConfig.thisParams.SQLAO.GroupName) Group for SQL Always On"
                Members     = $SQLAOGroupMembers
                DependsOn   = '[WriteStatus]SQLAOGroup'
            }

            ActiveDirectorySPN SQLAOSPN {
                Key              = 'Always'
                UserName         = $deployConfig.thisParams.SQLAO.SqlServiceAccount
                FQDNDomainName   = $DomainName
                OULocationUser   = $deployConfig.thisParams.SQLAO.OULocationUser
                OULocationDevice = $deployConfig.thisParams.SQLAO.OULocationDevice
                ClusterDevice    = $deployConfig.thisParams.SQLAO.ClusterNodes
                UserNameCluster  = $deployConfig.thisParams.SQLAO.SqlServiceAccount
                Dependson        = '[ADGroup]SQLAOGroup'
            }

            WriteEvent WriteDelegateControlfinished {
                LogPath   = $LogPath
                WriteNode = "DelegateControl"
                Status    = "Passed"
                Ensure    = "Present"
                DependsOn = "[ActiveDirectorySPN]SQLAOSPN"
            }

        }
        else {

            WriteEvent WriteDelegateControlfinished {
                LogPath   = $LogPath
                WriteNode = "DelegateControl"
                Status    = "Passed"
                Ensure    = "Present"
                DependsOn = $waitOnDependency
            }

        }

        if (-not ($PSName -or $CSName)) {

            WriteStatus Complete {
                DependsOn = "[WriteEvent]WriteDelegateControlfinished"
                Status    = "Complete!"
            }

        }
        else {

            WriteStatus WaitExtSchema {
                DependsOn = "[WriteEvent]WriteDelegateControlfinished"
                Status    = "Waiting for site to download ConfigMgr source files, before extending schema for Configuration Manager"
            }

            WaitForExtendSchemaFile WaitForExtendSchemaFile {
                MachineName = if ($CSName) { $CSName } else { $PSName }
                ExtFolder   = $CM
                Ensure      = "Present"
                DependsOn   = "[WriteEvent]WriteDelegateControlfinished"
            }

            WriteStatus Complete {
                DependsOn = "[WaitForExtendSchemaFile]WaitForExtendSchemaFile"
                Status    = "Complete!"
            }

        }

        WriteEvent WriteConfigFinished {
            LogPath   = $LogPath
            WriteNode = "ConfigurationFinished"
            Status    = "Passed"
            Ensure    = "Present"
            DependsOn = "[WriteStatus]Complete"
        }
    }
}