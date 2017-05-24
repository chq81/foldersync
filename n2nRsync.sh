#!/bin/bash

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
    Usage: $program [-p profile] [-c] [-s] [-l] [-t] [-h]

      -p profile  rsync profile to execute
      -c          use when running via cron
                  when used, will output to log file
                  otherwise, defaults to stdout
      -s          sends a notification message to the synology DSM
      -l          list profiles available
      -t          runs with --dry-run enabled
      -h          shows this usage info
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

    if [ "$vSynology" = "yes" ]; then
        synodsmnotify @users
        "Backup finished" "Backup with profile '${vProfile}'  was not successful. See logs for more."
    fi
}

if [ $# -lt 1 ]; then
    usage;
    exit 1
fi

while getopts p:tcslh option; do
    case $option in
        p) vProfile=$OPTARG;;
        c) vCron="yes";;
        s) vSynology="yes";;
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


function prepare()
{
    ##
    #
    # Directories of interest
    #
    ##
    dirDoProfile="${dirProfiles}/${vProfile}"

    vBackupName=${vProfile}_Backup_${vDate}

    ##
    #
    # Enable logging to log file.  With -c option only
    #
    ##
    if [ "$vCron" = "yes" ]; then
        vLogF=${dirLogs}/${vBackupName}.log

        exec > $vLogF 2>&1
    fi
}

##
#
# Variable Checks Functions
#
##
function checkProfile()
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

function checkParameters()
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

function finish()
{

    vErrCode=$?

    if [[ $vErrCode -ne 0 ]]; then
        doErrStuff;
        exit 25
    fi

    if [ ! -z "$vTempFileDestination" ]; then
        rm ${vTempFileDestination}
    fi
    if [ ! -z "$vOutputFileDestination" ]; then
        rm ${vOutputFileDestination}
    fi

    echo
    echo "-----------------------------------------------"
    echo
    echo "    Backup appears to have completed (`date +%Y-%m-%dT%H%M`)"
    echo
    echo "-----------------------------------------------"
    echo
    echo "Following files were backed up:"
    echo "${overallFileNames}"

    if [ "$vSynology" = "yes" ] && [ ! -z "${overallFileNames}" ]; then
        synodsmnotify @users "Backup finished" "Backup with profile '${vProfile}' was successful with files: ${overallFileNames}"
    fi
}

##
#
# Prepare date related and file-marked backup strategies
#
##

function buildOptions()
{
    if [ -z "$1" ]; then
        return 0;
    else
        sourceFolder=$1
    fi


    if [ "$dDateRelatedBackup" = "yes" ]; then

        while read folder; do

            [ ! -d "${sourceFolder}/${folder}" ] && continue

            [ "${folder:0:1}" = "#" ] && continue

            find ${sourceFolder}/${folder}*/ -type d -newer ${sourceFolder}/${folder}backupDate.txt -printf "%T@ %p\n" | grep -v "@" | sort -n | tail -n ${dBackupAmount} \
            | sed -e "s/\(.*\)/\"\1\"/" -e "s/'/\\\'/g" | xargs -n1 basename | xargs -I {} echo ${folder}{} >> ${vTempFileDestination}

        	touch ${sourceFolder}/${folder}backupDate.txt

        done < ${dirDoProfile}/${vFilesFromFile}

    fi

    if [ "$dMarkedBackup" = "yes" ]; then

        while read folder; do

            [ "${folder:0:1}" = "#" ] && continue

            find ${sourceFolder}/${folder} -type f -name ${dMarkedForBackupFile} -exec dirname {} \; \
            | sed -e 's/\(.*\)/"\1"/' | xargs -n1 basename | xargs -I {} echo ${folder}{} >> ${vTempFileDestination}

        done < ${dirDoProfile}/${vFilesFromFile}

    fi

    if [ "$dDateRelatedBackup" = "yes" ] && [ "$dMarkedBackup" = "yes" ]; then
        sort ${vTempFileDestination} | uniq -d >> ${vOutputFileDestination}
    else
        cat ${vTempFileDestination} >> ${vOutputFileDestination}
    fi
}


##
#
# Variable Build Outs
#
##

function buildOuts()
{
    unset specificRsyncOpts;

    specificRsyncOpts=${vRsyncOpts}

    if [ ! -z "$vLogLvl" ]; then
            specificRsyncOpts="${specificRsyncOpts} ${vLogLvl}"
    fi

    if [ "$vEnableFilesFrom" = "yes" ] || [ ! -z "$vFilesFrom" ]; then

        if [ -z "$vFilesFrom" ]; then
            vFilesFrom=${dirDoProfile}/${vFilesFromFile}
        fi
        specificRsyncOpts="${specificRsyncOpts} --recursive --files-from=${vFilesFrom}"
    fi

    if [ "$vEnableExcludeFrom" = "yes" ]; then

        if [ "$vEnableDeleteExcluded" = "yes" ]; then
            specificRsyncOpts="${specificRsyncOpts} --delete-excluded"
        fi

        specificRsyncOpts="${specificRsyncOpts} --exclude-from=${dirDoProfile}/${vExcludeFromFile}"
    fi

    if [ "$vDoDryRun" = "yes" ]; then
        specificRsyncOpts="${specificRsyncOpts} --dry-run"

        echo "--dry-run enabled.  No files being transferrred"
        echo
    fi

    vDest=$dDirBase

    if [ "$dLoc" = "remote" ]; then
        vDest="${rUserHost}:${vDest}"
    fi
}


##
#
# start the sync
#
##

function doSync()
{
        if [ -z "$1" ]; then
            return 0;
        else
            sourceFolder=$1
        fi

    if [ "$dLoc" = "local" ]; then
        echo "rsync ${specificRsyncOpts} ${sourceFolder} ${vDest}"
        echo
        output=$(rsync --stats ${specificRsyncOpts} ${sourceFolder} ${vDest})
    else
        echo "rsync ${specificRsyncOpts} -e \"ssh -i ${rUserKey}\" ${sourceFolder} ${vDest}"
        echo
        output=$(rsync --stats ${specificRsyncOpts} -e "ssh -p ${rSshPort} -i ${rUserKey}" ${sourceFolder} ${vDest})
    fi

    echo "${output}"

    IFS=$'\n' read -d '' -r -a outputArray <<< "$output"

    fileArray=()
    count=0
    fileEndReached=0

    for info in "${outputArray[@]}"; do
        if [[ ! ${info} =~ .*"Number of files".* ]]; then
            if [ ${fileEndReached} != 1 ] && [ "${info}" != "sending incremental file list" ]; then
                fileArray+=("${info}")
            fi
        fi
        if [[ ${info} =~ .*"Number of files".* ]]; then
            fileEndReached=1
        fi
    done

    fileNames=$(IFS=$'\n'; echo "${fileArray[*]}")

    overallFileNames+="${fileNames}"
}


function run()
{
    echo
    echo "-----------------------------------------------"
    echo
    echo "   n2nBackup Script"
    echo
    echo "      Name: ${vBackupName}"
    echo
    echo "-----------------------------------------------"
    echo

    vTempFileDestination=${dirLogs}/tempFilesToBackup
    vOutputFileDestination=${dirLogs}/filesToBackup
    overallFileNames="";

    IFS=', ' eval 'array=(${dirSrc})'

    for source in "${array[@]}"; do

        > ${vTempFileDestination}
        > ${vOutputFileDestination}

        if [ "$dDateRelatedBackup" = "yes" ] || [ "$dMarkedBackup" = "yes" ]; then
            buildOptions ${source};

            vFilesFrom=${vOutputFileDestination}
         fi

        buildOuts;
        doSync ${source};
    done

}

##
#
# Run the sync
#
##

prepare;

checkProfile;

. ${dirDoProfile}/rsync.conf

. ${dirDoProfile}/dest.conf

. ${dirDoProfile}/options.conf

checkParameters;

run;

finish;
