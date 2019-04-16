############################################################################################
# This scrips inserts 2029-12-31T23:59:00 into HLS ADIs Licensing_Window_End and EST_Licensing_Window_End
# it also check the start of the license window and if in window updates the EST_Licensing_Window_Start
# to equal the Licensing_Window_Start, otherwise it kicks an error and exits the script so you can
# adjust the input file.
# 
#
# Name:     adjustLWE.ps1
# Authors:  James Griffith
# Version:  1.1.1
# History:  05-18-17 - Initial release
#			05-23-17 - add check and logic for EST_Licensing_Window
#			05-24-17 - add more node checking logic for license windows
#
############################################################################################

# set out input file and load it into $file_contents
$input_txt_file = "C:\vodscripts\adjustLWE.txt"	# change this to a file of your choice
$file_contents = Get-Content $input_txt_file

# set our working directories and sort by date each time we run this
$work_directory = "C:\vodscripts\_adjustLWE\"
$originals = $work_directory + (Get-Date).ToString('MMddyyyy') + "\Originals"
$modified = $work_directory + (Get-Date).ToString('MMddyyyy') + "\Modified" 
$failure_log_file = $work_directory + (Get-Date).ToString('MMddyyyy') + "\FailureLogFile.txt"

# make our sub-directories if they dont already exist
If (!(Test-Path -Path $originals ))
{
    New-Item -Path $originals -ItemType directory
}

If (!(Test-Path -Path $modified ))
{
    New-Item -Path $modified -ItemType directory
}


# set our DB connection handles
$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'

# cycle each line in the input file
Foreach ($line in $file_contents)
{
	$hd_variant = 0
    $sd_variant = 0

	# create our SQL querry and match the assest ID's in the input file
    $SqlQuery = "SELECT strscreenformat, xmlContent, dtmEndDate
    FROM [ProvisioningWorkFlow].[Pro].[tAssetInputXML] (nolock)
    where strContentItemID = '$line'"

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
		# check screen format for HD/SD 
		# saves query data to ORIGINAL directory with filename <assestID #_strscreenformat>.xml
		If ($value.strscreenformat -like "*HLS_SM_HD*")
			{
				$hd_variant = 1
				[void]($content = [xml]($value.xmlContent))
				$content.Save($originals + "/" + $line + "_" + $value.strscreenFormat + ".xml")
				[void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)
				
				#get our LWE/LWS nodes
				$LWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
				$LWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
				$estLWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_End"})
				$estLWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_Start"})
				
				
			}
		# same as previous but for SD variant
		If ($value.strscreenformat -like "*HLS_SM_SD*")
			{
				$sd_variant = 1
				[void]($content = [xml]($value.xmlContent))
				$content.Save($originals + "/" + $line + "_" + $value.strscreenFormat + ".xml")
				[void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)
				
				#get our LWE/LWS nodes
				$LWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
				$LWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
				$estLWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_End"})
				$estLWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_Start"})
			}
			
		# check screen format for HD/SD -- only grabs HLS for now
		# saves query data to ORIGINAL directory with filename <assestID #_strscreenformat>.xml
		If ($value.strscreenformat -like "*iPHONE_SM_HD*")
			{
				$hd_variant = 1
				[void]($content = [xml]($value.xmlContent))
				$content.Save($originals + "/" + $line + "_" + $value.strscreenFormat + ".xml")
				[void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)
				
				#get our LWE/LWS nodes
				$LWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
				$LWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
				$estLWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_End"})
				$estLWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_Start"})
				
			}
		# same as previous but for SD variant
		If ($value.strscreenformat -like "*iPHONE_SM_SD*")
			{
				$sd_variant = 1
				[void]($content = [xml]($value.xmlContent))
				$content.Save($originals + "/" + $line + "_" + $value.strscreenFormat + ".xml")
				[void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)
				
				#get our LWE/LWS nodes
				$LWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
				$LWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
				$estLWE = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_End"})
				$estLWS = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name -eq "EST_Licensing_Window_Start"})
			}
			
			
		#set License end and EST_license end to the same value
		# check that the nodes exist. build them if they dont. make them equal no matter what!
		
		if (!($LWE) -or ($LWE -eq $null))
		{
			Write-Host ("$($line):: Licensing_Window_End is MISSING !! Building node...")
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","MOD")
			$app_elem.SetAttribute("Name","Licensing_Window_End")
			$app_elem.SetAttribute("Value","2029-12-31T23:59:00")
			$content.ADI.Asset.Metadata.AppendChild($app_elem)
			Write-Host ("$($line):: Node complete.")
		} else {
			
			Write-Host ("$($line):: License End found setting to new value")
			$LWE.Value = "2029-12-31T23:59:00"
		}
		
		if (!($estLWE) -or ($estLWE -eq $null))
		{
			Write-Host ("$($line):: EST_Licensing_Window_End is MISSING !! Building node...")
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","MOD")
			$app_elem.SetAttribute("Name","EST_Licensing_Window_End")
			$app_elem.SetAttribute("Value","2029-12-31T23:59:00")
			$content.ADI.Asset.Metadata.InsertAfter($app_elem, $LWE)
			Write-Host ("$($line):: Node complete.")
		
		} else {
			
			Write-Host ("$($line):: EST License End found setting to new value")
			$estLWE.Value = "2029-12-31T23:59:00"
		}
		
			
		# check if Licensing_Window_Start exist THEN check if its in the future... throw error if either are true
		# next, check for the EST_Licensing_Window_Start .. if it exist = set to $LWS
		# if it does not exist, build node and set to the $LWS
		if (!($LWS) -or ($LWS -eq $null)){
		
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
				
			if ((!($estLWS) -or ($estLWS -eq $null))){
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
		$content.Save($modified + "/" + $line + "_" + $value.strscreenFormat + ".xml")
		
	}		
}