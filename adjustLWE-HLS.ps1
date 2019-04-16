############################################################################################
# This scrips inserts 2029-12-31T23:59:00 into HLS ADIs Licensing_Window_End and EST_Licensing_Window_End
# it also check the start of the license window and if in window updates the EST_Licensing_Window_Start
# to equal the Licensing_Window_Start, otherwise it kicks an error and exits the script so you can
# adjust the input file.
# 
#
# Name:     adjustLWE.ps1
# Authors:  James Griffith
# Version:  1.2.1
# History:  05-18-17 - Initial release
#			05-23-17 - add check and logic for EST_Licensing_Window
#			05-24-17 - add more node checking logic for license windows
#			09-27-17 - update functions to include logging and debug switch
#					 - update file and directory checks to work with log and debug
#					 - update SQL query to only pull HLS content (SD/HD)
#
############################################################################################

# set out input file and load it into $file_contents
$input_txt_file = "C:\vodscripts\adjustLWE-HLS.txt"	# change this to a file of your choice
$file_contents = Get-Content $input_txt_file

# set our working directories and sort by date each time we run this
$work_dir = "C:\vodscripts\_adjustLWE\"
$daily_directory = (Get-Date).ToString('MMddyyyy') + ("_TESTING")	# uncomment "+ ("_TESTING")" for debug
$originalD = $work_dir + (Get-Date).ToString('MMddyyyy') + "\Originals"
$modifiedD = $work_dir + (Get-Date).ToString('MMddyyyy') + "\Modified" 
$failure_log_file = $work_dir + (Get-Date).ToString('MMddyyyy') + "\FailureLogFile.txt"

# Write-Debug -- this might work
	#uncomment preference to turn on/off output
	#$DebugPreference = "SilentlyContinue"
	$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")
	
# set the log file
$logfile = "logfile.txt"
$tolog = $work_dir + $daily_directory + "\" + $logfile
$e_message = ""

# log-o-funky
function Write-Log {
    # write to our log file
    param ($filename, $message)
	$datetime = (Get-Date).ToString('MM-dd-yyyy hh:mm:ss')
    Add-Content $tolog ($datetime + "::" + $filename + " | " + $message)
	

### check and create direcotries and files ###
if(!(Test-Path -Path $work_dir)){
    Write-Debug ("cant find working directory .. creating..") -ForegroundColor Yellow
	New-Item -Path $work_dir -ItemType Directory
	Write-Debug ("FIXED!") -ForegroundColor Green
}

if(!(Test-Path -Path $originalD)){
    Write-Debug ("ORIGINALS directory not found! Creating ...") -ForegroundColor Yellow
    New-Item -Path $originalD -ItemType Directory
    Write-Debug ("FIXED!") -ForegroundColor Green
}

if(!(Test-Path -Path $modifiedD)){
    Write-Debug ("MODIFIED directory not found! Creating ...") -ForegroundColor Yellow
    New-Item -Path $modifiedD -ItemType Directory
    Write-Debug ("FIXED!") -ForegroundColor Green
}

if(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!") -ForegroundColor Green

	
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


# set our DB connection handles
$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'

# cycle each line in the input file
Foreach ($line in $file_contents)
{
	# create our SQL querry and match the assest ID's in the input file
	# get only HLS meta for both HD/SD -- NO IPHONE!
    $SqlQuery = "SELECT strscreenformat, xmlContent, dtmEndDate
    FROM [ProvisioningWorkFlow].[Pro].[tAssetInputXML] (nolock)
    where strContentItemID = '$line' and strScreenFormat like '%HLS_SM_%'"

    ## connect to the database
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security = True"
 
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
 
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

    $SqlAdapter.SelectCommand = $SqlCmd
 
	# set our querry results to a handler for easy processing
    $DataSet = New-Object System.Data.DataSet
    [void]($SqlAdapter.Fill($DataSet))
	
	
	# cycle through the results of our querry
	Foreach ($value in $DataSet.Tables[0])
	{
		# saves query data to ORIGINAL directory with filename <assestID #_strscreenformat>.xml
		
		$content = [xml]($value.xmlContent)
		$content.Save($originalD + "/" + $line + "_" + $value.strscreenFormat + ".xml")
		$metafile = ($line + "_" + $value.strscreenFormat + ".xml")
		
		#set our node variables
		$p_class = $content.ADI.Metadata			# Asset_Class="package" node
		$t_class = $content.ADI.Asset.Metadata			# Asset_Class="title" node
		$m_class = $content.ADI.Asset.Asset.Metadata	# AMS Asset_Class="movie" node
		
		# get our element values
		$product = ($p_class.AMS.Product)
		$LWE = ($t_class.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
		$LWS = ($t_class.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
		$estLWE = ($t_class.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_End"})
		$estLWS = ($t_class.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_Start"})

		Write-Host("$($line) :: Processing ...")
		# set License end and EST_license end to 2029-12-31T23:59:00
		# check that License_Window_Start exist.
		# if EST_Licensing_Window_Start has value leave it, otherwise build it and
		# set it to the License_Window_Start value
		
		if (IsNull($LWE))
		{	#does LWE exist
			$e_message = "Licensing_Window_End is MISSING !!"
			Write-Host ($e_message) -ForegroundColor Red
			Write-Host ("Building ...") -ForegroundColor Yellow
			Write-Log ($metafile, $e_message)
			
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","MOD")
			$app_elem.SetAttribute("Name","Licensing_Window_End")
			$app_elem.SetAttribute("Value","2029-12-31T23:59:00")
			$content.ADI.Asset.Metadata.AppendChild($app_elem)
			
			Write-Log ($metafile, "created: $($app_elem)")
			Write-Debug ("tolog: $($app_elem)")
			Write-Host ("Fixed.") -ForegroundColor Green
		} else {
			# LWE exists but is it out of window?
			Write-Debug ("License_Window_End found... Value is: $($LWE.Value)")
			if ((get-date $LWE.Value) -lt get-date){
				$e_message = "License_Window_End has an expired date!"
				Write-Debug ("$($e_message) -- value: $($LWE.Value)") -ForegroundColor Red
				Write-Log ($metafile, $e_message)
				Write-Log ($metafile, "$($LWE.Value) ... breaking out and moving on.")
				Write-Host ("$($e_message), check log file.") -ForegroundColor Red
				Break;
			}

		}
		
		if (IsNull($estLWE))
		{	# does estLWE exist
			$e_message = "EST_Licensing_Window_End is MISSING !!"
			Write-Host ($e_message) -ForegroundColor Red
			Write-Host ("Building ...") -ForegroundColor Yellow
			Write-Log ($metafile, $e_message)
			
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","MOD")
			$app_elem.SetAttribute("Name","EST_Licensing_Window_End")
			$app_elem.SetAttribute("Value","2029-12-31T23:59:00")
			$content.ADI.Asset.Metadata.InsertAfter($app_elem, $LWE.Value)
			
			Write-Log ($metafile, "created: $($app_elem)")
			Write-Debug ("tolog: $($app_elem)")
			Write-Host ("Fixed.") -ForegroundColor Green
		
		} else {
			
			Write-Host ("$($line):: EST License End found setting to new value")
			$estLWE.Value = "2029-12-31T23:59:00"
		}
		
			
		# check if Licensing_Window_Start exist THEN check if its in the future... throw error if either are true
		# next, check for the EST_Licensing_Window_Start .. if it exist = set to $LWS
		# if it does not exist, build node and set to the $LWS
		if (IsNull($LWS)){
		
			throw ("$($line) does not contain a Licensing_Window_Start !!")
			
		} else {
			Write-Host ("$($line):: Licensing_Window_Start exist... Checking Date...")
			
			If ((get-date) -lt (get-date $LWS.Value))
			{
				# we are before the license start date and need to error out!
				Write-Host ("$($line) has a Licensing_Window_Start in the future ... continuing") -ForegroundColor Red
			}

			Write-Host ("$($line):: Licensing_Window_Start is: $($LWS.Value)")
			Write-Host ("$($line):: Checking for EST_Licensing_Window_Start...")
				
			if (IsNull($estLWS){
				Write-Host ("$($line):: EST_Licensing_Window_Start is MISSING!! Building nodes...")
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App","MOD")
				$app_elem.SetAttribute("Name","EST_Licensing_Window_Start")
				$app_elem.SetAttribute("Value",$LWS.Value)
				$content.ADI.Asset.Metadata.InsertAfter($app_elem,$LWS)
				Write-Host ("$($line):: Node complete.")
			} else {
				Write-Host ("$($line):: Setting EST_Licensing_Window_Start ...")
				$estLWS.Value = $LWS.Value
				Write-Host ("$($line):: EST_Licensing_Window_Start set to: $($estLWS.Value)")
			}
		}
		
		# save our MODIFIED file
		$content.Save($modifiedD + "/" + $line + "_" + $value.strscreenFormat + ".xml")
		
	}		
}