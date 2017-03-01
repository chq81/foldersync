#!/bin/bash

program=$(basename $0)

function usage()
{
	echo "
	Usage: $program [-h]
	" >&2
	exit 1
}

if [ $# -lt 1 ]; then
	usage
fi

while getopts p:h option; do
	case $option in
		p) vProfile=$OPTARG;;
		h) usage;;
		*) usage;;
	esac
done

