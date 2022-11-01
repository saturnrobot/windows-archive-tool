<#
Run as admin

This is a tool to perform basic file moving commands and mainly for backing up and merging data
#>

param (
	[parameter(mandatory = $true)][string]$srcDir,
	[parameter(mandatory = $true)][string]$dstDir,
	[string]$logdir = "C:\logs\archivescript\"
)

# Check if log directory exists and make sure it can at least be created before doing anything
if (!(test-path -path $logdir)) {
	if (!(new-item -itemtype directory -force -path $logdir)) {
		throw "Could not create log directory"
		exit 1
	}
}

# Prepares a directory path for use in this script (triming and getting full path)
function preparePath([string]$dir) {

	# Windows network shares have this in front of them some times
	$pText = "Microsoft.PowerShell.Core\FileSystem::"
	if ($dir.startswith($pText)) {
		$dir = $dir.substring($pText.length, $dir.length - $pText.length)
	}
	return $dir.trimend("\").trimend("/") | resolve-path
}

# Prepare paths for use by program (trim slashes and verify/get absolute path)
$srcDir = preparePath($srcDir)
$dstDir = preparePath($dstDir)
$logdir = preparePath($logdir)

# set up log paths to variables
$mainlogname = "archivescript.log"
$mainlog = "$logdir\$mainlogname"
$mergeconflictdir = "$logdir\mergeconflictfiles"

#Wait for input without message
function nullpause {
	[void][System.Console]::ReadKey($FALSE)
}

<#
Write to log and screen
message: Takes a message to write out
quiet: print to screen or not
logfile: where to send ouput
level: log level to print beside message
exitf: throw and error and exit
#>
function write-out {
	param(
		[parameter(mandatory = $true)][string]$message,
		[parameter(mandatory = $false)][boolean]$quiet = $false,
		[parameter(mandatory = $false)][string]$logfile = $mainlog,
		[parameter(mandatory = $false)][validateset("INFO", "WARN", "ERROR")][string]$level = "INFO",
		[parameter(mandatory = $false)][boolean]$exitf = $false
	)

	if ($logfile) {
		$tstamp = (get-date).tostring("yyyy/MM/dd HH:mm:ss")
		$finalMessage = "$tstamp $level $message"
		add-content $logfile -value $finalMessage
	}
	if ($exitf) {
		throw $message
	}
	if (!$quiet) {
		write-output $message
	}
}

# Just print out menu
function show-menu {
	param (
		[string]$title = 'Windows Archive Script'
	)
	clear-host
	write-host "================ $title ================"
	write-host "Main log location: $mainlog"
	write-host "Source/New directory: $srcDir"
	write-host "Destination/Original directory: $dstDir"
	write-host ""
	write-host "[1]: Merge two directories"
	write-host "[2]: Diff two directories"
	write-host "[3]: Backup two directories"
	write-host "[4]: Check for merge errors"
	write-host "[5]: Change source directory"
	write-host "[6]: Change destination directory"
	write-host "[q]: Quit this menu"
}

<#
Prompt for yes or no
prompt: prompt message
t: default check mainly for changing the default value
#>
function promptYN([string]$prompt = "Continue? [y/N]", [validateset("y", "n")][string]$t = "y") {
	return $(read-host $prompt).tolower() -eq $t
}

<# 
Read directory fron user and prepare it
prompt: message to user on input
create: enable ask to create file if it exists or not
#>
function promptDir([string]$prompt, [boolean]$create = $false) {
	$dir = read-host -prompt $prompt
	if (test-path -path $dir) {
		return preparePath($dir)
	}
	if ($create) {
		write-host -f yellow "Directory does not exist!"
		if (promptYN "Create it? [y/N]") {
			if (new-item -itemtype directory -force -path $dir) {
				return $dir
			}
		}
	}
	write-out "$dir does not exist!" $false $mainlog "ERROR" $true
}

<#
Merge source directory in to destination directory
Dry run will run command without actually modifying any files
#>
function merge {
	<#
	Robocopy arguments
	/xo if destination file exists and is the same date or newer than source dont overwrite it
	/xx dont delete extra files from destination
	/e copy all subfolders
	/b run in backup mode
	/copyall copy all file attributes
	/r:0 set number of retries to 0
	/w:0 set wait time between retries to 0
	/log+ append to log file
	/nfl dont list files (speeds up command)
	/ndl dont list directories (speeds up command)
	#>
	$arguments = "/xo /xx /e /b /copyall /r:0 /w:0 /log+:$mainlog /nfl /ndl"
	if (!(promptYN "Run test merge? [Y/n]" "n")) {
		write-out "Dry run of merge of $srcDir into $dstDir"
		invoke-expression "robocopy $srcDir $dstDir /l $arguments" 
		write-out "Done dry run of merge of $srcDir into $dstDir"
		pause
		return
	}
	write-out "Merging $srcDir into $dstDir"
	pause
	invoke-expression "robocopy $srcDir $dstDir $arguments"
	write-out "Done merge of $srcDir into $dstDir"
	pause
}

<# 
run diff command between entire directory and output results to archivescriptdiff.txt in the logdir 
#>
function diff {
	write-out "Running diff between $dstDir and $srcDir"
	$refFiles = get-childitem -path $dstDir -recurse -file
	$difFiles = get-childitem -path $srcDir -recurse -file
	compare-object -referenceobject $refFiles -differenceobject $difFiles | set-content "$logdir\archivescriptdiff.txt"
	write-out "Output of diff wrote to $logdir\archivescriptdiff.txt"
	pause
}

<#
Check for files on source that are bigger but older than files on destination
Commented out code contains examples of different strategies which might help for creating a more generic solution
For the sake of speed this script assumes that destination and source files have same path names
#>
function errorDiff {
	# Refrence (ref) would be the original file and Difference (dif) would be the new file
	write-host "Merge errors. Checking for files on source that are bigger but older than files on destination"
	write-out "Checking for merge errors between orignial $dstDir to new $srcDir"
	$pattern = "[\\\/]Changed[\\\/]"
	# Using get child item, this is the slowest but it is using proper powershell cmdlets
	<#
	$refFiles = get-childitem -path "$dstDir" -recurse -force -file | where-object name -notmatch $pattern
	$difFiles = get-childitem -path "$srcDir" -recurse -force -file | where-object name -notmatch $pattern
	$sameObjects = compare-object -referenceobject $refFiles -differenceobject $difFiles -includeequal -excludedifferent -passthru
	#>
	
	# Using robocopy this is faster but not as fast as dir
	<#
	(robocopy $dstDir null /l /s /njh /njs /nc /ns /ndl /xj /r:0 /w:0 | findstr /v /i $pattern | findstr /r /v "^$").replace("$dstDir\", "").trim() | set-content "$logdir\reffiles.txt"
	(robocopy $srcDir null /l /s /njh /njs /nc /ns /ndl /xj /r:0 /w:0 | findstr /v /i $pattern | findstr /r /v "^$").replace("$srcDir\", "").trim() | set-content "$logdir\diffiles.txt"
	$sameObjects = compare-object -referenceobject (get-content "$logdir\reffiles.txt") -differenceobject (get-content "$logdir\diffiles.txt") -includeequal -excludedifferent -passthru
	# Test robocopy
	#write-output (robocopy $srcDir null /l /s /njh /njs /nc /ns /ndl /xj /r:0 /w:0 | findstr /v /i $pattern | findstr /r /v "^$").replace("$srcDir\", "").trim()
	#>
	
	# Quick and dirty robocopy (use with quick loop)
	<#
	(robocopy $srcDir null /l /s /njh /njs /nc /ns /ndl /xj /r:0 /w:0 | findstr /v /i $pattern | findstr /r /v "^$").replace("$srcDir\", "").trim() | set-content "$logdir\diffiles.txt"
	#>
	
	# Fast dir clean
	<#
	(./listcreate.bat "$srcDir" "$pattern").replace("$srcDir\", "").trim() | select -skip 2 | set-content "$logdir\diffiles.txt"
	(./listcreate.bat "$dstDir" "$pattern").replace("$dstDir\", "").trim() | select -skip 2 | set-content "$logdir\reffiles.txt"
	$sameObjects = compare-object -referenceobject (get-content "$logdir\reffiles.txt") -differenceobject (get-content "$logdir\diffiles.txt") -includeequal -excludedifferent -passthru
	#>
	
	# Start process approach may allow cmd more ram but requires more read and writes
	<#
	start-process -filepath ".\listcreate.bat" -argumentlist "$srcDir $pattern" -wait -nonewwindow -redirectstandardoutput "$logdir\diffilesraw.txt"
	(get-content "$logdir\diffilesraw.txt").replace("$srcDir\", "").trim() | set-content "$logdir\diffiles.txt"
	remove-item "$logdir\diffilesraw.txt"
	start-process -filepath ".\listcreate.bat" -argumentlist "$dstDir $pattern" -wait -nonewwindow -redirectstandardoutput "$logdir\reffilesraw.txt"
	(get-content "$logdir\reffilesraw.txt").replace("$dstDir\", "").trim() | set-content "$logdir\reffiles.txt"
	remove-item "$logdir\reffilesraw.txt"
	$sameObjects = compare-object -referenceobject (get-content "$logdir\reffiles.txt") -differenceobject (get-content "$logdir\diffiles.txt") -includeequal -excludedifferent -passthru
	#>
	
	# Quick and dirty dir
	
	#$sameObjects = (./listcreate.bat "$srcDir" "$pattern").replace("$srcDir\", "").trim() | select -skip 2
	
	<#foreach ($file in $sameObjects) {

		$ref = "$dstDir\$file"
		if (!(test-path -path $ref)) { continue }
		if (test-path -path "$ref" -pathtype container) { continue }

		$dif = "$srcDir\$file"
		
		if ((get-filehash -path "$ref" -algorithm MD5).hash -eq (get-filehash -path "$dif" -algorithm MD5).hash) { continue }
		
		#Item on backup
		$refItem = get-item "$ref"
		#Item on fragment
		$difItem = get-item "$dif"
		
		if (((get-date $refItem.lastwritetime) -ge (get-date $difItem.lastwritetime)) -and ($refItem.length -lt $difItem.length)) {
			$f = split-path "$mergeconflictdir\$file" -parent
			if (!(test-path -path $f)) {
				new-item -itemtype directory -force -path $f | out-null
			}
			write-out "Merge issue with $ref and $dif"
			$refDest = "$mergeconflictdir\$file".trimend($refItem.extension) + "_original$($refItem.extension)"
			$difDest = "$mergeconflictdir\$file".trimend($difItem.extension) + "_merge$($difItem.extension)"
			copy-item "$ref" "$refDest" -force
			copy-item "$dif" "$difDest" -force
		}
		#write-host "$refItem $(get-date $refItem.lastwritetime) $($refItem.length)"
		#write-host "$difItem $(get-date $difItem.lastwritetime) $($difItem.length)"
	}#>
	
	# Quick and dirty fast read
	# This method assumes that the dif files will have the same paths as the ref files
	start-process -filepath ".\listcreateout.bat" -argumentlist "$srcDir $pattern `"$logdir\diffiles.txt`"" -wait -nonewwindow
	[System.IO.StreamReader]$sr = [System.IO.File]::Open("$logdir\diffiles.txt", [System.IO.FileMode]::Open)
	while (-not $sr.EndOfStream) {
		# Make line generic so respective paths can be created
		$file = $sr.ReadLine().remove(0, ($srcDir.length) + 1)
		$ref = "$dstDir\$file"
		# These check if the files exists or is a directory really not needed just for worst case fail safe if the files are chaning when running
		if (!(test-path -path $ref)) { continue }
		if (test-path -path "$ref" -pathtype container) { continue }

		$dif = "$srcDir\$file"
		
		# If the files are the same move on to next one
		if ((get-filehash -path "$ref" -algorithm MD5).hash -eq (get-filehash -path "$dif" -algorithm MD5).hash) { continue }
		
		#Item on backup
		$refItem = get-item "$ref"
		#Item on fragment
		$difItem = get-item "$dif"
		
		# Check if fragment item is older and bigger
		if (((get-date $refItem.lastwritetime) -ge (get-date $difItem.lastwritetime)) -and ($refItem.length -lt $difItem.length)) {
			# Create directory as if it was a mirror to put merge conflicts
			$f = split-path "$mergeconflictdir\$file" -parent
			if (!(test-path -path $f)) {
				new-item -itemtype directory -force -path $f | out-null
			}
			write-out "Merge issue with $ref and $dif"
			# Name files they dont overwrite eachother
			$refDest = "$mergeconflictdir\$file".trimend($refItem.extension) + "_original$($refItem.extension)"
			$difDest = "$mergeconflictdir\$file".trimend($difItem.extension) + "_merge$($difItem.extension)"
			# Copy it over to newly created merge conflict directory
			copy-item "$ref" "$refDest" -force
			copy-item "$dif" "$difDest" -force
		}
	}
	$sr.Close()
	write-out "Merge error check complete! Merge errors copied to $mergeconflictdir"
	pause
}

<# 
Copy a full mirror of source into destination removing destination files not in source
#>
function backup {
	<#
	Robocopy arguments
	/copyall copy all file attributes
	/b run in backup mode
	/mir bothe /purge and /e
	/e copy all subfolders
	/purge remove files from destination that arent in source
	/r:0 set number of retries to 0
	/w:0 set wait time between retries to 0
	/log+ append to log file
	/nfl dont list files (speeds up command)
	/ndl dont list directories (speeds up command)
	#>
	$arguments = "/copyall /b /mir /r:0 /w:0 /log+:$mainlog /nfl /ndl"
	write-host -foregroundcolor yellow "This will make a perfect copy of source into destination removing files in destination that are not in source (Press Ctrl C to abort)"
	if (!(promptYN "Run test backup? [Y/n]" "n")) {
		write-out "Dry run of backup of $srcDir into $dstDir"
		invoke-expression "robocopy $srcDir $dstDir /l $arguments" 
		write-out "Done dry run of backup of $srcDir into $dstDir"
		pause
		return
	}
	write-out "Backing up $srcDir into $dstDir"
	pause
	invoke-expression "robocopy $srcDir $dstDir $arguments"
	write-out "Done backup of $srcDir into $dstDir"
	pause
}

function main {
	
	# Test necessary paths they must be valid to continue
	
	if (!(test-path -path $mainlog)) {
		if (!(new-item -itemtype file -force -path $mainlog)) {
			throw "Could not create log file"
			exit 1
		}
	}

	if (!(test-path -path $mergeconflictdir)) {
		new-item -itemtype container -force -path $mergeconflictdir
	}

	if (!(test-path -path $srcDir)) {
		throw "$srcDir does not exist"
	}

	if (!(test-path -path $dstDir)) {
		throw "$dstDir does not exist"
	}
	
	# Start of main loop

	write-out "Script started"

	:mainLoop while ($true) {
		show-menu
		switch (read-host "Operation") {
			'1' { merge; Break }
			'2' { diff; Break }
			'3' { backup; Break }
			'4' { errorDiff; Break }
			'5' { $srcDir = promptDir "Enter source/new directory"; Break }
			'6' { $dstDir = promptDir "Enter destination/original directory"; Break }
			'q' { Break mainLoop }
			default { write-host -f red "Invalid input!"; nullpause }
		}
	}
	write-out "Script quit"
}

main
