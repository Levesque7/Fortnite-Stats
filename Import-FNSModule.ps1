$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$moduleName = "Fortnite-Stats"
$test = Get-Module -Name $moduleName
if ($test) { Remove-Module -Name $moduleName }
Import-Module "$ScriptDir\$moduleName.psd1"