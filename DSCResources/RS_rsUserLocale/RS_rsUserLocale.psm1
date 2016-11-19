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

        # log current settings first
        $CurrentDateTimeAndNumbersCulture = (Get-Culture).Name
        $CurrentDateTimeAndNumbersCultureLegacy = Get-Item 'HKCU:\Control Panel\International' | Get-ItemPropertyValue -Name LocaleName
        Write-Verbose "Current DateTimeAndNumbersCulture is $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy Control Panel\International\LocaleName from registry)"

        # TODO: should compare all the values, not just culture used for formatting!
        if ($CurrentDateTimeAndNumbersCultureLegacy -ne $DateTimeAndNumbersCulture)
        {
            # set current user's settings before copying values from current user's registry to the rest of the local users
            Write-Verbose "Changing basic locale settings for current user"

            # the specific order of those settings is necessary
            # to correctly apply all the overrides and opt outs and such stuff

            Set-WinHomeLocation $LocationID

            # run Set-Culture for the first time, this time normally in the DSC execution flow, more info below
            Set-Culture $DateTimeAndNumbersCulture

            Set-WinUserLanguageList $DateTimeAndNumbersCulture -Force
            Set-WinUILanguageOverride $UICulture
            # set date, time and numbers formatting to specific value instead of "Match Windows display language"
            Set-WinCultureFromLanguageListOptOut -OptOut $true

            # from my testing it looks like that Set-Culture method doesn't work at all when launched under LocalSystem
            #  account (which is the account that PowerShell DSC usually uses), also other methods of setting regional
            #  settings doesn't work (I tried PowerShell cmdlets, control.exe with intl.cpl, direct registry manipulation)
            # maybe it would work with the following trick (running of the cmdlet under scheduled job, which means
            #  different "scope of things", out of the normal DSC execution flow), but unfortunately the registration
            #  of the scheduled job by this simple method also doesn't work under LocalSystem account :)
            # therefore for this resource to work, one must execute it under OTHER THAN LocalSystem user account
            #  by using the PsDscRunAsCredential parameter of the resource in DSC configuration
            Register-ScheduledJob -Name "Set-Culture" -RunNow -ScriptBlock {
                Param(
                    $Culture
                )
                Set-Culture $Culture -Verbose
            } -ArgumentList @($DateTimeAndNumbersCulture)
            sleep 1
            Get-Job -Name "Set-Culture" | Receive-Job -Wait
            sleep 1
            Unregister-ScheduledJob -Name "Set-Culture"
            
            ClearDown

            Write-Verbose "User locale basic settings DONE, requesting reboot"

            # require reboot after changing of the basic settings, system will "pick up" the changes
            $global:DSCMachineStatus = 1
            
            return
        }
        else
        {
            Write-Verbose "User locale basic settings already set, continuing with copying of the settings to other users"
        }

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

                if (Test-Path -Path (Join-Path $path "Control Panel\International"))
                {
                    Write-Verbose "`nRemoving $path\Control Panel\International"
                    Remove-Item -Path (Join-Path $path "Control Panel\International") -Recurse -Force -Verbose

                    Write-Verbose "Copying current user's International settings to $path\Control Panel\International"
                    Copy-Item -Path "HKCU:\Control Panel\International" (Join-Path $path "Control Panel\") -Force -Recurse -Verbose
                }

                Write-Verbose "Force default keyboard language to $InputLocaleID for $($_.PSChildName)"
                
                if (Test-Path -Path (Join-Path $path "Keyboard Layout\Preload"))
                {
                    Remove-ItemProperty -Path (Join-Path $path "Keyboard Layout\Preload") -Name "1" -Force
                }
                Set-ItemProperty -Path (Join-Path $path "Keyboard Layout\Preload") -Name "1" -Value $InputLocaleID -Type String -Force
            }
        }

        Set-Location C:\
        Remove-PSDrive HKU

        # will help with successful unload of the registry hive, see comments in ClearDown function
        Remove-Variable path
        Remove-Variable currentSID
        
        ClearDown

        reg unload HKU\NEW_USER
        
        Write-Verbose "User locale all settings DONE, requesting reboot"

        # require reboot after performing all the changes
        $global:DSCMachineStatus = 1
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
        # discover current settings for the system account
        
        # user locale, which means datetime and numbers formatting
        $CurrentDateTimeAndNumbersCulture = (Get-Culture).Name
        $CurrentDateTimeAndNumbersCultureLegacy = Get-Item 'HKCU:\Control Panel\International' | Get-ItemPropertyValue -Name LocaleName
        Write-Verbose "Current DateTimeAndNumbersCulture is $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy Control Panel\International\LocaleName from registry)"
        if ($CurrentDateTimeAndNumbersCultureLegacy -like $DateTimeAndNumbersCulture)
        {
            Write-Verbose "Culture setting for date, time and numbers formatting is consistent - $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy)"
            $DateTimeAndNumbersCultureResult = $true
        }
        else
        {
            Write-Verbose "Culture setting for date, time and numbers formatting is inconsistent - $CurrentDateTimeAndNumbersCulture, $CurrentDateTimeAndNumbersCultureLegacy (legacy)"
            $DateTimeAndNumbersCultureResult = $false
        }

        $CurrentUICulture = (Get-WinUILanguageOverride).Name
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

        $CurrentLocationID = Get-WinHomeLocation
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

        $CurrentUserLanguageList = (Get-WinUserLanguageList).InputMethodTips
        $CurrentLCIDHex = $CurrentUserLanguageList.Split(':')[0]
        $CurrentInputLocaleID = $CurrentUserLanguageList.Split(':')[1]
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

        # more complicated check - if user locale is set to the same value (we will check just the LocaleName value, not every formatting setting) for every user

        $LocaleNameSyncedResult = $true

        $null = New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS
        # settings for "new users"
        reg load HKU\NEW_USER C:\Users\Default\NTUSER.DAT | Out-Null
        Set-Location HKU:\

        $currentSID = (New-Object System.Security.Principal.NTAccount((whoami))).Translate([System.Security.Principal.SecurityIdentifier]).value
        Write-Verbose "Current user's SID is $currentSID"

        Get-ChildItem | Where-Object { ! ($_.Name -match ".*Classes$")} | ForEach-Object {
            $path = (Resolve-Path $_).Path

            Write-Verbose "Processing local user $($_.PSChildName)"

            # skip SYSTEM (which should be the current user!) and .DEFAULT registry hive as we loop through all existing users
            # ... because .DEFAULT has SAME values as SYSTEM user (Set-Culture under SYSTEM user results in value change under .DEFAULT)
            if (($currentSID -like $_.PSChildName) -or (".DEFAULT" -like $_.PSChildName))
            {
                Write-Verbose "`nSkipping SYSTEM (current user) and .DEFAULT user registry hives`n"
            }
            else
            {
                if ((Get-ItemPropertyValue -Path (Join-Path $path "Control Panel\International") -Name LocaleName) -eq $DateTimeAndNumbersCulture)
                {
                    Write-Verbose "Locale name is consistent"
                    $LocaleNameSyncedResult = $true
                }
                else
                {
                    Write-Verbose "Locale name is inconsistent"
                    $LocaleNameSyncedResult = $false
                }
            }
        }

        Set-Location C:\
        Remove-PSDrive HKU

        # will help with successful unload of the registry hive, see comments in ClearDown function
        Remove-Variable path
        Remove-Variable currentSID
        
        ClearDown

        reg unload HKU\NEW_USER | Out-Null

        # end of more complicated check :)
        
        # check if everything matches or something is off
        if (($InputResult -eq $true) -and ($GeoIdResult -eq $true) -and ($UICultureResult -eq $true) -and ($DateTimeAndNumbersCultureResult -eq $true) -and ($LocaleNameSyncedResult -eq $true))
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
