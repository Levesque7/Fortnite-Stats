# README

## Initialization

1. Get an API key from [Fortnite Tracker](https://fortnitetracker.com/site-api).
2. Run the `Import-FNSModule.ps1` script. This must be done every time you open a new instance of Powershell. Alternatively, add the module to your Powershell profile to avoid having to import every time.
3. Make sure to run `Set-TRNApiKey` or `Get-TRNApiKey` at the beginning of a script or program, or when you load the module.
4. Add *at least* one user: `New-FNPlayer [-Username] <string[]> [-Platform] <string[]>`. This should be the Epic username, regardless of platform.

    **Valid Platform entries:**
    * pc
    * xbox
    * psn

## Help

* For a list of available commands: `Get-Command -Module Fortnite-Stats`
* Command self-documentation will be updated in the future
