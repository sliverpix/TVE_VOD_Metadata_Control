####################################################################
# This scrips downloads pulls ADI files out of the DB for
# Alt_Codes provided in UpdatePrices_Promo_Rentals.txt file
# and updates the SD/HD prices to $2.99/$3.99
# 
#
# Name:     UpdatePrices_Promo_Rentals.ps1
# Authors:  James Griffith
# Version:  2.0.1
# History:  https://github.com/sliverpix/TVE_VOD_Metadata_Control/
#
####################################################################

	# Write-Debug -- this might work
	#uncomment preference to turn on/off output
	$DebugPreference = "SilentlyContinue"
	#$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")

# ### set our variables first ### #

# point to our input input file for targeted asset processing
Switch ($DebugPreference){
	"SilentlyContinue"	{	
							$input_txt_file = "C:\vodscripts\UpdatePrices_Promo_Rentals.txt"
							$work_directory = "C:\vodscripts\_PromoPrices_Rentals\"
	}
	"Continue"			{	$input_txt_file = "C:\vodscripts\testlist.inc"
							$work_directory = "C:\vodscripts\_PromoPrices_Rentals\_Testing\"
	
	}
	default				{	Write-Host "Debug broke! Input file and work directory not set!" -ForegroundColor RED
							EXIT;
	
	}
}

# hard code our SD/HD price values
$sd_price = "2.99"
$hd_price = "3.99"

# set our variables
$alt_codes = Get-Content $input_txt_file
$daily_directory = (Get-Date).ToString('MMddyyyy')
$originals = $work_directory + $daily_directory + "\Originals"
$modified = $work_directory + $daily_directory + "\Modified"
$reviewD = $work_directory + $daily_directory + "\Review"

# set the log file
$logfile = "logfile.txt"
$tolog = $work_directory + $daily_directory + "\" + $logfile

$numRuns = [int] 0
$erro = [int] 0
$warn = [int] 0
$info = [int] 0


# file/directory check/create
If (!(Test-Path -Path $originals ))
{
    New-Item -Path $originals -ItemType directory
}

If (!(Test-Path -Path $modified ))
{
    New-Item -Path $modified -ItemType directory
}

If (!(Test-Path -Path $reviewD ))
{
    New-Item -Path $reviewD -ItemType directory
}


If(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}



# ## FUNCTIONS ## #
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
	Write-Host $numError -Foreground Red
	Write-Host -NoNewline "WARNings Logged				.....	"
	Write-Host $numWarn -Foreground Yellow
	Write-Host -NoNewline "Number of Type 1 matches	.....	"
	Write-Host $numType1 -Foreground Green
	Write-Host -NoNewline "Number of Type 2 matches	.....	"
	Write-Host $numType2 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 3 matches	.....	"
	Write-Host $numType3 -ForegroundColor Green
	Write-Host -NoNewline "Number of Type 4 matches	.....	"
	Write-Host $numType4 -ForegroundColor Yellow
}

# ##### MAIN BODY ##### #

# Db connection NFO
$SQLServer = 'MSVTXCAWDPV01\MSVPRD01' #use Server\Instance for named SQL instances! 
$SQLDBName = 'ProvisioningWorkFlow'


Foreach ($alt_code in $alt_codes)
{
    $hd_variant = 0
    $sd_variant = 0
      
    $SqlQuery = "SELECT strscreenformat, xmlContent
    FROM [ProvisioningWorkFlow].[Pro].[tAssetInputXML]
    where strContentItemID = '$alt_code' and strscreenformat like '%HLS_%'"

    # connect to our DB
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
	Write-Host("$($alt_code) :: Processing ...")

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
	
	# isReview flag to tell us when to save xml to \Review\ directory
	$isReview = 0
	
   
    Foreach ($value in $DataSet.Tables[0])
    {
		# save our ORIGINAL metadata
		[void]($content = [xml]($value.xmlContent))
		$xml_filename = ($alt_code + "_" + $value.strscreenFormat + ".xml")

		# setup our HD/SD dependant values/variables
		Switch -wildcard ($value.strScreenFormat) {
			"*_HD" { 
						Write-Host("... $($value.strscreenformat) meta")
						Write-Log $xml_filename "I" "Found HD metadata. Processing ..."
						$msvFound = 1
						$hd_variant = 1
						$newRentalPrice = $hd_price

						BREAK;
			}
			"*_SD" {
						Write-Host("... $($value.strscreenformat) meta")
						Write-Log $xml_filename "I" "Found SD metadata. Processing ..."
						$msvFound = 1
						$sd_variant = 1
						$newRentalPrice = $sd_price

						BREAK;
			}
			default {
						Write-Log $xml_filename "E" "No XML meta was found. Is this it he right Asset ID?"
						Write-Host("NO XML META FOUND!") -ForegroundColor Red
						BREAK;
			}
		}
		
		# catch Asset Id duplication in our input file.
		# if we already have the original filename - break out
		# otherwise lets save it and coninue on.
		# $content.Save($original + "\" + $xml_filename)
		
        $orgcheck = gci $originals -Name -File

        if($orgcheck -contains $xml_filename){
            Write-Debug "Found a DUPE! ... $($xml_filename)"
            Write-Log $xml_filename "W" "Found duplicate file for $($xml_filename)... Skipping!)"
            #write-Host("Duplicate file found ORIGINAL directory... skipping $($xml_filename)") -ForegroundColor Yellow
            BREAK;
        } else {
            $content.Save($originals + "\" + $xml_filename)
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
		$app_Title = ($class_title.App_Data | Where-Object {$_.Name -eq "Title"})
		$app_SuggestedPrice = ($class_title.App_Data | Where-Object {$_.Name -eq "suggested_price"})
		# $app_HDSD_RentalPrice = ($class_title.App_Data | Where-Object {$_.Name -eq $rentalNodeName})
		# $app_RentalPrice = ($class_title.App_Data | Where-Object {$_.Name -eq "rental_price"})
		# $app_MSVOffer = ($class_title.App_Data | Where-Object {($_.Name -eq "msv_offer") -and ($_.value -like "*rent*")})		# we only want the offer for rentals
		$app_Rental = ($class_title.App_Data | Where-Object {$_.Name -eq "Rental"})
		$app_LWS = ($class_title.App_Data | Where-Object {$_.Name -eq "Licensing_Window_Start"})
		$app_LWE = ($class_title.App_Data | Where-Object {$_.Name -eq "Licensing_Window_End"})
		
		
		
		# ### START MAIN LOGIC ### #
		
		# NODE CHECK
		
		# Rental Node
		if(!($app_Rental)){
			
			# node missing
			Write-Debug "MISSING Node: Rental ..."
			
			# build it
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Rental")
			$app_elem.SetAttribute("Value","Y")	
			$app_Rental = $class_title.AppendChild($app_elem)
			
			Write-Host "Rental Node built." -ForegroundColor Green
			Write-Log $xml_filename "W" "Rental node was missing. Built node and set to 'Y'."
			
		} else {
		
			# node found ... check value and/or set
            Write-Debug "FOUND $($app_Rental.Name) ..."
            Write-Log $xml_filename "I" "Rental node found with value: $($app_Rental.Value)"

			if ($app_Rental.value -ne "Y") {
				Write-Host -NoNewline "Rental value changed from $($app_Rental.value) --> " -ForegroundColor Yellow
				$app_Rental.value = "Y"
				Write-Host "$($app_Rental.value)" -ForegroundColor Green
                Write-Log $xml_filename "I" "changed Rental node value to: $($app_Rental.Value)"
			}
		}
		
		# Suggested_Price Node
		if(!($app_SuggestedPrice)){
			
			# node missing
			Write-Debug "MISSING Node: Suggested_Price ..."
			
			# build it
			$app_elem = $content.CreateElement("App_Data")
			$app_elem.SetAttribute("App","$($AMS_product)")
			$app_elem.SetAttribute("Name","Suggested_Price")
			$app_elem.SetAttribute("Value","$($newRentalPrice)")
			$app_SuggestedPrice = $class_title.AppendChild($app_elem)
			
			Write-Host "Built $($app_SuggestedPrice.Name) node." -ForegroundColor Green
            Write-Log $xml_filename "W" "Suggested_Price node missing. Built node and set value: $($app_SuggestedPrice.value)"
			
		} else {
		    Write-Debug "FOUND $($app_SuggestedPrice.Name) ..."
            Write-Log $xml_filename "I" "Found $($app_SuggestedPrice.Name) with value: $($app_SuggestedPrice.Value)"

			# node found ... check value and/or set
			if($app_SuggestedPrice.value -ne $newRentalPrice){
				$app_SuggestedPrice.value = $newRentalPrice
				Write-Host "Changed $($app_SuggestedPrice.Name) to $($app_SuggestedPrice.value)" -ForegroundColor Green
                Write-Log $xml_filename "I" "Changed $($app_SuggestedPrice.Name) to $($app_SuggestedPrice.value)"
			}
			
		}
		
		# Licensing_Window_Start Node
		if(!($app_LWS)){
			# Node missing
			Write-Host "MISSING Node: Licensing_Window_Start. Check the REVIEW directory for $($xml_filename)" -ForegroundColor Red
            Write-Log $xml_filename "E" "Licensing_Window_Start is missing! copy of metadata saved to \Review\ with filename $($xml_filename)"
            Write-Log $xml_filename "E" "Check for mispellings in node name, improperly formated date value, or missing node."
            Write-Log $xml_filename "E" "Breaking out and moving to next asset."

            #save modified version in \Review\
	    	$isReview++
		
		} else {
			# Found node
			Write-debug "Found $($app_LWS.Name)"
			Write-Log $xml_filename "I" "Found $($app_LWE.Name) with value: $($app_LWE.Value)"
			
			# recast value from string to Date-Time
			[DateTime]$dt_LWS = $app_LWS.value
			$today = Get-Date
            $newLWS = $today.AddDays(-1)

            # if LWS is not at least yesterday or later raise error and save to \REVIEW\
            if(!($dt_LWS -lt $today)){
                # $isReview++

                Write-Debug "$($app_LWS.Name) [$($app_LWS.Value)] is NOT LESS THAN $($today)"
                Write-Log $xml_filename "W" "$($app_LWS.Name) [$($app_LWS.Value)] is NOT LESS THAN $($today)"

                # set the LWS value to yesterday
                $app_LWS.Value = $newLWS

                Write-Debug "Set $($app_LWS.Name) to $($app_LWS.Value)"
                Write-Log $xml_filename "W" "Set $($app_LWS.Name) to $($app_LWS.Value)"

            } else {
                Write-Debug "$($app_LWS.Name) is in the past."
            }
			
		}
		
		
		# Licensing_Window_End Node
		if(!($app_LWE)){
			# Node MISSING
			Write-Host "MISSING Node: EST_Licensing_Window_End. Check the REVIEW directory for $($xml_filename)" -ForegroundColor Red
            Write-Log $xml_filename "E" "EST_Licensing_Window_End is missing! copy of metadata saved to \Review\ with filename $($xml_filename)"
            Write-Log $xml_filename "E" "Check for mispellings in node name, improperly formated date value, or missing node."
            Write-Log $xml_filename "E" "Breaking out and moving to next asset."

            #save modified version in \Review\
	    	$isReview++
			
		} else {
            Write-Debug "FOUND $($app_LWE.Name) ..."
            Write-Log $xml_filename "I" "Found $($app_LWE.Name) with value: $($app_LWE.Value)"

			# Node Found
			[DateTime]$dt_LWE = $app_LWE.value
			$today = Get-Date
            $newLWE = $today.AddDays(7)
			
			# is LWE more than 7 days in the future
			if($dt_LWE -gt ($today+7)){
				Write-Debug "$($app_LWE.Name) is MORE than 7 days in the future"
                Write-Log $xml_filename "I" "$($app_LWE.Name) is MORE than 7 days in the future"
			} else {
				Write-Host -NoNewline "$($app_LWE.Name) [$($app_LWE.value)] changed to " -ForegroundColor Red

                $app_LWE.value = [string]$newLWE

                Write-Host -NoNewline "--> " -ForegroundColor Yellow
                Write-Host "$($app_LWE.Value)" -ForegroundColor Green

                Write-Log $xml_filename "W" "$($app_LWE.Name) was less than 7 days in the future."
                Write-Log $xml_filename "W" "changed value to: $($app_LWE.Value)"
			}
		}
		
	
		# done processing and moving to next asset
		if($isReview -ge 1){
			Write-Debug "Saving $($xml_filename) to $($reviewD)"
			Write-Log $xml_filename "I" "Unknown warnings or errors found."
			Write-Log $xml_filename "I" "Saving $($xml_filename) to $(reviewD) for review."
			$content.Save($reviewD + "\" + $xml_filename)
		}
		
		if($msvFound -eq 1){
			Write-Host("Processing complete. Saving changes to $($modified)")
			
			#save modified version -- this in the right place?
			$numMod++
			$content.Save($modified + "\" + $xml_filename)
			
		} else {
			Write-Host("AssetID was not found in MSV!") -ForegroundColor Red
		}	
	}
}

$SqlConnection.Close()