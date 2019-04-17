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
# Version:  1.7
# History:  10-30-17	- Initial release
#			11-03-17	- include trailing \s in type 5 regex. hopefully reduce
#							number of false positive matches.
#						- enabled "loose" type extrapolation (... scary ...)
#						- ADD new type to match S##E## pattern
#			04-30-18    - [Russ N] added new regex type and adjust content_type logic
#			05-01-18	- Fix Node checking logic to check more nodes and either 
#							build or modify everything we run through this script.
#						- Fix Content_Type check to build node if missing and set value
#							 to TVS.
#						- Fix REGEX checks to address ### vs #### bug
#			05-02-18	- Add function to address unwanted "_" and "_(HD)" in Series_ID,
#							Series_Name and Series_Description
#						- Add Directory sorting for meta that changes some nodes but does
#							not	match our REGEX. (makes it easier on our folks making 
#							manual changes)
#			05-03-18	- remove node checks for Series_Description, Season_ID and Series_Name
#			05-08-18	- add isReview flag to fix SD saving bug. Where some SD meta was 
#							getting skipped due	broken season/episode extrapolation failure.
#						- re-wrote if-elseif-else for match TYPE checking to a SWITCH case
#							style [no impact to user]
#			05-08-18	- add log level to Write-Log()
#						- add additional string trasformation to cleanUp() for Series_Name and
#							Series_ID
#			05-17-18	- add functionality to address "blob"-like strings in the Series_Name 
#							and Series_ID
#			06-05-18	- and new DATE TYPE match and transform logic. Ex: 5/30 becomes episode
#							5-30. Set SEASON to YEAR unless it already has a value.
#						- Replace "/" with "-" in TITLE_BRIEF or EPISODE_NAME (depending on 
#							which one is built)
#						- add new type (3.1) to match (ex: S2 E01). Very close to Type 3, thus
#							it is handled the same way as a Type 3 match
#						- and new type (Type 8) to match "S1 Episode 8 HD". This should be a 
#							pretty tight match.
#			06-06-18	- removed ability to set SEASON when DATE TYPE match is found. We will
#							still build all nodes but wont set a value to SEASON for DATE Type matches
#			06-12-18	- fix substring bug in type 3 match
#			06-15-18	- fix file count and duplication bug. Script now will check the ORIGINAL directory
#							filenames against the current processing filename. If they are the same (duplicated)
#							it will skip the currently processing ID and log it for later. No other output
#							is done. Thus a list of Asset IDs with duplicated numbers will be caught
#							and no loger rewrite original/modified/reviewed files and the summary output
#							will be correct.
#			06-28-2018	- Removed Title Case ability from cleanString Function per Russ request.
#           07-06-2018  - add Trim() to the return of the getSeasonEpisode function.
#                       - add new type (3.2) to match "S1 Ep01". Very close to a type 3 match, thus
#                           we will handle it the same way.
#                       - Fixed dateType match bug not setting to the episode. value of variable logic was
#                           out of order and not being caught in the Get-SeasonEpisode function.
#           07-24-2018  - added a TrimEnd to remove " HD" being seeen at the END of a string (title)
#			07-25-2018	- added new "HD" variant to cleanUp Function: TrimEnd(" HD")
#						- Rebuilt CleanUp function to include a switch for series name. If this switch is set, we will call
#							Find_SeriesName function passing to it the string from cleanUp function.
#						- Add new function Find_SeriesName. The function will take any string passed to it and, depending on the switch,
#							check that string for a match in the previously created dictionary CSV file. This is the default option of
#							the function and is always performed. IF no match is found AND there is a switch set, then additional 
#							checks will be made. There are 3 switches that can be passed: TitleCheck, CategoryCheck and CheckAll.
#							- TitleCheck will also try and match the value of TITLE element to the dictionary file.
#							- CategoryCheck will also try and match the value(s) of CATEGORY_DISPLAY element to the dictionary file.
#							- CheckAll will perform all the checks previously stated.
#							If a match is FOUND in the dictionary file, we will return the CORRECT_NAME from it to populate the Series_Name
#							element.
#						- add string.replace to swap out "_" for whitespace in the TITLE element. This check is done AFTER any function passthroughs
#							so preserve the integrity of function that process the original string from the TITLE value.
#						- add new typw pattern (5.1) "S01_E07". Very close to type 5 match, thus we will handle it the same way
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

# ### LOCAL TESTING ###
#$input_txt_file = "C:\Users\jgg049\Documents\VZ3 TVE\VOD\Alt_Code_Proj\assetid_filelist.inc"
#$work_dir = "C:\Users\jgg049\Documents\VZ3 TVE\VOD\Alt_Code_Proj\_UpdateSeasonEpisode\"
#$SQLServer = 'MSVTXCAWDPV01.vhe.fiosprod.net\MSVPRD01'

# targeted asset ID list
$input_txt_file = "C:\vodscripts\testlist.inc"
#$input_txt_file = "C:\vodscripts\assetid_filelist.inc"	    # target assest ID list
$contents = Get-Content $input_txt_file

# Write-Debug -- debug mode
#uncomment preference to turn on/off output
$DebugPreference = "SilentlyContinue"
#$DebugPreference = "Continue"
Write-Debug("DEBUG ACTIVE!")

# set the directories we will be working in
$work_dir = "C:\vodscripts\_UpdateSeasonEpisode\_Testing\"
#$work_dir = "C:\vodscripts\_UpdateSeasonEpisode\"
$daily_directory = (Get-Date).ToString('MMddyyyy') 
$originalD = $work_dir + $daily_directory + "\Originals"	# save all meta we find before changes
$modifiedD = $work_dir + $daily_directory + "\Modified"		# save any meta we do change
$reviewD = $work_dir + $daily_directory + "\Review"			# save any meta we change but may need human eyes/brains to check it
$libPath = "C:\vodscripts\_Includes"						# path to our library files
$blobDict = $libPath + "\SeriesNamesNew.csv"				# Dictionary file for our Series_Name & Series_ID

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
						Write-Host("[Get-SeasonEpisode] Season and/or Episode is NOT DISCERNIBLE. Check Log") -ForegroundColor Red
						$script:numError++
						Write-Log $xml_filename "w" "[Get-SeasonEpisode]Failed to match any Season/Episode pattern! the string was: "
						Write-Log $xml_filename "w" "[Get-SeasonEpisode] $($cleanString)"
                        Return $false
                        
            }
		}
		
	Write-Debug "[Get-SeasonEpisode] Im out of the SWITCH in getSeasonEpisode"
	return $s1, $e1, $typeMatch
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
	$dirtyString = $dirtyString.Replace('_(HD)','')
	$dirtyString = $dirtyString.Replace('_hd','')
	$dirtyString = $dirtyString.Replace('_',' ')
	$dirtyString = $dirtyString.TrimEnd(" HD")
	[string]$cleanString = $dirtyString.Trim() 

	# removed totitlecase per russ request 06-28-2018
	if (!($isSeries)){
		Write-Debug("[cleanUp] cleanUp returning $($cleanString)")
	#	return (Get-Culture).textinfo.totitlecase($cleanString.tolower())
		return $cleanString
	} else {
		write-debug ("[cleanUp] Cleanup switch isSeries was SET")
		write-debug ("[cleanUp] Passing $($cleanString) to Find_SeriesName with checkall switch")
		[string]$seriesNameString = Find_SeriesName -stringtocheck $cleanString -checkall
		
		if($seriesNameString -eq $false){
			#false return from Find_SeriesName
			Write-Host("[cleanUp] Find_SeriesName returned FALSE") -ForegroundColor Red
			return $false
		} else {
			Write-Debug ("[cleanUp] Find_SeriesName returned STRING: $($seriesNameString)")
		#	return (Get-Culture).textinfo.totitlecase($cleanString.tolower())
			$cleanString = $seriesNameString
			return [string]$cleanString
		}
	}	
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
}


# check our Dictionary file for the Series_Name... if no match
# check the TITLE element against the dictionary
# break with REVIEW if nothing else matched.
function Find_SeriesName{
	
	#set our paramaters make it required
	Param
(
#		[parameter(Mandatory=$true, ParameterSetName="thisString")]
		[string[]]
        $stringtocheck,

 #       [parameter(Mandatory=$false, ParameterSetName="theSwitches")]
		[switch]$titlecheck, 
        [switch]$categorycheck,
        [switch]$checkall
)

	# 1 = found a match
	$matchfound = 0
	
	Foreach ($item in $seriesDict){
		if ($stringtocheck -eq $item."BLOB_NAME"){
			Write-Debug ("[Find_SeriesName] found a BLOBNAME: $($stringtocheck)")
			$returnString = $item."CORRECT_NAME"
			$matchfound = 1
		}
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
					if ($catSplit -like "*$($item.BLOB_NAME)*"){
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
            if($matchfound -eq 0){Write-Debug("[Find_SeriesName.titlecheck] No match found!")}
		} else {
			write-debug("[Find_SeriesName.titlecheck] A MATCH was already found.")
		}
	}

	write-debug("[Find_SeriesName]: matchfound is $($matchfound)")
	if($matchfound -eq 0){
		RETURN $false
	} else {
		RETURN [string]$returnString
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
	$seriesDict = Import-Csv $blobDict -Delimiter ";"
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
	Write-Host("")
	Write-Host("$($line) :: Processing ...")
	
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
		

		### START LOGIC ###
        # Check our NODES and ELEMENTS. If we dont have them.. build them.
		#
		
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
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
			
			if(!($app_SeriesName.value = Find_SeriesName $app_SeriesName.value -checkall)){
				Write-Debug("[SERIES_NAME node] Find_SeriesName returned FALSE")
				Write-Debug("[SERIES_NAME node] SERIES_NAME is emepty")
			} else {
				Write-Debug("[SERIES_NAME node] Find_SeriesName was FALSE. set Series_Name to $($app_SeriesName.value)")
			}
		}else{
			# the element node exists so clean it up
			if (!(IsNull $app_SeriesName.value)){
				Write-Debug ("[SERIES_NAME node] Found SERIES_NAME. Cleaning it up!")
				Write-Debug ($app_SeriesName.value)
				Write-Log $xml_filename "i" "SERIES_NAME found: $($app_SeriesName.value). Cleaning it up..."
                Write-Host("[SERIES_NAME node] Found SERIES_NAME element... Cleaning value: $($app_SeriesName.Value)")
				
                # pass value of Series_Name element to cleanup
				if(!($seriesNameClean = cleanUp $app_SeriesName.Value -isSeries)) {
                    Write-Debug("[SERIES_NAME node] Find_SeriesName returned FALSE")
					Write-Debug("[SERIES_NAME node] SERIES_NAME is empty")
                    Write-Host("[SERIES_NAME node] No match found. Leaving value: $($app_SeriesName.Value)")
                } else {
					$app_SeriesName.value = $seriesNameClean
					Write-Debug ("[SERIES_NAME node] Rec'd $($seriesNameClean) from CLEANUP!")
					Write-Debug ("[SERIES_NAME node] Setting Series_Name to $($app_SeriesName.value)")
					Write-Log $xml_filename "i" "Finished cleaning: $($app_SeriesName.value)"
                    Write-Host ("[SERIES_NAME node] Setting Series_Name to $($app_SeriesName.value)") -ForegroundColor Yellow
                }
            # Series_Name value is empty
			} else {
				Write-Host("[SERIES_NAME node] Series_Name is empty! Ill try and find a match...")
				if(!($app_SeriesName.value = Find_SeriesName $app_SeriesName.value -checkall)){
					Write-Debug("[SERIES_NAME node] Find_SeriesName returned FALSE")
					Write-Debug("[SERIES_NAME node] SERIES_NAME is empty")
                    Write-Host("[SERIES_NAME node] No match found for Series_Name.")
				} else {
					Write-Host("[SERIES_NAME node] Find_SeriesName set Series_Name to $($app_SeriesName.value)")
				}
			}
		}
		
		# SERIES_ID NODE
		if (!($app_SeriesID) -or (IsNull $app_SeriesID.value)){
			$e_message = "Series_ID node is MISSING or empty!! Skip checking this node..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Debug ("[Series_ID node]: $($e_message)")
			<#
			Write-Host ($e_message) -ForegroundColor yellow
			
			# build our node and set an empty value for now.
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Series_ID")
			$app_elem.SetAttribute("Value","")	
			$app_SeriesID = $content.ADI.Asset.Metadata.AppendChild($app_elem)
			Write-Log $xml_filename "w" " Finished building Series_ID node. It is empty currently."
			Write-Host ("Fixed. Check log.") -ForegroundColor Green
			#>
		}else{
			# the element node exists and has value, so clean it up and remove underscores
			Write-Debug ("[Series_ID node]: Found SERIES_ID. Cleaning it up!")
			Write-Debug ("[Series_ID node]: $($app_SeriesID.value)")
			Write-Log $xml_filename "i" "SERIES_ID found: $($app_SeriesID.value). Cleaning it up..."
			$seriesIDClean = cleanUp $app_SeriesID.Value
			$app_SeriesID.value = $seriesIDClean.replace("_"," ")
			Write-Debug ("[Series_ID node]: Finished cleaning: $($app_SeriesID.value)")
			Write-Log $xml_filename "i" "Finished cleaning: $($app_SeriesID.value)"
		}
		
		
		# SEASON NODE
        if (!($app_Season)){
			$e_message = "SEASON node is MISSING !! Building node..."
			$numWarn++
			Write-Log $xml_filename "w" "$($e_message)"
			Write-Host ($e_message) -ForegroundColor yellow
			
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
		}
		
		# EPISODE NODE
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
		
		#### NODE Check Stop #####
		
		
		Write-Debug ("[TITLE_BRIEF node] checking Title_Brief...")
		# check Title_brief element. If empty/missing/not set.. check the Episode_Name element...
		# if neither has value/str... then its messed up, so BREAK OUT
		# else set our $SeasonEpisodeSTR for extrapolation
		if (IsNull($app_TitleBrief.value)){
			$e_message = "[TITLE_BRIEF node]Title_Brief is not set!"
			$script:numError++
			Write-Debug ("$($e_message) check log for [ERROR]") 
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
								
				$SeasonEpisodeSTR = $app_EpisodeName.value
				
                # replace "/" with "-" in Title_Brief
				$app_EpisodeName.Value = $app_EpisodeName.Value.Replace("/","-")
				Write-Debug("[TITLE_BRIEF node] Replacing slashses with dashes. EPISODE_NAME: $($app_EpisodeName.value)")
				Write-Log $xml_filename "I" "[TITLE_BRIEF node] Cleaning EPISODE_NAME of /: $($app_EpisodeName)"
				
				# replace "_" with whitespace in Title_Brief
				$app_EpisodeName.Value = $app_EpisodeName.Value.Replace("_"," ")
				Write-Debug("[TITLE_BRIEF node] Replacing underscore with whitespace. EPISODE_NAME: $($app_EpisodeName.value)")
				Write-Log $xml_filename "I" "[TITLE_BRIEF node] Cleaning EPISODE_NAME of underscores: $($app_EpisodeName)"
			}
		} else {
			Write-Host("[TITLE_BRIEF node] Found TITLE BRIEF: $($app_TitleBrief.value)")
			Write-Log $xml_filename "i" "[TITLE_BRIEF node] Found TITLE BRIEF: $($app_TitleBrief.value)"
						
            # dont clean this as it will break our matching in the functions later.
			$SeasonEpisodeSTR = $app_TitleBrief.value
			
			# replace "/" with "-" in Title_Brief
			$app_TitleBrief.Value = $app_TitleBrief.Value.Replace("/","-")
			Write-Debug("[TITLE_BRIEF node] Replacing slashses with dashes. TITLE_BRIEF: $($app_TitleBrief.value)")
			Write-Log $xml_filename "i" "[TITLE_BRIEF node] Cleaning TITLE_BRIEF of /: $($app_TitleBrief.value)"
			
			# replace "_" with whitespace in Title_Brief
			$app_TitleBrief.Value = $app_TitleBrief.Value.Replace("_"," ")
			Write-Debug("[TITLE_BRIEF node] Replacing underscores with whitespace. TITLE_BRIEF: $($app_TitleBrief.value)")
			Write-Log $xml_filename "i" "[TITLE_BRIEF node] Cleaning TITLE_BRIEF of underscores: $($app_TitleBrief.value)"
            
            #finished replacing
            Write-Host("[TITLE_BRIEF node] Finished cleaning: $($app_TitleBrief.Value)")
		}
						
			
		#from extrapolation get season and episode number
		if (IsNull($SeasonEpisodeSTR)){
			$e_message = "[EXTRAPOLATION] I dont have a STRING to check for Season and Episode!"
			Write-Debug($e_message)
			$script:numError++
			Write-Log $xml_filename "e" "[EXTRAPOLATION] $($e_message)"
			Write-Log $xml_filename "e" "[EXTRAPOLATION] value of SeasonEpisodeSTR is: $($SeasonEpisodeSTR)"
			Write-Host("[EXTRAPOLATION] Something Broke!") -ForegroundColor Red
			BREAK;
		} else {
			$se_array = Get-SeasonEpisode($SeasonEpisodeSTR)
			$exSeason = $se_array[0]
			$exEpisode = $se_array[1]
			$exTypeMatch = $se_array[2]
		}
			
		# check our function returned some usefule data or break
		if (IsNull($exTypeMatch) -or IsNull($exSeason) -or IsNull($exEpisode)){
			$e_message = "[EXTRAPOLATION] EXTRAPOLATION failed! Saving meta changes for Review, check log file!"
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
					if ($isNullSeason = 0){
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
				}
				default{
					# match or set season and episode numbers
					$e_message = "[EXTRAPOLATION] TYPE $($exTypeMatch) match found."
					$llevel = "I"
					
					#$app_EpisodeID.value = $exEpisode
					$app_EpisodeNum.value = $exEpisode
					$app_Season.value = $exSeason
					#$app_SeasonID.value = $exSeason
					
					Write-Host $e_message -BackgroundColor DarkGray -ForegroundColor Green
					BREAK;
				}
			}
			
			# log our findings/changes
			Write-Log $xml_filename $llevel "[EXTRAPOLATION] $($e_message)"
			Write-Log $xml_filename $llevel "[EXTRAPOLATION] String sent to function: $($SeasonEpisodeSTR)"
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