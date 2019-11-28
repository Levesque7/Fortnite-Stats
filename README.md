# Initialization

1. Run the `Import-FNSModule.ps1` script. This must be done every time you open a new instance of Powershell. Alternatively, add the module to your Powershell profile.
2. Initialize the directories needed by the module: `Initialize-FNSDirectories`
3. Add *at least* one user: `New-FNPlayer [-Username] <string[]> [-Platform] <string[]>`

    **Valid Platform entries:**
    * pc
    * xbox
    * psn
