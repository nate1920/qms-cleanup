# Find user using old qms, create file with AD location, username to begin

# REQUIREMENTS:
#	PsTerminalServices Module (https://psterminalservices.codeplex.com/)
#	ActiveDirectory Module
#	CSV from KBox imported to git repo
#	Run as Admin
ipmo PSTerminalServices
ipmo ActiveDirectory

# server variables
$svrprefix = "input prefix for servers if you have one, input * if not"
$svrOU = "Full Path to OU in AD (e.g. OU=Demo,DC=Test,DC=Local)"

# pull list of server names from AD location that match wildcard
$comps = get-adcomputer -Filter * -SearchBase $svrOU | `
    where { $_.DNSHostName -like $svrprefix } | select -Exp DNSHostName

$users = ""

echo ""
echo "SERVERS searched:"
echo "-------------"
# loop through servers to return active user session usernames
foreach ($comp in $comps) {
    echo $comp

        # if it's the first in the list we need to create the variable initially--after that we add to it
        if ($comp -like $comps[0]) {
            $users = @(get-tssession -computername $comp -erroraction SilentlyContinue -state active | select -Exp Username)
        }
        else { 
            $users = @($users + (get-tssession -computername $comp -ErrorAction SilentlyContinue -state active | select -Exp Username))
        }
}

# strip empty values from users array, shouldn't be any with -state active, but who knows
$users = $users | ? {$_}

# much of output goes to shell, but didn't seem necessary to put all in txt files
echo ""
echo "USERS using old TS:"
echo "----------"
echo "There are " $users.count " users."
echo $users

<# / optional section to check if users are in appropriate OU (for GPO purposes for us)
$newOU = "String Containing Name of New OU, can use Wildcards"

echo ""
echo "USERS not in New OU:"
echo "-----------"
# loop through usernames to find locations in AD
foreach ($user in $users) {
    get-aduser $user | where { $_.DistinguishedName -notlike $newOU } | select -exp DistinguishedName
}
end optional section / #>

# asks you if you want to run cleanup on their machines and alert them on old TS
$cleanup = Read-Host "Do you wish to run the cleanup? (y/n)"

# message that will be sent to users on old farm, make it short.
$message = "Please log out or be terminated."

# msg all users of old TS to log out of old servers and onto new
foreach ($comp in $comps) { msg * /server:$comp $message }


if ($cleanup -eq 'y') {
# PHASE TWO
#	run the cleanup script on users using old terminal server

# remove old text files so we don't append irrelevant data
remove-item fails.txt
remove-item success.txt
remove-item badfiles.txt

# get content from kbox csv file (in git repo)
$kbox = import-csv computer_inventory.csv | select Name,"User Domain"

# NOTE: if you use another comp inventory system, you'll have to edit the hash value below
$csvuser = $_."User Domain"

# primary loop to search csv for name and return comp name (dforget append)
foreach ($user in $users) {
    $parsed_kbox = $kbox | where { $csvuser -like $user }
    $parsed_kbox | export-csv -path temp.csv -Append
}

$parsed_kbox = import-csv -Path "temp.csv"

# loop to invoke copy
foreach ($tg in $parsed_kbox) {
    $username = $tg."User Domain"
    $comp = $tg.Name
    $pathtonewfile = "\\path\to\new\rdp\file.rdp"
    $filename = 'Name for New File.rdp'

    # assign copy result to var
    $good_copy = copy-item -Path $pathtonewfile -Destination "\\$comp\c$\users\$username\desktop\$filename" -erroraction SilentlyContinue
    
    # if copy good, do copy. if copy bad, alert
    if (-not $?) { echo "$tg FAILED" | out-file fails.txt -append }
    else { echo "$tg SUCCESS" | out-file success.txt -append }

    # text to search for (for removal) is inc, exclude new file name
    $inc = *qms*.rdp
    $exc = *$filename

    # remove existing qms icon
    $badfiles1 = get-childitem "\\$comp\c$\users\$username\desktop\*" -include $inc -exclude $exc -recurse
        echo $badfiles1 | out-file -filepath "badfiles.txt" -append
    $badfiles = get-childitem "\\$comp\c$\users\Public\Desktop\*" -include $inc -exclude $exc -Recurse
        echo $badfiles | out-file -FilePath "badfiles.txt" -append
    $badfiles | Remove-Item
}

remove-item temp.csv

echo ""
echo "For successful removals and failed removals, see c:\scripts\files\qms\"
echo "For a list of files removed, see c:\scripts\files\qms\badfiles.txt"
}

else {
    echo ""
    echo "you chose not to run the cleanup tool"
    pause
    exit
}