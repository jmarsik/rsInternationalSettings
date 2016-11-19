rsInternationalSettings DSC Module
=======================

**rsInternationalSettings** is a PowerShell DSC resource module, which can be used to manage international system settings such as setting system locale, time zone user keyboard layout and culture (formatting) settings.

##Changelog

######v0.4
More changes in the method of setting of the values, previous attempt failed when changing the user locale, because it looks like that the Set-Culture PowerShell cmdlet doesn't work under LocalSystem user account (used by default by DSC) and also when launched via DSC under any account! So I tried to use the trick with scheduled job to discover problems with registering this scheduled job under LocalSystem account :) The only combination left was running DSC resource under other than LocalSystem account and using the scheduled job trick in the resource's code. Aaaand ... it worked! Hurray!

######v0.3
Completely refactored and changed rsUserLocale resource, separated date, time and numbers formatting user locale from UI user locale, changed method of setting of the values, cleaned up copying from current user to other users and the template for new users.

######v0.2
Added support for setting manual peer list for NTP servers in rsTime using the PeerList variable.
######v0.1
Added support for setting time zone, culture, system local and all local (including default) user profile settings.

####To-do:
Add support for provision of an optional time server parameter.

##Syntax##

See usage examples below...

###Usage Examples

**Set Server to US locale and user input**

This will force all system and user settings to US codepage, including input setting:

```
    $credential = [pscredential]::new("SomeLocalAccountWithAdminRights", (ConvertTo-SecureString -String "PasswordOfThatAccount" -AsPlainText -Force))

    rsSysLocale SysLoc
    {
        SysLocale = "en-US"
    }
    
    rsTime time
    {
        TimeZone = "Central Standard Time"
    }
    
    rsUserLocale UserLocale
    {
        Name = "UserLocale"
        DateTimeAndNumbersCulture = "en-US"
        UICulture = "en-US"
        LocationID = "244"
        LCIDHex = "0409"
        InputLocaleID = "00000409"

        PsDscRunAsCredential = $credential
    }
```

**Set Server to UK locale and user input**

This will force all system and user settings to UK codepage, including input setting:

```
    $credential = [pscredential]::new("SomeLocalAccountWithAdminRights", (ConvertTo-SecureString -String "PasswordOfThatAccount" -AsPlainText -Force))

    rsSysLocale SysLoc
    {
        SysLocale = "en-GB"
    }
    
    rsTime time
    {
        TimeZone = "GMT Standard Time"
    }
    
    rsUserLocale UserLocale
    {
        Name = "UserLocale"
        DateTimeAndNumbersCulture = "en-GB"
        UICulture = "en-GB"
        LocationID = "242"
        LCIDHex = "0809"
        InputLocaleID = "00000809"

        PsDscRunAsCredential = $credential
    }
```

**Add manual NTP peer server list**

To override the default time.windows.com NTP server or the automatic AD member time synchronisation, you can specify the PeerList parameter for rsTime, which will register the Windows Time service and configure it accordingly. Please note that omitting this parameter will always result in Windows Time Service to be unregistered if one is running already.

    rsTime time
    {
        TimeZone = "GMT Standard Time"
        PeerList = @("0.pool.ntp.org","1.pool.ntp.org","2.pool.ntp.org")
    }

###Acceptable parameter values

#####$DateTimeAndNumbersCulture
User locale used to format date, time, numbers and other such values.
Use the following PowerShell command to list all available options:

    [cultureinfo]::GetCultures([System.Globalization.CultureTypes]::AllCultures)

#####$UICulture
User locale used for the language of the user interface (menu items, ...).

#####$TimeZone
System time zone name description. Ex "GMT Standard Time"
Use the `tzutil /l` command to list all possible options.

#####$PeerList
An array of NTP servers to configure the local Windows Time service.

#####$LocationID
Geographical System location ID (GEOID). Refer to [Table of Geographical Locations](http://msdn.microsoft.com/en-us/library/windows/desktop/dd374073(v=vs.85).aspx) for full list of possible options.

#####$LCIDHex
Keyboard Language ID as defined by Microsoft. Used in combination with InputLocaleID, see [Keyboard Language & Locale IDs Assigned by Microsoft](http://msdn.microsoft.com/en-gb/goglobal/bb895996.aspx)

#####$InputLocaleID
Locale ID as defined by Microsoft. Used in combination with LCIDHex, see [Keyboard Language & Locale IDs Assigned by Microsoft](http://msdn.microsoft.com/en-gb/goglobal/bb895996.aspx)

###Keyboard options tip:
To easily identify correct settings for user keyboard options (*LCIDHex* & *InputLocaleID*), set the desired keyboard settings on a Windows 8/2012, or later, machine and run the following PS command `Get-WinUserLanguageList`. Property named "InputMethodTips" will provide the correct Language Code ID as `{<LCIDHex>:<InputLocaleID>}`.

#####Example:

    PS C:\Users\Administrator> Get-WinUserLanguageList
    
    LanguageTag : en-US
    Autonym : English (United States)
    EnglishName : English
    LocalizedName   : English (United States)
    ScriptName  : Latin script
    InputMethodTips : {0409:00000409}
    Spellchecking   : True
    Handwriting : False

