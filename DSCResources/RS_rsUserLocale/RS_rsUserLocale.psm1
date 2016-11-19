function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name = "UserLocale"
    )

    ClearDown

    try
    {
        $DateTimeAndNumbersCulture = (Get-Culture).Name
        $UICulture = (Get-WinUILanguageOverride).Name
        Write-Verbose "Current DateTimeAndNumbersCulture is $DateTimeAndNumbersCulture, UICulture is $UICulture"

        $LocationID = Get-WinHomeLocation
        Write-Verbose "Current WinHomeLocation is $($LocationID.HomeLocation), GeoId is $($LocationID.GeoId)"

        $UserLanguageList = @((Get-WinUserLanguageList).InputMethodTips.Split(':'))
        $LCIDHex = $UserLanguageList[0]
        $InputLocaleID = $UserLanguageList[1]
        Write-Verbose "Current Keyboard LCIDHex is $LCIDHex and InputLocaleID is $InputLocaleID"
    }
    catch
    {
        
    }
    finally
    {
        
    }
    
    $returnValue = @{
        Name = $Name
        DateTimeAndNumbersCulture = $DateTimeAndNumbersCulture
        UICulture = $UICulture
        LocationID = $LocationID.GeoId
        LCIDHex = $LCIDHex
        InputLocaleID = $InputLocaleID
    }
    
    $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name = "UserLocale",

        [System.String]
        $DateTimeAndNumbersCulture,

        [System.String]
        $UICulture,

        [System.String]
        $LocationID,

        [System.String]
        $LCIDHex,

        [System.String]
        $InputLocaleID
    )

    try
    {
        ClearDown

        # Set current user's settings before copying the affected registry hives to the rest of the local users
        Set-WinHomeLocation $LocationID
        Set-Culture $DateTimeAndNumbersCulture
        Set-WinUserLanguageList $DateTimeAndNumbersCulture -Force
        Set-WinUILanguageOverride $UICulture
        # Set date, time and numbers formatting to specific value instead of "Match Windows display language"
        Set-WinCultureFromLanguageListOptOut -OptOut $true
        # For that we have to perform Set-Culture once again
        Set-Culture $DateTimeAndNumbersCulture
        
        ClearDown

        $null = New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS
        # settings for "new users"
        reg load HKU\NEW_USER C:\Users\Default\NTUSER.DAT

        Set-Location HKU:\

        $currentSID = (New-Object System.Security.Principal.NTAccount((whoami))).Translate([System.Security.Principal.SecurityIdentifier]).value
        Write-Verbose "Current user's SID is $currentSID"

        # remove backup regional settings to prevent conflicts
        if (Test-Path -Path "HKU:\$currentSID\Control Panel\International\User Profile System Backup")
        {
            Write-Verbose "Removing current user's User Profile System Backup"
            Remove-Item "HKU:\$currentSID\Control Panel\International\User Profile System Backup" -Recurse -Force -Verbose
        }

        Write-Verbose "Making changes to all local users..."

        # copy current user's locale settings to all local users' registry hives, but skip system and default hives
        Get-ChildItem | Where-Object { ! ($_.Name -match ".*Classes$")} | ForEach-Object {
            $path = (Resolve-Path $_).Path

            Write-Verbose "Processing local user $($_.PSChildName)"

            # skip current user and .DEFAULT registry hive as we loop through all existing users
            # ... because .DEFAULT has SAME values as SYSTEM user ?!?
            if (($currentSID -like $_.PSChildName) -or (".DEFAULT" -like $_.PSChildName))
            {
                Write-Verbose "`nSkipping current user or .DEFAULT user registry hives`n"
            }
            else
            {
                Write-Verbose "`nForce all culture settings to $DateTimeAndNumbersCulture"

                if (Test-Path -Path "$path\Control Panel\International")
                {
                    Write-Verbose "`nRemoving $path\Control Panel\International"
                    Remove-Item "$path\Control Panel\International" -Recurse -Force

                    Write-Verbose "Copying current user International settings to $path\Control Panel\International"
                    Copy-Item "HKCU:\Control Panel\International" -Destination "$path\Control Panel" -Recurse -Force
                }

                Write-Verbose "Force default keyboard language to $InputLocaleID for $($_.PSChildName)"
                
                if (Test-Path -Path "$path\Keyboard Layout\Preload")
                {
                    Remove-ItemProperty "$path\Keyboard Layout\Preload" -Name "1" -Force
                }
                Set-ItemProperty "$path\Keyboard Layout\Preload" -Name "1" -Value $InputLocaleID -Type String -Force
            }
        }

        Set-Location C:\
        Remove-PSDrive HKU

        # will help with successful unload of the registry hive, see comments in ClearDown function
        Remove-Variable path
        Remove-Variable currentSID
        
        ClearDown

        reg unload HKU\NEW_USER
        
        Write-Verbose "User Reginal Settings DONE"
    }
    catch
    {
        $error[0].Exception
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name = "UserLocale",

        [System.String]
        $DateTimeAndNumbersCulture,

        [System.String]
        $UICulture,

        [System.String]
        $LocationID,

        [System.String]
        $LCIDHex,

        [System.String]
        $InputLocaleID
    )

    try
    {
        # Discover current settings for the system account
        $CurrentDateTimeAndNumbersCulture = (Get-Culture).name
        $CurrentDateTimeAndNumbersCultureLegacy = Get-Item 'HKCU:\Control Panel\International' | Get-ItemPropertyValue -Name LocaleName
        $CurrentUICulture = (Get-WinUILanguageOverride).name
        $CurrentLocationID = Get-WinHomeLocation
        $CurrentUserLanguageList = (Get-WinUserLanguageList).InputMethodTips
        $CurrentLCIDHex = $CurrentUserLanguageList.Split(':')[0]
        $CurrentInputLocaleID = $CurrentUserLanguageList.Split(':')[1]

        Write-Verbose "Current DateTimeAndNumbersCulture is $CurrentDateTimeAndNumbersCulture"
        if ($CurrentDateTimeAndNumbersCulture -like $DateTimeAndNumbersCulture)
        {
            Write-Verbose "Culture setting for date, time and numbers formatting is consistent - $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy)"
            $DateTimeAndNumbersCultureResult = $true
        }
        else
        {
            Write-Verbose "Culture setting for date, time and numbers formatting is inconsistent - $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy)"
            $DateTimeAndNumbersCultureResult = $false
        }

        Write-Verbose "Current UICulture is $CurrentUICulture"
        if ($CurrentUICulture -like $UICulture)
        {
            Write-Verbose "Culture setting for user interface is consistent - $CurrentUICulture"
            $UICultureResult = $true
        }
        else
        {
            Write-Verbose "Culture setting for user interface is inconsistent - $CurrentUICulture"
            $UICultureResult = $false
        }

        Write-Verbose "Current WinHomeLocation is $($CurrentLocationID.HomeLocation), GeoId is $($CurrentLocationID.GeoId)"
        if ($($CurrentLocationID.GeoId) -like $LocationID)
        {
            Write-Verbose "GeoId setting is consistent"
            $GeoIdResult = $true
        }
        else
        {
            Write-Verbose "GeoId setting is inconsistent"
            $GeoIdResult = $false
        }

        Write-Verbose "Current Keyboard LCIDHex is $CurrentLCIDHex and InputLocaleID is $CurrentInputLocaleID"
        if ($CurrentUserLanguageList -like ($LCIDHex,$InputLocaleID -join ":"))
        {
            Write-Verbose "Input setting is consistent"
            $InputResult = $true
        }
        else
        {
            Write-Verbose "Input setting is inconsistent"
            $InputResult = $false
        }

        if (($InputResult -eq $true) -and ($GeoIdResult -eq $true) -and ($UICultureResult -eq $true) -and ($DateTimeAndNumbersCultureResult -eq $true))
        {
            $result = $true
            Write-Verbose "All settings are consistent"
        }
        else
        {
            $result = $false
            Write-Verbose "Some or all settings are inconsistent"
        }
    }
    catch
    {
        
    }
    finally
    {
        
    }
    
    $result
}


# Garbage collection function
# because unloading registry hive is only possible when there are no references to it
#   including instances that are out of scope, but not garbaged
# see https://social.technet.microsoft.com/Forums/en-US/034338e6-5db3-4fa1-8140-cdbfe9235e59/using-reg-load-and-reg-unload-setitemproperty-and-newitemproperty-bugs?forum=winserverpowershell
function ClearDown
{
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
}


Export-ModuleMember -Function *-TargetResource
