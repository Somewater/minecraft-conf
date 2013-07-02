#!/bin/bash
# /etc/init.d/minecraft

### BEGIN INIT INFO
# Provides:   minecraft
# Required-Start: $local_fs $remote_fs
# Required-Stop:  $local_fs $remote_fs
# Should-Start:   $network
# Should-Stop:    $network
# Default-Start:  2 3 4 5
# Default-Stop:   0 1 6
# Short-Description:    Minecraft server
# Description:    Init script for minecraft/bukkit server, with rolling logs and use of ramdisk for less lag. 
### END INIT INFO

# Created by Ahtenus

# Based on http://www.minecraftwiki.net/wiki/Server_startup_script
# Support for multiworld by Benni-chan
# Log rolls without needing restarts by Solorvox
# Option for killing server in an emergency by jbondhus

# Loads config file

#if [ -L $0 ]
#then
#	source `readlink -e $0 | sed "s:[^/]*$:config:"`
#else
#	source `echo $0 | sed "s:[^/]*$:config:"`
#fi
source '/data/srv/minecraft/config.conf'

if [ "$SERVICE" == "" ]
then
	echo "Couldn't load config file, please edit config.example and rename it to config"
	logger -t minecraft-init "Couldn't load config file, please edit config.example and rename it to config"
	exit
fi

ME=`whoami`
as_user() {
	if [ $ME == $USERNAME ] ; then
		bash -c "$1"
	else
		su $USERNAME -s /bin/bash -c "$1"
	fi
}

is_running(){
	# Checks for the minecraft servers screen session
	# returns true if it exists.
	pidfile=${MCPATH}/${SCREEN}.pid

	if [ -r "$pidfile" ]
	then
		pid=$(head -1 $pidfile)
		if ps ax | grep -v grep | grep ${pid} | grep "${SCREEN}" > /dev/null
		then
			return 0
		else 
			if [ -z "$isInStop" ]
			then
				if [ -z "$roguePrinted" ]
				then
					roguePrinted=1
					echo "Rogue pidfile found!"
				fi
			fi
			return 1
		fi
	else
		if ps ax | grep -v grep | grep "${SCREEN} ${INVOCATION}" > /dev/null
		then
			echo "No pidfile found, but server's running."
			echo "Re-creating the pidfile."
			
			pid=$(ps ax | grep -v grep | grep "${SCREEN} ${INVOCATION}" | cut -f1 -d' ')
			check_permissions
			as_user "echo $pid > $pidfile"

			return 0
		else
			return 1
		fi
	fi
}

datepath() {
	# datepath path filending-to-check returned-filending

	# Returns an file path with added date between the filename and file ending.
	# $1 filepath (not including file ending)
	# $2 file ending to check for uniqueness
	# $3 file ending to return

	if [ -e $1`date +%F`$2 ]
	then
		echo $1`date +%FT%T`$3
	else
		echo $1`date +%F`$3
	fi
}

mc_start() {
	pidfile=${MCPATH}/${SCREEN}.pid
	check_permissions

	as_user "cd $MCPATH && screen -dmS $SCREEN $INVOCATION"
	as_user "screen -list | grep '\.$SCREEN' | cut -f1 -d'.' | tr -d -c 0-9 > $pidfile"

	#
	# Waiting for the server to start
	#
	seconds=0
	until is_running 
	do
		sleep 1
		seconds=$seconds+1
		if [[ $seconds -eq 5 ]]
		then
			echo "Still not running, waiting a while longer..."
		fi
		if [[ $seconds -ge 120 ]]
		then
			echo "Failed to start, aborting."
			exit 1
		fi
	done	
	echo "$SERVICE is running."
}

mc_command() {
		if is_running
		then
				as_user "screen -p 0 -S $SCREEN -X eval 'stuff \"$(eval echo $FORMAT)\"\015'"
		else
				echo "$SERVICE was not running. Not able to run command."
		fi
}

mc_saveoff() {
	if is_running
	then
		echo "$SERVICE is running... suspending saves"
		mc_command save-off
		mc_command save-all
		sync
		sleep 10
	else
		echo "$SERVICE was not running. Not suspending saves."
	fi
}

mc_saveon() {
	if is_running
	then
		echo "$SERVICE is running... re-enabling saves"
		mc_command save-on
	else
		echo "$SERVICE was not running. Not resuming saves."
	fi
}

mc_say() {
	if is_running
	then
		echo "Said: $1"
		mc_command "say $1"
	else
		echo "$SERVICE was not running. Not able to say anything."
	fi
}

mc_stop() {
	pidfile=${MCPATH}/${SCREEN}.pid
	#
	# Stops the server
	#
	echo "Saving worlds..."
	mc_command save-all
	sleep 10
	echo "Stopping server..."
	mc_command stop
	sleep 0.5
	#
	# Waiting for the server to shut down
	#
	seconds=0
	isInStop=1
	while is_running
	do
		sleep 1 
		seconds=$seconds+1
		if [[ $seconds -eq 5 ]]
		then
			echo "Still not shut down, waiting a while longer..."
		fi
		if [[ $seconds -ge 120 ]]
		then
			logger -t minecraft-init "Failed to shut down server, aborting."
			echo "Failed to shut down, aborting."
			exit 1
		fi
	done
	as_user "rm $pidfile"
	unset isInStop
	is_running
	echo "$SERVICE is now shut down."
}

get_worlds() {
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")

	a=1
	for NAME in $(ls $WORLDSTORAGE)
	do
		if [ -d $WORLDSTORAGE/$NAME ]
		then
			WORLDNAME[$a]=$NAME
			if [ -e $WORLDSTORAGE/$NAME/ramdisk ]
			then
				WORLDRAM[$a]=true
			else
				WORLDRAM[$a]=false
			fi
			a=$a+1
		fi
	done

	IFS=$SAVEIFS
}

mc_whole_backup() {
	echo "backing up entire setup into $WHOLEBACKUP"
	path=`datepath $WHOLEBACKUP/mine_`
	locationOfScript=$(dirname "$(readlink -e "$0")")
	as_user "mkdir -p $path"
	
	if [ -r "$locationOfScript/exclude.list" ]
	then
		echo "...except the following files and/or dirs:"
		cat $locationOfScript/exclude.list
		
		if [ "$COMPRESS_WHOLEBACKUP" ]
		then
			as_user "tar -cpjf $path/whole-backup.tar.bz2 $MCPATH -X $locationOfScript/exclude.list"
		else
			as_user "tar -cpf $path/whole-backup.tar $MCPATH -X $locationOfScript/exclude.list"
		fi
	else
		if [ "$COMPRESS_WHOLEBACKUP" ]
		then
			as_user "tar -cpjf $path/whole-backup.tar.bz2 $MCPATH"
		else
			as_user "tar -cpf $path/whole-backup.tar $MCPATH"
		fi
	fi
}

mc_world_backup() {
	#
	# Backup the worlds and puts them in a folder for each day (unless $BACKUPSCRIPTCOMPATIBLE is set)
	#

	get_worlds
	today="`date +%F`"
	as_user "mkdir -p $BACKUPPATH"
	# Check if the backupt script compatibility is enabled
		if [ "$BACKUPSCRIPTCOMPATIBLE" ]
		then
			# If it is enabled, then delete the old backups to prevent errors
			echo "Detected that backup script compatibility is enabled, deleting old backups that are not necessary."
			as_user "rm -r $BACKUPPATH/*"
		fi
	for INDEX in ${!WORLDNAME[@]}
	do
		echo "Backing up minecraft ${WORLDNAME[$INDEX]}"
		case "$BACKUPFORMAT" in
			tar)
				if [ "$WORLDEDITCOMPATIBLE" ]
				# If this is set tars will be created compatible to WorldEdit
				then
					as_user "mkdir -p $BACKUPPATH/${WORLDNAME[$INDEX]}"
					path=`datepath $BACKUPPATH/${WORLDNAME[$INDEX]}/ .tar.bz2 .tar.bz2`
				elif [ "$BACKUPSCRIPTCOMPATIBLE" ]
				# If is set tars will be put in $BACKUPPATH without any timestamp to be compatible with
				# [backup rotation script](https://github.com/adamfeuer/rotate-backups)
				then
					path=$BACKUPPATH/${WORLDNAME[$INDEX]}.tar.bz2
				else
					as_user "mkdir -p $BACKUPPATH/${today}"
					path=`datepath $BACKUPPATH/${today}/${WORLDNAME[$INDEX]}_ .tar.bz2 .tar.bz2`
				fi
				if [ "$WORLDEDITCOMPATIBLE" ]
				# Don't store the complete path
				then
					as_user "cd $MCPATH && tar -hcjf $path ${WORLDNAME[$INDEX]}"
				else
					as_user "tar -hcjf $path $MCPATH/${WORLDNAME[$INDEX]}"
				fi
				;;
			zip)
				if [ "$WORLDEDITCOMPATIBLE" ]
				then
					as_user "mkdir -p $BACKUPPATH/${WORLDNAME[$INDEX]}"
					path=`datepath $BACKUPPATH/${WORLDNAME[$INDEX]}/ .zip .zip`
				elif [ "$BACKUPSCRIPTCOMPATIBLE" ]
				then
					path=$BACKUPPATH/${WORLDNAME[$INDEX]}.zip
				else
					as_user "mkdir -p $BACKUPPATH/${today}"
					path=`datepath $BACKUPPATH/${today}/${WORLDNAME[$INDEX]}_ .zip .zip`
				fi
				if [ "$WORLDEDITCOMPATIBLE" ]
				then
					as_user "cd $MCPATH && zip -rq $path ${WORLDNAME[$INDEX]}"
				else
					as_user "zip -rq $path $MCPATH/${WORLDNAME[$INDEX]}"
				fi
				;;
			*)
				echo "$BACKUPFORMAT is not a supported backup format"
				;;
		esac
	done
}

check_links() {
	get_worlds
	for INDEX in ${!WORLDNAME[@]}
	do
		if [[ -L $MCPATH/${WORLDNAME[$INDEX]} || ! -a $MCPATH/${WORLDNAME[$INDEX]} ]]
		then
			link=`ls -l $MCPATH/${WORLDNAME[$INDEX]} | awk '{print $11}'`
			if ${WORLDRAM[$INDEX]}
			then
				if [ "$link" != "$RAMDISK/${WORLDNAME[$INDEX]}" ]
				then
					as_user "rm -f $MCPATH/${WORLDNAME[$INDEX]}"
					as_user "ln -s $RAMDISK/${WORLDNAME[$INDEX]} $MCPATH/${WORLDNAME[$INDEX]}"
					echo "Created link for ${WORLDNAME[$INDEX]}"
				fi
			else
				if [ "$link" != "${WORLDSTORAGE}/${WORLDNAME[$INDEX]}" ]
				then
					as_user "rm -f $MCPATH/${WORLDNAME[$INDEX]}"
					as_user "ln -s ${WORLDSTORAGE}/${WORLDNAME[$INDEX]} $MCPATH/${WORLDNAME[$INDEX]}"
					echo "Created link for ${WORLDNAME[$INDEX]}"
				fi
			fi
		else
			echo "Could not process the world named '${WORLDNAME[$INDEX]}'. Please move all worlds to ${WORLDSTORAGE}."

			exit 1
		fi
	done
}

to_ram() {
	get_worlds
	for INDEX in ${!WORLDNAME[@]}
	do
		if ${WORLDRAM[$INDEX]}
		then
			if [ -L $MCPATH/${WORLDNAME[$INDEX]} ]
			then
				as_user "mkdir -p $RAMDISK"
				as_user "rsync -rt --exclude 'ramdisk' ${WORLDSTORAGE}/${WORLDNAME[$INDEX]}/ $RAMDISK/${WORLDNAME[$INDEX]}"
				echo "${WORLDNAME[$INDEX]} copied to ram"
			fi
		fi
	done
}

to_disk() {
	get_worlds
	for INDEX in ${!WORLDNAME[@]}
	do
		if ${WORLDRAM[$INDEX]}
		then
			as_user "rsync -rt --exclude 'ramdisk' $MCPATH/${WORLDNAME[$INDEX]}/ ${WORLDSTORAGE}/${WORLDNAME[$INDEX]}"
			echo "${WORLDNAME[$INDEX]} copied to disk"
		fi
	done
}

check_update_vanilla() {
	MC_SERVER_URL=`wget -q -O - http://minecraft.net/download | grep minecraft_server.jar\ | cut -d \" -f 6`

	echo "Checking for update for minecraft_server.jar (Vanilla)"
	as_user "cd $MCPATH && wget -q -O $MCPATH/minecraft_server.jar.update $MC_SERVER_URL"

	if [ -r "$MCPATH/minecraft_server.jar.update" ]
	then
		if `diff $MCPATH/$MC_JAR $MCPATH/minecraft_server.jar.update >/dev/null`
		then
			echo "You are already running the latest version of minecraft_server.jar."
			return 1
		else
			echo "Update of $MC_JAR is needed."
			return 0
		fi
	else
		echo "Something went wrong. Couldn't download minecraft_server.jar"
	fi	
}

get_cb_release_channel() {
	CB_URL="http://dl.bukkit.org/latest-"

	case $CB_RELEASE in
		unstable|UNSTABLE|Unstable|dev|development)
			echo $CB_URL"dev/craftbukkit.jar"
		;;
		beta|Beta|BETA)
			echo $CB_URL"beta/craftbukkit.jar"
		;;
		*)
			echo $CB_URL"rb/craftbukkit.jar"
		;;
	esac
}

check_update_craftbukkit() {
	echo "Checking for update for craftbukkit.jar"
	echo "You are on release channel \"$CB_RELEASE\""

	as_user "cd $MCPATH && wget -q -O $MCPATH/craftbukkit.jar.update $(get_cb_release_channel)"
	if [ -r "$MCPATH/craftbukkit.jar.update" ]
	then
		if `diff $MCPATH/$CB_JAR $MCPATH/craftbukkit.jar.update >/dev/null`
		then
			echo "You are already running the latest version of craftbukkit.jar."
			return 1
		else
			echo "Update of $CB_JAR is needed."
			return 0
		fi
	else
		echo "Something went wrong. Couldn't download craftbukkit.jar"
	fi
}

mc_update() {
	if is_running
	then
		echo "$SERVICE is running! Will not start update."
	else
		if check_update_vanilla
		then
			if [ -r "$MCPATH/minecraft_server.jar.update" ]
			then
				as_user "mv $MCPATH/minecraft_server.jar.update $MCPATH/$MC_JAR"
				echo "Thats it. Update of $MC_JAR done."
			else
				echo "Something went wrong. Couldn't replace your original $MC_JAR with minecraft_server.jar.update"
			fi
		else
			echo "Not updating $MB_JAR. It's not necessary"
			as_user "rm $MCPATH/minecraft_server.jar.update"
		fi

		if check_update_craftbukkit
		then
			if [ -r "$MCPATH/craftbukkit.jar.update" ]
			then
				as_user "mv $MCPATH/craftbukkit.jar.update $MCPATH/$CB_JAR"
				echo "Thats it. Update of $CB_JAR done."
			else
				echo "Something went wrong. Couldn't replace your original $CB_JAR with craftbukkit.jar.update"
			fi
		else
			echo "Not updating $CB_JAR. It's not necessary"
			as_user "rm $MCPATH/craftbukkit.jar.update"
		fi
	fi
}

change_ramdisk_state() {
	if [ ! -e $WORLDSTORAGE/$1 ]
	then
		echo "World \"$1\" not found."
		exit 1
	fi
	
	if [ -e $WORLDSTORAGE/$1/ramdisk ]
	then
		rm $WORLDSTORAGE/$1/ramdisk
		echo "Removed ramdisk flag from \"$1\""
	else
		touch $WORLDSTORAGE/$1/ramdisk
		echo "Added ramdisk flag to \"$1\""
	fi
	echo "Changes will only take effect after server is restarted."	
}

overviewer_start() {
		if [ ! -e $OVPATH/overviewer.py ]
		then
				if [ ! "$OVPATH" == "apt" ]
				then
						echo "Minecraft-Overviewer is not installed in \"$OVPATH\""
						exit 1
				else
						echo "Using APT repository installed Minecraft-Overviewer"
				fi
		fi
		if [ ! -e $OUTPUTMAP ]
		then
				as_user "mkdir -p $OUTPUTMAP"
		fi
		if [ -e $OVCONFIGPATH/$OVCONFIGNAME ]
		then
				echo "Start generating map with Minecraft-Overviewer..."
				if [ "$OVPATH" == "apt" ]
				then
						as_user "overviewer.py --config=$OVCONFIGPATH/$OVCONFIGNAME"
				else
						as_user "python $OVPATH/overviewer.py --config=$OVCONFIGPATH/$OVCONFIGNAME"
				fi
				echo "Map generated."
		else
				echo "No config file found. Start with default config..."
				if [ -z $1 ] || [ ! -e $OVBACKUP/$1 ]
				then
						echo "World \"$1\" not found."
				else
						echo "Start generating map with Minecraft-Overviewer..."
						if [ "$OVPATH" == "apt" ]
						then
								as_user "nice overviewer.py $OVBACKUP/$1 $OUTPUTMAP"
						else
								as_user "nice python $OVPATH/overviewer.py $OVBACKUP/$1 $OUTPUTMAP"
						fi
						echo "Map generated."
				fi
		fi
}

overviewer_copy_worlds() {
	#
	# Backup the worlds for overviewer
	#

	get_worlds
	for INDEX in ${!WORLDNAME[@]}
	do
		echo "Copying minecraft ${WORLDNAME[$INDEX]}."
		as_user "mkdir -p $OVBACKUP"
		as_user "rsync -rt --delete $WORLDSTORAGE/${WORLDNAME[$INDEX]} $OVBACKUP/${WORLDNAME[$INDEX]}"
	done
}

whitelist(){
	mc_command "whitelist list"
	sleep 1s
	whitelist=$(tac $MCPATH/server.log | grep -m 1 "White-listed players:")
	
	echo
	echo "Currently there are the following players on your whitelist:"
	echo
	echo ${whitelist:49} | sed 's/, /\n/g'
}

force_exit() {	# Kill the server running (messily) in an emergency
	echo ""
	echo "SIGINIT CALLED - FORCE EXITING!"
	pidfile=${MCPATH}/${SCREEN}.pid
	rm $pidfile
	echo "KILLING SERVER PROCESSES!!!"
		# Display which processes are being killed
		ps aux | grep -e 'java -Xmx' | grep -v grep | awk '{print $2}' | xargs -i echo "Killing PID: " {}
		ps aux | grep -e 'SCREEN -dmS minecraft java' | grep -v grep | awk '{print $2}' | xargs -i echo "Killing PID: " {}
		ps aux | grep -e '/etc/init.d/minecraft' | grep -v grep | awk '{print $2}' | xargs -i echo "Killing PID: " {}
		
		# Kill the processes
		ps aux | grep -e 'java -Xmx' | grep -v grep | awk '{print $2}' | xargs -i kill {}
		ps aux | grep -e 'SCREEN -dmS minecraft java' | grep -v grep | awk '{print $2}' | xargs -i kill {}
		ps aux | grep -e '/etc/init.d/minecraft' | grep -v grep | awk '{print $2}' | xargs -i kill {}

	exit 1
}

get_script_location() {
	echo $(dirname "$(readlink -e "$0")")
}

check_permissions() {
	as_user "touch $pidfile"
	if ! as_user "test -w '$pidfile'" ; then 
		echo "Check Permissions. Cannot write to $pidfile. Correct the permissions and then excute: $0 status"
	fi
}

trap force_exit SIGINT

case "$1" in
	start)
		# Starts the server
		if is_running; then
			echo "Server already running."
		else
			check_links
			to_ram
			mc_start
		fi
		;;
	stop)
		# Stops the server
		if is_running; then
			mc_say "SERVER SHUTTING DOWN!"
			mc_stop
			to_disk
		else
			echo "No running server."
		fi
		;;
	restart)
		# Restarts the server
		if is_running; then
			mc_say "SERVER REBOOT IN 10 SECONDS!"
			mc_stop
			to_disk
		else
			echo "No running server, starting it..."
		fi
		check_links
		to_ram
		mc_start
		;;
	whitelist)
		if is_running; then
			whitelist
		else
			echo "Server not running."
		fi
		;;
	whitelist-reload)
		# Reloads the whitelist
		if is_running; then
			mc_command "whitelist reload"
		else
			echo "No running server."
		fi
		;;
	whitelist-add)
		# Adds a player to the whitelist
		if is_running; then
			mc_command "whitelist add $2"
		else
			echo "No running server."
		fi
		;;
	backup)
		# Backups world
		if is_running; then
			mc_say "Backing up world."
			mc_saveoff
			to_disk
			mc_world_backup
			mc_saveon
			mc_say "Backup complete."
		else
			mc_world_backup
		fi
		;;
	whole-backup)
				# Backup everything
		if is_running; then
			mc_say "COMPLETE SERVER BACKUP IN 10 SECONDS.";
			mc_say "WARNING: WILL RESTART SERVER SOFTWARE!"
			mc_stop
			to_disk
			mc_whole_backup
			check_links
			mc_start
		else
			mc_whole_backup
		fi
		;;
	check-update)
		check_update_vanilla
		check_update_craftbukkit
		as_user "rm $MCPATH/minecraft_server.jar.update"
		as_user "rm $MCPATH/craftbukkit.jar.update"
		;;
	update)
		#update minecraft_server.jar and craftbukkit.jar (thanks karrth)
		if is_running; then
			mc_say "SERVER UPDATE IN 10 SECONDS."
			mc_stop
			to_disk
			mc_whole_backup
			mc_update
			check_links
			mc_start
		else
			mc_whole_backup
			mc_update
		fi
		;;
	to-disk)
		# Writes from the ramdisk to disk, in case the server crashes. 
		mc_saveoff
		to_disk
		mc_saveon
		;;
	save-off)
		# Flushes the state of the world to disk, and then disables
		# saving until save-on is called (useful if you have your own
		# backup scripts).
		if is_running; then
			mc_saveoff
		else
			echo "Server was not running, syncing from ram anyway..."
		fi
		to_disk
		;;
	save-on)
		# Re-enables saving if it was disabled by save-off.
		if is_running; then
			mc_saveon
		else
			echo "No running server."
		fi
		;;
	say)
		# Says something to the ingame chat
		if is_running; then
			shift 1
			mc_say "$*"
		else
			echo "No running server to say anything."
		fi
		;;
	command)
		if is_running; then
			shift 1
			mc_command "$*"
			echo "Sent command: $*"
		else
			echo "No running server to send a command to."
		fi
		;;
	connected)
		# Lists connected users
		if is_running; then
			mc_command list
			sleep 3s
			tac $MCPATH/server.log | grep -m 1 "Connected"
		else
			echo "No running server."
		fi
		;;
	log-roll)
		# Moves and Gzips the logfile
		if [ ! -d $LOGPATH ]; then
			as_user "mkdir -p $LOGPATH"
		fi
		path=`datepath $LOGPATH/server_ .log.gz .log`
		as_user "cp $MCPATH/server.log $path && gzip $path"
		# only if previous command was successful
		if [ $? -eq 0 ]; then
			# turnacate the existing log without restarting server
			as_user "cp /dev/null $MCPATH/server.log"
			as_user "echo \"Previous logs rolled to $path\" > $MCPATH/server.log "
		else    
			echo "Failed to rotate logs to $LOGPATH/server_$path.log.gz"
		fi
		;;
	last)
		# Greps for recently logged in users
		echo Recently logged in users:
		cat $MCPATH/server.log | awk '/entity|conn/ {sub(/lost/,"disconnected");print $1,$2,$4,$5}'
		;;
	status)
		# Shows server status
		if is_running
		then
			echo "$SERVICE is running."
		else
			echo "$SERVICE is not running."
		fi
		;;
	version)
		if is_running; then
			mc_command version
			tac $MCPATH/server.log | grep -m 1 "This server is running"
		else
			echo "The server needs to be running to check version."
		fi
		;;
	links)
		check_links
		;;
	ramdisk)
		change_ramdisk_state $2
		;;
	worlds)
		get_worlds
		for INDEX in ${!WORLDNAME[@]}
		do
			if ${WORLDRAM[$INDEX]}
			then
				echo "${WORLDNAME[$INDEX]} (ramdisk)"
			else
				echo ${WORLDNAME[$INDEX]}
			fi
		done
		;;
	overviewer)
		if is_running; then
			mc_say "Generating overviewer map."
			mc_saveoff
			to_disk
			overviewer_copy_worlds
			mc_saveon
			overviewer_start $2
		else
			overviewer_copy_worlds
			overviewer_start $2
		fi
		;;
	screen)
		if is_running; then
			as_user 'script /dev/null -q -c "screen -rx $SCREEN"'
		else
		echo "Server is not running. Do you want to start it?"
		echo "Please put \"Yes\", or \"No\": "
		read START_SERVER
		case "$START_SERVER" in
			[Yy]|[Yy][Ee][Ss])
				check_links
				to_ram
				mc_start
				as_user 'script /dev/null -q -c "screen -rx $SCREEN"'
				;;
			[Nn]|[Nn][Oo])
				clear
				echo "Aborting startup!"
				sleep 1
				clear
				exit 1
				;;
			*)
				clear
				echo "Invalid input"
				sleep 1
				clear
				exit 1
				;;
		esac
		fi
		;;
	kill)
		WIDTH=`stty size | cut -d ' ' -f 2`            # Get terminal's character width
		pstree | grep MDSImporte | cut -c 1-${WIDTH}   # Chop output after WIDTH chars
		
		echo "Killing the server is an EMERGENCY procedure, and should not be used to perform a normal shutdown! All changes younger than 15 minutes could be permanantly lost and WORLD CORRUPTION is possible! Are you ABSOLUTELY POSITIVE this is what you want to do?"
		echo "Please put \"Yes\", or \"No\": "
		read KILL_SERVER
		case "$KILL_SERVER" in	# Determine which option was specified
			[Yy]|[Yy][Ee][Ss])	# If yes, kill the server
				echo "KILLING SERVER PROCESSES!!!"
				force_exit
				exit 1
				;;
			[Nn]|[Nn][Oo])	# If no, abort and exit 1
				echo "Aborting!"
				exit 1
				;;
			*)	# If anything else, exit 1
				echo "Error: Invalid Input!"
				exit 1
				;;
		esac
		;;
	help|--help|-h)
		echo "Usage: $0 COMMAND"
		echo 
		echo "Available commands:"
		echo -e "   start \t\t Starts the server"
		echo -e "   stop \t\t Stops the server"
		echo -e "   kill \t\t Kills the server"
		echo -e "   restart \t\t Restarts the server"
		echo -e "   backup \t\t Backups the worlds defined in the script"
		echo -e "   whole-backup \t Backups the entire server folder"
		echo -e "   check-update \t Checks for updates of $CB_JAR and $MC_JAR"
		echo -e "   update \t\t Fetches the latest version of minecraft.jar server and Bukkit"
		echo -e "   log-roll \t\t Moves and gzips the logfile"
		echo -e "   to-disk \t\t Copies the worlds from the ramdisk to worldstorage"
		echo -e "   save-off \t\t Flushes the world to disk and then disables saving"
		echo -e "   save-on \t\t Re-enables saving if it was previously disabled by save-off"
		echo -e "   say \t\t\t Prints the given string to the ingame chat."
		echo -e "   connected \t\t Lists connected users"
		echo -e "   status \t\t Displays server status"
		echo -e "   version \t\t Displays Bukkit version and then exits"
		echo -e "   links \t\t Creates nessesary symlinks"
		echo -e "   last \t\t Displays recently connected users"
		echo -e "   worlds \t\t Displays a list of available worlds"
		echo -e "   ramdisk WORLD \t Toggles ramdisk configuration for WORLD"
		echo -e "   overviewer WORLD \t Creates a map of the WORLD with Minecraft-Overviewer"
		echo -e "   whitelist \t\t Prints the current whitelist"
		echo -e "   whitelist-add NAME \t Adds the specified player to the server whitelist"
		echo -e "   whitelist-reload \t Reloads the whitelist"
		echo -e "   screen \t\t Shows the server screen"
		;;
	*)
		echo "No such command, see $0 help"
		exit 1
		;;
esac

exit 0