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
# Version:  1.10.5
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

# ### LOCAL TESTING ###
#$input_txt_file = "C:\Users\jgg049\Documents\VZ3 TVE\VOD\Alt_Code_Proj\assetid_filelist.inc"
#$work_dir = "C:\Users\jgg049\Documents\VZ3 TVE\VOD\Alt_Code_Proj\_UpdateSeasonEpisode\"
#$libPath = "C:\Users\jgg049\Documents\VZ3 TVE\VOD\Alt_Code_Proj\"
#$SQLServer = 'MSVTXCAWDPV01.vhe.fiosprod.net\MSVPRD01'

# Write-Debug -- debug mode
# uncomment preference to turn on/off output
#$DebugPreference = "SilentlyContinue"
$DebugPreference = "Continue"
Write-Debug("DEBUG ACTIVE!")

# set environment variables
if($DebugPreference -eq "Continue"){
    $work_dir = "C:\vodscripts\_UpdateSeasonEpisode\_Debug\"
    $input_txt_file = "C:\vodscripts\testlist.inc"
} else {
    $work_dir = "C:\vodscripts\_UpdateSeasonEpisode\"
    $input_txt_file = "C:\vodscripts\assetid_filelist.inc"
}

# set the directories we will be working in
$daily_directory = (Get-Date).ToString('MMddyyyy') 
$originalD = $work_dir + $daily_directory + "\Originals"	# save all meta we find before changes
$modifiedD = $work_dir + $daily_directory + "\Modified"		# save any meta we do change
$reviewD = $work_dir + $daily_directory + "\Review"			# save any meta we change but may need human eyes/brains to check it
$libPath = "C:\vodscripts\_Includes"						# path to our library files
$blobDict = $libPath + "\SeriesNamesNew.csv"				# Dictionary file for our Series_Name & Series_ID. Delimited by "|"
$provDict = $libPath + "\csv_Providers.inc"					# Dictionary file of Providers and the Codes for them. Delimited by ':'
$contents = Get-Content $input_txt_file						# load the data in our input file


# set the log file
$logfile = "logfile.txt"
$tolog = $work_dir + $daily_directory + "\" + $logfile

# NODE check and value of SEASON
# we will assume SEASON has some kind of value for now
$isNullSeason = 1

# set counters for summary
# -- TYPE_UPDATE --
Write-Debug("Counters RESET")
$numContentID = 0
$numOrig = 0
$numMod = 0
$numRev = 0
$numError = 0
$numWarn = 0
$numType1 = 0
$numType2 = 0
$numType3 = 0
$numType4 = 0
$numType5 = 0
$numType6 = 0
$numType7 = 0
$numType8 = 0
$numTypeDate = 0
$numByProvider = 0


### FUNCTIONS ###


function Get-SeasonEpisode($stringToCheck) {
	# take given string and run against REGEX to find Season Number and
	# Episode Number. Returns an array where [0] is season and [1] is episode.
	
	# define regex strings that matches patterns
	# these are not all inclusive and could miss or hit on the wrong thing sometimes
	# When we ADD more regex_type's be sure we add the variable name to the logic later in this file
		# -- update the value/variable at TYPE_UPDATE (search this file)
	
	# DOUBLE CHECK THE OUTPUT!
    $rgx_type1 = [regex] 'S\d{1,2}:\d{1,3}'		# S##:## / ##:## (example: S04:05 = Season 4 episode 5)
	
	$rgx_type1_1 = [regex] 'S\d{1,2}:E\d{1,3}'	# S##:E### (Example: S13:E17 = Season 13 Episdoe 17)
	
	$rgx_type2 = [regex] 'S\d{1,2}-\d{1,3}'		# S##-## / ##-## (example: S04-05 = Season 4 episode 5)
	
	$rgx_type3 = [regex] '\d{1,2}E\d{1,3}'		# S##E## (example: S5E12 = Season 5 episode 12)
	
	$rgx_type3_1 = [regex] 's\d{1,2}\sE\d{1,3}'	# S## E## (example: S2 E01) = Season 2 Episode 01
    
    $rgx_type3_2 = [regex] 's\d{1,2}\sEp\d{1,3}' # S## Ep## (example: S1 Ep01) = Season 1 Episode 01
		
	$rgx_type4 = [regex] '\sS\d{1,2}:\s\d{1,3}'	# very loose but looks for the space between season and episode
												# (example: S9: 005 = season 9 episode 5)
	
	$rgx_type5 = [regex] '\d{2,2}_\d{1,3}'		# ##_### (example: (Vice News) 04_014 = season 4 episode 14)

    $rgx_type5_1 = [regex] 'S\d{2,2}_E\d{2,2}'  # S##_E## (example: Bug Juce_S01_E07 = season 1 episode 07)
		
	$rgx_type6 = [regex] '\d{3,3}'		        # ### / ### (format of SEE - season: Episode# Episode#)
												# example: 214 = season 2, episode 14
												# [Alpha]### (example: S104 = season 1 episode 04)
												
	$rgx_type7 = [regex] '\d{4,4}'		        # ### / ### (format of SEE - season: Episode# Episode#)
												# example: 1214 = season 12, episode 14
												# [Alpha]### (example: S1204 = season 12 episode 4)
	
    $rgx_type8 = [regex] 'S\d{1,2}\sE\w+e\s\d{1,2}'		# matches formats like "S1 Episode 8 HD"

	
	$rgx_typeDate = [regex] '\s\d{1,2}/\d{1,2}'	# (special match) Date-Style format of " 5/30"
												# will xform to " 5-30" and set EPISODE_NUMBER to 5-30
												# if SEASON has value we will leave it, otherwise set it to 2018
	
	
    Write-Debug("[Get-SeasonEpisode] In function: stringTocheck: $($stringToCheck)")
	$tString = [String] $stringToCheck
	$cleanString = $tString.Trim()
	
	$s1 = ""
	$e1 = ""
	Switch -regex ($cleanString)
		{			
			$rgx_type1 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 1")
							$typeMatch = 1
                            $script:numType1++
							$splitString = $matches.values.Trim() -split ":"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")  
							$s1 = $splitString[0].Substring(1)
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			$rgx_type1_1 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 1")
							$typeMatch = 1
                            $script:numType1++
							$splitString = $matches.values.Trim() -split ":"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")  
							$s1 = $splitString[0].Substring(1)
							$e1 = $splitString[1].Substring(1)
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			$rgx_type2 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 2")
							$typeMatch = 2
                            $script:numType2++
							$splitString = $matches.values.Trim() -split "-"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")  
							$s1 = $splitString[0].Substring(1)
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			$rgx_type3 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 3")
						    $typeMatch = 3
                            $script:numType3++
                            $splitString = $matches.values.Trim() -split "E"
							Write-Debug("[Get-SeasonEpisode] $($matches.values)")
							$s1 = $splitString[0]
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
            $rgx_type3_1 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 3.1")
						    $typeMatch = 3
                            $script:numType3++
                            $splitString = $matches.values.Trim() -split "E"
							Write-Debug("[Get-SeasonEpisode] $($matches.values)")
							$s1 = $splitString[0].Substring(1)
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
            $rgx_type3_2{
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 3.2")
						    $typeMatch = 3
                            $script:numType3++
                            $splitString = $matches.values.Trim() -split "Ep"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")
							$s1 = $splitString[0].Substring(1)
					    	$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
                            BREAK;
            }
			$rgx_type4 { 	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 4")
						    $typeMatch = 4
                            $script:numType4++
                            $splitString = $matches.values.Trim() -split ":\s"
							Write-Debug("[Get-SeasonEpisode] $($matches.values)")
							$s1 = $splitString[0].Substring(1,1)
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			$rgx_type5 {	
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 5")
						    $typeMatch = 5
                            $script:numType5++
							$splitString = $matches.values.Trim() -split "_"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)") 
							$s1 = $splitString[0]
							$e1 = $splitString[1]
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
            $rgx_type5_1 {
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 5.1")
						    $typeMatch = 5
                            $script:numType5++
							$splitString = $matches.values.Trim() -split "_"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)") 
							$s1 = $splitString[0].Substring(1)
							$e1 = $splitString[1].Substring(1)
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
            }
            $rgx_type8 {
                            Write-Debug("[Get-SeasonEpisode] I matched TYPE 8")
                            $typeMatch = 8
                            $script:numType8++
                            $splitString = $matches.values.Trim() -split "Episode"
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")
                            $s1 = $splitString[0].Substring(1)
                            $e1 = $splitString[1].Trim()
                            Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
            }
			$rgx_typeDate {
							Write-Debug("[Get-SeasonEpisode] I matched DATE TYPE")
							$typeMatch = "DateType"
                            $script:numTypeDate++
							$splitString = $matches.values.Trim()
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")
						    Write-Log $xml_filename "I" "[Get-SeasonEpisode] DATE TYPE match detected."
						    Write-Log $xml_filename "I" "[Get-SeasonEpisode] String: $($cleanString)"
							$s1 = (Get-Date).ToString('yyyy')
							$e1 = $splitString.Replace("/","-")
							Write-Log $xml_filename "I" "[Get-SeasonEpisode] Setting EPISODE to $($e1)"
							Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
            $rgx_type7 {
							Write-Debug("[Get-SeasonEpisode] I matched TYPE 7")
							$typeMatch = 7
                            $script:numType7++
							$splitString = $matches.values.Trim()
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")
						    Write-Host("[Get-SeasonEpisode] I loosely matched TYPE 7 pattern. Double check my changes.") -ForegroundColor Yellow
							$script:numWarn++
						    Write-Log $xml_filename "W" "[Get-SeasonEpisode] TYPE 7 match detected. This could be a false positive."
						    Write-Log $xml_filename "W" "[Get-SeasonEpisode] String: $($cleanString)"
							$s1 = $splitString.Substring(0,2)
							$e1 = $splitString.Substring(2,($splitString.length-2))
							Write-Log $xml_filename "w" "[Get-SeasonEpisode] I matched: Season - $($s1) / Episode - $($e1)"
							Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			$rgx_type6 {
							Write-Debug("[Get-SeasonEpisode] I matched TYPE 6")
							$typeMatch = 6
                            $script:numType6++
							$splitString = $matches.values.Trim()
                            Write-Debug("[Get-SeasonEpisode] $($matches.values)")
						    Write-Host("[Get-SeasonEpisode] I loosely matched TYPE 6 pattern. Double check my changes.") -ForegroundColor Yellow
							$script:numWarn++
						    Write-Log $xml_filename "w" "[Get-SeasonEpisode] TYPE 6 match detected. This could be a false positive."
						    Write-Log $xml_filename "w" "[Get-SeasonEpisode] String: $($cleanString)"
							$s1 = $splitString.Substring(0,1)
							$e1 = $splitString.Substring(1,($splitString.length-1))
							Write-Log $xml_filename "w" "[Get-SeasonEpisode] I matched: Season - $($s1) / Episode - $($e1)"
							Return $s1.Trim(),$e1.Trim(),$typeMatch
							BREAK;
			}
			default {
                        Write-Debug("[Get-SeasonEpisode] I didnt match anything!?!")
						Write-Host("[Get-SeasonEpisode] Season and/or Episode is NOT DISCERNIBLE. Check Log") -ForegroundColor Yellow
						$script:numWarn++
						Write-Log $xml_filename "w" "[Get-SeasonEpisode]Failed to match any Season/Episode pattern! the string was: "
						Write-Log $xml_filename "w" "[Get-SeasonEpisode] $($cleanString)"
                        Return $false
                        
            }
		}
}



# log-o-funky
function Write-Log {
    # write to our log file
	# Log level can only be I-INFO, W-WARN or E-ERROR... fail on anything else
    param ($filename, $loglevel, $message)

	switch($loglevel){
		"I" {$ll="INFO"; break;}
		"W" {$ll="WARN"; break;}
		"E" {$ll="ERROR"; break;}
		default {Write-Debug("Fatal-error in WRITE-LOG: Log Level flag can only be I, W, or E!!"); break;}
	}
	
	$datetime = (Get-Date).ToString('MM-dd-yyyy hh:mm:ss')
    Add-Content $tolog ("$($datetime) :: $($filename) [$($ll)] $($message)")

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

# Clean the string provided
function cleanUp($dirtyString, [switch]$isSeries){

	# if its a SERIES node, we need to check some other things
	# need to check Series_Name and Series_ID
	# make it a string
	
	Write-Debug("[cleanUp] cleanUp rec'd $($dirtyString)")
	
	# cleanup an title or string we receive. removes as many varians of "HD" as we know of
	# also changes all "_" to spaces to correct title/series names we are receiving with
	# underscores for spaces. Finally remove any whitespace from beginning/end of our string
	$dirtyString = $dirtyString.toString()
	$dirtyString = $dirtyString.Replace('_',' ')	#this works ok
    $dirtyString = $dirtyString -replace ('&amp;','and')
	$dirtyString = $dirtyString -replace '\(hd\)$'	#not case sensitice like .Replace()
	$dirtyString = $dirtyString -replace 'hd$'		#not case sensitice like .Replace()

	$cleanString = $dirtyString.Trim()

	# removed totitlecase per russ request 06-28-2018
	if (!($isSeries)){
		Write-Debug("[cleanUp] cleanUp returning $($cleanString)")
	#	return (Get-Culture).textinfo.totitlecase($cleanString.tolower())
	} else {
		write-debug ("[cleanUp] Cleanup switch isSeries was SET")
		write-debug ("[cleanUp] Passing $($cleanString) to Find_SeriesName with checkall switch")
		$seriesNameString = Find_SeriesName -stringtocheck $cleanString -checkall
		
		if($seriesNameString -eq $false){
			#false return from Find_SeriesName
			Write-Host("[cleanUp] Find_SeriesName returned FALSE. Returning $($cleanString)") -ForegroundColor Red
		} else {
			Write-Debug ("[cleanUp] Find_SeriesName returned STRING: $($seriesNameString)")
		#	return (Get-Culture).textinfo.totitlecase($cleanString.tolower())
			$cleanString = $seriesNameString
		}
	}

	return [string]$cleanString
}

# summary report of script/process
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
	Write-Host -NoNewline "XML for Review				.....	"
	Write-Host $numRev -ForegroundColor Red
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
	Write-Host $numType5 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 6 matches	.....	"
	Write-Host $numType6 -ForegroundColor Yellow
	Write-Host -NoNewline "Number of Type 7 matches	.....	"
	Write-Host $numType7 -ForegroundColor Yellow
	Write-Host -NoNewline "Number of Type 8 matches	.....	"
	Write-Host $numType8 -ForegroundColor Green
	Write-Host -NoNewline "Number of Date Type matches	.....	"
	Write-Host $numTypeDate -ForegroundColor Green
    Write-Host -NoNewline "Number of Provider matches	.....	"
    Write-Host $numByProvider -ForegroundColor Yellow

}


# check our Dictionary file for the Series_Name... if no match
# check the TITLE element against the dictionary
# break with REVIEW if nothing else matched.
function Find_SeriesName{
	
	#set our paramaters make it required
	Param
(
		#[parameter(Mandatory=$true, ParameterSetName="thisString")]
		#[string[]]
        $stringtocheck,

		#[parameter(Mandatory=$false, ParameterSetName="theSwitches")]
		[switch]$titlecheck, 
        [switch]$categorycheck,
        [switch]$checkall
)

	# 1 = found a match
	$matchfound = 0
	write-debug ("[Find_SeriesName] Matchfound set: $($matchfound)")
	
	
	Foreach ($item in $seriesDict){
		if ($stringtocheck -eq $item."BLOB_NAME"){
			Write-Debug ("[Find_SeriesName] found a BLOBNAME: $($stringtocheck)")
			$returnString = $item."CORRECT_NAME"
			$matchfound = 1
			write-debug ("[Find_SeriesName] Matchfound changed: $($matchfound)")
		}
	}
	
    # did out sting match in the dictionary file?
    if($matchfound -eq 0){
        Write-debug("[Find_SeriesName] Didnt find a match for $($stringtocheck) in CSV")
    }

	# Use Category_Display to ran against our Dictionary file and look for a match.
	if($categorycheck -or $checkall){
		#check the Category_Display element for a series name match
		if($matchfound -eq 0){
			# Category_Display Node check.
			# if its not present, maybe we should check for CATEGORY element?? -- add this later
			if (!($app_CategoryDisplay)){
				Write-Debug ("[Find_SeriesName.categorycheck] Category_Display is not set/built")
				Write-Debug ("[Find_SeriesName.categorycheck] I rec'd $($app_CategoryDisplay.value)")
				# no reason to return false here.. we will use $matchfound at the end of the logic for that
			} else {
				Write-Debug ("[Find_SeriesName.categorycheck] Category_Display was found...")
				Write-Debug ("[Find_SeriesName.categorycheck] its value is $($app_CategoryDisplay.value)")
				
				$catSplit = $app_CategoryDisplay.value -split ","

				write-debug("[Find_SeriesName.categorycheck] $($catSplit.Length)")

				Foreach ($catval in $catSplit){
    				write-debug("[Find_SeriesName.categorycheck] $($catval)")
				}

				# check if our category csv contains anything from
				# category_display
				Foreach ($item in $seriesDict){
					if ($catSplit -like "*$($item.BLOB_NAME)"){
						Write-Host("[Find_SeriesName.categorycheck] The array contained: $($item.BLOB_NAME)") -ForegroundColor Green
						Write-Host("[Find_SeriesName.categorycheck] returning CORRECT_NAME: $($item.CORRECT_NAME)") -ForegroundColor Green
						$returnString = $item.CORRECT_NAME
						$matchfound = 1
						BREAK;
					}
				}
                if($matchfound -eq 0){Write-Debug("[Find_SeriesName.categorycheck] No match found!")}
			}
		} else {
			write-debug("[Find_SeriesName.categorycheck] A MATCH was already found.")
		}
	}
	
	if($titlecheck -or $checkall){
		#check the TITLE element for a series name match
		if($matchfound -eq 0){
			Foreach ($item in $seriesDict){
                if($app_Title.value -like $item.BLOB_NAME){
                    Write-Host("[Find_SeriesName.titlecheck] TITLE matched $($item.BLOB_NAME)") -ForegroundColor Green
                    Write-Host("[Find_SeriesName.titlecheck] returning CORRECT_NAME: $($item.CORRECT_NAME)") -ForegroundColor Green
                    $returnString = $item.CORRECT_NAME
					$matchfound = 1
                    BREAK;
                }
            }

            #did we find a match -- without spitting output for each line of the dictionary file
            if($matchfound -eq 0){Write-Debug("[Find_SeriesName.titlecheck] No match found for TiTLE: $($app_Title.Value)")}

		} else {
			write-debug("[Find_SeriesName.titlecheck] A MATCH was already found.")
		}
	}

	#write-debug("[Find_SeriesName]: matchfound is $($matchfound)")
	if($matchfound -eq 0){
		write-Host("[Find_SeriesName] No match was found. Returning: $($stringtocheck)") -ForegroundColor Yellow
		RETURN [string]$stringtocheck
	} else {
		Write-Host("[Find_SeriesName] Found Match. Returning: $($returnString)") -ForegroundColor Green
		RETURN [string]$returnString
	}
}

# ## Get-SeasonEpisodebyProider()
# a differnt way to get and set Season and Episode meta.
# Using Category_Disply we will look for a match in our
# Provider CSV. If a match is found, we will set the EPISODE_NAME
# to the TITLE_BRIEF value, SEASON & EPISODE_NUMBER will be
# set to '0'.
function Get-SeasonEpisodebyProvider{

	# check our nodes
	if(!($app_EpisodeName)){
		$e_message = "[Get-SeasonEpisodebyProvider] EPISODE_NAME is missing."
		$numWarn++
		write-log $xml_filename "W" $e_message+" ... building node..."
		Write-Debug $e_message
		
		# build the EPISODE_NAME node
		# build our node and set an empty value for now.
		$app_elem = $content.CreateElement("App_Data")
		$app_elem.SetAttribute("App","$($AMS_product)")
		$app_elem.SetAttribute("Name","Episode_Name")
		$app_elem.SetAttribute("Value","")	
		$app_EpisodeName = $content.ADI.Asset.Metadata.AppendChild($app_elem)
        Write-Debug("[Get-SeasonEpisodebyProvider] built")
	}
	
	if(!($app_CategoryDisplay)){
		$e_message = "[Get-SeasonEpisodebyProvider] CATEGORY_DISPLAY is missing!"
		$numError++
		Write-Log $xml_filename "e" $e_message
		Write-Host "$($e_message) ... BREAKING OUT!"
		return $False
	} else {
		# split our category display to check it against the provider file
		$catSplit = $app_CategoryDisplay.Value -split ","
        Write-Debug("[Get-SeasonEpisodebyProvider] Category Display has $($catSplit.length) values")
	}
	
	# check if our provider.csv contains anything from
	# category_display and prep our output
    $matchfound=0
	Foreach ($catval in $catSplit){
    	write-debug("[Get-SeasonEpisodebyProvider] Checking Provider CSV for: $($catval)")
		if ($catval -in $providerDict.TVS){
            $e_message = "[Get-SeasonEpisodebyProvider] setting EPISODE_NAME to: $($app_TitleBrief.value)"
			Write-Host("[Get-SeasonEpisodebyProvider] The PROVIDER array contained: $($catval)") -ForegroundColor Green
			Write-Host("$($e_message)") -ForegroundColor Green
			$app_EpisodeName.value = $app_TitleBrief.value
			$retEName = "byProvider"
			$s1=0
			$e1=0
            $matchfound=1

            Write-Log $xml_filename "I" $e_message
            Write-Log $xml_filename "I" "[Get-SeasonEpisodebyProvider] Season and Episdoe set to 0"
		} else {
            $e_message = "[Get-SeasonEpisodebyProvider] No match found in PROVIDER CSV for $($catval)"
			write-debug ($e_message)
            Write-Log $xml_filename "W" $e_message
            $numWarn++
		}
	}
	
	# if found a match in the provider csv, so return season=0 / episode=0/ episode_name = title_brief
    if($matchfound=1){
        $script:numByProvider++
	    Return $s1, $e1, $retEName
    } else{
        Return $false
    }

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

if(!(Test-Path -Path $reviewD)){
	Write-Debug ("REVIEW directory not found! Creating ...")
	New-Item -Path $reviewD -ItemType Directory
	Write-Debug ("Fixed!")
}

if(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}

if(!(Test-Path -Path $blobDict -PathType leaf)){
    Write-Log $xml_filename "E" "Series Dictionary file is MISSING!"
	Write-Host ("Library file missing!") -ForegroundColor Red
    Write-Debug ("Path to BLOB File: $($blobDict)")
	Break;
} else {
	# set our Dictionary array
	$seriesDict = Import-Csv $blobDict -Delimiter "|"
}

if (!(Test-Path -Path $provDict -PathType leaf)){
    Write-Log $xml_filename "E" "Provider Dictionary file is MISSING!"
	Write-Host ("Library file missing!") -ForegroundColor Red
    Write-Debug ("Path to PROVIDER File: $($provDict)")
	Break;
} else {
	# set or Provider array
	$providerDict = Import-Csv $provDict -Delimiter ":"
}


# ## User Input ## #
# This will decide which functions to run to get our season and episode data
Write-Host "Please choose one option below to continue."
Write-Host "     [A] - by Category"
Write-Host "     [B] - by Provider"
$vuserInput = Read-Host -Prompt "How should I find SEASON & EPISODE?"

switch ($vuserInput){
    "A" {$vprocessBy = "byCategory"
        Break;
	}
    "B" {$vprocessBy = "byProvider"
        Break;
	}
    Default {
		$vprocessBy = $null
		Write-debug "You choose poorly!"
		Break;
	}
}

# check our user input for a bad return and breakout!
if(IsNull ($vprocessBy)){
	Write-host "User Input was not recognized!" -foregroundcolor Red
	Break;
}


# common MSV DB lines
$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'

# cycle through each line of our assets file
Foreach ($line in $contents){

	# whats the altcode we are using. Need for checks through out this script
	$alt_code = $line
	$numContentID++
	
	# set our query string to only get our targeted ASSETIDs and HLS_SM_
	$SqlQuery = "SELECT strTitle, strscreenformat, xmlContent
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
	Write-Host("")
	Write-Host("$($line) :: Processing ...")

    $numRows = $Dataset.Tables.Rows | Measure-Object

    # if no rows returned from QUERY move on to the next ASSET ID
    if($numRows.Count -eq 0)
    {        
		$numError++
        $e_message = "No Match found in tAssestInputXML table!"
		Write-Host("$($alt_code) :: [ERROR] $($e_message) ... skipping") -ForegroundColor Red
        Write-Log -filename $alt_code -loglevel "E" -message $e_message
        Break;
    }else{
        $numinfo++
        $e_message = "$($numRows.Count) ROWS returned for $($alt_code)"
        Write-Debug $e_message
        Write-Log -filename $alt_code -loglevel "I" -message $e_message
    }
	
	# setting MSVFOUND flag to indicate if we actually found the ASSETID in MSV
	$msvFound = 0
	
	# cycle through our query return
    Foreach ($value in $DataSet.Tables[0])
    {
		# save our ORIGINAL metadata
		[void]($content = [xml]($value.xmlContent))
		$xml_filename = ($alt_code + "_" + $value.strscreenFormat + ".xml")
		
		$isReview = 0	# 0/1 Flag to log/affect changes to modified files when no TYPE MATCH is found.
		
		Switch -wildcard ($value.strScreenFormat) {
			"*_HD*" { 
						Write-Host("... HD meta")
						Write-Log $xml_filename "I" "Found HD metadata. Processing ..."
						$msvFound = 1
						BREAK;
			}
			"*_SD*" {
						Write-Host("... SD meta")
						Write-Log $xml_filename "I" "Found SD metadata. Processing ..."
						$msvFound = 1
						BREAK;
			}
			default {
						Write-Log $xml_filename "E" "No XML meta was found. Is this it he right Asset ID?"
						Write-Host("NO XML META FOUND!") -ForegroundColor Red
			}
		}

        # catch Asset Id duplication in our input file.
		# if we already have the original filename - break out
		# otherwise lets save it and coninue on.
		#$content.Save($originalD + "\" + $xml_filename)
		
        $orgcheck = gci $originalD -Name -File

        if($orgcheck -contains $xml_filename){
            Write-Debug "Found a DUPE! ... $($xml_filename)"
            Write-Log $xml_filename "W" "Found duplicate file for $($xml_filename)... Skipping!)"
            write-Host("Duplicate file found ORIGINAL directory... skipping $($xml_filename)") -ForegroundColor Yellow
            BREAK;
        } else {
            $content.Save($originalD + "\" + $xml_filename)
            Write-Debug "Saving ORIGINAL file"
            Write-Log $xml_filename "I" "$($xml_filename) is ORIGINAL... Saving!"
            $numOrig++
        }
		
		
		#set class node values
			#$class_package = $content.ADI.Metadata.AMS		# dont need this one
		$class_title = $content.ADI.Asset.Metadata
			#$class_movie = $content.ADI.Asset.Asset		$ dont need this one
		
		#child nodes
		$ams_product = ($content.ADI.Metadata.AMS.Product)
		$app_contentType = ($class_title.App_Data | Where-Object {$_.Name -eq "Content_Type"})
		$app_TitleBrief = ($class_title.App_Data | Where-Object {$_.Name -eq "Title_Brief"})
		$app_Title = ($class_title.App_Data | Where-Object {$_.Name -eq "Title"})
		$app_SeriesName = ($class_title.App_Data | Where-Object {$_.Name -eq "Series_Name"})
		$app_SeriesID = ($class_title.App_Data | Where-Object {$_.NAME -eq "Series_ID"})
		$app_SeriesDesc = ($class_title.App_Data | Where-Object {$_.NAME -eq "Series_Description"})
		$app_Season = ($class_title.App_Data | Where-Object {$_.Name -eq "Season"})
		$app_SeasonID = ($class_title.App_Data | Where-Object {$_.Name -eq "Season_ID"})
		$app_EpisodeID = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_ID"})
		$app_EpisodeNum = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_Number"})
		$app_EpisodeName = ($class_title.App_Data | Where-Object {$_.Name -eq "Episode_Name"})
        $app_Category = ($class_title.App_Data | Where-Object {$_.Name -eq "Category"})
        $app_CategoryDisplay = ($class_title.App_Data | Where-Object {$_.Name -eq "Category_Display"})
		$app_RatingMPAA = ($class_title.App_Data | Where-Object {$_.Name -eq "Rating_MPAA"})
		$app_SubscriptionType = ($class_title.App_Data | Where-Object {$_.Name -eq "Subscription_type"})
		$app_IsSubscription = ($class_title.App_Data | Where-Object {$_.Name -eq "IsSubscription"})
		

		### START LOGIC ###
        # Check our NODES and ELEMENTS. If we dont have them.. build them.
		#
		
		# CONTENT_TYPE Node
		if (!($app_contentType)){
			# Content_Type node is missing ... build it!
			$e_message = "CONTENT_TYPE node is MISSING!! ... Building node ..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Content_Type")
			$app_elem.SetAttribute("Value","")	
			$app_contentType = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			Write-Log $xml_filename "w" " Finished building CONTENT_TYPE node"
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		} 
		# Set content type to TVS regardless of value (for targeted xml)
		if ($app_contentType.value -ne "TVS"){
			$e_message = "Content_Type is NOT TVS."
			$script:numWarn++
			$app_contentTypeWas = $app_contentType.value
			Write-Host ("[WARN]Setting Content_Type to TVS") -ForegroundColor yellow
			Write-Debug ("$($e_message) ... Im Seeing: $($app_contentTypeWas)")
			$app_contentType.value = "TVS"
			Write-Log $xml_filename "w" "$($e_message). Changing $($app_contentTypeWas) to $($app_contentType.value)"
		}
		

		# CATEGORY_DISPLAY and CATEGORY have the right TVS values
		$arrCatDisplay = ""
		if ($app_contentType.value -eq "TVS"){
			$arrCatDisplay = $app_CategoryDisplay.value -split ","
			write-debug("[CATEGORY_DISPLAY] Spliting ... $($arrCatDisplay)")
			
			# split the Category_Display string and cycle each one
			# check each value against our PROVIDER hash MOV values
			# if we find an MOV value.. change it to the TVS value
			for ($i=0;$i -lt $arrCatDisplay.length; $i++){
				write-debug("[CATEGORY_DISPLAY] checking $($arrCatDisplay[$i]) ...")
				foreach($val in $providerDict){
					if ($arrCatDisplay[$i] -eq $val.MOV){
						write-debug("[CATEGORY_DISPLAY] MATCH found $($arrCatDisplay[$i]) and $($val.mov)")
						$arrCatDisplay[$i] = $val.TVS
						write-debug("[CATEGORY_DISPLAY] changed to $($arrCatDisplay[$i])")
					}
				}
			}
			Write-Debug("[CATEGORY_DISPLAY] rebuilding string ...")
			
			# rebuild our Category_Display string and set the XML node value
            $newarrCatDisplay =""
			for ($i=0;$i -lt $arrCatDisplay.length;$i++){
				if($i -lt $arrCatDisplay.length-1){
					$arrCatDisplay[$i] +=","
				}
				
				$newarrCatDisplay += $arrCatDisplay[$i].ToString()
			}
			write-debug("[CATEGORY_DISPLAY] setting Category_Display to $($newarrCatDisplay)")
			$app_CategoryDisplay.value = $newarrCatDisplay
			
			# checking CATEGORY nodes
			Write-Debug("[CATEGORY] Checking CATEGORY nodes...")

            # if we only have one CATEGORY element.. make it a single array
            if(!($app_Category.Length)){
                Write-Debug("[CATEGORY] Single CATEGORY element. Making it an ARRAY")
                $app_Category = @($app_Category)
            }
			
            for($i=0;$i -lt $app_Category.Length;$i++){
                write-debug("[CATEGORY] Value: $($app_Category[$i].value)")

                #cycle Provider CVS for MOV value match
                foreach($pcVal in $providerDict){
                    if($app_Category[$i].value -eq $pcVal.MOV){
                        Write-Debug("[CATEGORY] MATCH found... changing $($app_Category[$i].value) to $($pcVal.TVS)")
                        $app_Category[$i].value = $pcVal.TVS
                    }
                }

                Write-Debug("[CATEGORY] CATEGORY VALUE now is: $($app_Category[$i].Value)")
            }
        }
		
		
        # SERIES_NAME NODE
        if (!($app_SeriesName)){
			$e_message = "Series_Name node is MISSING !! Building node..."
			$numWarn++
			write-log $xml_filename "w" " $($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Series_Name")
			$app_elem.SetAttribute("Value","")	
			$app_SeriesName = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			Write-Log $xml_filename "w" " Finished building Series_Name node. It is empty currently."
			Write-Host ("Series_Name element built. Checking for a Series Name match") -ForegroundColor Green
			
			if(!($app_SeriesName.value = [string](Find_SeriesName $app_SeriesName.value -checkall))) {
				$e_message = "[SERIES_NAME node] Find_SeriesName returned FALSE"
                $numWarn++
                Write-Log $xml_filename "w" "$($e_message). Its value will be empty/null."
                Write-Debug("$e_message")
				Write-Debug("[SERIES_NAME node] SERIES_NAME is empty")
                
			} else {
                $e_message = "[SERIES_NAME node] Find_SeriesName returned Series_Name of $($app_SeriesName.value)"
				Write-Log $xml_filename "i" "$($e_message)"
                Write-Debug($e_message)
			}

            Write-Host("$($e_message)") -ForegroundColor Yellow
            
		} else {
			# the element node exists so clean it up
			if (!(IsNull $app_SeriesName.value)){
				Write-Debug ("[SERIES_NAME node] Found SERIES_NAME. Cleaning it up!")
				Write-Debug ("[SERIES_NAME node] $($app_SeriesName.value)")
				Write-Log $xml_filename "i" "SERIES_NAME found: $($app_SeriesName.value). Cleaning it up..."
                Write-Host("[SERIES_NAME node] Found SERIES_NAME element... Cleaning value: $($app_SeriesName.Value)")
				
                # pass value of Series_Name element to cleanup
				if(!($seriesNameClean = cleanUp $app_SeriesName.Value -isSeries)) {
                    Write-Debug("[SERIES_NAME node] Find_SeriesName returned FALSE")
					Write-Debug("[SERIES_NAME node]is SERIES_NAME empty? or missing from Dictionary file?")
                    Write-Host("[SERIES_NAME node] No match found. Leaving value: $($app_SeriesName.Value)")
                } else {
                    #$trimSeriesnameclean = [string]$seriesNameClean
					$app_SeriesName.value = $seriesNameClean.toString()
					Write-Debug ("[SERIES_NAME node] Rec'd $($seriesNameClean) from CLEANUP!")
					Write-Debug ("[SERIES_NAME node] Setting Series_Name to $($app_SeriesName.value)")
					Write-Log $xml_filename "i" "Finished cleaning: $($app_SeriesName.value)"
                    Write-Host ("[SERIES_NAME node] Setting Series_Name to $($app_SeriesName.value)") -ForegroundColor Yellow
                }
            # Series_Name value is empty
			} else {
				Write-Host("[SERIES_NAME node] Series_Name is empty! Ill try and find a match...")
				if(!($app_SeriesName.value = (Find_SeriesName $app_SeriesName.value -checkall))){
					Write-Debug("[SERIES_NAME node] Find_SeriesName returned FALSE???")
					Write-Host("[SERIES_NAME node] Find_SeriesName returned false. Leaving Series_Name of: $($app_SeriesName.value)") -ForegroundColor yellow
				} else {
					Write-Host("[SERIES_NAME node] Find_SeriesName set Series_Name to $($app_SeriesName.value)")
				}
			}

		}
		
		# SERIES_ID Node
		# if node does NOT exist build it and set an empty value
		if (!($app_SeriesID)){
			$e_message = "[Series_Id] node is MISSING !! Building node..."
			$numWarn++
			write-log $xml_filename "w" " $($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Series_Id")
			$app_elem.SetAttribute("Value","")	
			$app_SeriesID = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			Write-Log $xml_filename "w" " Finished building Series_Id node. It is empty currently."
			Write-Host ("[Series_Id] element built. Value is currently EMPTY.") -ForegroundColor Green
		
		}
		

		
		# SEASON NODE
        if (!($app_Season)){
			$e_message = "SEASON node is MISSING !! Building node..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
            Write-Debug ("[SEASON Node] Season node is FALSE. Value is: $($app_Season)")
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Season")
			$app_elem.SetAttribute("Value","")	
			$app_Season = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			Write-Log $xml_filename "w" "Finished building SEASON node"
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
			
			# update SEASON value flag
			# 0 = empty
			# 1 = has value (default)
			$isNullSeason = 0
			
		} else {
			# Season node found but does it have value
			$e_message = "[SEASON Node] Found SEASON node. Checking value..."
			write-log $xml_filename "i" "$($e_message)"
			write-debug ($e_message)
			
			if(IsNull($app_Season.value)){
				# its empty
				$e_message = "[SEASON Node] node returned null value. Setting flag."
				write-log $xml_filename "i" "$($e_message)"
				write-debug ($e_message)
				$isNullSeason = 0
			} else {
				$e_message = "[SEASON Node] value is: $($app_Season.value)"
				write-log $xml_filename "i" "$($e_message)"
				write-debug ($e_message)
				# by default $isNullSeason is set to 1 - we assume it has value to start.
			}
		}
		
		# EPISODE_NUMBER NODE
        if (!($app_EpisodeNum)){
			$e_message = "EPISODE_NUMBER node is MISSING !! Building node..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Episode_Number")
			$app_elem.SetAttribute("Value","")	
			$app_EpisodeNum = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			Write-Log $xml_filename "w" "Finished building EPISODE_NUMBER node"
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
		}
		
		# Rating_MPAA NODE
		if (!($app_RatingMPAA)){
			$e_message = "Rating_MPAA Node is MISSING!! Checking for mispelled node..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Host ($e_message) -ForegroundColor Yellow
			
			# check for mispelled noden name
			$mispelledMPAA = $class_title.App_Data | Where-Object {$_.Name -eq "MPAA_Rating"}
			if ($mispelledMPAA.NAME){
				# mispelling found
				Write-Log $xml_filename "w" "Found mispelled Node: $($mispelledMPAA.Name) with value: $($mispelledMPAA.value)"
				Write-Debug "node name $($mispelledMPAA.Name) changed to..."
				$mispelledMPAA.Name = "Rating_MPAA"
				Write-Debug "node name $($mispelledMPAA.Name)"
				$e_message = "Changed element name 'MPAA_Rating' to '$($mispelledMPAA.NAME)'"
				Write-Log $xml_filename "w" "$e_message"
				
			} else {
				# node is missing so build our node and set an empty value for now.
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App","$($AMS_product)")
				$app_elem.SetAttribute("Name","Rating_MPAA")
				$app_elem.SetAttribute("Value","")	
				$app_RatingMPAA = $content.ADI.Asset.Metadata.AppendChild($app_elem)
				
				$e_message = "No mispelling found. Node Built. Fixed!"
				Write-Log $xml_filename "w" "$($e_message)"
				Write-Host ($e_message) -ForegroundColor Green
			}
			
		} else {
			Write-Debug "Rating_MPAA node Good"
		}
				
		#### NODE Check Stop #####
		
		# check Series_Id
		# case sensitive NAME check
		if(!($app_SeriesID.name -ceq "Series_Id")) {
			$app_SeriesID.name="Series_Id"
			$e_message = "[Series_Id] Improper Alpha-Case found. Changed element name to $($app_SeriesID.name)"
			Write-Debug($e_message)
			Write-Log $xml_filename "i" "$($e_message)"
		}
		
		
		# check EPISODE_ID
		# case sensitive NAME check
		if($app_EpisodeID -AND (!($app_EpisodeID.name -ceq "Episode_Id"))) {
			$app_EpisodeID.name="Episode_Id"
			$e_message = "[Episode_Id] Improper Alpha-Case found. Changed element name to $($app_EpisodeID.name)"
			Write-Debug($e_message)
			Write-Log $xml_filename "i" "$($e_message)"
		}
		
		# check for IsSubscription node/element
        if(!($app_IsSubscription)){
            Write-Debug "[IsSuscription] element/node is MISSING!"
        } else {
			Write-Debug "[IsSuscription] element/node FOUND!"
            Write-Debug $app_IsSubscription.Name
            Write-Debug $app_IsSubscription.Value
            Write-Debug $app_IsSubscription.App
        }


		# check & set value of Series_Id
		if ($app_IsSubscription.value -eq "Y")
		{
			Write-Debug("[Series_Id & Episode_Id] IsSubscription set to $($app_IsSubscription.value).")
			# if its an HBO show, dont prepend "Sub_" to Series_Id value
			Switch ($app_SubscriptionType.value)
			{
				"MSV_HBO"	{
								$e_message = "[Series_Id] Found MSV_HBO for $($app_SubscriptionType.name)"
								Write-Debug($e_message)
								Write-Log $xml_filename "i" "$($e_message)"
								
								if(isNull($app_SeriesID.value)) {
									$e_message = "[Series_Id] is EMPTY. Setting value to $($app_SeriesName.value)"
									Write-Debug($e_message)
									Write-Log $xml_filename "w" "$($e_message)"
									$numWarn++
									$app_SeriesID.value = $app_SeriesName.value
								}
				}
				default		{
								$e_message = "[Series_Id] Found $($app_SubscriptionType.value) for $($app_SubscriptionType.name)"
								Write-Debug($e_message)
								Write-Log $xml_filename "i" "$($e_message)"
								
								if(isNull($app_SeriesID.value)) {
									$e_message = "[Series_Id] is EMPTY. Setting value to Sub_$($app_SeriesName.value)"
									$app_SeriesID.value = "Sub_" + $app_SeriesName.value
								} else {
									$e_message = "[Series_Id] Setting value to Sub_$($app_SeriesID.value)"
									$app_SeriesID.value = "Sub_" + $app_SeriesID.value
								}
								
								Write-Debug($e_message)
								Write-Log $xml_filename "w" "$($e_message)"
								$numWarn++
				}
			}
		
		} else {
			$e_message = "[Series_Id & Episode_Id] IsSubscription set to $($app_IsSubscription.value)."
			Write-Debug($e_message)
			Write-Log $xml_filename "W" "$($e_message)"
			$numWarn++
		}
		
		Write-Debug ("[TITLE_BRIEF node] checking Title_Brief...")
		
		# check Title_brief element. If empty/missing/not set.. check the Episode_Name element...
		# if neither has value/str... then its messed up, so BREAK OUT
		
		if (IsNull($app_TitleBrief.value)){
			$e_message = "[TITLE_BRIEF node]Title_Brief is not set!"
			$script:numError++
			Write-Debug ("$($e_message)")
			Write-Log $xml_filename "e" "$($e_message) value is: $($app_TitleBrief.value)"
			Write-Host ("[TITLE_BRIEF node] TITLE_BRIEF not set... checking EPISODE NAME...") -ForegroundColor Red
			
			if (IsNull($app_EpisodeName.value)){
				$e_message = "[TITLE_BRIEF node] EPISODE_NAME is not set either!!"
				Write-Debug($e_message)
				$script:numError++
				Write-Log $xml_filename "E" "$($e_message)"
				Write-Log $xml_filename "W" "[TITLE_BRIEF node] Something is wrong with this META! Breaking out!"
				Write-Host("$($e_message) BREAKING OUT!") -ForegroundColor Red
				BREAK;
			} else {
				Write-Debug("[TITLE_BRIEF node] Found EPISODE NAME: $($app_EpisodeName.value)")
				Write-Host("[TITLE_BRIEF node] Found EPISODE NAME.") -ForegroundColor Green
				Write-Log $xml_filename "i" "[TITLE_BRIEF node] Found EPISODE NAME: $($app_EpisodeName.value)"
			
                # replace "/" with "-" in Title_Brief
				$app_EpisodeName.Value = $app_EpisodeName.Value.Replace("/","-")
				Write-Debug("[TITLE_BRIEF node] Replacing slashses with dashes. EPISODE_NAME: $($app_EpisodeName.value)")
				Write-Log $xml_filename "I" "[TITLE_BRIEF node] Cleaning EPISODE_NAME of /: $($app_EpisodeName)"
				
				# replace "_" with whitespace in Title_Brief
				$app_EpisodeName.Value = cleanUp $app_EpisodeName.Value
				Write-Debug("[TITLE_BRIEF node] CleanUp returned EPISODE_NAME: $($app_EpisodeName.value)")
				Write-Log $xml_filename "I" "[TITLE_BRIEF node] CleanUp returned EPISODE_NAME: $($app_EpisodeName.value)"

                #finished replacing
                Write-Host("[TITLE_BRIEF node] Finished cleaning: $($app_TitleBrief.Value)")
            }
		} else {
			Write-Host("[TITLE_BRIEF node] Found TITLE BRIEF: $($app_TitleBrief.value)")
			Write-Log $xml_filename "i" "[TITLE_BRIEF node] Found TITLE BRIEF: $($app_TitleBrief.value)"
			
			# replace "/" with "-" in Title_Brief
			$app_TitleBrief.Value = $app_TitleBrief.Value.Replace("/","-")
			Write-Debug("[TITLE_BRIEF node] Replacing slashses with dashes. TITLE_BRIEF: $($app_TitleBrief.value)")
			Write-Log $xml_filename "i" "[TITLE_BRIEF node] Cleaning TITLE_BRIEF of /: $($app_TitleBrief.value)"
			
			# replace "_" with whitespace in Title_Brief
			 $titlenameclean = cleanUp $app_TitleBrief.Value
			 $app_TitleBrief.Value = $titlenameclean.toString()
			Write-Debug("[TITLE_BRIEF node] CleanUp returned TITLE_BRIEF: $($app_TitleBrief.Value)")
			Write-Log $xml_filename "I" "[TITLE_BRIEF node] CleanUp returned TITLE_BRIEF: $($app_TitleBrief.Value)"
            
            #finished replacing
            Write-Host("[TITLE_BRIEF node] Finished cleaning: $($app_TitleBrief.Value)")
		}

		
		# check for season/episode matches and extrapolate
		write-debug("[EXTRAPOLATION] Attempting to find Season/Episode in TITLE_Brief node...")
		Switch ($vprocessBy){
			"byCategory"{
					if(!($se_array = Get-SeasonEpisode($app_TitleBrief.Value))){
						$e_message = "[EXTRAPOLATION] Get-SeasonEpisode returned false on TITLE_BRIEF string: $($app_TitleBrief.Value)"
						write-debug($e_message)
						write-log $xml_filename "w" "$($e_message)"
						$script:numWarn++
						write-debug("[EXTRAPOLATION] Checking EPISODE_NAME node ...")
						if(!($se_array = Get-SeasonEpisode($app_EpisodeName.Value))){
							$e_message = "[EXTRAPOLATION] Get-SeasonEpisode returned false on EPISODE_NAME string: $($app_EpisodeName.Value)"
							write-debug($e_message)
							write-log $xml_filename "w" "$($e_message)"
							$script:numWarn++
							write-debug("[EXTRAPOLATION] checking TITLE node ...")
							if(!($se_array = Get-SeasonEpisode($app_Title.value))){
								$e_message = "[EXTRAPOLATION] Get-SeasonEpisode returned false on TITLE string: $($app_Title.value)"
								write-debug($e_message)
								write-log $xml_filename "w" "$($e_message)"
								$script:numWarn++
							}
						}
					}
					Break;
				}
			"byProvider" {
					if(!($se_array = Get-SeasonEpisodebyProvider)){
						$e_message = "[EXTRAPOLATION] Get-SeasonEpisodebyProvider returned FALSE"
						write-debug ($e_message + ": " + $se_array)
						write-log $xml_filename "w" $e_message
					}
					Break;
				}
			
			# not setting a default will allow the $se_array to be null
		}	
		
		#from extrapolation get season and episode number
		if (IsNull($se_array)){
			$e_message = "[EXTRAPOLATION] Season/Episode array is empty!"
			Write-Debug($e_message)
			$script:numError++
			Write-Log $xml_filename "e" "[EXTRAPOLATION] $($e_message)"
			Write-Log $xml_filename "e" "[EXTRAPOLATION] value of Array is: $($se_array)"
			Write-Host("[EXTRAPOLATION] Something Broke!") -ForegroundColor Red
			BREAK;
		} else {
			$exSeason = $se_array[0]
			$exEpisode = $se_array[1]
			$exTypeMatch = $se_array[2]
		}
			
		# check our function returned some usefule data or break
		if (IsNull($exTypeMatch) -or IsNull($exSeason) -or IsNull($exEpisode)){
			$e_message = "[EXTRAPOLATION] failed! Saving meta changes for Review, check log file!"
			Write-Debug($e_message)
			#do not update error counters
			Write-Log $xml_filename "e" "[EXTRAPOLATION] $($e_message)"
			Write-Log $xml_filename "e" "[EXTRAPOLATION] Match Type: $($exTypeMatch)"
			Write-Log $xml_filename "e" "[EXTRAPOLATION] Season: $($exSeason)"
			Write-Log $xml_filename "e" "[EXTRAPOLATION] Episode: $($exEpisode)"
			Write-Log $xml_filename "i" "[EXTRAPOLATION] Saving changes made so far in \REVIEW\ ."
			Write-Host("[EXTRAPOLATION] Couldnt get season/episode from meta. Saving Changes to meta in Review Directory. Check Log.") -ForegroundColor Red
				
			# update our REVIEW counter and save our meta to the REVIEW directory.
			# Break out of our code and move to next assetID in list.
			$script:numRev++
			$isReview = 1
			$content.Save($reviewD + "\" + $xml_filename)
			
		}
			
		# check for TYPE 6 and 7 match.. very loose regex. Extrapolate but inform
		# operator to check meta to collect pattern for use later.
		# else set EPISODE_ID and SEASON_ID
		# update this value when new regex_types added
		# -- TYPE_UPDATE --
		
		# re-wrote with case logic instead of if-elseif-else
		if($isReview -eq 0){
			switch ($exTypeMatch){
				"6" {
					#dont update WARN counters
					$e_message = "[EXTRAPOLATION] TYPE 6 match is very loose. Please double check meta and log."
					$llevel = "W"

					#$app_EpisodeID.value = $exEpisode
					$app_EpisodeNum.value = $exEpisode
					$app_Season.value = $exSeason
					#$app_SeasonID.value = $exSeason
					
					Write-Host "[EXTRAPOLATION] Done!" -ForegroundColor Green
					BREAK;
				}
				"7" {
					#dont update WARN counters
					$e_message = "[EXTRAPOLATION] TYPE 7 match is very loose. Please double check meta and log."
					$llevel = "W"
					
					#$app_EpisodeID.value = $exEpisode
					$app_EpisodeNum.value = $exEpisode
					$app_Season.value = $exSeason
					#$app_SeasonID.value = $exSeason
					
					Write-Host "[EXTRAPOLATION] Done!" -ForegroundColor Green
					BREAK;
				}
				"DateType"{
					# match special case DateType
					Write-Debug "[EXTRAPOLATION] OUT of Get-SeasonEpisode: Matched DATE TYPE."
					# set EPISODE_NUMBER
					$app_EpisodeNum.value = $exEpisode
                    $e_message = "[EXTRAPOLATION] TYPE $($exTypeMatch) match found."
                    Write-Host $e_message -BackgroundColor DarkGray -ForegroundColor Green 
		
					
					# check for value of SEASON. if there is no value set it to the YEAR
					# 0 = empty
					# 1 = has value (default)
					if ($isNullSeason -eq 0){
						$app_Season.value = $exSeason
						$e_message = "[EXTRAPOLATION] DATE TYPE: SEASON has no value. Setting to $($exSeason)."
					} else {
						$e_message = "[EXTRAPOLATION] DATE TYPE: SEASON has value. Leaving it unchanged."
					}
					$llevel = "I"
					write-log $xml_filename $llevel $e_message
					Write-Debug ("$($e_message)")
					Write-Debug "[EXTRAPOLATION] Episode: $($app_EpisodeNum.value), and SEASON: $($app_Season.value)"
					Write-Host $e_message -ForegroundColor Yellow
					BREAK;
				}
                "byProvider"{
                    # Season and Episode was run and matched by PROVIDER CSV
                    $e_message ="[EXTRAPOLATION] TYPE $($exTypeMatch) match found."
                    $llevel = "I"

                   	$app_EpisodeNum.value = $exEpisode.ToString()
					$app_Season.value = $exSeason.ToString()
					
					Write-Host $e_message -BackgroundColor DarkGray -ForegroundColor Green
                    Write-Log $xml_filename $llevel $e_message
                    Write-Host "[EXTRAPOLATION] SEASON and EPISODE set to: $($app_Season.Value) and $($app_EpisodeNum.value)" -ForegroundColor Green
					BREAK;
                }
				default{
					# match or set season and episode numbers
					$e_message = "[EXTRAPOLATION] TYPE $($exTypeMatch) match found."
					$llevel = "I"
					
					#$app_EpisodeID.value = $exEpisode
					$app_EpisodeNum.value = $exEpisode.ToString()
					$app_Season.value = $exSeason.ToString()
					#$app_SeasonID.value = $exSeason
					
					Write-Host $e_message -BackgroundColor DarkGray -ForegroundColor Green
					BREAK;
				}
			}
			
			# log our findings/changes
			Write-Log $xml_filename $llevel "[EXTRAPOLATION] $($e_message)"
			Write-Log $xml_filename $llevel "[EXTRAPOLATION] SEASON String we matched: $($exSeason)"
			Write-Log $xml_filename $llevel "[EXTRAPOLATION] EPISODE String we matched: $($exEpisode)"
			
			# match or set season and episode numbers
			Write-Debug ("[EXTRAPOLATION] SEASON is $($app_Season.value)")
			Write-Debug ("[EXTRAPOLATION] EPISODE is $($app_EpisodeNum.value)")
			
			
			#save modified version -- this in the right place?
			$numMod++
			$content.Save($modifiedD + "\" + $xml_filename)
		} else {
			Write-Debug("[EXTRAPOLATION] The isReview Flag is SET! did something break?")
		}
	    
        # done processing and moving to next asset
		if($msvFound -eq 1){
			Write-Host("Processing complete.")
		} else {
			Write-Host("AssetID was not found in MSV!") -ForegroundColor Red
		}
	    
	}
}

# get summary report
Summarize