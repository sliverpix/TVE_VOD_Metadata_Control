############################################################################################
# This scrips inserts 2029-12-31T23:59:00 into HLS ADIs Licensing_Window_End and EST_Licensing_Window_End
# it also check the start of the license window and if in window updates the EST_Licensing_Window_Start
# to equal the Licensing_Window_Start, otherwise it kicks an error and exits the script so you can
# adjust the input file.
# 
# :BUG:	if more than one element/tag is found (ex: 2 sets of EST_License_Window_End) the script will break
#			and error out. Im currently leaving this place as a way to identify BAD-MOLDED metadata from
#			Vubiquity.
#
# Name:     adjustLWE.ps1
# Authors:  James Griffith
# Version:  1.2.1
#
############################################################################################

# set out input file and load it into $file_contents
$input_txt_file = "C:\vodscripts\adjustLWE-HLS.txt"	# change this to a file of your choice
$file_contents = Get-Content $input_txt_file

# set our working directories and sort by date each time we run this
$work_dir = "C:\vodscripts\_adjustLWE\"
$daily_directory = (Get-Date).ToString('MMddyyyy') + ("_TESTING")	# uncomment "+ ("_TESTING")" for debug
$originalD = $work_dir + $daily_directory + "\Originals"
$modifiedD = $work_dir + $daily_directory + "\Modified"


# Write-Debug -- this might work
	#uncomment preference to turn on/off output
	#$DebugPreference = "SilentlyContinue"
	$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")
	
# set the log file
$logfile = "logfile.txt"
$tolog = $work_dir + $daily_directory + "\" + $logfile
$e_message = ""


### check and create direcotries and files ###
if(!(Test-Path -Path $work_dir)){
    Write-Debug ("cant find $($work_dir) .. creating..")
	New-Item -Path $work_dir -ItemType Directory
	Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $daily_directory)){
	Write-Debug ("$($daily_directory) not found! Creating...")
	New-Item -Path $daily_directory -ItemType Directory
	Write-Debug ("FIXED!")
}
if(!(Test-Path -Path $originalD)){
    Write-Debug ("$($originalD) directory not found! Creating ...")
    New-Item -Path $originalD -ItemType Directory
    Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $modifiedD)){
    Write-Debug ("$($modifiedD) directory not found! Creating ...")
    New-Item -Path $modifiedD -ItemType Directory
    Write-Debug ("FIXED!")
}

if(!(Test-Path -Path $tolog)){
    Write-Debug ("$($tolog) not found! Creating ...")
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}

# log-o-funky
function Write-Log {
    # write to our log file
    param ($filename, $message)
	$datetime = (Get-Date).ToString('MM-dd-yyyy hh:mm:ss')
    Add-Content $tolog ($datetime + "::" + $filename + " | " + $message)
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

    if($objectToCheck -is [String] -and $objectToCheck -eq ""){
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
		$p_class = $content.ADI.Metadata				# Asset_Class="package" node
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
		Write-Host("Checking License_Window_End...") -ForegroundColor Yellow
		if (IsNull($LWE))
		{	#does LWE exist
			$e_message = "Licensing_Window_End is MISSING !!"
			Write-Host ($e_message) -ForegroundColor Red
			Write-Debug ("Building ...") 
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
			if ((get-date $LWE.Value) -lt (get-date)){
				$e_message = "License_Window_End has an expired date!"
				Write-Debug ("$($e_message) -- value: $($LWE.Value)") 
				Write-Log ($metafile, $e_message)
				Write-Log ($metafile, "$($LWE.Value) ... breaking out and moving on.")
				Write-Host ("$($e_message), check log file.") -ForegroundColor Red
				Break;
			} else {
				# set hard date of 2029-12-31T23:59:00
				$e_message = "License_Window_End currently: $($LWE.Value)"
				Write-Log ($metafile, $e_message)
				$e_message = "License_Window_End changed: $($LWE.Value)"
				Write-Log = ($metafile, $e_message)
				Write-Host("... OK") -ForegroundColor Green
			}

		}
		
		Write-Host("Checking EST_License_Window_End...") -ForegroundColor Yellow
		if (IsNull($estLWE.Value))
		{	# does estLWE exist
			$e_message = "EST_Licensing_Window_End is MISSING !!"
			Write-Debug ($e_message) 
			Write-Log ($metafile, $e_message)
			
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","MOD")
			$app_elem.SetAttribute("Name","EST_Licensing_Window_End")
			$app_elem.SetAttribute("Value","2029-12-31T23:59:00")
            
            if (!($estLWE)){
			$content.ADI.Asset.Metadata.InsertAfter($app_elem, $LWE)
            } else {$estLWE.Value = $LWE.Value}
			
			Write-Log ($metafile, "created: $($app_elem.Name) with value: $($estLWE.Value)")
			Write-Debug ("Created EST_License_Window_End: $($estLWE.Value)")
			Write-Host ("EST_Licensing_Window_End was Fixed.") -ForegroundColor Green
		
		} else {
			# EST_Licensing_Window_End was found. Check if we are in window
			if ((get-date $estLWE.Value) -lt (get-date)){
				$e_message = "EST_License_Window_End has an expired date!"
				Write-Debug ("$($e_message) -- value: $($estLWE.Value)") 
				Write-Log ($metafile, $e_message)
				Write-Log ($metafile, "$($estLWE.Value) ... breaking out and moving on.")
				Write-Host ("$($e_message), check log file.") -ForegroundColor Red
				Break;
			} else {
				# set hard date of 2029-12-31T23:59:00
				$e_message = "EST_License_Window_End currently: $($LWE.Value)"
				Write-Log ($metafile, $e_message)
				$e_message = "EST_License_Window_End changed: $($LWE.Value)"
				Write-Log = ($metafile, $e_message)
				Write-Debug ("EST_License_Window_End set to: $($estLWE.Value)")
				Write-Host("... OK") -ForegroundColor Green
			}
		}
		
			
		# check if Licensing_Window_Start exist THEN check if its in the future... Break out if either are true
		# next, check for the EST_Licensing_Window_Start .. if it exist = set to $LWS
		# if it does not exist, build node and set to the $LWS
		
		Write-Host("Checking License_Window_Start...") -ForegroundColor Yellow
		if (IsNull($LWS)){
		
			$e_message = "Licensing_Window_Start is EMPTY or MISSING !!"
			Write-Debug ("$($e_message) : $($LWS)") 
			Write-Log ($metafile, $e_message)
			Write-Host ("$($e_message) Breaking out!") -ForegroundColor Red
			Break;
			
		} else {
			Write-Debug (" Licensing_Window_Start exist... Checking Date...")
			
			If ((get-date) -lt (get-date $LWS.Value))
			{
				# we are before the license start date. leave it and move on
				Write-Debug ("Licensing_Window_Start in the future ... $($LWS.Value)") 
			} else {
                $e_message = "License_Window_Start is $($LWS.value)"
                Write-Log ($metafile, $e_message)
				Write-Debug ($e_message)
				Write-Host("... OK") -ForegroundColor Green
            }

			# check the EST_Licensing_Window_Start for validity
			Write-Host("Checking EST_License_Window_Start...") -ForegroundColor Yellow
			if (IsNull($estLWS.value)){
				# EST_Licensing_Window_Start is missing/null
				$e_message = "EST_Licensing_Window_Start is EMPTY or MISSING!!"
				Write-Debug ("$($e_message) Building nodes...") 
				
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App","MOD")
				$app_elem.SetAttribute("Name","EST_Licensing_Window_Start")
				$app_elem.SetAttribute("Value",$LWS.Value)

                if(!($estLWS)){
				$content.ADI.Asset.Metadata.InsertAfter($app_elem,$LWS.value)
                } else {$estLWS.Value = $LWS.Value}
				
				$e_message = "EST_Licensing_Window_Start node built: $($estLWS.Value)"
				Write-Debug ($e_message)
				Write-Log ($metafile, $e_message)
				Write-Host ("EST_Licensing_Window_Start fixed. see log.") -ForegroundColor Green
				
			} else {
				# EST_Licensing_Window_Start exists. set it to License_Window_Start value
				$e_message = "EST_Licensing_Window_Start is present and has value: $($estLWS.Value)"
				Write-Debug ($e_message)
				Write-Log ($metafile, $e_message)
			}

            Write-Debug ("License_Window_Start is OK")
			Write-Host("... OK") -ForegroundColor Green
		}
		
		Write-Debug ("Done processing. Saving modified file.")
		# save our MODIFIED file
		$content.Save($modifiedD + "/" + $line + "_" + $value.strscreenFormat + ".xml")
		
	}
}
