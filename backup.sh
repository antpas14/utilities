#!/bin/bash
# This script will perform a periodic backup from a list of $FOLDERS contained inside a $SRC path.
# These folders will be backuped using rsync afer a $BACKUP_INTERVAL.
# If disk with UUID $DISK_UUID is not connected a message will appear to connect the disk to the PC.
# Disk will be automatically mounted using fs $DISK_FS.

# TODO: check that interval is a numeric value
# TODO: fix warn message using crontab
# TODO: warn user to work on multiple DE 

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

LOG_FILE=${SCRIPTPATH}"/backup.log"
CONFIG_FILE=${SCRIPTPATH}"/backup.conf"

CONFIG_FIELDS="SRC MNT_DST BACKUP_FOLDER DISK_UUID DISK_FS BACKUP_INTERVAL FOLDERS"

main() {
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

check_dependencies() {
	rsync --version > /dev/null 2>&1 || { echo "Missing rsync" | tee --append $LOG_FILE; return 1; }
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
			echo "Variable "$f" not set. Calling setup" | tee --append $LOG_FILE
			return 1
		fi 
	done

	# Check particular value
	check_fs_support $DISK_FS || return 1

	# Check paths
	check_paths || return 1

	# Check interval (numeric value)
#	check_interval || return 1
}

setup() {
	set_config
	check_config
	set_cronjob
}

set_config() {
	echo "Config file is invalid or missing. Starting configuration..."
	# Ask the user for: $SRC, $MNT_DST, $BACKUP_FOLDER, $DISK_UUID, $DISK_FS (ntfs by default), $BACKUP_INTERVALo
	for f in $CONFIG_FIELDS; do
		echo "Insert value for ${f}" | tee --append $LOG_FILE
		read value
		set_entry -k $f -v "$value" -f $CONFIG_FILE
	done

	set_entry -k LAST_BACKUP -v 0 -f $CONFIG_FILE
}

# TODO: add to a library lib/config.inc.sh for handling configuration files among different scripts
set_entry(){
	local key=""
	local value=""
	local config_file=""
	while getopts "k:v:f:" opt; do
        	case $opt in
	        k)
        		key=$OPTARG
		;;
	        v)
			value=$OPTARG
      		;;
		f)
	        	config_file=$OPTARG
        	;;
        	esac
	done

	if [ $( cat $config_file | grep $key | wc -l ) -gt 0 ]; then
		sudo sed -i "s|^\("$key"\s*=\s*\).*\$|\1\"$value\"|" $config_file
	else
		echo $key"="\"$value\" >> $config_file
	fi
	OPTIND=1
}

set_cronjob() {
	echo "Setting up cronjob" | tee --append $LOG_FILE
	croncmd=$(realpath $0)" -b > "$(dirname $(realpath $0))"/backup.log 2>&1"
	cronjob="0 * * * * $croncmd"
	( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -
}

check_last_backup() {
	[ $(( $LAST_BACKUP + $BACKUP_INTERVAL )) -gt $(date +%s) ] && exit 0;
}

check_disk() {
	[ ! -e /dev/disk/by-uuid/$DISK_UUID ] && warn_user 
}

check_fs_support() {
	if [ "$DISK_FS" == "ntfs-3g" ]; then
		ntfs-3g --version > /dev/null 2>&1 || { echo "missing ntfs-3g support."; return 1; }
	else
		[ "$(awk -v fs=$DISK_FS '($NF != "") { if (fs == $NF) { print "true"; exit } } ' /proc/filesystems)" == "true" ] || return 1
	fi
}

check_paths() {
	if [ ! -d $SRC ]; then
		echo "Path "$SRC" does not exists;" >> $LOG_FILE
		exit 1
	fi

        if [ ! -d $MNT_DST ]; then
                echo "Path "$MNT_DST" does not exists;" >> $LOG_FILE
                exit 1
        fi

}

warn_user() {
	kdialog --title "Scheduled backup" --yesno "Backup disk with UUID $DISK_UUID is not connected.\n Connect it now and click Ok."
	if [ $? -eq 0 ]; then
		main -b
	else 
		exit 1;
	fi
}

mount_disk() {
	sudo mount -t $DISK_FS UUID=$DISK_UUID $MNT_DST 
}

backup() {
	echo "Starting backup" | tee --append $LOG_FILE
	sudo mkdir -p $MNT_DST/$BACKUP_FOLDER
	for f in $FOLDERS; do
		echo "Syncing folder $f" | tee --append $LOG_FILE
		rsync -ravz $SRC/$f $MNT_DST/$BACKUP_FOLDER
	done
	echo "Backup finished" | tee --append $LOG_FILE
	set_entry -k LAST_BACKUP -v $(date +%s) -f $CONFIG_FILE
}

main $@
