# README

## Initialization

1. Get an API key from [Fortnite Tracker](https://fortnitetracker.com/site-api).
2. Add a one line .txt file named `api_key.txt` to the root directory with your API key as the only text.
3. Run the `Import-FNSModule.ps1` script. This must be done every time you open a new instance of Powershell. Alternatively, add the module to your Powershell profile to avoid having to import every time.
4. Initialize the directories needed by the module: `Initialize-FNSDirectories`
5. Add *at least* one user: `New-FNPlayer [-Username] <string[]> [-Platform] <string[]>`

    **Valid Platform entries:**
    * pc
    * xbox
    * psn

## Help

* For a list of available commands: `Get-Command -Module Fortnite-Stats`
* Command self-documentation will be updated in the future
