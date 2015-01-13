$debug = 0
$AwsStatusWebPageUri = 'http://status.aws.amazon.com'


Function Get-AllServiceUris 
    {
    $StatusWebPage = Invoke-WebRequest -Uri $AwsStatusWebPageUri
    $RssFeeds = ($StatusWebPage.links |  Where {$_.href -like "*.rss"}).href 

    $AWSRegions = (Get-AWSRegion).Region
    [regex] $AWSRegions_regex = ‘(‘ + (($AWSRegions |foreach {[regex]::escape($_)}) –join “|”) + ‘)’
    
    $AllServiceUris = @()

    Foreach ($RssFeed in $RssFeeds) {
        If($RssFeed -match $AWSRegions_regex) {
            #Write-Host $RssFeed 
            $entry = New-Object PSObject -Property @{
                Service = ($RssFeed -split $matches[1])[0] -replace ('^rss/','') -replace ('-$','')
                Region = $matches[1]
                Uri = $AwsStatusWebPageUri + "/" + $RssFeed
                }
            $AllServiceUris += $entry
            }
        Else {
            $entry = New-Object PSObject -Property @{
                Service = ($RssFeed -split $matches[1])[0] -replace ('^rss/','') -replace ('.rss$','')
                Region = $null
                Uri = $AwsStatusWebPageUri + "/" + $RssFeed
                }
            $AllServiceUris += $entry
            }
        }

    $AllServiceUris | Sort-Object Service,Region,Uri -unique

    }


function Convert-DateTimeString ([String]$strDateTime)
    {
        #source: http://www.powershellmagazine.com/2013/07/08/pstip-converting-a-string-to-a-system-datetime-object/ 
        #format reference: http://msdn.microsoft.com/en-us/library/8kb3ddd4.aspx
        $result = New-Object DateTime

        Switch -Regex ($strDateTime) #store with 'script' scope so they are available the next time function is called in case the new time does not have a date (i.e. assume date is same as previous)
            {
            '\d{2}\s\w{3}\s\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "dd MMM yyyy" ; break}
            '\d{1}\s\w{3}\s\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "d MMM yyyy" ; break}
            '\d{2}\/\d{2}\/\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "MM/dd/yyyy" ; break}
            '\d{2}\/\d{2}\/\d{2}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "MM/dd/yy" ; break}
            '\d{1}\/\d{2}\/\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "M/dd/yyyy" ; break}
            '\d{2}\/\d{1}\/\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "MM/d/yyyy" ; break}
            '\d{1}\/\d{2}\/\d{2}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "M/dd/yy" ; break}
            '\d{2}\/\d{1}\/\d{2}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "MM/d/yy" ; break}
            '\d{1}\/\d{1}\/\d{4}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "M/d/yyyy" ; break}
            '\d{1}\/\d{1}\/\d{2}' {$script:strDatePart = $matches[0] ; $script:DateFormat = "M/d/yy" ; break}
            }



        Switch -Regex ($strDateTime)
            {
            '\d{2}:\d{2}\s[AP]{1}[M]' {$strTimePart = $matches[0] ; $TimeFormat = "hh:mm tt" ; break}            
            '\d{1}:\d{2}\s[AP]{1}[M]' {$strTimePart = $matches[0] ; $TimeFormat = "h:mm tt" ; break}
            '\d{2}:\d{1}\s[AP]{1}[M]' {$strTimePart = $matches[0] ; $TimeFormat = "hh:m tt" ; break}
            '\d{1}:\d{1}\s[AP]{1}[M]' {$strTimePart = $matches[0] ; $TimeFormat = "h:m tt" ; break}
            '\d{2}:\d{2}:\d{2}' {$strTimePart = $matches[0] ; $TimeFormat = "HH:mm:ss" ; break}
            '\d{1}:\d{2}:\d{2}' {$strTimePart = $matches[0] ; $TimeFormat = "H:mm:ss" ; break}
            }
        
        If ($strDateTime -match 'PST|PDT|MDT') #convert timezone short code to offset from UTC. Assumed we will not have mixed timezone in a single event
            {
            $script:strTz = $matches[0]
            $script:intTzOffset = Switch ($strTz)
                {
                PST {-8}
                PDT {-7}
                MST {-7}
                MDT {-6}
                }
            }
        
        $strDateTimeTz = "$strDatePart $strTimePart $intTzOffset"
        $Format = "$DateFormat $TimeFormat z"

        $convertible = [DateTime]::TryParseExact(
            $strDateTimeTz,
            $Format,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$result)
 
        if ($convertible) {$result}

        If ($Debug)
            {
            Write-Host " "
            Write-Host "Input strDateTime: $strDateTime"
            Write-Host "strDatePart: $strDatePart"
            Write-Host "DateFormat: $DateFormat"
            Write-Host "strTimePart: $strTimePart"
            Write-Host "TimeFormat: $TimeFormat"
            Write-Host "intTzOffset: $intTzOffset"
            Write-Host "strDateTimeTz: $strDateTimeTz"
            Write-Host "Format: $Format"
            Write-Host "Result: $result"
            }
    }


$AllServiceUris = Get-AllServiceUris
#$RssUris = $AllServiceUris | Where {($_.Region -like 'eu-west-1') -and ($_.Service -like 'ec2')}
#$RssUris = $AllServiceUris | Where {($_.Region -like 'sa-east-1') -and ($_.Service -like 'ec2')}
$RssUris = $AllServiceUris 

$Rss = @()
$arrIncidents = @()
Foreach ($Uri in $RssUris)
    {
    Write-Host -noNewLine "."
    $Rss = Invoke-RestMethod -Uri $Uri.Uri
    Foreach ($RssEntry in $Rss) #Each Uri returns multiple events so need to expand them out so we can add Region and Service properties to each
        {
        $PubDateConverted = Convert-DateTimeString $RssEntry.pubDate #Must convert publish date first to set the date and timezone for conversions of time in description field (which may not specify date or timezone)
        If ($RssEntry.description -match '(?<start>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?).*\s(?<finish>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?)') #Just looking for descriptions that have at least 2 times with anything between them. Where there are incidents which have multiple start and end times it just takes the first as start and last as end, i.e. extreme ends. Also include date if it exists in 1/1/2011 format.
            {
            $startDate = Convert-DateTimeString $matches["start"]
            $finishDate = Convert-DateTimeString $matches["finish"]
            }
        Else
            {
            $startDate = $null
            $finishDate = $null
            }
        $NotePropertyMembers = @{
            Region = $Uri.Region
            Service = $Uri.Service
            PubDateConverted = $PubDateConverted
            StartTimeConverted = $startDate
            EndTimeConverted = $finishDate
            IncidentMinutes = ($finishDate - $startDate).TotalMinutes
            TimeZone = $strTz
            TimeZoneOffset = $intTzOffset
            }
        Add-Member -InputObject $RssEntry -NotePropertyMembers $NotePropertyMembers
        $arrIncidents += $RssEntry
        }
    
    }

Write-Host "" 


$arrIncidents  | Sort PubDateConverted | ft Region,Service,PubDate,TimeZone,TimeZoneOffset,PubDateConverted,StartTimeConverted,EndTimeConverted,IncidentMinutes,Description -AutoSize -Wrap
$arrIncidents  | Sort PubDateConverted | Select Region,Service,PubDate,TimeZone,TimeZoneOffset,PubDateConverted,StartTimeConverted,EndTimeConverted,IncidentMinutes,Description | Export-Csv .\aws-status-rss.csv -NoTypeInformation
$arrIncidents | Out-GridView

# *** Testing ***

# Quick check for all unique timezones in pubDate because TZ abbreviations are not unique: http://www.iana.org/time-zones  http://www.timeanddate.com/time/zones/ 
# $tz = @() ; $rss | foreach {$arrPubDate = $_.pubDate.split() ;  $tz += ($arrPubDate[-1])  } ; $tz | select -unique  #-1 is shorthand for last element in array
# Currently only PST (-8), PDT (-7), MST (-7)

# $arrIncidents | where {$_.description -match '\d{1,2}\/\d{1,2}\/\d{2,4}'} #date in description 01/02/2014
# $arrIncidents | where {$_.description -match '\d{1,2}:\d{1,2}'} #time in description 01:01 


# "Between 11:05 AM PST and 11:44 AM PST some customers" -match '(?<start>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?).*\s(?<finish>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?)' ; $matches
# "Between 11:05 AM PST 01/01/14 and 11:44 AM PST 01/02/14 some customers" -match '(?<start>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?).*\s(?<finish>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?)' ; $matches
# "Between 11:05 AM PST 01/01/14 bla" -match '(?<start>\d{1,2}:\d{2}\s[AP]{1}[M](\s\d{1,2}\/\d{1,2}\/\d{2,4})?)' ; $matches


# To Fix:  "Between December 13 10:39 PM and December 14 01:16 AM PST Route 53 customers"