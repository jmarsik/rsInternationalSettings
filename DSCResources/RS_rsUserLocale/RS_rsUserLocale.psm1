function ClearDown {
[gc]::Collect()
[gc]::WaitForPendingFinalizers()
}

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
        $Culture = (Get-Culture).name
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
		Culture = $Culture
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
		$Culture,

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

        Set-WinHomeLocation $LocationID
        Set-Culture $Culture

        Set-WinUserLanguageList $Culture -force -confirm:$false

        Set-WinDefaultInputMethodOverride ($LCIDHex,$InputLocaleID -join ":")
        Set-WinCultureFromLanguageListOptOut 1
        Set-WinDefaultInputMethodOverride ($LCIDHex,$InputLocaleID -join ":")
        Set-WinUILanguageOverride $Culture
        
        ClearDown

        $null = New-PSDrive -Name HKU   -PSProvider Registry -Root Registry::HKEY_USERS
        reg load HKU\DEFAULT_USER C:\Users\Default\NTUSER.DAT
        Set-Location HKU:\

        $currentSID = (New-Object System.Security.Principal.NTAccount((whoami))).Translate([System.Security.Principal.SecurityIdentifier]).value
        Write-Verbose "Current Users SID is $currentSID"

        # Copy current user's locale settings to all local user's registry hives (including the default user)
        Get-ChildItem | Where-Object { ! ($_.Name -match ".*Classes$")} | ForEach-Object {

            # Skip current user's registry hive as we loop through all existing users
            #Write-Verbose "Try skipping $currentSID"
            write-verbose "Making changes to user SID $($_.PSChildName)"

            if (($currentSID -like $_.PSChildName) -or (".DEFAULT" -like $_.PSChildName))
            {
                Write-Verbose "Skipping current user regstry hive: $currentSID"

            }
            else
            {
                $path = (Resolve-Path $_).path
                Write-Verbose "Modifying: $path"

                if (Test-Path -Path "$path\Control Panel\International")
                {
                    #Write-Verbose "Making a backup of $path\Control Panel\International"
                    #Copy-Item "$path\Control Panel\International" -Destination "$path\Control Panel\International_backup\" -Recurse -Force
                    
                    Write-Verbose "Removing $path\Control Panel\International"
                    Remove-Item "$path\Control Panel\International" -Recurse -Force

                    Write-Verbose "Copying current user International settings to $_\Control Panel\International"
                    Copy-Item "HKCU:\Control Panel\International" -Destination "$_\Control Panel" -Recurse -Force
                }
                
                Write-Verbose "Force default input language to the provided InputLocaleID for everyone"
                Set-ItemProperty "$path\Keyboard Layout\Preload" -Name "1" -Value $InputLocaleID -Type String -Force
            }

            if (Test-Path -Path "$path\Control Panel\International\User Profile System Backup")
            {
                Remove-Item "$path\Control Panel\International\User Profile System Backup" -Recurse -Force
            }


        }

        Set-Location C:\
        Remove-PSDrive HKU
        ClearDown
        reg unload HKU\DEFAULT_USER
        
        Write-Verbose "New User Account Reginal Settings DONE"

    }
    catch
    {
    }

	#Resource requires a system reboot.
	#$global:DSCMachineStatus = 1

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
		$Culture,

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
        $CurrentCulture = (Get-Culture).name
        $CurrentLocationID = Get-WinHomeLocation
        $CurrentUserLanguageList = (Get-WinUserLanguageList).InputMethodTips
        $CurrentLCIDHex = $CurrentUserLanguageList.Split(':')[0]
        $CurrentInputLocaleID = $CurrentUserLanguageList.Split(':')[1]

        Write-Verbose "Current CurrentCulture is $CurrentCulture"
        if ($CurrentCulture -like $Culture)
        {
            Write-Verbose "Culture setting is consistent - $CurrentCulture"
            $CultureResult = $true
        }
        else
        {
            Write-Verbose "Culture setting is inconsistent - $CurrentCulture"
            $CultureResult = $false
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

        if (($InputResult -eq $true) -and ($GeoIdResult -eq $true) -and ($CultureResult -eq $true))
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


Export-ModuleMember -Function *-TargetResource

