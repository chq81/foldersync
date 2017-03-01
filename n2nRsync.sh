#!/bin/bash

##
#
# Updated:
#
##

##
#
# Changes
#
# -
#
##

##
#
#
#
##
cd $(dirname $0)

program=$(basename $0)

vCron="no"
vErr="no"
vErrCode=0
vDate=`date +%Y-%m-%dT%H%M`
vDoDryRun="no"

dirLogs="./logs"
dirProfiles="./profiles"

function listProfiles()
{
	echo
	echo "    Profiles Found"
	echo "    --------------------"
	for d in `ls ${dirProfiles}`
	do
	        if [ -d "${dirProfiles}/${d}" ]; then
	        	echo "      $d"
	        fi
	done

	echo

	exit 24
}

function usage()
{
	echo "
	Usage: $program [-p profile] [-c] [-l] [-t] [-h]

	  -p profile		rsync profile to execute
	  -c			use when running via cron
	  			when used, will output to log file
	  			otherwise, defaults to stdout
	  -l			list profiles available
	  -t			runs with --dry-run enabled
	  -h			shows this usage info
	" >&2
}

function doErrStuff()
{
	vErr="yes"

	echo
	echo "ERR : Rsync returned a non-zero result code (${vErrCode})"
	echo

	if [ "$vCron" = "yes" ]; then
		mv $vLogF $dirLogs/n2n_${vBackupName}.err
	fi
}

if [ $# -lt 1 ]; then
	usage;
	exit 1
fi

while getopts p:tclh option; do
	case $option in
		p) vProfile=$OPTARG;;
		c) vCron="yes";;
		t) vDoDryRun="yes";;
		l) listProfiles
		   ;;
		h) usage;
		   exit 2
		   ;;
		*) usage;
		   exit 3
		   ;;
	esac
done

##
#
# Variable Checks Functions
#
##
function varCheck1()
{
	if [ -z "$vProfile" ]; then
		echo "    ERR : Profile directory was not supplied"
		usage;
		exit 4
	fi

	if [ ! -d "${dirDoProfile}" ]; then
		echo "    ERR : Profile directory does not exist (${dirDoProfile})"
		exit 5
	fi

	if [ ! -f "${dirDoProfile}/dest.conf" ]; then
		echo "    ERR : Destination conf does not exist (${dirDoProfile}/dest.conf"
		exit 6
	fi

	if [ ! -f "${dirDoProfile}/rsync.conf" ]; then
		echo "    ERR : Rsync conf does not exist (${dirDoProfile}/rsync.conf"
		exit 7
	fi

	if [ ! -f "${dirDoProfile}/src_dirs.conf" ]; then
		echo "    ERR : Source Directories conf does not exist (${dirDoProfile}/src_dirs.conf)"
		exit 8
	fi
}

function varCheck2()
{
	if [ -z "$dLoc" ]; then
		echo "    ERR : Destination Location not defined"
		exit 11
	fi

	if [ -z "$dDirBase" ]; then
		echo "    ERR : Destination Base Directory not defined"
		exit 12
	else
		if [ ! -d "$dDirBase" ]; then
			echo "    ERR : Destination Directory does not exist (${dDirBase})"
			exit 27
		fi
	fi

	case "$dLoc" in
		local) ;;
		remote) ;;
		*) echo "    ERR : Destination Location has an invalid value ($dLoc)"
		   exit 13
		   ;;
	esac

	if [ "$dLoc" = "remote" ]; then
		if [ -z "$rHost" ]; then
			echo "    ERR : Remote Host not defined"
			exit 14
		fi

		if [ -z "$rUser" ]; then
			echo "    ERR : Remote User not defined"
			exit 15
		fi

		if [ -z "$rUserKey" ]; then
			echo "    ERR : Remote User Key not defined"
			exit 16
		else
			if [ ! -f "${rUserKey}" ]; then
				echo "    ERR : Remote User Key does not exist (${rUserKey})"
				exit 17
			fi
		fi

		if [ -z "$rSshPort" ]; then
			echo "    ERR : Remote SSH Port is not defined"
			exit 26
		fi
	fi

	if [ -z "$dirSrc" ]; then
		echo "    ERR : Source Directory not defined"
		exit 20
	else
		if [ ! -d "$dirSrc" ]; then
			echo "    ERR : Source Directory does not exist (${dirSrc})"
			exit 21
		fi
	fi

	if [ "$vEnableFilesFrom" = "yes" ]; then

		if [ -z "$vFilesFromFile" ]; then
			echo "    ERR : Files From is enabled, but input file is not defined"
			exit 18
		else
			if [ ! -f "${dirDoProfile}/${vFilesFromFile}" ]; then
				echo "    ERR : Files From is enabled, but input file is not found (${vFilesFromFile})"
				exit 19
			fi
		fi
	fi

	if [ "$vEnableExcludeFrom" = "yes" ]; then
		if [ -z "$vExcludeFromFile" ]; then
			echo "    ERR : Exclude From is enabled, but input file is not defined"
			exit 22
		else
			if [ ! -f "${dirDoProfile}/${vExcludeFromFile}" ]; then
				echo "    ERR : Exlude From is enabled, but input file is not found (${vExcludeFromFile})"
				exit 23
			fi
		fi
	fi
}

vBackupName=Backup_${vDate}

##
#
# Directories of interest
#
##
dirDoProfile="${dirProfiles}/${vProfile}"

##
#
# Enable logging to log file.  With -c option only
#
##
if [ "$vCron" = "yes" ]; then
	vLogF=${dirLogs}/n2n_${vBackupName}.log

	exec > $vLogF 2>&1
fi

echo
echo "-----------------------------------------------"
echo
echo "   n2nBackup Script"
echo
echo "      Name: ${vBackupName}"
echo
echo "-----------------------------------------------"
echo

##
#
# Variable Checks and Imports
#
##
varCheck1;

. ${dirDoProfile}/rsync.conf

. ${dirDoProfile}/dest.conf

. ${dirDoProfile}/options.conf

varCheck2;

##
#
# Prepare date related and file-marked backup strategies
#
##
if [ "$dDateRelatedBackup" = "yes" ] || [ "$dMarkedBackup" = "yes" ]; then

    vTempFileDestination=${dirLogs}/tempFilesToBackup
    vOutputFileDestination=${dirLogs}/filesToBackup

    > ${vTempFileDestination}
    > ${vOutputFileDestination}

    if [ "$dDateRelatedBackup" = "yes" ]; then

        while read folder; do

            [ "${folder:0:1}" = "#" ] && continue

            ls -1td ${dirSrc}/${folder}/*/ | head -n ${dBackupAmount} | rev | \
            cut -c 2- | rev | tr '\n' '\0' | xargs -0 -n1 basename | xargs -I {} echo ${folder}/{} >> ${vTempFileDestination}

        done < ${dirDoProfile}/${vFilesFromFile}

    fi

    if [ "$dMarkedBackup" = "yes" ]; then

        while read folder; do

            [ "${folder:0:1}" = "#" ] && continue

            find ${dirSrc}/${folder} -type f -name $dMarkedForBackupFile \
            -exec dirname {} \; | xargs -n1 basename | xargs -I {} echo ${folder}/{} >> ${vTempFileDestination}

        done < ${dirDoProfile}/${vFilesFromFile}

    fi

    if [ "$dDateRelatedBackup" = "yes" ] && [ "$dMarkedBackup" = "yes" ]; then
        sort ${vTempFileDestination} | uniq -d >> ${vOutputFileDestination}
    else
        cat ${vTempFileDestination} >> ${vOutputFileDestination}
    fi

    vFilesFrom=${vOutputFileDestination}

fi


##
#
# Variable Build Outs
#
##
if [ ! -z "$vLogLvl" ]; then
        vRsyncOpts="${vRsyncOpts} ${vLogLvl}"
fi

if [ "$vEnableFilesFrom" = "yes" ] || [ ! -z "$vFilesFrom" ]; then

    if [ -z "$vFilesFrom" ]; then
        vFilesFrom=${dirDoProfile}/${vFilesFromFile}
    fi
	vRsyncOpts="${vRsyncOpts} --recursive --files-from=${vFilesFrom}"
fi

if [ "$vEnableExcludeFrom" = "yes" ]; then

	if [ "$vEnableDeleteExcluded" = "yes" ]; then
		vRsyncOpts="${vRsyncOpts} --delete-excluded"
	fi

	vRsyncOpts="${vRsyncOpts} --exclude-from=${dirDoProfile}/${vExcludeFromFile}"
fi

if [ "$vDoDryRun" = "yes" ]; then
	vRsyncOpts="${vRsyncOpts} --dry-run"

	echo "--dry-run enabled.  No files being transferrred"
	echo
fi

vDest=$dDirBase

if [ "$dLoc" = "remote" ]; then
	vDest="${rUserHost}:${vDest}"
fi

##
#
# Rsync Magic
#
##

if [ "$dLoc" = "local" ]; then
	echo "rsync ${vRsyncOpts} ${dirSrc} ${vDest}"
	echo
	rsync ${vRsyncOpts} ${dirSrc} ${vDest}
else
	echo "rsync ${vRsyncOpts} -e \"ssh -i ${rUserKey}\" ${dirSrc} ${vDest}"
	echo
	rsync ${vRsyncOpts} -e "ssh -p ${rSshPort} -i ${rUserKey}" ${dirSrc} ${vDest}
fi

vErrCode=$?

if [[ $vErrCode -ne 0 ]]; then
#	vErrCode=$?
	doErrStuff;
	exit 25
fi

echo
echo "-----------------------------------------------"
echo
echo "    Backup appears to have completed (`date +%Y-%m-%dT%H%M`)"
echo
echo "-----------------------------------------------"
echo
