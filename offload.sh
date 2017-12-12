#!/bin/bash

# offload.sh
# ----------
# Checks and sets offload settings of network devices

#set -x

MODE="list"
SSH_PORT=22

declare -a ALL_OFFLOADS=( rx tx sg tso ufo gso gro lro rxvlan txvlan ntuple rxhash )

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
if [ ${#DEVICES[@]} -eq 0 ]
then
	if [ ${PORT} -ne 22 ]
	then
		DEVICES+=( $( ssh -p ${PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "/sbin/ip addr | grep '^[0-9]*:' | grep -v \@ | awk -F':' '{ print \$2 }' | sed -e 's/ //g'" ) )
	else
		DEVICES+=( $( ssh -q ${REMOTE_USER}@${REMOTE_HOST} "/sbin/ip addr | grep '^[0-9]*:' | grep -v \@ | awk -F':' '{ print \$2 }' | sed -e 's/ //g'" ) )
	fi
fi

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
		#echo "ssh -q ${REMOTE_USER}@${REMOTE_HOST} \"/usr/sbin/ethtool -K ${DEVICE} ${COMMAND}\""
		if [[ "${USER}" == "root" ]]
		then
			if [ ${PORT} -ne 22 ]
			then
				ssh -p ${PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "/usr/sbin/ethtool -K ${DEVICE} ${COMMAND}"
			else
				ssh -q ${REMOTE_USER}@${REMOTE_HOST} "/usr/sbin/ethtool -K ${DEVICE} ${COMMAND}"
			fi
		else
			if [ ${PORT} != 22 ]
			then
				ssh -p ${PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "sudo /usr/sbin/ethtool -K ${DEVICE} ${COMMAND}"
			else
				ssh -q ${REMOTE_USER}@${REMOTE_HOST} "sudo /usr/sbin/ethtool -K ${DEVICE} ${COMMAND}"
			fi
		fi
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
		for DEVICE in ${DEVICES[@]}
		do
			if [ -z ${INPUT_FILE} ]
			then
				if [ ${PORT} -ne 22 ]
				then
					LIST=$( ssh -p ${PORT} -q ${REMOTE_USER}@${REMOTE_HOST} "/usr/sbin/ethtool -k ${DEVICE}" )
				else
					LIST=$( ssh -q ${REMOTE_USER}@${REMOTE_HOST} "/usr/sbin/ethtool -k ${DEVICE}" )
				fi
			else
				LIST=$( grep ${DEVICE} ${INPUT_FILE} | awk -F";" '{ print $2 }' )
			fi
			declare -A CURRENT_STATE=()
			printf "%20s" "${DEVICE} "
			
			IFS=$'\n'
			for ITEM in ${LIST}
			do
				if [ ! -z ${OUTPUT_FILE} ]
				then
					echo "${DEVICE};${ITEM}" >> ${OUTPUT_FILE}
				fi
				NAME=$( echo "${ITEM}" | awk -F":" '{ print $1 }' | sed -e 's/ //g' )
				STATE=$( echo "${ITEM}" | awk -F":" '{ print $2 }' | sed -e 's/ //g' )
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
			done

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
		done
		;;
esac

for ITEM in ${UNKNOWN[@]}
do
	echo "UNKNOWN: ${ITEM}"
done
