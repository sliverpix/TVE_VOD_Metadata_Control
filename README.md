# TVE_VOD_Metadata_Control
Version control for TVE's VOD ingestion Metadata and related libraries


# UpdatePrices_Promo_Rental
__Description__:

Authors: | James Griffith
-------- | ---------------
__Version:__ | __2.0.1__

This scrips download/pull ADI files out of the DB for Alt_Codes provided in UpdatePrices_Promo_Rentals.txt file and updates the SD/HD prices to $2.99/$3.99


__History__:
* 02-14-17 - Initial release
* 02-07-18 - [Griffith] add processing functions from my library to keep better track of of this scripts work
* 04-26-19 - Rewriting code base... simpilier ways to accomplish the same thing. Need to add many core functions from the other scripts. Make this a little less complicated and a little more manageable
* 05-15-19 - [Griffith] fix HD/SD switch block detection.
	* Edit header to point to Repo for history.


# UpdatePrices_Promo_Purchase
__Description__:

Authors: | James Griffith
-------- | ---------------
__Version:__ | __1.4__

This scrips downloads pulls ADI files out of the DB for Alt_Codes provided in UpdatePrices_Promo_Purchases.txt file and updates the SD/HD prices to prices provided in the file. While we are at it, we will check and set the PURCHASE flag, License_Window_Start/END
 and the EST_License_Window_Start/END dates.
 

__History__:
* 02-14-17 - Initial release
* 11-02-17 - ADD logging feature
	* ADD debug feature
	* ADD IsNull checking funtion
	* UPDATE logic to check the PURCHASE flag and EST_License_Window_Start/_END dates
* 11-30-17 - move HD/SD notification from DEBUG to production mode, log it and add to summary report
* 10-10-18 - Reorganize code for debugging and testing
	* Fix XML node adding bug when EST_LICENSE_WINDOW_START/_END is missing.
	* update Write-Log() to latest function version from psmodTVEVODUtils.psm1
* 12-12-18 - [bug fix] Powershell version changed to 4.0.1.1 and we lost access to Rows.Count
	* ADD Dataset.Tables.Rows | Measure-Object to get number of rows returned from our SQL query. If no ROWS returned we break out since there is no data for us to work with. The incident is also logged and output set to the user.
  
  
# UpdateSeasonEpisodeInformation
__Description__:

 Authors: | James Griffith
 -------- | ---------------
 __Version:__ | __1.11T__
 
 This script downloads / pulls ADI files out of the DB for correction to SEASON and Season_ID, EPISODE_NUM and EPISODE_ID, Checks for necessary  element nodes in the metadata and creates/changes values to those elements/nodes.. ONLY HLS title types are checked. If the element/nodes are not present in the original XML we will build them and populate them. XML files are saved to ORIGINAL and MODIFIED folders to maintain the integrity of our library. We target HLS formats in both HD and SD and set values based on TITLE or Title_Brief value. If these dont exist we break out, log it and and notify the user.

 Logging function has been added to help track processing, error,
 and logic checks.

 Summary Report has been added to let the user know what was done. This
 saves on memeory and outputs minimal test to the screen


__History:__:
* 10-30-17	- Initial release
* 11-03-17	- include trailing \s in type 5 regex. hopefully reduce	number of false positive matches.
	* enabled "loose" type extrapolation (... scary ...)
	* ADD new type to match SE pattern
* 04-30-18    - [Russ N] added new regex type and adjust content_type logic
* 05-01-18	- Fix Node checking logic to check more nodes and either build or modify everything we run through this script.
	* Fix Content_Type check to build node if missing and set value to TVS.
	* Fix REGEX checks to address  vs  bug
* 05-02-18	- Add function to address unwanted "_" and "_(HD)" in Series_ID, Series_Name and Series_Description
	* Add Directory sorting for meta that changes some nodes but does not match our REGEX. (makes it easier on our folks making manual changes)
* 05-03-18	- remove node checks for Series_Description, Season_ID and Series_Name
* 05-08-18	- add isReview flag to fix SD saving bug. Where some SD meta was getting skipped due broken season/episode extrapolation failure.
	* re-wrote if-elseif-else for match TYPE checking to a SWITCH case style [no impact to user]
* 05-08-18	- add log level to Write-Log()
	* add additional string trasformation to cleanUp() for Series_Name and Series_ID
* 05-17-18	- add functionality to address "blob"-like strings in the Series_Name and Series_ID
* 06-05-18	- and new DATE TYPE match and transform logic. Ex: 5/30 becomes episode 5-30. Set SEASON to YEAR unless it already has a value.
	* Replace "/" with "-" in TITLE_BRIEF or EPISODE_NAME (depending on which one is built)
	* add new type (3.1) to match (ex: S2 E01). Very close to Type 3, thus it is handled the same way as a Type 3 match
	* and new type (Type 8) to match "S1 Episode 8 HD". This should be a pretty tight match.
* 06-06-18	- removed ability to set SEASON when DATE TYPE match is found. We will still build all nodes but wont set a value to SEASON for DATE Type matches
* 06-12-18	- fix substring bug in type 3 match
* 06-15-18	- fix file count and duplication bug. Script now will check the ORIGINAL directory filenames against the current processing filename. If they are the same (duplicated) it will skip the currently processing ID and log it for later. No other output is done. Thus a list of Asset IDs with duplicated numbers will be caught and no loger rewrite original/modified/reviewed files and the summary output will be correct.
* 06-28-2018	- Removed Title Case ability from cleanString Function per Russ request.
* 07-06-2018  - add Trim() to the return of the getSeasonEpisode function.
	* add new type (3.2) to match "S1 Ep01". Very close to a type 3 match, thus we will handle it the same way.
    * Fixed dateType match bug not setting to the episode. value of variable logic was out of order and not being caught in the Get-SeasonEpisode function.
* 07-24-2018  - added a TrimEnd to remove " HD" being seeen at the END of a string (title)
* 07-25-2018	- (1.7.2) added new "HD" variant to cleanUp Function: TrimEnd(" HD")
	* Rebuilt CleanUp function to include a switch for series name. If this switch is set, we will call Find_SeriesName function passing to it the string from cleanUp function.
	* Add new function Find_SeriesName. The function will take any string passed to it and, depending on the switch, check that string for a match in the previously created dictionary CSV file. This is the default option of the function and is always performed. IF no match is found AND there is a switch set, then additional checks will be made. There are 3 switches that can be passed: TitleCheck, CategoryCheck and CheckAll.
	* TitleCheck will also try and match the value of TITLE element to the dictionary file.
	* CategoryCheck will also try and match the value(s) of CATEGORY_DISPLAY element to the dictionary file.
	* CheckAll will perform all the checks previously stated. If a match is FOUND in the dictionary file, we will return the CORRECT_NAME from it to populate the Series_Name element.
	* add string.replace to swap out "_" for whitespace in the TITLE element. This check is done AFTER any function passthroughs so preserve the integrity of function that process the original string from the TITLE value.
	* add new typw pattern (5.1) "S01_E07". Very close to type 5 match, thus we will handle it the same way
* 08-01-2018	- (1.7.1) reverted to a -Replace switch in the cleanup() functions to address the wierd returns from the various "(HD)" matches we were getting with the .Replace method.
	* (bug) case where "&amp;" is being passed as "&" within powershell variables but not being passed to the XML.
* 08-08-2018	- (1.8) Add secondary logic to extrapolate SEASON/EPISODE number. If TITLE_BRIEF and EPISODE_NAME fails to match, check TITLE for a match to our patterns.
	* Cleanup logging and debug statements.
	* fixed mispellings/bugs (uncaught somehow)
* 08-21-2018	- (1.9) Added new branch of logic to help find and set Episode Name, Season and Episode number by PROVIDER. user input is taken at the start of the script, to either set/change these values by either CATEGORY or by PROVIDER in our CSV files. Thus, the user can choose which logic to use. The rest of the logic remains the same.
	* Get-SeasonEpisodebyProvider() will check for EPISODE_NAME node and build it, if it is missing. It will take CATEGORY_DISPLAY value and split it to an array. then take each value in the array and look for a match in the csv_Providers.inc file. if it finds a match it will set the EPISODE_NAME to the Title_Brief value, set the SEASON and EPISODE_NUMBER to '0'
	* All other logic is the same as previously built/used. Thus choosing "By Category" will follow the original logic chain.
* 08-28-2018	- (1.9.1) adding value check to Category_Display and Category nodes. If we find MOV values from provider CSV, change them to TVS values.
* 12-12-2018	- (1.10) Powershell version changed to 4.0.1.1 and we lost access to Rows.Count
	* ADD Dataset.Tables.Rows | Measure-Object to get number of rows returned from our SQL query. If no ROWS returned we break out since there is no data for us work with. The incident is also logged and output set to the user.
	* (1.10) Added DEBUG logic for easier targeting for $work_dir and $input_txt_file
* 12-13-2018	- (1.10.1) removed CLEANED TITLE string from file name. Thus it should be alt_code_sd/hd.xml
* 04-16-2019	- (1.10.2) BUG FIX:- Correct bug on line 645 "$app_elem.SetAttribute("Name","Epipode_Name") to correct the mispelling of EPISODE_NAME. This caused a node to be built with the wrong NAME value and thus was not caught when checking for the existance of the EPISODE_NAME node, thus continually appending a mispelled node each time the xml was iterated through.
* 04-22-2019	- (1.10.3) ADDed node check for MPAA_Rating. Check and build node, check for mispelling of NAME elemental and/or correct it and set VALUE element.
* 06-03-2019	- (1.10.4) Retruned Series_Id and Episode_Id node checks.
	* Alpha-Case "name" check for Series_Id and EPISODE_ID
	* Build missing Series_Id and Episode_Id nodes.
	* Add Logic to set empty values of Series_Id to Series_Name value
	* Add Logic to prepend pre-pend "Sub_" to Series_Id values if isSubscription node is "Y"
	* Add Logic for HBO Shows, NOT TO pre-pend to Series_Id value. This avoids perpetual issue where the application code would create a "Sub_Sub_" prepend value.
* 06-11-2019	- (1.10.3.1) Reverted to base 1.10.3 and added the following
	* Alpha-Case "name" check for Series_Id and EPISODE_ID
	* Add new Season/Episode type-match 1_1 "S##:E###" (Ex: S13:E17).
	* Add debugging switch (y/n) user input. Target working directory and target asset file list will change depending on option taken. Defaults to EXIT if not "y" or "n"
	* REMOVE all logic that touches prepending "Sub_"
* 06-25-2019	- (1.10.3.1) remove "BREAK" statement that was causing the script to stop processing the asset ID list -IF- there was no return from our query. By removing this statement, we allow the second ForEach loop to check and process any return(s) in the dataset. Due to the nature of the loop, if there is no data returned, then the loop does not execute and control is returned to the first ForEach and it cycles to the next asset ID number in the lsit. No change made to the version number as only a single word statement is removed.
* 07-11-2019	- (1.10.6) Add cleanUp() to SERIES ID and logic to set SeiriesID.value to seriesName.value in some cases.
* 07-19-2019	- (1.11T) Uncomment SUB_ processing in code and add user input. User can choose to turn on SUB_ processing. (may remove in the future but for now its a choice)
				- Include REALITY check code. Currently commented out, and needs more testing.
