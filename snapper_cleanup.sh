#!/bin/bash
# Since strategies in snapper (timeline and number) are failing to delete older snapshots this script is aimed to delete them in order to keep their number to a fixed value 
# defined in constant NUMBER_TO_KEEP so to not occupy too much space on the disk.
# This will preserve the current snapshot (0) and the oldest snapshot and the 8 most recent snapshots (if NUMBER_TO_KEEP is 10)
#
# Snapper list of snapshots is printed out with this format:
#
# Type   | #   | Pre | 
# single | N   |     |
# pre    | N+1 |     |
# post   | N+2 | N+1 |

# The script will delete the pre type only when deleting the post type

# Script has been successfully tested on openSuse Leap 42.3 running snapper version 0.5.0

NUMBER_TO_KEEP=10
HELP="Snapper cleanup help\n -d: delete snapper snapshot in order to keep their number to "$NUMBER_TO_KEEP"\n -t: will list the snapshots that will be delete by -d option\n -h: display this help" 

main() {
	[ $# -eq 0 ] && { display_help; exit 0;	}
	
	while getopts "htd" arg; do
		case $arg in
    		h)
			display_help 
			break;
		;;
    		d)
			delete_snapshots
			break;
		;;
		t)
			test_delete_snapshots
			break;
	      	;;
		*)
			echo "Wrong option"
			display_help
			exit 1
		;;
		esac
	done
}

# This functions returns the list of snapshots to not keep
calculate_snapshots() {
	OIFS=$IFS
	IFS=$'\n'

	# Get number of snapshots, excluding header (3 rows), current configuration (0) and 	
	local number=$(sudo snapper -c root list | tail -n +5 | wc -l)
	local snapshots_number_to_delete=$(( $number - $(($NUMBER_TO_KEEP - 2)) ))
	local snapshots_to_delete=""
	local iteration=1
	if [ $snapshots_number_to_delete -gt 0 ]; then
		for row in $(sudo snapper -c root list | tail -n +5 | head -n $snapshots_number_to_delete); do
			type=$(echo $row | awk -F'|' '{print $1}' | tr -d ' ')
			number=$(echo $row | awk -F'|' '{print $2}' | tr -d ' ')
			pre_number=$(echo $row | awk -F'|' '{print $2}' | tr -d ' ')
		if [ $type == "single" ]; then
			snapshots_to_delete=$snapshots_to_delete" "$number
		elif [ $type == "post" ]; then
			snapshots_to_delete=$snapshots_to_delete" "$pre_number" "$number
		fi
		iteration=$(( $iteration + 1 ))
		done
	fi
	IFS=$OIFS
	echo $snapshots_to_delete
}

delete_snapshots() {
	snapshots_to_delete=$(calculate_snapshots)
	if [ "$snapshots_to_delete" != "" ]; then
		echo -n "Deleting snapshots "$snapshots_to_delete"..."
		sudo snapper delete $snapshots_to_delete >> snapper_cleanup.log 2>&1
		echo "done"
	else
		echo "No snapshot to delete"
	fi
}

test_delete_snapshots() {
        snapshots_to_delete=$(calculate_snapshots)
        if [ "$snapshots_to_delete" != "" ]; then
                echo "Snapshots to delete are "$snapshots_to_delete              
        else
                echo "No snapshot to delete"
        fi
}

display_help() {
	echo -e $HELP
}

main $@
