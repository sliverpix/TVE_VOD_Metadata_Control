####################################################################
# This scrips downloads pulls ADI files out of the DB for
# Alt_Codes provided in UpdatePrices_Promo_Purchases.txt file
# and updates the SD/HD prices to prices provided in the file
#
# While we are at it, we will check and set the PURCHASE flag, License_Window_Start/END
# and the EST_License_Window_Start/END dates.
# 
#
# Name:     UpdatePrices_Promo_Purchases.ps1
# Authors:  Elena Raines and James Griffith
# Version:  1.3
# History:  02-14-17 - 	Initial release
#			11-02-17 - 	ADD logging feature
#						ADD debug feature
#						ADD IsNull checking funtion
#						UPDATE logic to check the PURCHASE flag and EST_License_Window_Start/_END dates
#			11-30-17 -	move HD/SD notification from DEBUG to production mode, log it and add to summary report
#           10-10-18 -  Reorganize code for debugging and testing
#                    -  Fix XML node adding bug when EST_LICENSE_WINDOW_START/_END is missing.
#                    -  update Write-Log() to latest function version from psmodTVEVODUtils.psm1
#
####################################################################

# Write-Debug -- this might work
	#uncomment preference to turn on/off output
	$DebugPreference = "SilentlyContinue"
	#$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")

# set environment variables
if($DebugPreference -eq "Continue"){
    $work_directory = "C:\vodscripts\_PromoPrices_Purchases\_Debug\"
    $input_txt_file = "C:\vodscripts\testlist.inc"
} else {
    $work_directory = "C:\vodscripts\_PromoPrices_Purchases\"
    $input_txt_file = "C:\vodscripts\UpdatePrices_Promo_Purchases.txt"
}

$file_contents = Get-Content $input_txt_file
$originals = $work_directory + (Get-Date).ToString('MMddyyyy') + "\Originals"
$modified = $work_directory + (Get-Date).ToString('MMddyyyy') + "\Modified" 
$LWEdefault = "2029-12-31T23:59:00"

# set the log file
$logfile = "logfile.txt"
$tolog = $work_directory + (Get-Date).ToString('MMddyyyy') + "\" + $logfile

# check paths and files. creat if missing
If (!(Test-Path -Path $originals ))
{
    New-Item -Path $originals -ItemType directory
	Write-Debug ("ORIGINAL directory created!")
}

If (!(Test-Path -Path $modified ))
{
    New-Item -Path $modified -ItemType directory
	Write-Debug ("MODIFIED directory created!")
}

if(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}

# Log-O-funky
# from psmodTVEVODUtils.psm1
function Write-Log {
	[CmdletBinding(PositionalBinding=$false)]
	Param(
		[Parameter(Mandatory=$True,
		HelpMessage="Message to log.")]
		[string]$message,
		
		[Parameter(Mandatory=$True,
		HelpMessage = "Level of log message. Can be I or INFO, W or WARN, E or ERROR, and Alert. Must be a string")]
		[ValidateNotNullOrEmpty()]
		[string]$loglevel,
		
		[Parameter(Mandatory=$True,
		HelpMessage="Name of file we are logging information about. Must be a string")]
		[ValidateNotNullOrEmpty()]
		[string]$filename
	)

	switch($loglevel){
		({"I","INFO" -contains $_}) {$ll="INFO"; break;}
		({"W","WARN" -contains $_}) {$ll="WARN"; break;}
		({"E","ERROR" -contains $_}) {$ll="ERROR"; break;}
		"Alert" {$ll="ALERT";break;}
		default {Write-Debug("Fatal-error in WRITE-LOG: Log Level flag UNRECOGNIZED!!"); break;}
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
	
	if ($objectToCheck -is [String] -and $objectToCheck -eq ""){
		return $true
	}

    if ($objectToCheck -is [DBNull] -or $objectToCheck -is [System.Management.Automation.Language.NullString]) {
        return $true
    }

    return $false
}

# variables for summary
$numRuns = [int] 0
$numError = [int] 0
$numWarn = [int] 0
$numinfo = [int] 0
$numContentID = [INT] 0
$numOrig = [INT] 0
$numMod = [INT] 0
$numMisSD = [INT] 0
$numMisHD = [INT] 0

# summarry report of script/process
function Summarize(){
	Write-Host ".."
	Write-Host ".."
	Write-Host ".."
	Write-Debug "Number of Times I have ran -- $($numRuns)"
	Write-Host "	-/-  ***   SUMMARY REPORT   ***  -\-" -BackgroundColor DarkCyan
	Write-Host "---------------------------------------------" -BackgroundColor DarkCyan
	Write-Host -NoNewline "Content ID's Processed		.....	"
	Write-Host $numContentID -ForegroundColor Cyan
	Write-Host -NoNewline "Original XML created		.....	"
	Write-Host $numOrig -ForegroundColor Cyan
	Write-Host -NoNewline "Modified XML created		.....	"
	Write-Host $numMod -ForegroundColor Cyan
	Write-Host -NoNewline "ERRORs Logged				.....	"
	Write-Host $numError -Foreground Red
	Write-Host -NoNewline "WARNings Logged				.....	"
	Write-Host $numWarn -Foreground Yellow
	Write-Host -NoNewline "INFOs Logged				.....	"
	Write-Host $numinfo -ForegroundColor Cyan
	Write-Host
	Write-Host -NoNewline "HD versions missing			.....	"
	Write-Host $numMisHD -ForegroundColor Yellow
	Write-Host -NoNewline "SD versions missing			.....	"
	Write-Host $numMisSD -ForegroundColor Yellow
}

$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'


Foreach ($line in $file_contents)
{
    
	$numContentID++
	# process out input file and set variables
	$hd_variant = 0
    $sd_variant = 0

    $alt_code = $line.Split(',')[0]
    $sd_price = $line.Split(',')[1]
    $hd_price = $line.Split(',')[2]
     
	# set our SQL querry string
    #$alt_code = "TVNX0031945001951330"
    $SqlQuery = "SELECT strscreenformat, xmlContent
    FROM [ProvisioningWorkFlow].[Pro].[tAssetInputXML]
    where strContentItemID = '$alt_code' and strScreenFormat like '%HLS_SM_%'"

    # connect and hook SQL connection to DB
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security = True"
 
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
 
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

    $SqlAdapter.SelectCommand = $SqlCmd

	# get our query return
    $DataSet = New-Object System.Data.DataSet
    [void]($SqlAdapter.Fill($DataSet))
    $numRows = $Dataset.Tables.Row.count

    if($numRows -eq 0)
    {        
		$numError++
        $e_message = "No Match found in tAssestInputXML table!"
		Write-Host("$($alt_code) :: [ERROR] $($e_message) ... skipping") -ForegroundColor Red
        Write-Log -filename $alt_code -loglevel "E" -message $e_message
    }else{
        $numinfo++
        $e_message = "$($numRows) ROWS returned for $($alt_code)"
        Write-Debug $e_message
        Write-Log -filename $alt_code -loglevel "I" -message $e_message
    }
	  
    Foreach ($value in $DataSet.Tables[0])
    {
    if($numRows -eq 0){Write-Debug("No data in DATASET.TABLES ... Breaking out!");Break;}

        # get XML from dataset return (query) and save the original
         [void]($content = [xml]($value.xmlContent))
		 [void]($cfid = $alt_code + "_" + $value.strscreenFormat + ".xml")		# set our file name for use later
         $content.Save($originals + "\" + $cfid)
		 $numOrig++
         [void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)
		 Write-Host("$($cfid) :: Processing ...")
		 
		
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
		$purchase = ($t_class.App_Data | Where-Object {$_.Name -eq "Purchase"})
		
		# SD and HD
		# check for PURCHASE FLAG set to Y
		# check for exsistance EST_License_Window_Start and _End
		#	if they exist _End should = 2029-12-31T23:59:00
		#	and _Start should be -LT or -EQ to today's date AND -EQ to License_Window_Start date
		#
		Write-Debug("Checking Purchase")
		if (IsNull($purchase.value)){
            #purchase element is present but empty or missing
			$numWarn++
			$e_message = "Purchase element is NULL or MISSING!"
			Write-Debug ($e_message)
			Write-Log -filename $cfid -loglevel "W" -message $e_message
			
			if (!($purchase)){
				#purchase element is missing
				$e_message = "PURCHASE element is missing!"
				Write-Debug ($e_message)
				Write-Log -filename $cfid -loglevel "W" -message "$($e_message) building new element and adding it at the end of the APP_DATA node"
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App","$($product)")
				$app_elem.SetAttribute("Name","Purchase")
				$app_elem.SetAttribute("Value","Y")
				$content.ADI.Asset.Metadata.AppendChild($app_elem)
				Write-Debug ("FIXED!")
			} else {
				# purchase was empty
				Write-Debug("PURCHASE was empty. Setting to 'Y'")
				Write-Log -filename $cfid -loglevel "W" -message "PURCHASE is empty!"
				$purchase.value = "Y"
                Write-Log -filename $cfid -loglevel "W" -message "Set PURCHASE to: $($purchase.value)"
			}
			Write-Host("We set PURCHASE to '$($purchase.value)'") -ForegroundColor Green
			Write-Log-filename $cfid -loglevel "W" -message "PURCHASE: $($purchase.value) (changed)"
		}

        # check purchase is set to 'y'
        if ($purchase.Value -eq 'Y'){
            $numinfo++
            Write-Debug("PURCHASE is 'Y'")
            Write-Log -filename $cfid -loglevel "W" -message "Purchase is 'Y' so we continue."
        } else {
            Write-Debug("PURCHASE is 'N'")
            $e_message = "PURCHASE is set to '$($purchase.Value)'!"
            $numWarn++
            Write-Log -filename $cfid -loglevel "W" -message $e_message
            $purchase.value = 'Y'
            Write-Debug("PURCHASE is: '$($purchase.Value)'")
            Write-Host("Fixed PURCHASE") -ForegroundColor Yellow
            Write-Log -filename $cfid -loglevel "W" -message "PURCHASE is: '$($purchase.Value)' (changed)"
        }

		
		#set EST_license end to the same value
		# check that the nodes exist. build them if they dont. make them equal no matter what!
		Write-Debug("Checking EST_Licensing_Window_End")
		if (!($estLWE))
			{
				Write-Debug ("EST_License_Window_End is MISSING !! Building node...")
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App",$type)
				$app_elem.SetAttribute("Name","EST_Licensing_Window_End")
				$app_elem.SetAttribute("Value",$LWEdefault)
				$estLWE = $content.ADI.Asset.Metadata.InsertAfter($app_elem, $LWE)
				Write-Debug ("Node complete.")
				Write-log -filename $cfid -loglevel "I" -message "Built EST_License_Window_End complete."
			}

        Write-Debug("comparing value of EST_License_Window_End: $($estLWE.Value)")
		if (IsNull($estLWE.value) -or ($estLWE.value -lt $LWEdefault)) {
				# node is empty or out of window
				$numWarn++
				$e_message = "EST_License_Window_End is empty/null or in the past!"
				Write-Debug($e_message)
                Write-Debug ("estLWE is: $($estLWE.value)")
				Write-Log -filename $cfid -loglevel "W" -message $e_message
				$estLWE.Value = $LWEdefault
				Write-Host("Fixed EST_License_Window_End") -ForegroundColor Yellow
				Write-Log -filename $cfid -loglevel "W" -message "Setting EST_License_Window_End to: $($estLWE.Value)"
			} else {
				$numinfo++
				$e_message = "EST_License_Window_End is: $($estLWE.value)"
				Write-Debug($e_message)
				Write-Log -filename $cfid -loglevel "I" -message $e_message
			}
			
			
		# check if Licensing_Window_Start exist THEN check if its in the future... throw error if either are true
		# next, check for the EST_Licensing_Window_Start .. if it exist = set to $LWS
		# if it does not exist, build node and set to the $LWS
		Write-Debug("Checking License_Window_Start")
		if (!($LWS) -or (IsNull($LWS.value))) {
			$e_message = "License_Window_Start is MISSING or EMPTY!"
			$numError++
			Write-Host("$($e_message) Breaking out! {logged)") -ForegroundColor Red
			Write-Debug("LWS: $($LWS.value)")
			Write-Log -filename $cfid -loglevel "E" -message $e_message
			Write-Log -filename $cfid -loglevel "I" -message "LWS node/element: $($LWS)"
			Write-Log -filename $cfid -loglevel "I" -message "LWS value: $($LWS.value)"
			BREAK;
		} else {

			Write-Debug ("Licensing_Window_Start exist... Checking Date...")
			If ((Get-Date) -lt (Get-Date $LWS.Value)){
				# we are before the license start date. Advise and log
                $numWarn++
                $e_message = "License_Window_Start is in the Future (logged)"
				Write-Host($e_message) -ForegroundColor Yellow
                Write-Debug ("LWS is in the FUTURE. LWS is: $($LWS.Value)")
                $now = Get-Date
                Write-Log -filename $cfid -loglevel "W" -message $e_message
                Write-Log -filename $cfid -loglevel "I" -message "Today: $($now) <--> LWS: $($LWS.Value)"
                Write-Log -filename $cfid -loglevel "I" -message $e_message "Continuing on."
                
			}
			
			Write-Debug ("Checking EST_License_Window_Start")
			if (!($estLWS)){
                $numWarn++
                $e_message = "EST_Licensing_Window_Start is MISSING!! Building nodes..."
				Write-Debug ($e_message)
                Write-Log -filename $cfid -loglevel "W" -message $e_message
				$app_elem = $content.CreateElement("App_Data")
				$app_elem.SetAttribute("App","$type")
				$app_elem.SetAttribute("Name","EST_Licensing_Window_Start")
				$app_elem.SetAttribute("Value",$LWS.Value)
				$estLWS = $content.ADI.Asset.Metadata.InsertBefore($app_elem,$estLWE)
				Write-Debug ("Node complete.")
                Write-Log -filename $cfid -loglevel "W" -message "Node Built with value: $($LWS.Value)"
				Write-Host("Built EST_License_Window_Start") -ForegroundColor Yellow
			}
			
			if (IsNull($estLWS.Value) -or ($estLWS.Value -ne $LWS.Value)){
				# estLWE should equal LWS
				$e_message = "EST_License_Window_Start does not equal License_Window_Start"
				Write-Debug ("$($e_message)")
				Write-Debug ("EST_LWS is $($estLWS.Value)")
				Write-Log -filename $cfid -loglevel "W" -message $e_message
				Write-Log -filename $cfid -loglevel "W" -message "EST_LWS is: $($estLWS.Value) <--> LWS is: $($LWS.Value)"
				$estLWS.value = $LWS.value
				Write-Debug ("Changed EST_LWS to: $($estLWS.value)")
				Write-Log -filename $cfid -loglevel "W" -message "Set EST_LWS to $($estLWS.Value)"
				Write-Host("Changed EST_License_Window_Start") -ForegroundColor Yellow
			}
		}
		
		
		
		
        ######################################################################################################################################
        # HD Values
        ######################################################################################################################################
        If ($value.strscreenformat -like "*HLS_SM_HD*")
        {
			$e_message = "Removing unnecesarry HD nodes..."
			$numinfo++
			Write-Debug($e_message)
			Write-Log -filename $cfid -loglevel "I" -message $e_message
            $hd_variant = 1

            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_purchase_price"})
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_purchase_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed HD_Purchase_Price"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }
            }

            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}))
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed EST_Suggested_Price"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }
            }

            
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")})
            {

                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed MSV_Offer containing 'purchase'"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }


            }

            Write-Debug("Setting HD_Purchase_Price")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_purchase_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_purchase_price"}).Value = $hd_price
				
            }
            Else
            {
                $new_hd_rental_price = $content.CreateElement("App_Data")
                $new_hd_rental_price.SetAttribute("App",$type)
                $new_hd_rental_price.SetAttribute("Name","HD_Purchase_Price")
                $new_hd_rental_price.SetAttribute("Value",$hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_hd_rental_price))
            }
			
            Write-Debug("Setting EST_Suggested_Price (HD variant)")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}).Value = $hd_price
            }
            Else
            {
                $new_rental_price = $content.CreateElement("App_Data")
                $new_rental_price.SetAttribute("App",$type)
                $new_rental_price.SetAttribute("Name","EST_Suggested_Price")
                $new_rental_price.SetAttribute("Value",$hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_rental_price))
            }

			Write-Debug("Setting MSV_Offer (HD variant)")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")}).Value = "Purchase|||$" + $hd_price
            }
            Else
            {
                $new_msv_offer = $content.CreateElement("App_Data")
                $new_msv_offer.SetAttribute("App",$type)
                $new_msv_offer.SetAttribute("Name","MSV_Offer")
                $new_msv_offer.SetAttribute("Value","Purchase|||$" + $hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_msv_offer))
            }
            
			Write-Debug("Saving HD version xml")
            $content.Save($modified + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml")
			$numMod++
        }

        ######################################################################################################################################
        # SD Values
        ######################################################################################################################################
		
        If ($value.strscreenformat -like "*HLS_SM_SD*")
        {
			$e_message = "Removing unnecesarry SD nodes..."
			$numinfo++
			Write-Debug($e_message)
			Write-Log -filename $cfid -loglevel "I" -message $e_message
            $sd_variant = 1
           
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_purchase_price"})
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_purchase_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed SD_Purchase_Price"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }
            }

            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}))
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed EST_Suggested_Price"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }
            }

            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")})
            {

                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
					$e_message = "Removed MSV_Offer containing 'purchase'"
					$numinfo++
					Write-Debug($e_message)
					Write-Log -filename $cfid -loglevel "I" -message $e_message
                }


            }

            Write-Debug("Setting SD_Purchase_Price")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_purchase_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_purchase_price"}).Value = $sd_price
            }
            Else
            {
                $new_sd_rental_price = $content.CreateElement("App_Data")
                $new_sd_rental_price.SetAttribute("App",$type)
                $new_sd_rental_price.SetAttribute("Name","SD_Purchase_Price")
                $new_sd_rental_price.SetAttribute("Value",$sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_sd_rental_price))
            }
            
			Write-Debug("Setting EST_Suggested_Price (SD variant)")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "est_suggested_price"}).Value = $sd_price
            }
            Else
            {
                $new_rental_price = $content.CreateElement("App_Data")
                $new_rental_price.SetAttribute("App",$type)
                $new_rental_price.SetAttribute("Name","EST_Suggested_Price")
                $new_rental_price.SetAttribute("Value",$sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_rental_price))
            }

			Write-Debug("Setting MSV_Offer (SD variant)")
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*purchase*")}).Value = "Purchase|||$" + $sd_price
            }
            Else
            {
                $new_msv_offer = $content.CreateElement("App_Data")
                $new_msv_offer.SetAttribute("App",$type)
                $new_msv_offer.SetAttribute("Name","MSV_Offer")
                $new_msv_offer.SetAttribute("Value","Purchase|||$" + $sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_msv_offer))
            }
            
			Write-Debug("Saving SD version.")
            $content.Save($modified + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml") 
			$numMod++
        }
    }

    If ($hd_variant -eq 0)
    {
		$numMisHD++
		Write-Host("HD version not found!(logged)") -ForegroundColor Yellow
        Write-Log -filename $alt_code -loglevel "W" -message "The HD version was not found"
    }
	
    If ($sd_variant -eq 0)
    {
		$numMisSD++
		Write-Host("SD version not found!(logged)") -ForegroundColor Yellow
        Write-Log -filename $alt_code -loglevel "W" -message "The SD version was not found"
    }
    
   $numRuns++
}
Summarize
$SqlConnection.Close()