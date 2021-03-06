<#
.SYNOPSIS
Script to train and test the preventive maintenance template with SQL + MLS

.DESCRIPTION
This script will show the E2E work flow of Preventive Maintenance machine learning
template with Microsoft SQL and ML services. 

Switch parameter Score allows you to score the production data with seleted model
Switch parameter ResetParmOnly allows you to reset the SQL related credentials

For the detailed description, please read README.md.
#>



[CmdletBinding()]
param(
# SQL server address
[parameter(Mandatory=$true,ParameterSetName = "Train_test")]
[ValidateNotNullOrEmpty()] 
[String]    
$serverName = "",

[parameter(Mandatory=$false, Position=2)]
[ValidateNotNullOrEmpty()] 
[string]$username,

[parameter(Mandatory=$false, Position=3)]
[ValidateNotNullOrEmpty()] 
[string]$password,

[parameter(Mandatory=$false, Position=4)]
[ValidateNotNullOrEmpty()] 
[string]$Prompt

)

###Check to see if user is Admin

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")
        
if ($isAdmin -eq 'True')
{
    ##Change Values here for Different Solutions 
    $SolutionName = "PredictiveMaintenanceModelingGuide"
    $SolutionFullName = "SQL-Server-R-Services-Samples" 
    $Shortcut = $SolutionName+"Help.url"
    $DatabaseName = "PredictiveMaintenanceModelingGuide_R" 

    $Branch = "master" 
    $InstallR = 'Yes'  ## If Solution has a R Version this should be 'Yes' Else 'No'
    $InstallPy = 'No' ## If Solution has a Py Version this should be 'Yes' Else 'No'
    $SampleWeb = 'No' ## If Solution has a Sample Website  this should be 'Yes' Else 'No' 
    $EnableFileStream = 'No' ## If Solution Requires FileStream DB this should be 'Yes' Else 'No'
    $IsMixedMode = 'No' ##If solution needs mixed mode this should be 'Yes' Else 'No'
    $Prompt = 'N'

    ###These probably don't need to change , but make sure files are placed in the correct directory structure 
    $solutionTemplateName = "Solutions"
    $solutionTemplatePath = "C:\" + $SolutionFullName
    $checkoutDir = $SolutionName
    $SolutionPath = $solutionTemplatePath + '\' + $checkoutDir
    $desktop = "C:\Users\Public\Desktop\"
    $scriptPath = $SolutionPath + "\Code\"
    $SolutionData = $SolutionPath + "\Data\"
    $moreSolutionsURL = "https://github.com/Microsoft/ML-Server/"
    $setupLog = "c:\tmp\"+$SolutionName+"_setup_log.txt"
    $installerFunctionsFileName = "installer_functions.ps1"
    $installerFunctionsURL = "https://raw.githubusercontent.com/Microsoft/ML-Server/master/$installerFunctionsFileName"
    $installerFunctionsFile = "$PSScriptRoot\$installerFunctionsFileName"
        
    ##########################################################################
    # Including function wrapper library
    ##########################################################################
    try {
        if (Test-Path $installerFunctionsFile) {
            Remove-Item $installerFunctionsFile
        }
        Invoke-WebRequest -uri $installerFunctionsURL -OutFile $installerFunctionsFile
        .($installerFunctionsFile)
    }
    catch {
        Write-Host -ForegroundColor Red "Error while loading supporting PowerShell Scripts."
        Write-Host -ForegroundColor Red $_Exception
        EXIT
    }

    WriteInstallStartMessage -SolutionName $SolutionName
    
    Start-Transcript -Path $setupLog
    $startTime = Get-Date
    Write-Host ("Start time: $startTime")

    Write-Host -Foregroundcolor green ("Performing set up.")

    ##########################################################################
    # Get connection string function
    ##########################################################################
    <#function GetConnectionString
    {
        if($IsMixedMode.ToUpper() -eq "YES") {
            $connectionString = "Driver=SQL Server;Server=$serverName;Database=$DatabaseName;UID=$username;PWD=$password"
        }
        else {
            $connectionString = "Driver=SQL Server;Server=$servername;Database=$DatabaseName;Trusted_Connection=Yes"
        }
        $connectionString
    }
    
    
    ##########################################################################
    # Construct the SQL connection strings
    ##########################################################################
        $connectionString = GetConnectionString
    #>
    
    ##################################################################
    ##DSVM Does not have SQLServer Powershell Module Install or Update 
    ##################################################################
        InstallOrUpdateSQLServerPowerShellModule

    ##########################################################################
    ##Clone Data from GIT
    ##########################################################################
        CloneFromGIT -SolutionFullName $SolutionFullName, -solutionTemplatePath $solutionTemplatePath -SolutionPath $SolutionPath

    ##########################################################################
    #Install R packages if required
    ##########################################################################
        If ($InstallR -eq 'Yes') {
            Write-Host("Installing R Packages")
            Set-Location "$SolutionPath\Resources\"
            # install R Packages
            Start-Process "C:\Program Files\Microsoft\ML Server\R_SERVER\bin\x64\Rscript.exe" -ArgumentList "packages.R " -Wait
        }

    ##########################################################################
    #Enabled FileStream if required
    ##########################################################################
        ## if FileStreamDB is Required Alter Firewall ports for 139 and 445
        If ($EnableFileStream -eq 'Yes') {
            netsh advfirewall firewall add rule name="Open Port 139" dir=in action=allow protocol=TCP localport=139
            netsh advfirewall firewall add rule name="Open Port 445" dir=in action=allow protocol=TCP localport=445
            Write-Host("Firewall as been opened for filestream access")
        }
        If ($EnableFileStream -eq 'Yes') {
            Set-Location "C:\Program Files\Microsoft\ML Server\PYTHON_SERVER\python.exe" 
            .\setup.py install
            Write-Host ("Py Install has been updated to latest version")
        }

    ############################################################################################
    #Configure SQL to Run our Solutions 
    ############################################################################################
        ##Get Server name if none was provided during setup
        if([string]::IsNullOrEmpty($serverName)) {
            $Query = "SELECT SERVERPROPERTY('ServerName')"
            $si = Invoke-Sqlcmd -Query $Query
            $si = $si.Item(0)
        }
        else {
            $si = $serverName
        }
        $serverName = $si
        Write-Host("Servername set to $serverName")

        ### Change Authentication From Windows Auth to Mixed Mode 
        ChangeAuthenticationFromWindowsToMixed -servername $servername -IsMixedMode $IsMixedMode -username $username -password $password

        Write-Host("Configuring SQL to allow running of External Scripts")
        ### Allow Running of External Scripts , this is to allow R Services to Connect to SQL
        ExecuteSQL -query "EXEC sp_configure  'external scripts enabled', 1" -dbName "master"

        ### Force Change in SQL Policy on External Scripts 
        ExecuteSQL -query "RECONFIGURE WITH OVERRIDE" -dbName "master"
        Write-Host("SQL Server Configured to allow running of External Scripts")

        ### Enable FileStreamDB if Required by Solution 
        if ($EnableFileStream -eq 'Yes') {
            # Enable FILESTREAM
            $instance = "MSSQLSERVER"
            $wmi = Get-WmiObject -Namespace "ROOT\Microsoft\SqlServer\ComputerManagement14" -Class FilestreamSettings | where-object {$_.InstanceName -eq $instance}
            $wmi.EnableFilestream(3, $instance)
            Stop-Service "MSSQ*" -Force
            Start-Service "MSSQ*"
 
            Set-ExecutionPolicy Unrestricted
            #Import-Module "sqlps" -DisableNameChecking
            ExecuteSQL -query "EXEC sp_configure filestream_access_level, 2" -dbName "master"
            ExecuteSQL -query "RECONFIGURE WITH OVERRIDE" -dbName "master"
            Stop-Service "MSSQ*"
            Start-Service "MSSQ*"
        }
        else { 
            Write-Host("Restarting SQL Services")
            ### Changes Above Require Services to be cycled to take effect 
            ### Stop the SQL Service and Launchpad wild cards are used to account for named instances  
            Restart-Service -Name "MSSQ*" -Force
        }

    ##########################################################################
    # Install Power BI
    ##########################################################################
    InstallPowerBI

    ##########################################################################
    # Create Shortcuts
    ##########################################################################
        ##Create Shortcuts and Autostart Help File 
        $shortcutpath = $scriptPath+$Shortcut
        Copy-Item $shortcutpath C:\Users\Public\Desktop\
        Copy-Item $shortcutpath "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\"
        $WsShell = New-Object -ComObject WScript.Shell
        $shortcut = $WsShell.CreateShortcut($desktop + $checkoutDir + ".lnk")
        $shortcut.TargetPath = $solutionPath
        $shortcut.Save()
        Write-Host("Shortcuts made on Desktop")

    
    ##########################################################################
    # Check if the SQL server and database exists
    ##########################################################################
        $query = "IF NOT EXISTS(SELECT * FROM sys.databases WHERE NAME = '$DatabaseName') CREATE DATABASE $DatabaseName"
        #Invoke-Sqlcmd -ServerInstance $serverName -Username $username -Password $password -Query $query -ErrorAction SilentlyContinue
        ExecuteSQL -query $query -dbName "master"
        if ($? -eq $false)
        {
            Write-Host -ForegroundColor Red "Failed the test to connect to SQL server: $serverName database: $DatabaseName !"
            Write-Host -ForegroundColor Red "Please make sure: `n`t 1. SQL Server: $serverName exists;
                                             `n`t 2. The current user has the right credential for SQL server access."
            exit
        }
        $query = "USE $DatabaseName;"
        ExecuteSQL -query $query -dbName "master"
        Write-Host("Using database $DatabaseName")
    
    ##########################################################################
    # Create tables
    ##########################################################################
        Write-Host("Creating tables")
        $scriptFile = $scriptPath + "pdm_create_tables.sql"
        ExecuteSQLScript -scriptFile $scriptFile

    ##########################################################################
    # Load data
    ##########################################################################
        Write-Host("Populating tables")
        Get-ChildItem -Path $SolutionData -File -Filter *.csv | ForEach-Object {
            $datafile = $_.BaseName
            $destination = $_.FullName
            Write-Host -ForeGroundColor 'magenta'("    Populate SQL table: {0}..." -f $dataFile)
            $tableName = $DatabaseName + ".dbo." + $dataFile
            $tableSchema = $SolutionData + $dataFile + ".xml"
            ExecuteBCP("bcp $tableName format nul -c -x -f $tableSchema -t ','")
            Write-Host -ForeGroundColor 'magenta'("    Loading {0} to SQL table..." -f $dataFile)
            ExecuteBCP("bcp $tableName in $destination -F 2 -t ',' -f $tableSchema -C 'RAW' -b 20000")
        }
    
    ##########################################################################
    # Fix the data after loading
    ##########################################################################
        Write-Host("Fixing data after populating")
        $scriptFile = $scriptPath + "pdm_update_tables.sql"
        ExecuteSQLScript -scriptFile $scriptFile

    ##########################################################################
    # Run feature engineering
    ##########################################################################
        Write-Host("Running feature engineering")
        $scriptFile = $scriptPath + "pdm_feature_engineering.sql"
        ExecuteSQLScript -scriptFile $scriptFile

    WriteThanksMessage -SolutionName $SolutionName -servername $serverName -databaseName $DatabaseName -moreSolutionsURL $moreSolutionsURL

}
else {
    Write-Host ("To install this Solution you need to run Powershell as an Administrator. This program will close automatically in 20 seconds")
    Start-Sleep -s 20
    ## Close Powershell 
    Exit-PSHostProcess
    EXIT 
}