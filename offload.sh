#!/bin/bash

# offload.sh
# ----------
# Checks and sets offload settings of network devices

#set -x

MODE="list"
SSH_PORT=22

declare -a ALL_OFFLOADS=( rx tx sg tso ufo gso gro lro rxvlan txvlan ntuple rxhash )

function allDevices {
	REMOTE_COMMAND=""
	if [[ "${REMOTE_USER}" != "root" ]]
	then
		ETHTOOL_COMMAND="sudo ${ETHTOOL_COMMAND}"
	fi
	for DEVICE in ${DEVICES[@]}
	do
		if [[ "${DEVICE}" == "lo" ]]
		then
			continue
		fi
		#echo "DEVICE: ${DEVICE}"
		if [[ "${REMOTE_COMMAND}" != "" ]]
		then
			if [[ "${EXTRA_OPTIONS}" != "" ]]
			then
				REMOTE_COMMAND="${REMOTE_COMMAND}; ${ETHTOOL_COMMAND} ${DEVICE} ${EXTRA_OPTIONS}"
			else
				REMOTE_COMMAND="${REMOTE_COMMAND}; ${ETHTOOL_COMMAND} ${DEVICE}"
			fi
		else
			if [[ "${EXTRA_OPTIONS}" != "" ]]
			then
				REMOTE_COMMAND="${ETHTOOL_COMMAND} ${DEVICE} ${EXTRA_OPTIONS}"
			else
				REMOTE_COMMAND="${ETHTOOL_COMMAND} ${DEVICE}"
			fi
		fi
	done
	if [ ${CAPTURE_OUTPUT} -eq 1 ]
	then
		ALL_DEVICES=$( ssh -p ${SSH_PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "${REMOTE_COMMAND}" )
	else
		ssh -p ${SSH_PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "${REMOTE_COMMAND}"
	fi
	#echo "ssh -p ${SSH_PORT} -q ${REMOTE_USER}@${REMOTE_HOST} \"${REMOTE_COMMAND}\""

}

function changeAllDevices {
	CAPTURE_OUTPUT=0
        ETHTOOL_COMMAND='/usr/sbin/ethtool -K'
	EXTRA_OPTIONS="${@}"
        allDevices
}

function listAllDevices {
	CAPTURE_OUTPUT=1
	ETHTOOL_COMMAND='/usr/sbin/ethtool -k'
	EXTRA_OPTIONS=""
	allDevices
}

function outputValues {
	COUNT=0
	declare -a UNKNOWN
	for ITEM in ${ALL_OFFLOADS[@]}
	do
		case ${CURRENT_STATE[${ITEM}]} in
			"on")
				echo -en "${BG_GREEN}"
				printf "%6s" " "
				echo -en "${NC}"
				;;
			"on[fixed]")
				echo -en "${BG_GREEN}"
				printf "%6s" "F"
				echo -en "${NC}"
				;;
			"on[requestedon]")
				echo -en "${BG_GREEN}"
				printf "%6s" "R: ON"
				echo -en "${NC}"
				;;
			"off")
				echo -en "${BG_RED}"
				printf "%6s" " "
				echo -en "${NC}"
				;;
			"off[fixed]")
				echo -en "${BG_RED}"
				printf "%6s" "F"
				echo -en "${NC}"
				;;
			"off[requestedon]")
				echo -en "${BG_RED}"
				printf "%6s" "R: ON"
				echo -en "${NC}"
				;;
			*)
				printf "%6s" "?"
				UNKNOWN+=( ${CURRENT_STATE[${ITEM}]} )
				;;
		esac
		(( COUNT+=1 ))
		if [ ${COUNT} -lt ${#ALL_OFFLOADS[@]} ]
		then
			echo -en " "
		else
			echo
		fi
	done	
}

while [ ${#} -gt 0 ]
do
	case ${1} in
		"-c"|"--command")
			COMMAND=${2}
			shift
			;;
		"-d"|"--device")
			DEVICE=${2}
			shift
			;;
		"-h"|"--host")
			REMOTE_HOST=${2}
			shift
			;;
		"-i"|"--input-file")
			INPUT_FILE=${2}
			shift
			;;
		"-m"|"--mode")
			MODE=${2}
			shift
			;;
		"-o"|"--output-file")
			OUTPUT_FILE=${2}
			if [ -e ${OUTPUT_FILE} ]
			then
				rm -f ${OUTPUT_FILE}
			fi
			shift
			;;
		"-p"|"--port")
			SSH_PORT=${2}
			shift
			;;
		"-u"|"--user")
			REMOTE_USER=${2}
			shift
			;;
	esac
	shift
done

if [ -z ${REMOTE_HOST} ] || [ -z ${REMOTE_USER} ]
then
	echo
	echo "ERROR: You must supply a remote host and remote user with -h and -u"
	echo
	echo "E.g. ${0} -h myhost -u myuser"
	echo
	exit 1
fi

# Get list of devices from remote host
declare -a DEVICES
#if [ ${#DEVICES[@]} -eq 0 ]
#then
#	DEVICES+=( $( ssh -p ${SSH_PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "/sbin/ip addr | grep '^[0-9]*:' | grep -v \@ | awk -F':' '{ print \$2 }' | sed -e 's/ //g'" ) )
#fi

case ${DEVICE} in
	"all"|"")
		DEVICES+=( $( ssh -p ${SSH_PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "/sbin/ip addr | grep '^[0-9]*:' | grep -v \@ | awk -F':' '{ print \$2 }' | sed -e 's/ //g'" ) )
		;;
	*)
		DEVICES+=( ${DEVICE} )
		;;
esac

BG_RED='\033[41m'
BG_GREEN='\033[42m'
NC='\033[0m'

case ${MODE} in
	"set")
		if [ -z "${COMMAND}" ] || [ -z "${DEVICE}" ]
		then
			echo
			echo "ERROR: You must supply a command and a device device with -c and -d when using set"
			echo
			echo "E.g. ${0} -c \"sg off\" -d eth0"
			echo
			exit 1
		fi
		if [[ "${COMMAND}" == "on" ]] || [[ "${COMMAND}" == "off" ]]
		then
			STATE=${COMMAND}
			COMMAND=""
			for OFFLOAD in ${ALL_OFFLOADS[@]}
			do
				COMMAND="${COMMAND} ${OFFLOAD} ${STATE}"
			done
		fi
		
		changeAllDevices ${COMMAND}
		;;
	"list")
		printf "%20s" "Interface "
		COUNT=0
		for VALUE in ${ALL_OFFLOADS[@]}
		do
			printf "%6s" "${VALUE}"
			(( COUNT+=1 ))
			if [ ${COUNT} -lt ${#ALL_OFFLOADS[@]} ]
			then
				echo -en " "
			else
				echo
			fi
		done
		listAllDevices
		IFS=$'\n'
		for LINE in ${ALL_DEVICES}
		do
			if [[ "${LINE}" =~ 'Features for' ]]
			then
				if [ ${#CURRENT_STATE[@]} -gt 0 ]
				then
					outputValues
				fi
				DEVICE=$( echo ${LINE} | awk -F" " '{ print $NF }' | sed -e 's/:$//' )
				printf "%20s" "${DEVICE} "
				declare -A CURRENT_STATE=()
			else
				NAME=$( echo "${LINE}" | awk -F":" '{ print $1 }' | sed -e 's/ //g' )
				STATE=$( echo "${LINE}" | awk -F":" '{ print $2 }' | sed -e 's/ //g' )
				case ${NAME} in
					"rx-checksumming")
						CURRENT_STATE+=( ["rx"]="${STATE}" )
						;;
					"tx-checksumming")
						CURRENT_STATE+=( ["tx"]="${STATE}" )
						;;
					"scatter-gather")
						CURRENT_STATE+=( ["sg"]="${STATE}" )
						;;
					"tcp-segmentation-offload")
						CURRENT_STATE+=( ["tso"]="${STATE}" )
						;;
					"udp-fragmentation-offload")
						CURRENT_STATE+=( ["ufo"]="${STATE}" )
						;;
					"generic-segmentation-offload")
						CURRENT_STATE+=( ["gso"]="${STATE}" )
						;;
					"generic-receive-offload")
						CURRENT_STATE+=( ["gro"]="${STATE}" )
						;;
					"large-receive-offload")
						CURRENT_STATE+=( ["lro"]="${STATE}" )
						;;
					"rx-vlan-offload")
						CURRENT_STATE+=( ["rxvlan"]="${STATE}" )
						;;
					"tx-vlan-offload")
						CURRENT_STATE+=( ["txvlan"]="${STATE}" )
						;;
					"ntuple-filters")
						CURRENT_STATE+=( ["ntuple"]="${STATE}" )
						;;
					"receive-hashing")
						CURRENT_STATE+=( ["rxhash"]="${STATE}" )
						;;
				esac
			fi
		done
		outputValues
		;;
esac

for ITEM in ${UNKNOWN[@]}
do
	echo "UNKNOWN: ${ITEM}"
done
