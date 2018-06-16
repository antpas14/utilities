#!/bin/bash
# This script will perform a periodic backup from a list of $FOLDERS contained inside a $SRC path.
# These folders will be backuped using rsync afer a $BACKUP_INTERVAL.
# If disk with UUID $DISK_UUID is not connected a message will appear to connect the disk to the PC.
# Disk will be automatically mounted using fs $DISK_FS.
# Notification requires notify-send and was tested on Plasma KDE.

# Libraries
. lib/config.inc.sh

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

LOG_FILE=${SCRIPTPATH}"/backup.log"
CONFIG_FILE=${SCRIPTPATH}"/backup.conf"
RSYNC_LOG=${SCRIPTPATH}"/rsync_$(date +%s).log"

WAIT_TIME=300

CONFIG_FIELDS="SRC MNT_DST BACKUP_FOLDER DISK_UUID DISK_FS BACKUP_INTERVAL FOLDERS"

main() {
	check_execution
	check_dependencies || exit 1
	check_config || setup
	local backup=false
	local force=false
	local setup=false
	while getopts "bfs" opt; do
        	case $opt in
	        b)
	       		backup=true
		;;
        	f)
        		force=true
		;;
		s)
			setup=true
		;;
		esac
	done
	OPTIND=1
	if [ $backup == true ]; then
		if [ $force == false ]; then
			check_last_backup
		fi
		check_disk
		mount_disk
		backup
	elif [ $setup == true ]; then
		setup
	fi
}

check_execution() {
	if pidof -o %PPID -x $(basename $0) > /dev/null; then
		log "Script is alredy running"
	    	exit 1
	fi
}

check_dependencies() {
	rsync --version > /dev/null 2>&1 || { log "Missing rsync"; return 1; }
}

check_config() {
	if [ ! -f $LOG_FILE ]; then
		touch $LOG_FILE
	fi	

	if [ ! -f $CONFIG_FILE ]; then
		touch $CONFIG_FILE
		setup
	fi 
	. $CONFIG_FILE

	# Check if all variables are set
	for f in $CONFIG_FIELDS; do
		if [ -z "${!f}" ]; then
			log "Variable "$f" not set. Calling setup"
			return 1
		fi 
	done

	# Check particular value
	check_fs_support $DISK_FS || return 1

	# Check paths
	check_paths || return 1

	# Check interval (numeric value)
	check_interval || return 1
}

setup() {
	set_config
	check_config
	set_cronjob
}

set_config() {
	echo "Config file is invalid or missing. Starting configuration..."
	# Ask the user for: $SRC, $MNT_DST, $BACKUP_FOLDER, $DISK_UUID, $DISK_FS (ntfs by default), $BACKUP_INTERVAL
	for f in $CONFIG_FIELDS; do
		echo "Insert value for ${f}"
		read value
		set_entry -k $f -v "$value" -f $CONFIG_FILE
	done

	set_entry -k LAST_BACKUP -v 0 -f $CONFIG_FILE
}

set_cronjob() {
	log "Setting up cronjob" 
	croncmd=$(realpath $0)" -b > "$(dirname $(realpath $0))"/backup.log 2>&1"
	cronjob="0 * * * * $croncmd"
	( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -
}

check_last_backup() {
	now=$(date +%s)
	next_date=$(( $LAST_BACKUP + $BACKUP_INTERVAL))
	[ $next_date -gt $now ] && { log "Next backup will be executed at date $(to_human_date $next_date)"; exit 0; }
}

to_human_date() {
	ts=$1
	echo $(date --date='@'"$ts"'')
}

check_disk() {
	while [ ! -e /dev/disk/by-uuid/$DISK_UUID ]; do 
		check_date=$(date -d "${WAIT_TIME} seconds")
		message="Backup disk with UUID $DISK_UUID is not connected. Next check is scheduled at "$check_date
	        notify-send "Backup script" "$message"
        	log $message
		sleep $WAIT_TIME
	done
}

check_fs_support() {
	if [ "$DISK_FS" == "ntfs-3g" ]; then
		ntfs-3g --version > /dev/null 2>&1 || { log "missing ntfs-3g support"; return 1; }
	else
		[ "$(awk -v fs=$DISK_FS '($NF != "") { if (fs == $NF) { print "true"; exit } } ' /proc/filesystems)" == "true" ] || return 1
	fi
}

check_paths() {
	if [ ! -d $SRC ]; then
		log "Path "$SRC" does not exist"
		exit 1
	fi

        if [ ! -d $MNT_DST ]; then
                log "Path "$MNT_DST" does not exist"
                exit 1
        fi
}

check_interval() {
	[ -z "${BACKUP_INTERVAL//[0-9]}" ] || { log "Invalid backup interval: ${BACKUP_INTERVAL}"; exit 1; }
}

log() {
	cmd="echo"
	msg=$@
	date=$(date +%F" "%R":"%S)
	$cmd "[" $date "]" $msg | tee --append $LOG_FILE 
}

mount_disk() {
	sudo mount -t $DISK_FS UUID=$DISK_UUID $MNT_DST 
}

backup() {
	log "Starting backup"
	notify-send "Backup script" "Starting backup"
	sudo mkdir -p $MNT_DST/$BACKUP_FOLDER
	for f in $FOLDERS; do
		if [ -d $SRC/$f ]; then
			log "Starting syncing folder $f"
			rsync -ravz $SRC/$f $MNT_DST/$BACKUP_FOLDER > $RSYNC_LOG 2>&1
			log "Finished syncing folder $f"
		else
			log "WARNING: folder $SRC/$f does not exit"
		fi
	done
	log "Backup finished"
	notify-send "Backup script" "Backup finished"
	set_entry -k LAST_BACKUP -v $(date +%s) -f $CONFIG_FILE
}

main $@
