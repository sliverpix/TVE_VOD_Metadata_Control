####################################################################
# This scrips downloads / pulls ADI files out of the DB for correction
# to SEASON, Season_ID, EPISODE_NUM and EPISODE_ID. ONLY HLS title
# types are checked. If the elements are not present in the original XML
# we will build them and populate them. XML files are saved to ORIGINAL
# and MODIFIED folders to maintain the integrity of our library. We
# target HLS formats in both HD and SD and set values based on TITLE
# or Title_Brief value. If these dont exist we break out, log it and
# and notify the user.
#
# Logging function has been added to help track processing, error,
# and logic checks.
#
# Summary Report has been added to let the user know what was done. This
# saves on memeory and outputs minimal test to the screen
#
# Name:     updateSeasonEpisodeInformation.ps1
# Authors:  James Griffith
# Version:  1.0.2
# History:  10-30-17	- Initial release
#			11-03-17	- include trailing \s in type 5 regex. hopefully reduce
#							number of false positive matches.
#						- enabled "loose" type extrapolation (... scary ...)
#						- ADD new type to match S##E## pattern
#			
#
####################################################################
#
# performance ideas
# https://blogs.technet.microsoft.com/ashleymcglone/2017/07/12/slow-code-top-5-ways-to-make-your-powershell-scripts-run-faster/
# 	-- lots of good ideas here
#
# http://sqlblog.com/blogs/linchi_shea/archive/2010/01/04/add-content-and-out-file-are-not-for-performance.aspx
#	-- great benchmarking of add-content, out-file, and streamwriter
#
# -- consider suppressing system output and using less write-host in combination with streamwriter to log
#	-- also consider [Console]::WriteLine()
#
####################################################################

# targeted asset ID list
$input_txt_file = "C:\vodscripts\assetid_filelist.inc"	    # target assest ID list
$contents = Get-Content $input_txt_file

# Write-Debug -- debug mode
	#uncomment preference to turn on/off output
	$DebugPreference = "SilentlyContinue"
	#$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")

# set the directories we will be working in
$work_dir = "C:\vodscripts\_UpdateSeasonEpisode\"
$daily_directory = (Get-Date).ToString('MMddyyyy') #+ ("_TESTING")	# uncomment "+ ("_TESTING")" for debug
$originalD = $work_dir + $daily_directory + "\Originals"
$modifiedD = $work_dir + $daily_directory + "\Modified"

# set the log file
$logfile = "logfile.txt"
$tolog = $work_dir + $daily_directory + "\" + $logfile


# set counters for summary
# -- TYPE_UPDATE --
Write-Debug("Counters RESET")
$numContentID = 0
$numOrig = 0
$numMod = 0
$numError = 0
$numWarn = 0
$numType1 = 0
$numType2 = 0
$numType3 = 0
$numType4 = 0
$numType5 = 0
$numType6 = 0


### FUNCTIONS ###


function Get-SeasonEpisode($stringToCheck) {
	# take given string and run against REGEX to find Season Number and
	# Episode Number. Returns an array where [0] is season and [1] is episode.
	
	# define regex strings that matches patterns
	# these are not all inclusive and could miss or hit on the wrong thing sometimes
	# When we ADD more regex_type's be sure we add the variable name to the logic later in this file
		# -- update the value/variable at TYPE_UPDATE (search this file)
	
	# DOUBLE CHECK THE OUTPUT!
    $rgx_type1 = [regex] '\d{1,2}:\d{1,3}'		# S##:## / ##:## (example: S04:05 = Season 4 episode 5)
	
	$rgx_type2 = [regex] '\d{1,2}-\d{1,3}'		# S##-## / ##-## (example: S04-05 = Season 4 episode 5)
	
	$rgx_type3 = [regex] 'S\d{1,2}E\d{1,3}'		# S##E## (example: S5E12 = Season 5 episode 12)
		
	$rgx_type4 = [regex] '\sS\d{1,2}:\s\d{1,3}'	# very loose but looks for the space between season and episode
												# (example: S9: 005 = season 9 episode 5)
	
	$rgx_type5 = [regex] '\d{2,2}_\d{1,3}'		# ##_### (example: (Vice News) 04_014 = season 4 episode 14)
		
	$rgx_type6 = [regex] '\s\d{2,3}\s'		    # ### / ### (format of SEE - season: Episode# Episode#)
												# example: 214 = season 2, episode 14
												# [Alpha]### (example: S104 = season 1 episode 4)
												# ## (example: 11 = tracy ullman - season 1 episode 1)
	
    Write-Debug("In function: stringTocheck: $($stringToCheck)")
	$tString = [String] $stringToCheck
	$cleanString = $tString.Trim()
	
	$s1 = ""
	$e1 = ""
	Switch -regex ($cleanString)
		{			
			$rgx_type1 { 	
                            Write-Debug("I matched TYPE 1")
							$typeMatch = 1
                            $script:numType1++
							$splitString = $matches.values.Trim() -split ":"
                            Write-Debug($matches.values)  
							$s1 = $splitString[0]
							$e1 = $splitString[1]
                            Return $s1,$e1,$typeMatch
							BREAK;
			}
			$rgx_type2 { 	
                            Write-Debug("I matched TYPE 2")
							$typeMatch = 2
                            $script:numType2++
							$splitString = $matches.values.Trim() -split "-"
                            Write-Debug($matches.values)  
							$s1 = $splitString[0]
							$e1 = $splitString[1]
                            Return $s1,$e1,$typeMatch
							BREAK;
			}
			$rgx_type3 { 	
                            Write-Debug("I matched TYPE 3")
						    $typeMatch = 3
                            $script:numType3++
                            $splitString = $matches.values.Trim() -split "E"
							Write-Debug($matches.Values)
							$s1 = $splitString[0].Substring(1,($splitString[0].length-1))
							$e1 = $splitString[1]
                            Return $s1,$e1,$typeMatch
							BREAK;
			}
			$rgx_type4 { 	
                            Write-Debug("I matched TYPE 4")
						    $typeMatch = 4
                            $script:numType4++
                            $splitString = $matches.values.Trim() -split ":\s"
							Write-Debug($matches.Values)
							$s1 = $splitString[0].Substring(1,1)
							$e1 = $splitString[1]
                            Return $s1,$e1,$typeMatch
							BREAK;
			}
			$rgx_type5 {	
                            Write-Debug("I matched TYPE 5")
						    $typeMatch = 5
                            $script:numType5++
							$splitString = $matches.values.Trim() -split "_"
                            Write-Debug($matches.Values) 
							$s1 = $splitString[0]
							$e1 = $splitString[1]
                            Return $s1,$e1,$typeMatch
							BREAK;
			}
			$rgx_type6 {
							Write-Debug("I matched TYPE 6")
							$typeMatch = 6
                            $script:numType6++
							$splitString = $matches.values.Trim()
                            Write-Debug($matches.Values)
						    Write-Host("I loosely matched TYPE 5 pattern. Double check my changes.") -ForegroundColor Yellow
							$script:numWarn++
						    Write-Log($xml_filename, "[WARN] TYPE5 match detected. This could be a flase positive.")
						    Write-Log($xml_filename, "[WARN] String: $($cleanString)")
							$s1 = $splitString.Substring(0,1)
							$e1 = $splitString.Substring(1,($splitString.length-1))
							Write-Log($xml_filename, "[WARN] I matched: Season - $($s1) / Episode - $($e1)")
							Return $s1,$e1,$typeMatch
							BREAK;
			}
			default {
                        Write-Debug("I didnt match anything!?!")
						Write-Host("Season and/or Episode is NOT DISCERNIBLE. Check Log") -ForegroundColor Red
						$script:numError++
						Write-Log($xml_filename, "[ERROR] Failed to match any Season/Episode pattern! the string was: ")
						Write-Log($xml_filename, "[ERROR] $($cleanString)")
                        Return $false
                        
            }
		}
		
	Write-Debug "Im out of the SWITCH in getSeasonEpisode"
	return $s1, $e1, $typeMatch
}



# log-o-funky
function Write-Log {
    # write to our log file
    param ($filename, $message)
	$datetime = (Get-Date).ToString('MM-dd-yyyy hh:mm:ss')
    Add-Content $tolog ("$($datetime) :: $($filename) $($message)")
}

# check for all NULL types of a variable - the smoooth way - JAZZY!
function IsNull($objectToCheck) {
	# https://www.codykonior.com/2013/10/17/checking-for-null-in-powershell/
    if ($objectToCheck -eq $null) {
        return $true
    }

    if ($objectToCheck -is [String] -and $objectToCheck -eq [String]::Empty) {
        return $true
    }

    if ($objectToCheck -is [DBNull] -or $objectToCheck -is [System.Management.Automation.Language.NullString]) {
        return $true
    }

    return $false
}

# summarry report of script/process
function Summarize(){
	Write-Host ".."
	Write-Host ".."
	Write-Host ".."
	Write-Host "	-/-  ***   SUMMARY REPORT   ***  -\-" -BackgroundColor DarkCyan
	Write-Host "---------------------------------------------" -BackgroundColor DarkCyan
	Write-Host -NoNewline "Content ID's Processed		.....	"
	Write-Host $numContentID -ForegroundColor Cyan
	Write-Host -NoNewline "Original XML created		.....	"
	Write-Host $numOrig -ForegroundColor Cyan
	Write-Host -NoNewline "Modified XML created		.....	"
	Write-Host $numMod -ForegroundColor Cyan
	Write-Host -NoNewline "ERRORs Logged				.....	"
	Write-Host $numError -ForegroundColor Red
	Write-Host -NoNewline "WARNings Logged				.....	"
	Write-Host $numWarn -ForegroundColor Yellow
	# -- TYPE_UPDATE --
	Write-Host -NoNewline "Number of Type 1 matches	.....	"
	Write-Host $numType1 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 2 matches	.....	"
	Write-Host $numType2 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 3 matches	.....	"
	Write-Host $numType3 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 4 matches	.....	"
	Write-Host $numType4 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 5 matches	.....	"
	Write-Host $numType4 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 6 matches	.....	"
	Write-Host $numType5 -ForegroundColor Yellow
}


### check and create direcotries and files ###
if(!(Test-Path -Path $work_dir)){
    Write-Debug ("cant find working directory .. creating..")
	New-Item -Path $work_dir -ItemType Directory
	Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $originalD)){
    Write-Debug ("ORIGINALS directory not found! Creating ...")
    New-Item -Path $originalD -ItemType Directory
    Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $modifiedD)){
    Write-Debug ("MODIFIED directory not found! Creating ...")
    New-Item -Path $modifiedD -ItemType Directory
    Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}



# common MSV DB lines
$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'

# cycle through each line of our assets file
Foreach ($line in $contents)
{

	# whats the altcode we are using. Need for checks through out this script
	$alt_code = $line
	$numContentID++
	
	# set our query string to only get our targeted ASSETIDs and HLS_SM_
	$SqlQuery = "SELECT strscreenformat, xmlContent
    FROM [ProvisioningWorkFlow].[Pro].[tAssetInputXML]
    where strContentItemID = '$alt_code' and strScreenFormat like '%HLS_SM_%'"

	# connect to the Databae
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security = True"
 
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
 
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

    $SqlAdapter.SelectCommand = $SqlCmd
 
    $DataSet = New-Object System.Data.DataSet
    [void]($SqlAdapter.Fill($DataSet))
	
	# tell us what we are procesing
	Write-Host ("$($line) :: Processing ...")
	
	# cycle through our query return
    Foreach ($value in $DataSet.Tables[0])
    {
		# save our ORIGINAL metadata
		[void]($content = [xml]($value.xmlContent))
		$xml_filename = ($alt_code + "_" + $value.strscreenFormat + ".xml")
		$content.Save($originalD + "\" + $xml_filename)
		$numOrig++
		
		if ($value.strScreenFormat -like "*_HD*") {Write-Host("... HD meta")}
		if ($value.strScreenFormat -like "*_SD*") {Write-Host("... SD meta")}
		
			
		#set class node values
			#$class_package = $content.ADI.Metadata.AMS		# dont need this one
		$class_title = $content.ADI.Asset.Metadata
			#$class_movie = $content.ADI.Asset.Asset		$ dont need this one
		
		#child nodes
		$ams_product = ($content.ADI.Metadata.AMS.Product)
		$app_contentType = ($class_title.App_Data | Where-Object {$_.Name -eq "Content_Type"})
		$app_TitleBrief = ($class_title.App_Data | Where-Object {$_.Name -eq "Title_Brief"})
		$app_Season = ($class_title.App_Data | Where-Object {$_.Name -eq "Season"})
		$app_SeasonID = ($class_title.App_Data | Where-Object {$_.Name -eq "Season_ID"})
		$app_EpisodeID = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_ID"})
		$app_EpisodeNum = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_Number"})
		$app_EpisodeName = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_Name"})
		

		### START LOGIC ###
        # Check our NODES and ELEMENTS. If we dont have them.. build them.
		#
		# SEASON NODE
        if (!($app_Season)){
			$e_message = "SEASON node is MISSING !! Building node..."
			$numWarn++
			write-log ($xml_filename, "[WARN] $($e_message)")
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Season")
			$app_elem.SetAttribute("Value","")	
			$app_Season = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			write-log ($xml_filename, "[WARN] Finished building SEASON node")
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		}
		
		# SEASON_ID NODE
        if (!($app_SeasonID)){
			$e_message = "SEASON_ID node is MISSING !! Building node..."
			$numWarn++
			write-log ($xml_filename, "[WARN] $($e_message)")
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Season_ID")
			$app_elem.SetAttribute("Value","")	
			$app_SeasonID = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			write-log ($xml_filename, "[WARN] Finished building SEASON_ID node.")
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		}
		
		# EPISODE NODE
        if (!($app_EpisodeNum)){
			$e_message = "EPISODE_NUMBER node is MISSING !! Building node..."
			$numWarn++
			write-log ($xml_filename, "[WARN] $($e_message)")
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Episode_Number")
			$app_elem.SetAttribute("Value","")	
			$app_EpisodeNum = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			write-log ($xml_filename, "[WARN] Finished building EPISODE_NUMBER node")
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		}
		
		# EPISODE_ID NODE
        if (!($app_EpisodeID)){
			$e_message = "EPISODE_ID node is MISSING !! Building node..."
			$numWarn++
			write-log ($xml_filename, "[WARN] $($e_message)")
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Episode_ID")
			$app_elem.SetAttribute("Value","")	
			$app_EpisodeID = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			write-log ($xml_filename, "[WARN] Finished building EPISODE_ID node")
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		}
		#### NODE Check Stop #####

        # if we dont have this we cant proceed
		if ($app_contentType.value -eq "TVS"){
			#im a TV Show
			Write-Debug ("checking Title_Brief...")
			
			# check Title_brief element. If empty/missing/not set.. check the Episode_Name element...
			# if neither has value/str... then its messed up, so BREAK OUT
			# else set our $SeasonEpisodeSTR for extrapolation
			if (IsNull($app_TitleBrief.value)){
				$e_message = "Title_Brief is not set!"
				$script:numError++
				Write-Debug ("$($e_message) check log for [ERROR]") 
				Write-Log ($xml_filename, ("[ERROR] $($e_message) value is: $($app_TitleBrief.value)"))
				Write-Host ("TITLE_BRIEF not set... checking EPISODE NAME...") -ForegroundColor Red
				
				if (IsNull($app_EpisodeName.value)){
					$e_message = "EPISODE_NAME is not set either!!"
					Write-Debug($e_message)
					$script:numError++
					Write-Log($xml_filename,"[ERROR] $($e_message)")
					Write-Log($xml_filename, "Something is wrong with this META! Breaking out!")
					Write-Host("$($e_message) BREAKING OUT!") -ForegroundColor Red
					BREAK;
				} else {
					Write-Debug("Found EPISODE NAME: $($app_EpisodeName.value)")
					Write-Host("Found EPISODE NAME.") -ForegroundColor Green
					Write-Log($xml_filename,"Found EPISODE NAME: $($app_EpisodeName.value)")
					$SeasonEpisodeSTR = $app_EpisodeName.value
				}
			} else {
				Write-Debug("Found TITLE BRIEF: $($app_TitleBrief.value)")
				Write-Log($xml_filename,"[INFO] Found TITLE BRIEF: $($app_TitleBrief.value)")
				$SeasonEpisodeSTR = $app_TitleBrief.value
			}
						
			
			#from extrapolation get season and episode number
			if (IsNull($SeasonEpisodeSTR)){
				$e_message = "I dont have a STRING to check for Season and Episode!"
				Write-Debug($e_message)
				$script:numError++
				Write-Log($xml_filename,"[ERROR] $($e_message)")
				Write-Log($xml_filename,"value of SeasonEpisodeSTR is: $($SeasonEpisodeSTR)")
				Write-Host("Something Broke!") -ForegroundColor Red
				BREAK;
			} else {
				$se_array = Get-SeasonEpisode($SeasonEpisodeSTR)
				$exSeason = $se_array[0]
				$exEpisode = $se_array[1]
				$exTypeMatch = $se_array[2]
			}
			
			# check our function returned some usefule data or break
			if (IsNull($exTypeMatch) -or IsNull($exSeason) -or IsNull($exEpisode)){
				$e_message = "EXTRAPOLATION failed! No changes were made, check log file!"
				Write-Debug($e_message)
				#do not update error counters
				Write-log($xml_filename,"[ERROR] $($e_message)")
				Write-Log($xml_filename,"[ERROR] Match Type: $($exTypeMatch)")
				Write-Log($xml_filename,"[ERROR] Season: $($exSeason)")
				Write-Log($xml_filename,"[ERROR] Episode: $($exEpisode)")
				Write-Host("Couldnt get season/episode from meta. Check Log") -ForegroundColor Red
				BREAK;
			}
			
			# check for TYPE 5 match.. very loose regex. Extrapolate but inform
			# operator to check meta to collect pattern for use later.
			# else set EPISODE_ID and SEASON_ID
			# update this value when new regex_types added
			# -- TYPE_UPDATE --
			if ($exTypeMatch -eq 6){
				$e_message = "TYPE 5 match is very loose. Please double check meta and log."
				#dont update WARN counters
				Write-Log($xml_filename, "[WARN] $($e_message)")
				Write-Log($xml_filename, "[WARN] String sent to function: $($SeasonEpisodeSTR)")
				Write-Log($xml_filename, "[WARN] SEASON String we matched: $($exSeason)")
				Write-Log($xml_filename, "[WARN] EPISODE String we matched: $($exEpisode)")
				
				# match or set season and episode numbers
				Write-Debug ("SEASON is $($app_Season.value) ==>> changing to: $($exSeason)")
				Write-Debug ("EPISODE is $($app_episodeID.value) ==>> changing to: $($exEpisode)")
				
				$app_EpisodeID.value = $exEpisode
				$app_EpisodeNum.value = $exEpisode
				$app_Season.value = $exSeason
				$app_SeasonID.value = $exSeason

                Write-Host "Done!" -ForegroundColor Green
				
			} else {
			# match or set season and episode numbers
				$e_message = "TYPE $($exTypeMatch) match found."
				Write-Debug $e_message
				Write-Debug ("SEASON is $($app_Season.value) ==>> changing to: $($exSeason)")
				Write-Debug ("EPISODE is $($app_episodeID.value) ==>> changing to: $($exEpisode)")
				
				Write-log ($xml_filename, "[INFO] $($e_message)")
				Write-Log ($xml_filename, "[INFO] changing SEASON from $($app_Season.value) <to> $($exSeason)")
				Write-Log ($xml_filename, "[INFO] changing EPISODE from $($app_EpisodeID.value) <to> $($exEpisode)")
				
				$app_EpisodeID.value = $exEpisode
				$app_EpisodeNum.value = $exEpisode
				$app_Season.value = $exSeason
				$app_SeasonID.value = $exSeason
				
				Write-Host $e_message -BackgroundColor DarkGray -ForegroundColor Green
                #Write-Host "Done!" -ForegroundColor Green
			}
			
		} else {
			#im NOT a TV Show
			$e_message = "Content_Type is NOT TVS."
			$script:numError++
			Write-Host ("[ERROR]! Skipping... check log file!") -ForegroundColor red
			Write-Debug ("$($e_message) ... Im Seeing: $($app_contentType.value)")
			Write-Log($xml_filename, ("[ERROR] $($e_message). Check $($originalD)\$($xml_filename)"))
			Break;
		}
		
		#save modified version -- this in the right place?
		$numMod++
		$content.Save($modifiedD + "\" + $xml_filename)
	}
}

# get summary report
Summarize