####################################################################
# This scrips downloads pulls ADI files out of the DB for
# Alt_Codes provided in UpdatePrices_Promo_Rentals.txt file
# and updates the SD/HD prices to $2.99/$3.99
# 
#
# Name:     UpdatePrices_Promo_Rentals.ps1
# Authors:  Elena Raines
# Version:  1.1
# History:  02-14-17 - Initial release
#			02-07-18 - [Griffith] add processing functions from my
#						library to keep better track of of this
#						scripts work
#
####################################################################

	# Write-Debug -- this might work
	#uncomment preference to turn on/off output
	#$DebugPreference = "SilentlyContinue"
	$DebugPreference = "Continue"
	Write-Debug("DEBUG ACTIVE!")

# ### set our variables first ### #

# point to our input input file for targeted asset processing
$input_txt_file = "C:\vodscripts\UpdatePrices_Promo_Rentals.txt"
$alt_codes = Get-Content $input_txt_file

$work_directory = "C:\vodscripts\_PromoPrices_Rentals\"
$originals = $work_directory + (Get-Date).ToString('MMddyyyy’) + "\Originals"
$modified = $work_directory + (Get-Date).ToString('MMddyyyy’) + "\Mofied" 
$failure_log_file = $work_directory + (Get-Date).ToString('MMddyyyy’) + "\FailureLogFile.txt"

# set the log file
$logfile = "logfile.txt"
$tolog = $work_dir + $daily_directory + "\" + $logfile

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

If (Test-Path $failure_log_file)
{
	Remove-Item $failure_log_file
}

If(!(Test-Path -Path $tolog)){
    New-Item -Path $tolog -ItemType File
    Write-Debug ("New log file created!")
}

# hard code our SD/HD price values
$sd_price = "2.99"
$hd_price = "3.99"

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
    param ($filename, $message)
	$datetime = (Get-Date).ToString('MM-dd-yyyy hh:mm:ss')
    Add-Content $tolog ($datetime + "::" + $filename + " | " + $message)
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
    where strContentItemID = '$alt_code'"

    
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = "Server = $SQLServer; Database = $SQLDBName; Integrated Security = True"
 
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
 
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter

    $SqlAdapter.SelectCommand = $SqlCmd
 
    $DataSet = New-Object System.Data.DataSet
    [void]($SqlAdapter.Fill($DataSet))
   
    Foreach ($value in $DataSet.Tables[0])
    {
        
        ######################################################################################################################################
        # HD Values
        ######################################################################################################################################
        If ($value.strscreenformat -like "*HLS_SM_HD*")
        {
            $hd_variant = 1
            [void]($content = [xml]($value.xmlContent))
            $content.Save($originals + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml")
            [void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)



            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"})
            {
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }
            
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_rental_price"})
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_rental_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }

            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}))
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }

            
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")})
            {
   
                $old_offer = ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")}).Value.Split("|")
                $days = $old_offer[1]
                $hours = $old_offer[2]

                $msv_offer = "Extended Rent|" + $days + "|" + $hours + "|`$3.99"
                [void](($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")}).Value = $msv_offer)


            }

            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"}).Value = $hd_price
            }
            Else
            {
                $new_suggested_price = $content.CreateElement("App_Data")
                $new_suggested_price.SetAttribute("App",$type)
                $new_suggested_price.SetAttribute("Name","Suggested_Price")
                $new_suggested_price.SetAttribute("Value",$hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_suggested_price))
            }
            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_rental_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "hd_rental_price"}).Value = $hd_price
            }
            Else
            {
                $new_hd_rental_price = $content.CreateElement("App_Data")
                $new_hd_rental_price.SetAttribute("App",$type)
                $new_hd_rental_price.SetAttribute("Name","HD_Rental_Price")
                $new_hd_rental_price.SetAttribute("Value",$hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_hd_rental_price))
            }
            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}).Value = $hd_price
            }
            Else
            {
                $new_rental_price = $content.CreateElement("App_Data")
                $new_rental_price.SetAttribute("App",$type)
                $new_rental_price.SetAttribute("Name","Rental_Price")
                $new_rental_price.SetAttribute("Value",$hd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_rental_price))
            }
            
             $content.Save($modified + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml")

        }

        ######################################################################################################################################
        # SD Values
        ######################################################################################################################################
        If ($value.strscreenformat -like "*HLS_SM_SD*")
        {
            $sd_variant = 1
            [void]($content = [xml]($value.xmlContent))
            $content.Save($originals + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml")
            [void]($type = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "title"}).App)



            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"})
            {
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }
            
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_rental_price"})
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_rental_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }

            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}))
            {
            
                $node = ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"})
                Foreach ($n in $node)
                {
                    [void]($n.ParentNode.RemoveChild($n))
                }
            }

            
            If ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")})
            {
   
                $old_offer = ($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")}).Value.Split("|")
                $days = $old_offer[1]
                $hours = $old_offer[2]

                $msv_offer = "Extended Rent|" + $days + "|" + $hours + "|`$2.99"
                [void](($content.ADI.Asset.Metadata.App_Data | Where-Object {($_.Name.ToLower() -eq "msv_offer") -and ($_.Value.ToLower() -like "*rent*")}).Value = $msv_offer)


            }

            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "suggested_price"}).Value = $sd_price
            }
            Else
            {
                $new_suggested_price = $content.CreateElement("App_Data")
                $new_suggested_price.SetAttribute("App",$type)
                $new_suggested_price.SetAttribute("Name","Suggested_Price")
                $new_suggested_price.SetAttribute("Value",$sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_suggested_price))
            }
            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_rental_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "sd_rental_price"}).Value = $sd_price
            }
            Else
            {
                $new_sd_rental_price = $content.CreateElement("App_Data")
                $new_sd_rental_price.SetAttribute("App",$type)
                $new_sd_rental_price.SetAttribute("Name","SD_Rental_Price")
                $new_sd_rental_price.SetAttribute("Value",$sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_sd_rental_price))
            }
            
            If (($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}).Value )
            { 
                ($content.ADI.Asset.Metadata.App_Data | Where-Object {$_.Name.ToLower() -eq "rental_price"}).Value = $sd_price
            }
            Else
            {
                $new_rental_price = $content.CreateElement("App_Data")
                $new_rental_price.SetAttribute("App",$type)
                $new_rental_price.SetAttribute("Name","Rental_Price")
                $new_rental_price.SetAttribute("Value",$sd_price)
                [void]($content.ADI.Asset.Metadata.AppendChild($new_rental_price))
            }
            
             $content.Save($modified + "\" + $alt_code + "_" + $value.strscreenFormat + ".xml") 

        }
    }

    If ($hd_variant -eq 0)
    {
        Add-Content $failure_log_file "$alt_code : the HD version was not found"
      
    }
    If ($sd_variant -eq 0)
    {
        Add-Content $failure_log_file "$alt_code : the SD version was not found"
      
    }
    
    
}
$SqlConnection.Close()
