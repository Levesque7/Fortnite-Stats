#Requires -Version 5.0

# Settings
$Env:FNSDirectory = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$ENV:TRNApiUrl = "https://api.fortnitetracker.com/v1/"
$Env:FNSScorePerElim = 15
$Env:FNSScorePerWin = 35
$Env:FNSScorePerTop10Percent = 15 # Solo Top 10, Duo Top 5, Squads Top 3
$Env:FNSScorePerTop25Percent = 0 # Solo Top 25, Duo Top 12, Squads Top 6
$Env:FNSScorePerPlayerOutlived = 1 

# Directories
$Env:FNSRecycleBinDir = "$Env:FNSDirectory\recycle_bin"
$Env:FNSLogsDir = "$Env:FNSDirectory\logs"
$Env:FNSAssetsDir = "$Env:FNSDirectory\assets"
$Env:FNSStreamStatsDir = "$Env:FNSDirectory\stream_stats"

# Databases
$Env:FNSUserDB = "$Env:FNSAssetsDir\players.csv"
$Env:FNSEventsDB = "$Env:FNSAssetsDir\events.csv"
$Env:FNSMatchDB = "$Env:FNSAssetsDir\matches.csv"
$Env:FNSCareerDB = "$Env:FNSAssetsDir\career_stats.csv"
$Env:FNSVictoryDB = "$Env:FNSAssetsDir\royales.csv"
$ENV:FNSPlaylistDB = "$Env:FNSAssetsDir\playlists.csv"

Function Set-TRNApiKey {
    Param([parameter(Mandatory)][string]$Key)
    $Env:TRNApiKey = $Key
}

Function Get-TRNApiKey {
    Param([string]$Key = $Env:TRNApiKey)
    if ($Key) { $Env:TRNApiKey = $Key }
    elseif ($Env:TRNApiKey) { $Key = $Env:TRNApiKey }
    else {
        $Key = Read-Host "TRN API key not yet set. Enter API key"
        Set-TRNApiKey -Key $Key
    }
    $return = @{"TRN-Api-Key"=$Key}
    $return
}

Function Initialize-FNSDirectories {
    $allDirs = @($Env:FNSRecycleBinDir,$Env:FNSLogsDir,$Env:FNSAssetsDir,$Env:FNSStreamStatsDir)
    foreach ($dir in $allDirs) {
        $exist? = Test-Path "$dir"
        if (!$exist?) { New-Item "$dir" -ItemType Directory }
    }
}

Function Invoke-FNTrackerRestMethod {
    Param([parameter(Mandatory)][string]$Endpoint)
    $response = Invoke-RestMethod -Uri "$ENV:TRNApiUrl/$Endpoint" -Headers (Get-TRNApiKey)
    $response
}

Function Get-FNPlayerList {
    $export = @()
    $list = Import-Csv "$Env:FNSUserDB"
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
    if ($update) { $export | Export-Csv -Path "$Env:FNSUserDB" -Force -NoTypeInformation }
    $export
}

Function Get-FNAccountID {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][string]$Platform
    )
    
    $response = Get-FNPlayerStats -Username $Username -Platform $Platform
    $response.AccountID
}

Function New-FNPlayer {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][ValidateSet("pc","xbox","psn")][string]$Platform
    )
    
    $exist? = Test-Path "$Env:FNSUserDB"
    if ($exist?) { $list = Import-Csv "$Env:FNSUserDB" }
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

    $list | Export-Csv -Path "$Env:FNSUserDB" -Force -NoTypeInformation
    New-PlayerTransactionLogEntry -Username $Username -Platform $Platform -Type "Added"
    $object
}

Function Get-FNStore {
    $storeURL = "store"
    $store = Invoke-FNTrackerRestMethod -Endpoint $storeURL
    $store
}

Function Update-PlayerMatchDB {
    Param(
        [Parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][array]$Entries

    )

    $path = $Env:FNSMatchDB
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
                Username = $Username
            }

            $allMatches += $object
            $total += $object.Matches
            $format = Format-MatchOutput -Entry $object -IncludeUsername -IncludeNumberOfMatches -IncludeScore -IncludeMinutesPlayed -IncludePlayersOutlived
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

    $path = "$Env:FNSLogsDir\requests.log"
    $duration = [Math]::Round(($EndTime - $StartTime).TotalMilliseconds)

    if ($NewEntries -ge 1) {
        $output = "CompletionTime = $EndTime | Duration = $duration Milliseconds | TotalRequests = $Requests"
        $output | Add-Content -Path $path -Force
    }
}

Function Get-FNPlayerStats {
    Param(
        [parameter(Mandatory)][string]$Username,
        [string]$Platform
    )
    if(!$Platform) { $platform = Get-PlayerPlatform -Username $Username }
    
    $profile = "profile/$Platform/$Username"
    Do {
        $retry = $false
        $response = Invoke-FNTrackerRestMethod -Endpoint $profile
        if ($response.error -eq "Player Not Found") { Throw $response.error }
        elseif ($response.error) { $retry = $true }
    }
    Until (!$retry)
    
    <#$object = $response.lifeTimeStats
    Add-Member -InputObject $object -NotePropertyName Username -NotePropertyValue $response.epicUserHandle

    $careerStats = Import-Csv -Path $Env:FNSCareerDB | Where-Object {$_.Username -ne $Username}
    $careerStats += $object
    $careerStats | Export-Csv -Path $Env:FNSCareerDB#>
    
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
    #Remove-PlayerMatchHistory -Username $Username
    Remove-PlayerFromList -Username $Username
}

Function Remove-PlayerFromList {
    Param([parameter(Mandatory)][string]$Username)
    $platform = Get-PlayerPlatform $Username
    $path = "$Env:FNSUserDB"

    $list = Import-CSV $path
    $newlist = $list | Where-Object {$_.Username -ne $Username}
    $newlist | Export-CSV $path -Force -NoTypeInformation

    $entry = New-PlayerTransactionLogEntry -Username $Username -Platform $Platform -Type "Removed"
    $entry
}

Function Clear-Logs {
        Move-Item -Path "$Env:FNSLogsDir\*.log" -Destination "$Env:FNSRecycleBinDir" -Force    
}

Function New-PlayerTransactionLogEntry {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][string]$Platform,
        [parameter(Mandatory)][string]$Type
    )

    $Date = Get-Date

    $entry = "$Date | $Username | $Platform | $Type"
    $entry | Add-Content -Path "$Env:FNSLogsDir\player_transactions.log" -Force

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

Function Get-TopElimGames {
    Param(
        [string]$Username = "*",
        [string]$Playlist = "*",
        [int]$Count = 25,
        [int]$Days = 5000
    )
    $include = @("p2","p9","p10")
    $recentDate = (Get-Date).AddDays(-$Days)
    $singleMatches = Get-LocalGamesPlayed | Where-Object {((Get-Date -Date $_.DateCollected) -ge $recentDate) -and ($_.matches -eq 1) -and ($include -contains $_.Playlist) -and ($_.Username -like $Username)}
    $formatted = @()
    foreach ($m in $singleMatches) {
        $match = Format-MatchOutput -Entry $m -IncludeUsername -IncludeScore -IncludePlayersOutlived
        $formatted += $match
    }
    $topScores = $formatted | Where-Object { $_.Playlist -like $Playlist } | Sort-Object -Property @{Expression = {$_.Elims}; Ascending = $false}, Date | Select-Object -First $Count
    $topScores
}

Function New-MatchLogEntry {
    Param(
        [parameter(Mandatory)][string]$Username,
        [parameter(Mandatory)][int]$MatchesAdded
    )

    $date = Get-Date

    if ($MatchesAdded -ge 1) {
        $entry = "$date | $MatchesAdded Matches Added for $Username"
        $entry | Add-Content -Path "$Env:FNSLogsDir\match_discovery.log" -Force
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

Function Get-LocalGamesPlayed {
    Param([string]$Username = "*")
    $matches = Import-Csv -Path $Env:FNSMatchDB | Where-Object {$_.Username -like $Username}
    $matches
}


Function Convert-PlaylistName {
    Param([parameter(Mandatory)][string]$Playlist)
    $playlists = Get-Playlists
    if ($playlists.Code -contains $Playlist) {
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
        [switch]$IncludeUsername,
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
    if ($IncludeUsername) { Add-Member -InputObject $object -NotePropertyName Username -NotePropertyValue $Entry.Username }
    $object
}

Function New-SoloEvent {
    Param(
        [parameter(Mandatory)][datetime]$EndDate,
        [datetime]$StartDate = (Get-Date),
        [parameter][ValidateSet("SingleElim","DoubleElim","Classic")][string]$Type = "Classic",
        [array]$ScoringSettings = @($Env:FNSScorePerElim,$Env:FNSScorePerWin,$Env:FNSScorePerTop10Percent,$Env:FNSScorePerTop25Percent,$Env:FNSScorePerPlayerOutlived),
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
    $eventsDB = Import-Csv -Path $Env:FNSEventsDB

    if ($StartDate -gt (Get-Date)) { $status = "Upcoming" }
    elseif ($StartDate -le (Get-Date)) { $status = "Active" }
    
    $newEvent = [pscustomobject] @{
        EventID = $eventNumber
        StartDate = $StartDate
        EndDate = $EndDate
        PointsPerElim = $ScoringSettings[0]
        PointsPerWin = $ScoringSettings[1]
        PointsPerTop10 = $ScoringSettings[2]
        PointsPerTop25 = $ScoringSettings[3]
        PointsPerPlayerOutlived = $ScoringSettings[4]
        Status = $status
    }

    $eventsDB += $newEvent
    $eventsDB | Export-Csv -Path $Env:FNSEventsDB -Force -NoTypeInformation
    
}

Function New-EventPlayerList {
    Param(
        [parameter(Mandatory)][array]$Owner,
        [parameter(Mandatory)][uint64]$EventNumber
    )
    $Owner | Export-CSV -Path "$Env:FNSEventsDir\$EventNumber\playerList.csv" -Force -NoTypeInformation
}

Function Get-EventNumber {
    $existingEvents = Import-CSV -Path "$Env:FNSAssetsDir\events.csv"
    $nextNumber = ([int]$existingEvents.eventID | Measure-Object -Maximum).Maximum + 1 
    $nextNumber
}

Function Get-MatchScore {
    Param(
        [parameter(Mandatory)][array]$Match,
        [array]$ScoringSettings = @($Env:FNSScorePerElim,$Env:FNSScorePerWin,$Env:FNSScorePerTop10Percent,$Env:FNSScorePerTop25Percent,$Env:FNSScorePerPlayerOutlived)
    )

    $Wins = [int]$Match.Top1
    $Top10Percent = [int]$Match.Top3 + [int]$Match.Top5 + [int]$Match.Top10
    $Top25Percent = [int]$Match.Top6 + [int]$Match.Top12 + [int]$Match.Top25
    $PlayersOutlived = [int]$Match.PlayersOutlived

    $place = ($Wins * [int]$ScoringSettings[1]) + ($Top10Percent * [int]$ScoringSettings[2]) + ($Top25Percent * [int]$ScoringSettings[3]) + ($PlayersOutlived * [int]$ScoringSettings[4])
    
    $elims = [int]$Match.kills * [int]$ScoringSettings[0]

    $score = [pscustomobject]@{
        Eliminations = $elims
        Placement = $place
        Total = $elims + $place
    }

    $score
}

Function Update-AllMatchScores {
    $PlayerList = Get-FNPlayerList
    foreach ($p in $PlayerList) {
        $updatedMatches = @()
        $matches = Get-LocalGamesPlayed
        foreach ($m in $matches) {
            $m.Score = (Get-MatchScore -Match $m).Total
            $updatedMatches += $m
        }
        $updatedMatches | Export-Csv -Path $Env:FNSMatchDB -NoTypeInformation -Force
    }
}

Function Get-TopScoringGames {
    Param(
        [string]$Username = "*",
        [string]$Playlist = "*",
        [int]$Count = 25,
        [int]$Days = 5000
    )
    $include = @("p2","p9","p10")
    $recentDate = (Get-Date).AddDays(-$Days)
    $singleMatches = Get-LocalGamesPlayed | Where-Object {((Get-Date -Date $_.DateCollected) -ge $recentDate) -and ($_.matches -eq 1) -and ($include -contains $_.Playlist) -and ($_.Username -like $Username)}
    $formatted = @()
    foreach ($m in $singleMatches) {
        $match = Format-MatchOutput -Entry $m -IncludeUsername -IncludeScore -IncludePlayersOutlived
        $formatted += $match
    }
    $topScores = $formatted | Where-Object { $_.Playlist -like $Playlist } | Sort-Object -Property @{Expression = {$_.Score}; Ascending = $false}, Date | Select-Object -First $Count
    $topScores
}

Function Clear-RecycleBin {
    Remove-Item "$Env:FNSRecycleBinDir\*" -Force
}

Function Get-RecentMatches {
    Param(
        [string]$Username = "*",
        [string]$Playlist = "*",
        [int]$Days = 7
    )

    $recentDate = (Get-Date).AddDays(-$Days)
    $matches = Get-LocalGamesPlayed -Username $Username | Where-Object {((Get-Date -Date $_.DateCollected) -ge $recentDate) -and ((Convert-PlaylistName -Playlist ($_.Playlist + $_.PlaylistID)) -like $Playlist)}
    $matches
}

Function Get-PlayerRecentStats {
    Param(
        [parameter(Mandatory)][string]$Username,
        [string]$Playlist = "*",
        [int]$Days = 7
    )
    
    $matches = Get-RecentMatches -Username $Username -Days $Days -Playlist $Playlist
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
    Param(
        [string]$Playlist = "*",
        [int]$Days = 7
    )
    $all = @()
    $players = Get-FNPlayerList
    foreach ($p in $players) {
        $playerRecent = Get-PlayerRecentStats -Username $p.Username -Days $Days -Playlist $Playlist
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

Function Get-Playlists {
    $playlists = Import-CSV $Env:FNSPlaylistDB
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

    $matches = Get-LocalGamesPlayed -Username $Username | Where-Object { ((Get-Date -Date $_.DateCollected) -gt $StartDate) -and ($validPlaylists -contains $_.Playlist) }

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

    New-StatsObjectToHTML -Object $games | Out-File "$Env:FNSStreamStatsDir\games.html"
    New-StatsObjectToHTML -Object $elims | Out-File "$Env:FNSStreamStatsDir\elims.html"
    New-StatsObjectToHTML -Object $wins | Out-File "$Env:FNSStreamStatsDir\wins.html"
    New-StatsObjectToHTML -Object $KD | Out-File "$Env:FNSStreamStatsDir\KD.html"
}

Function Test-Username {
    Param(
        [parameter(Mandatory)][string]$Username
    )

    $exist = $false
    $PlayerList = (Get-FNPlayerList).Username

    if ($PlayerList -notcontains $Username) {
        foreach ($p in $Env:FNSPlatforms) {
            $new = New-FNPlayer -Username $Username -Platform $p
            if ($new) {$exist = $true}
        }
    }
    else { $exist = $true }

    $exist
}

Function Get-NewVictoryRoyales {
    $royalesLoc = $Env:FNSVictoryDB
    $royales = @()

    # Get Royales Today
    $validPlaylists = @("p2","p9","p10")
    $validPlayIDs = @("ltm109","ltm139")
    $games = Get-LocalGamesPlayed
    $wins = $games | Where-Object {($_.top1 -eq 1) -and ($_.matches -eq 1) -and (($validPlaylists -contains $_.Playlist) -or ($validPlayIDs -contains ("$($_.Playlist)$($_.PlaylistID)")))}
    if (($wins | Measure-Object).Count -gt 0) {
        foreach ($w in $wins) {
            $playlist = Convert-PlaylistName -Playlist "$($w.Playlist)$($w.PlaylistID)"
            $object = [PSCustomObject] @{
                ID = $w.ID
                Username = $w.Username
                'Date Collected' = $w.DateCollected
                Eliminations = $w.Kills
                Playlist = $playlist
                'Minutes Played' = $w.MinutesPlayed
                'Players Outlived' = $w.PlayersOutlived
            }
            $royales += $object
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

Function Find-UnknownPlaylists {
    $output = @()
    $allMatches = Get-LocalGamesPlayed
    $playlists = Get-Playlists
    foreach ($m in $allMatches) {
        $code = $m.Playlist + $m.PlaylistID
        if ($playlists.code -notcontains $code) {
            $format = Format-MatchOutput -Entry $m -IncludeUsername -IncludeNumberOfMatches -IncludeMinutesPlayed -IncludePlayersOutlived
            $output += $format
        }
    }

    $output
}

Function Get-DailyLeaderboard {

}

Initialize-FNSDirectories