$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
$key = @{"TRN-Api-Key"=(Get-Content -Path "$ScriptDir\api_key.txt")}
# Directories
$matchDir = "match_histories"
$recycleBinDir = "recycle_bin"
$logsDir = "logs"
$pagesDir = "pages"
$eventsDir = "events"
$assetsDir = "assets"
$allDirs = @($matchDir,$recycleBinDir,$logsDir,$pagesDir,$eventsDir,$assetsDir)
# Filenames
$playerList = "$assetsDir\players.CSV"
$requestsLog = "requests.log"
$playerTransactionLog = "player_transactions.log"
$matchDiscoveryLog = "match_discovery.log"

$platforms = @("pc","xbox","psn")
$defaultScoring = @(1,6,1,0)
# Solo  - p2    - top 1,10,25
# Duo   - p10   - top 1,5,12
# Squad - p9    - top 1,3,6 

Function Initialize-FNSDirectories {
    foreach ($dir in $allDirs) {
        $exist? = Test-Path "$ScriptDir\$dir"
        if (!$exist?) { New-Item "$ScriptDir\$dir" -ItemType Directory }
    }
}

Function Get-FNPlayerList {
    $export = @()
    $list = Import-Csv "$ScriptDir\$playerList"
    $update = $false
    
    foreach ($p in $list) {
        if ($p.AccountID -eq "") { 
            $AccountID = Get-FNAccountID -Username $p.Username -Platform $p.Platform 
            $update = $true
        }
        else {
            $AccountID = $p.AccountID
        }
        $object = [pscustomobject]@{
            Username = $p.Username
            Platform = $p.Platform
            AccountID = $AccountID
        }
        $export += $object
    }
    if ($update) { $export | Export-Csv -Path "$ScriptDir\$playerList" -Force -NoTypeInformation }
    $export
}

Function Get-FNAccountID {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][string]$Platform
    )
    
    $playerStats = "https://api.fortnitetracker.com/v1/profile/$platform/$username"
    $response = Invoke-RestMethod -Uri $playerStats -Headers $key
    if ($response.error -eq "Player Not Found") { Throw $response.error }
    $response.AccountID
}

Function New-FNPlayer {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][ValidateSet("pc","xbox","psn")][string]$Platform
    )
    
    $exist? = Test-Path "$ScriptDir\$playerList"
    if ($exist?) { $list = Import-Csv "$ScriptDir\$playerList" }
    else { $list = @() }

    $listLength = ($list | Measure-Object).Count
    

    $AccountID = Get-FNAccountID -Username $Username -Platform $Platform -ErrorAction Continue

    $object = [pscustomobject]@{
        Username = $Username
        Platform = $Platform
        AccountID = $AccountID
    }

    if ($listLength -eq 0) { $list = $object }
    elseif ($listLength -eq 1) { $list = @($list,$object) }
    else { $list += $object }

    $list | Export-Csv -Path "$ScriptDir\$playerList" -Force -NoTypeInformation
    New-PlayerTransactionLogEntry -Username $Username -Platform $Platform -Type "Added"
    $object
}

## No longer used. Out of date
<# 
 Function Get-FNPlayerMatchHistory { 
    Param([parameter(Mandatory)][string]$Username)
    $accountID = Get-PlayerAccountID -Username $Username

    $playerMatchHistory = "https://api.fortnitetracker.com/v1/profile/account/$accountID/matches"
    $matches = Invoke-RestMethod -Uri $playerMatchHistory -Headers $key
    $matches
}
#>

<#
Function Update-FNPlayerMatchHistory { #Do not use anymore.
    Param([parameter(Mandatory)][string]$Username)

    $matches = Get-FNPlayerMatchHistory -Username $Username
    Update-PlayerMatchDB -Username $Username -Entries $matches
}
#>

Function Get-FNStore {
    $getStore = "https://api.fortnitetracker.com/v1/store"
    $store = Invoke-RestMethod -Uri $getStore -Headers $key
    $store
}

Function Update-AllFNPlayersMatchHistory {
    $allPlayers = Get-FNPlayerList
    foreach ($p in $allPlayers) {
        Update-FNPlayerMatchHistory -Username $p.Username
    }
}

Function Update-PlayerMatchDB {
    Param(
        [Parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][array]$Entries

    )

    $path = "$ScriptDir\$matchDir\$Username.CSV"
    $new = @()
    $allMatches = @()
    $total = 0
    $est = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
    $utc = [System.TimeZoneInfo]::FindSystemTimeZoneById("UTC")

    if (Test-Path $path) { 
        $csv = Import-CSV $path 
        $allMatches += $csv
    }

    foreach ($m in $Entries) {
        if ($allMatches.id -notcontains $m.id) {
            $object = [pscustomobject]@{
                ID = $m.id
                DateCollected = [System.TimeZoneInfo]::ConvertTime(([datetime]$m.dateCollected), $utc, $est)
                Kills = $m.kills
                Matches = $m.matches
                Playlist = $m.playlist
                Score = (Get-MatchScore -Match $m).Total
                Top1 = $m.top1
                Top10 = $m.top10
                Top12 = $m.top12
                Top25 = $m.top25
                Top3 = $m.top3
                Top5 = $m.top5
                Top6 = $m.top6
                MinutesPlayed = $m.minutesPlayed
                Platform = $m.platform
                PlaylistID = $m.playlistId
                PlayersOutlived = $m.playersOutlived
                EventID = $null
            }

            $allMatches += $object
            $total += $object.Matches
            $format = Format-MatchOutput -Entry $object -Username $Username -IncludeNumberOfMatches -IncludeScore -IncludeMinutesPlayed -IncludePlayersOutlived
            $new += $format
        }
    }

    $allMatches | Sort-Object -Property id -Descending | Export-CSV -Path $path -Force -NoTypeInformation
    if ($total -gt 0) { 
        New-MatchLogEntry -Username $Username -MatchesAdded $total 
        Write-Output $new | Format-Table
    }
}

Function New-RequestsLogEntry {
    Param(
        [parameter(Mandatory)][datetime]$StartTime,
        [parameter(Mandatory)][datetime]$EndTime,
        [parameter(Mandatory)][int]$Requests
    )

    $path = "$ScriptDir\$logsDir\$requestsLog"
    $duration = [Math]::Round(($EndTime - $StartTime).TotalMilliseconds)

    if ($NewEntries -ge 1) {
        $output = "CompletionTime = $EndTime | Duration = $duration Milliseconds | TotalRequests = $Requests"
        $output | Add-Content -Path $path -Force
    }
}

Function Get-FNPlayerStats {
    Param([parameter(Mandatory)][string]$Username)
    $platform = Get-PlayerPlatform -Username $Username
    
    $playerStats = "https://api.fortnitetracker.com/v1/profile/$platform/$username"
    Do {
        $retry = $false
        $response = Invoke-RestMethod -Uri $playerStats -Headers $key
        if ($response.error -eq "Player Not Found") { Throw $response.error }
        elseif ($response.error) { $retry = $true }
    }
    Until (!$retry)
    $response
}

Function Get-FNRecentMatches {
    Param([parameter(Mandatory)][string]$Username)
    $return = (Get-FNPlayerStats -Username $Username).recentMatches
    $return
}

function Get-PlayerPlatform {
    Param([parameter(Mandatory)][string]$Username)

    $list = Get-FNPlayerList
    if ($list.Username -contains $Username) {
        $platform = ($list | Where-Object {$_.Username -eq $Username}).Platform
    }
    else { Throw "Player does not exist. Please add the player with New-FNPlayer" }
    $platform
}

Function Get-PlayerAccountID {
    Param([parameter(Mandatory)][string]$Username)

    $list = Get-FNPlayerList
    if ($list.Username -contains $Username) {
        $accountID = ($list | Where-Object {$_.Username -eq $Username}).AccountID
    }
    else { Throw "Player does not exist. Please add the player with New-FNPlayer" }
    $accountID
}

Function Remove-Player {
    Param([parameter(Mandatory)][string]$Username)
    Remove-PlayerMatchHistory -Username $Username
    Remove-PlayerFromList -Username $Username
}

Function Remove-PlayerMatchHistory {
    Param([parameter(Mandatory)][string]$Username)
    $platform = Get-PlayerPlatform -Username $Username

    Move-Item -Path "$ScriptDir\$matchDir\$Username.CSV" -Destination "$ScriptDir\$recycleBinDir" -Force
    $entry = New-PlayerTransactionLogEntry -Username $Username -Platform $platform -Type "Cleared"
    $entry
}

Function Remove-PlayerFromList {
    Param([parameter(Mandatory)][string]$Username)
    $platform = Get-PlayerPlatform $Username
    $path = "$ScriptDir\$playerList"

    $list = Import-CSV $path
    $newlist = $list | Where-Object {$_.Username -ne $Username}
    $newlist | Export-CSV $path -Force -NoTypeInformation

    $entry = New-PlayerTransactionLogEntry -Username $Username -Platform $Platform -Type "Removed"
    $entry
}

Function Clear-Logs {
        Move-Item -Path "$ScriptDir\$logsDir\*.log" -Destination "$ScriptDir\$recycleBinDir" -Force    
}

Function New-PlayerTransactionLogEntry {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][string]$Platform,
        [parameter(Mandatory)][string]$Type
    )

    $Date = Get-Date

    $entry = "$Date | $Username | $Platform | $Type"
    $entry | Add-Content -Path "$ScriptDir\$logsDir\$playerTransactionLog" -Force

}

Function Clear-AllPlayerMatchHistories {
    $files = Get-ChildItem -Path "$ScriptDir\$matchDir" 

    foreach ($f in $files) {
        Move-Item -Path "$ScriptDir\$matchDir\$($f.Name)" -Destination "$ScriptDir\$recycleBinDir" -Force
    }
        
    $entry = New-PlayerTransactionLogEntry -Username "All Users" -Platform "All Platforms" -Type "Cleared"
    $entry
}

Function Get-FNPlayerLifeTimeStats {
    Param([parameter(Mandatory)][string]$Username)
    $return = (Get-FNPlayerStats -Username $Username).lifeTimeStats
    $return
}

Function Update-FNRecentMatches {
    Param([parameter(Mandatory)][string]$Username)
    $matches = Get-FNRecentMatches -Username $Username
    if ($null -ne $matches) { Update-PlayerMatchDB -Username $Username -Entries $matches }
    # else { Write-Host "No recent matches for $Username`r`n" -ForegroundColor Yellow }
    
}

Function Update-AllFNRecentMatches {
    $players = Get-FNPlayerList
    $i = 0
    foreach ($p in $players) {
        $i++
        $perc = [Math]::Round(($i/$players.Count)*100)
        Update-FNRecentMatches -Username $p.Username
        Write-Progress -Activity "Checking for new matches" -Status "$i Players Complete" -PercentComplete $perc -CurrentOperation "Checking $($p.Username)"
        Start-Sleep -Milliseconds 500
    }
}

Function Get-TopKillGames {
    $all = @()
    $players = Get-FNPlayerList
    foreach ($p in $players) {
        $playerTop = Get-PlayerTopKillGames -Username $p.Username
        $all += $playerTop
    }
    $all = $all | Sort-Object -Property @{Expression = {$_.Elims}; Ascending = $false}, Date | Select-Object -First 25
    $all
}

Function Update-TopKillGames {
    $output = Get-TopKillGames | Sort-Object -Property @{Expression = {$_.Elims}; Ascending = $false}, Date | Select-Object -First 25
    $output | Export-CSV -Path "$ScriptDir\$pagesDir\TopKillGames.CSV" -Force -NoTypeInformation
}

Function Get-PlayerTopKillGames {
    Param([parameter(Mandatory)][string]$Username)
    $all = @()
    $min = 4
    $include = @("p2","p9","p10")
    
    $matches = Import-Csv "$ScriptDir\$matchDir\$Username.CSV"
    foreach ($m in $matches) {
        if (($m.matches -eq 1) -and ($m.kills -ge $min) -and ($include -contains $m.Playlist)) {
            $object = Format-MatchOutput -Entry $m -Username $Username
            $all += $object
        }
    }  
    $all = $all | Sort-Object -Property @{Expression = {$_.Elims}; Ascending = $false}, Date
    $all
}

Function Get-RemainingWebRequests {
    $getStore = "https://api.fortnitetracker.com/v1/store"
    $store = Invoke-WebRequest -Uri $getStore -Headers $key
    $store.Headers.'X-RateLimit-Remaining-minute'
} 

Function New-MatchLogEntry {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][int]$MatchesAdded
    )

    $date = Get-Date

    if ($MatchesAdded -ge 1) {
        $entry = "$date | $MatchesAdded Matches Added for $Username"
        $entry | Add-Content -Path "$ScriptDir\$logsDir\$matchDiscoveryLog" -Force
    }
}

Function Start-FNPlayerMatchMonitor {
    Param([string]$EndDateTime)
    if (!$EndDateTime) { $convertedDate = (Get-Date).AddYears(5)}
    else { $convertedDate = Get-Date -Date $EndDateTime }
    Write-Host "Match monitor running..."
    Do {
        Update-AllFNRecentMatches
        Start-Countdown -Seconds 60 -Status "Rate Limiting"
    }
    Until ((Get-Date) -gt $convertedDate)
    Write-Host "Match monitor is now stopped."
}

Function Get-PlayerLocalGamesPlayed {
    Param([parameter(Mandatory)][string]$Username)
    $matches = Import-Csv -Path "$ScriptDir\$matchDir\$Username.CSV"
    $matches
}

Function Convert-PlaylistName {
    Param([parameter(Mandatory)][string]$Playlist)
    $playlists = Get-AllPlaylists
    if ($playlists.Code -contains $Playlist ) {
        $output = ($playlists | Where-Object {$_.Code -eq $Playlist}).Name
    }
    else { 
        $output = switch ($Playlist) {
            { $_ -like "p2*" }   { "Solo $Playlist" }
            { $_ -like "p10*" }  { "Duo $Playlist" }
            { $_ -like "p9*" }   { "Squad $Playlist" }
            { $_ -like "ltm*" }  { "LTM $Playlist" }
            { $_ -like "misc*" } { "Misc $Playlist"}
            Default { "Uknown" }
        }
    }
    $output
}

Function Format-MatchOutput {
    Param(
        [parameter(Mandatory)][array]$Entry,
        [string]$Username,
        [switch]$IncludeNumberOfMatches,
        [switch]$IncludeScore,
        [switch]$IncludeMinutesPlayed,
        [switch]$IncludePlayersOutlived
    )

    $object = [pscustomobject]@{
        Date = [datetime]$Entry.dateCollected
        Playlist = Convert-PlaylistName -Playlist ($Entry.playlist + $Entry.PlaylistID)
        Elims = $Entry.kills     
    } 

    if ($Entry.Matches -eq 1) {
        $Result = switch ($Entry) {
            {$Entry.top1 -eq 1}     { "Win"; break }
            {$Entry.top3 -eq 1}     { "Top 3"; break }
            {$Entry.top5 -eq 1}     { "Top 5"; break }
            {$Entry.top6 -eq 1}     { "Top 6"; break }
            {$Entry.top10 -eq 1}    { "Top 10"; break }
            {$Entry.top12 -eq 1}    { "Top 12"; break }
            {$Entry.top25 -eq 1}    { "Top 25"; break }
            Default             { "Defeat" }
        }
    }
    else {
        $Result = "$($Entry.top1) Wins"
    }
    if ($IncludeScore) { Add-Member -InputObject $object -NotePropertyName Score -NotePropertyValue (Get-MatchScore $Entry).Total}
    if ($IncludeNumberOfMatches) { Add-Member -InputObject $object -NotePropertyName Matches -NotePropertyValue $Entry.matches }
    Add-Member -InputObject $object -NotePropertyName Result -NotePropertyValue $Result
    if ($IncludeMinutesPlayed) { Add-Member -InputObject $object -NotePropertyName MinutesPlayed -NotePropertyValue $Entry.MinutesPlayed }
    if ($IncludePlayersOutlived) { Add-Member -InputObject $object -NotePropertyName PlayersOutlived -NotePropertyValue $Entry.PlayersOutlived }
    if ($Username) { Add-Member -InputObject $object -NotePropertyName Username -NotePropertyValue $Username }
    $object
}

Function New-Event {
    Param(
        [parameter(Mandatory)][ValidateScript({
            if (Get-FNPlayerList -contains $Username) { $True }
            else { Throw "Username does not exist in the database. Use New-FNPlayer to add."}
        })][string]$Username,
        [parameter(Mandatory)][ValidateSet("Solo","Duo","Squad")][string]$Playlist,
        [parameter][ValidateSet("SingleElim","DoubleElim","Classic")][string]$Type = "Classic",
        [array]$ScoringSettings = $defaultScoring,
        [int]$NumberofGames,
        [int]$MaxTeams
    )
    
    if (!$NumberofGames) { 
        if ($Type -eq "Classic") { $NumberofGames = 10 }
        else { $NumberofGames = 2 }
    }

    if ((!$MaxTeams) -or ($MaxTeams -gt 64)) {
        if ($Type -eq "DoubleElim") { $MaxTeams = 64 }
        elseif ($Type -eq "SingleElim")  { $MaxTeams = 128}
    }
    if ((!$MaxTeams) -and ($Type -eq "Classic")) { $MaxTeams = 1000 }

    $eventNumber = Get-EventNumber
    New-Item -ItemType Directory -Path "$ScriptDir\$eventsDir\$eventNumber"
    $owner = New-EventUserObject -Username $Username -Platform (Get-PlayerPlatform -Username $Username) -Owner
    New-EventPlayerList -Owner $owner -EventNumber $eventNumber
    
}

Function New-EventPlayerList {
    Param(
        [parameter(Mandatory)][array]$Owner,
        [parameter(Mandatory)][uint64]$EventNumber
    )
    $Owner | Export-CSV -Path "$ScriptDir\$eventsDir\$EventNumber\playerList.csv" -Force -NoTypeInformation
}

Function Get-EventNumber {
    $existingEvents = @()
    $existingEvents += (Get-ChildItem -Path "$ScriptDir\$eventsDir" -Directory -ErrorAction SilentlyContinue).Name.ToUInt64($_)
    if ($null -ne $existingEvents) { $nextNumber = ($existingEvents | Measure-Object -Maximum).Maximum + 1 }
    else { $nextNumber = 1 }
    $nextNumber
}

Function New-EventUserObject {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][ValidateSet("pc","psn","xbox")][string]$Platform,
        [switch]$Owner = $false
    )

    $userObject = [pscustomobject]@{
        Username = $Username
        Platform = Get-PlayerPlatform -Username $Username
        Owner = $Owner
    }
    
    $userObject
}

Function New-ScoringSettings {
    Param(
        [int]$Elims = 0,
        [int]$Wins = 0,
        [int]$Top10Percent = 0,
        [int]$Top25Percent = 0
    )
    
    $scoringArray = @($Elims,$Wins,$Top10Percent,$Top25Percent)
    if (($scoringArray | Measure-Object -Sum).Sum -le 0) { Throw "Scoring settings must include points somewhere!" }
    $scoringArray
}

Function Get-MatchScore {
    Param(
        [parameter(Mandatory)][array]$Match,
        [array]$ScoringSettings = $defaultScoring
    )

    $Wins = [int]$Match.Top1
    $Top10Percent = [int]$Match.Top3 + [int]$Match.Top5 + [int]$Match.Top10
    $Top25Percent = [int]$Match.Top6 + [int]$Match.Top12 + [int]$Match.Top25

    $place = ($Wins * $ScoringSettings[1]) + (($Top10Percent - $Wins) * $ScoringSettings[2]) + (($Top25Percent - $Top10Percent - $Wins) * $ScoringSettings[3])
    
    $elims = [int]$Match.kills * $ScoringSettings[0]

    $score = [pscustomobject]@{
        Eliminations = $elims
        Placement = $place
        Total = $elims + $place
    }

    $score
}

Function Add-PlayerToEvent {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][ValidateSet("pc","psn","xbox")][string]$Platform,
        [parameter(Mandatory)][uint64]$EventNumber
    )
}

Function Update-AllMatchScores {
    $playerList = Get-FNPlayerList
    foreach ($p in $playerList) {
        $updatedMatches = @()
        $path = "$ScriptDir\$matchDir\$($p.Username).CSV"
        $matches = Import-Csv -Path $path
        foreach ($m in $matches) {
            $m.Score = (Get-MatchScore -Match $m).Total
            $updatedMatches += $m
        }
        $updatedMatches | Export-Csv -Path $path -NoTypeInformation -Force
    }
}

Function Get-TopScoringGames {
    $topScores = @()
    $playerList = Get-FNPlayerList
    foreach ($p in $playerList) {
        $playTops = Get-PlayerTopScoringGames -Username $p.Username
        $topScores += $playtops
    }
    $topScores = $topScores | Sort-Object -Property @{Expression = {$_.Score}; Ascending = $false}, Date | Select-Object -First 25
    $topScores
}

Function Get-PlayerTopScoringGames {
    Param([parameter(Mandatory)][string]$Username)
    $singleMatchScores = @()
    $include = @("p2","p9","p10")
    $matches = Import-CSV "$ScriptDir\$matchDir\$Username.CSV"
    foreach ($m in $matches) {
        if (($m.matches -eq 1)  -and ($include -contains $m.Playlist)) {
            $matchData = Format-MatchOutput -Entry $m -IncludeScore -Username $Username -IncludePlayersOutlived
            if($matchData.Score -ge 5) { $singleMatchScores += $matchData }
        }
    }
    $singleMatchScores = $singleMatchScores | Sort-Object -Property @{Expression = {$_.Score}; Ascending = $false}, Date
    $singleMatchScores
}

Function Clear-RecycleBin {
    Remove-Item "$ScriptDir\$recycleBinDir\*" -Force
}

Function Update-TopScoringGames {
    $output = Get-TopScoringGames | Sort-Object -Property @{Expression = {$_.Score}; Ascending = $false}, Date | Select-Object -First 25
    $output | Export-CSV -Path "$ScriptDir\$pagesDir\TopScoreGames.CSV" -Force -NoTypeInformation
}

Function Get-FNPlayerCareerStats {
    Param(
        [parameter(Mandatory)][string]$Username,
        [array]$ScoringSettings = $defaultScoring
    )

    $lifeTimeStats = (Get-FNPlayerStats -Username $Username).lifeTimeStats
    $wins = [int]$lifeTimeStats[8].Value
    $Top10Percent = ([int]$lifeTimeStats[0].Value + [int]$lifeTimeStats[1].Value + [int]$lifeTimeStats[3].Value)
    $Top25Percent = ([int]$lifeTimeStats[2].Value + [int]$lifeTimeStats[4].Value + [int]$lifeTimeStats[5].Value)
    $placementPoints = ($wins * $ScoringSettings[1]) + (($Top10Percent - $Wins) * $ScoringSettings[2]) + (($Top25Percent - $Top10Percent - $Wins) * $ScoringSettings[3])
    $score = [int]$lifeTimeStats[10].Value + $placementPoints

    $object = [pscustomobject]@{
        Username = $Username
        Matches = [int]$lifeTimeStats[7].Value
        Wins = $wins
        WinPercent = [Math]::Round((([int]$lifeTimeStats[8].Value / [int]$lifeTimeStats[7].Value) * 100),2)
        Elims = [int]$lifeTimeStats[10].Value
        KD = [Math]::Round(([int]$lifeTimeStats[10].Value / ([int]$lifeTimeStats[7].Value - $wins)),2) 
        Score = $score
        ScorePerMatch = [Math]::Round(($score/[int]$lifeTimeStats[7].Value),2)
    }

    $object
}

Function Get-AllFNPlayerCareerStats {
    $all = @()
    $players = Get-FNPlayerList
    foreach ($p in $players) {
        $playerTop = Get-FNPlayerCareerStats -Username $p.Username
        $all += $playerTop
    }
    $all = $all | Sort-Object -Property @{Expression = {$_.ScorePerMatch}; Ascending = $false}, Wins, Matches
    $all
}

Function Get-PlayerRecentStats {
    Param(
        [parameter(Mandatory)][string]$Username,
        [array]$ScoringSettings = $defaultScoring,
        [int]$Days = 7
    )
    $recentDate = (Get-Date).AddDays(-$Days)
    $matches = Get-PlayerLocalGamesPlayed -Username $Username | Where-Object {(Get-Date -Date $_.DateCollected) -ge $recentDate}
    $wins = ($matches.top1 | Measure-Object -Sum).Sum

    $object = [pscustomobject]@{
        Username = $Username
        Matches = ($matches.Matches | Measure-Object -Sum).Sum
        Wins = $wins
        WinPercent = [Math]::Round((($wins/(($matches.Matches | Measure-Object -Sum).Sum))*100),2)
        Elims = ($matches.Kills | Measure-Object -Sum).Sum
        KD =  [Math]::Round(((($matches.Kills | Measure-Object -Sum).Sum)/((($matches.Matches | Measure-Object -Sum).Sum) - $wins)),2)
        Score = ($matches.Score | Measure-Object -Sum).Sum
        ScorePerMatch = [Math]::Round(((($matches.Score | Measure-Object -Sum).Sum)/(($matches.Matches | Measure-Object -Sum).Sum)),2)
    }

    $object
}

Function Get-AllPlayerRecentStats {
    Param([int]$Days = 7)
    $all = @()
    $players = Get-FNPlayerList
    foreach ($p in $players) {
        $playerRecent = Get-PlayerRecentStats -Username $p.Username -Days $Days
        if ($playerRecent.Matches -gt 0) { $all += $playerRecent } 
    }
    $all = $all | Sort-Object -Property @{Expression = {$_.ScorePerMatch}; Ascending = $false}, Wins, Matches
    $all
}

Function Start-Countdown {
    Param(
        [parameter(Mandatory)][int]$Seconds,
        [parameter(Mandatory)][string]$Status
    )

    $endSleep = (Get-Date).AddSeconds($Seconds)
    While ($Seconds -ge 0) {
        $Seconds = [Math]::Round(($endSleep - (Get-Date)).TotalSeconds)
        Write-Progress -Activity "Sleeping" -Status $Status -SecondsRemaining $Seconds
        Start-Sleep -Milliseconds 200
    }
}

Function Get-AllPlaylists {
    $playlists = Import-CSV "$ScriptDir\$assetsDir\playlists.csv"
    $playlists
}

Function New-StatsObjectToHTML {
        Param(
            [parameter(Mandatory,ValueFromPipeline=$true)][psobject]$Object,
            [parameter][string]$Header,
            [parameter][string]$Footer
        )
        
        $htmlhead = "<html>
                        <meta http-equiv='refresh' content='10'>
                        <style>
                        BODY { 
                            font-family: 'Montserrat',Arial; text-transform: uppercase;
                        }
                        TABLE {
                            font-size: 18pt; 
                            font-family: 'Montserrat','Segoe UI Light','Segoe UI','Lucida Grande',Verdana,Arial,Helvetica,sans-serif;

                        }
                        TH {
                            color: #00faaa;
                            opacity: 0;
                            text-align: left;
                            vertical-align: bottom;
                        }
                        TD {
                            color: #FFFFFF;
                            text-align: left;
                            vertical-align: top;
                            font-weight: bold;
                        }

                        td.pass{background: #B7EB83;}
                        td.warn{background: #FFF275;}
                        td.fail{background: #FF2626; color: #ffffff;}
                        td.info{background: #85D4FF;}
                        </style>
                        <body>
                        <p>$Header</p>"
    
        $htmltail = "<p>$Footer</p> 
                    </body> 
                    </html>"
    
        $html = $Object | ConvertTo-Html
        $body = $htmlhead + $html + $htmltail
        $body
    }

    Function Start-StreamStatsOverlay {
        Param(
            [parameter(Mandatory)][string]$Username,
            [string]$StartDateTime
        )

        if (!(Test-Username -Username $Username)) { Throw "User does not exist."}

        if (!$StartDateTime) { $start = (Get-Date)}
        else { $start = Get-Date -Date $StartDateTime }
        Write-Host "Stream overlay running..."
        Do {
            Update-FNRecentMatches -Username $Username
            Update-StatsOverlay -Username $Username -StartDate $start
            Start-Countdown -Seconds 60 -Status "Rate Limiting"
        }
        Until ((Get-Date) -gt $start.AddHours(12))
        Write-Host "Sream overlay is now stopped."
    }

Function Update-StatsOverlay {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][datetime]$StartDate    
    )
    
    $validPlaylists = @(
        "p2",
        "p9",
        "p10"
    )

    $matches = Get-PlayerLocalGamesPlayed $Username | Where-Object { ((Get-Date -Date $_.DateCollected) -gt $StartDate) -and ($validPlaylists -contains $_.Playlist) }

    if ((($matches.Kills | Measure-Object -Sum).Sum) -gt 0) {
        $KDcalc = [Math]::Round(((($matches.Kills | Measure-Object -Sum).Sum)/((($matches.Matches | Measure-Object -Sum).Sum)-(($matches.Top1 | Measure-Object -Sum).Sum))),2)
    }
    else {
        $KDcalc = 0
    }

    $games = [pscustomobject] @{ GAMES = ($matches.Matches | Measure-Object -Sum).Sum }
    $elims = [pscustomobject] @{ ELIMS = ($matches.Kills | Measure-Object -Sum).Sum }
    $wins = [pscustomobject] @{ WINS = ($matches.Top1 | Measure-Object -Sum).Sum }
    $KD = [pscustomobject] @{ KD = $KDcalc }

    New-StatsObjectToHTML -Object $games | Out-File "$ScriptDir\stream_stats\games.html"
    New-StatsObjectToHTML -Object $elims | Out-File "$ScriptDir\stream_stats\elims.html"
    New-StatsObjectToHTML -Object $wins | Out-File "$ScriptDir\stream_stats\wins.html"
    New-StatsObjectToHTML -Object $KD | Out-File "$ScriptDir\stream_stats\KD.html"
}

Function Test-Username {
    Param(
        [parameter(Mandatory)][string]$Username
    )

    $exist = $false
    $playerList = (Get-FNPlayerList).Username

    if ($playerList -notcontains $Username) {
        foreach ($p in $platforms) {
            $new = New-FNPlayer -Username $Username -Platform $p
            if ($new) {$exist = $true}
        }
    }
    else { $exist = $true }

    $exist
}

Function Get-NewVictoryRoyales {
    $royalesLoc = "$ScriptDir\$pagesDir\IndividualVictoryRoyales.CSV"
    $royales = @()

    # Get Royales Today
    $players = Get-FNPlayerList
    foreach ($p in $players) {
        $validPlaylists = @("p2","p9","p10")
        $validPlayIDs = @("ltm109","ltm139")
        $games = Get-PlayerLocalGamesPlayed -Username $p.Username
        $wins = $games | Where-Object {($_.top1 -eq 1) -and ($_.matches -eq 1) -and (($validPlaylists -contains $_.Playlist) -or ($validPlayIDs -contains ("$($_.Playlist)$($_.PlaylistID)")))}
        if (($wins | Measure-Object).Count -gt 0) {
            foreach ($w in $wins) {
                $playlist = Convert-PlaylistName -Playlist "$($w.Playlist)$($w.PlaylistID)"
                $object = [PSCustomObject] @{
                    ID = $w.ID
                    Username = $p.Username
                    'Date Collected' = $w.DateCollected
                    Eliminations = $w.Kills
                    Playlist = $playlist
                    'Minutes Played' = $w.MinutesPlayed
                    'Players Outlived' = $w.PlayersOutlived
                }
                $royales += $object
            }
        }
    }

    # Check Royales List and Update
    $newRoyales = @()
    $exist? = Test-Path $royalesLoc
    if ($exist?) {
        $merge = Import-CSV -Path $royalesLoc
    }
    else {
        $merge = @()
    }

    foreach ($r in $royales) {
        if ($merge.ID -notcontains $r.ID) {
            if (($merge | Measure-Object).Count -gt 1) {
                $merge += $r
            }
            elseif (($merge | Measure-Object).Count -eq 1) {
                $merge = @($merge,$r)
            }
            else {
                $merge = $r
            }
            $newRoyales += $r
        }
    } 

    $merge | Sort-Object -Property 'Date Collected' -Descending | Export-Csv -Path $royalesLoc -NoTypeInformation -Force
    $newRoyales
}
