$credential = [pscredential]::new("Lekis", (ConvertTo-SecureString -String "Oa1jGlMCeBlW8Q" -AsPlainText -Force))



psexec /s /nobanner /accepteula powershell -Command "Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName"
reg load HKU\NEW_USER C:\Users\Default\NTUSER.DAT ; New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS ; Get-ItemPropertyValue -Path 'HKU:\NEW_USER\Control Panel\International\' -Name LocaleName ; Remove-PSDrive -Name HKU ; reg unload HKU\NEW_USER
Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName



Invoke-DscResource -Name rsUserLocale -Method Test -ModuleName rsInternationalSettings -Verbose -Property @{
    Name = "UserLocale"
    DateTimeAndNumbersCulture = "cs-CZ"
    UICulture = "en-US"
    LocationID = "75"
    LCIDHex = "0405"
    InputLocaleID = "00000405"
    PsDscRunAsCredential = $credential
}



Invoke-DscResource -Name cScriptWithParams -Method Test -ModuleName DSC_ColinsALMCorner.com -Verbose -Property @{
    SetScript = {
#        Write-Verbose $(Get-Module | Format-List | Out-String)
        Write-Verbose $(whoami)
        Write-Verbose $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
        Set-Culture $Culture -Verbose
        Write-Verbose $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
#        Write-Verbose $(Get-Module | Format-List | Out-String)
    }
    TestScript = {                
        Write-Verbose $(whoami)
        (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName) -eq $Culture
    }
    GetScript = {
        @{
            cParams = @{
                Culture = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName)
            }
        }
    }
    cParams = @{
        Culture = "cs-CZ"
    }
    PsDscRunAsCredential = $credential
}



Invoke-DscResource -Name cScriptWithParams -Method Test -ModuleName DSC_ColinsALMCorner.com -Verbose -Property @{
    SetScript = {
#        Write-Verbose $(Get-Module | Format-List | Out-String)
        Write-Verbose $(whoami)
        Write-Verbose $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)

        $CultureToSet = $Culture
        $xml = @"
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current" CopySettingsToDefaultUserAcct="true" CopySettingsToSystemAcct="true" />
    </gs:UserList>
    <gs:UserLocale>
        <gs:Locale Name="$CultureToSet" SetAsCurrent="true" ResetAllSettings="true" />
    </gs:UserLocale>
</gs:GlobalizationServices>
"@
        Set-Content -Path "C:\locale.xml" -Encoding UTF8 -Value $xml

        # https://www.autoitscript.com/forum/topic/118706-fastest-way-command-line-to-change-system-locale/
        # http://archives.miloush.net/michkap/archive/2006/05/30/610505.html
        # http://archives.miloush.net/michkap/archive/2006/05/20/602745.html
        # https://msdn.microsoft.com/en-ie/goglobal/bb964650(en-us).aspx
        # arguments passed as array, double quotes escaped with backtick
        $a = @("intl.cpl,,/f:`"c:\locale.xml`"")
        & control.exe $a

        Remove-Item -Path "C:\locale.xml" -Force

        Write-Verbose $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
#        Write-Verbose $(Get-Module | Format-List | Out-String)
    }
    TestScript = {                
        Write-Verbose $(whoami)
        (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName) -eq $Culture
    }
    GetScript = {
        @{
            cParams = @{
                Culture = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName)
            }
        }
    }
    cParams = @{
        Culture = "cs-CZ"
    }
    PsDscRunAsCredential = $credential
}



$credential = [pscredential]::new("Lekis", (ConvertTo-SecureString -String "Oa1jGlMCeBlW8Q" -AsPlainText -Force))
Register-ScheduledJob -Name "Set-Culture" -Credential $credential -RunNow -ScriptBlock {
        Param(
            $Culture
        )
        Write-Host $(whoami)
        Write-Host $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
        Set-Culture $Culture -Verbose
        Write-Host $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
} -ArgumentList @("cs-CZ")
sleep 1
Get-Job -Name "Set-Culture" | Receive-Job -Wait
sleep 1
Unregister-ScheduledJob -Name "Set-Culture"



Invoke-DscResource -Name cScriptWithParams -Method Test -ModuleName DSC_ColinsALMCorner.com -Verbose -Property @{
    SetScript = {
        Register-ScheduledJob -Name "Set-Culture" -RunNow -ScriptBlock {
                Param(
                    $Culture
                )
                Write-Host $(whoami)
                Write-Host $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
                Set-Culture $Culture -Verbose
                Write-Host $(Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International\' -Name LocaleName)
        } -ArgumentList @($Culture)
        sleep 1
        Get-Job -Name "Set-Culture" | Receive-Job -Wait
        sleep 1
        Unregister-ScheduledJob -Name "Set-Culture"
    }
    TestScript = {                
        Write-Verbose $(whoami)
        (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName) -eq $Culture
    }
    GetScript = {
        @{
            cParams = @{
                Culture = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\International" -Name LocaleName)
            }
        }
    }
    cParams = @{
        Culture = "cs-CZ"
    }
    # MUSI byt spousteno pod lokalnim uzivatelskym uctem (nikoliv pod vychozim Local System, kdyz neni tento parametr uveden), protoze pridavani
    #  scheduled jobs / tasks pod Local System nefunguje; zmeny regional settings pod Local System take nefunguji, aspon teda zmena "user locale"
    PsDscRunAsCredential = $credential
}
