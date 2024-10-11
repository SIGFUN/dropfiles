#!/bin/bash -O extglob

# Module preamble
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
	echo "library modules cannot be executed directly" >&2
	exit 1
fi

if [ -z "$libdir" ]; then
	echo "library modules must be initialized by sourcer" >&2
	exit 1
fi

# Imports
. "${libdir}/Lib.sh"
. "${libdir}/Module.sh"

# MARK: Object Fields
F_STATISTICS_SERIES=()
F_STATISTICS_MEAN=
F_STATISTICS_MEDIAN=

# MARK: Internal
function Statistics._mean_slow()
{
	local n=$#
	local t=0
	local mean=

	if [ $n -eq 0 ]; then
		echo "0"
		return
	fi

	for si in "$@"; do
		(( t += si ))
	done

	mean=$(( t / n ))
	echo "$mean"
}

function Statistics._find_quartiles()
{
	local n=$#
	local q1=$(( (n * 1) / 4 ))
	local q2=$(( (n * 2) / 4 ))
	local q3=$(( (n * 3) / 4 ))
	local q=()
	local sorted=()

	if [ $n -eq 0 ]; then
		echo "0 0 0"
		return
	fi

	sorted=($(IFS=$'\n' ; echo "$*" | sort -n))
	q=("${sorted[$q1]}" "${sorted[$q2]}" "${sorted[$q3]}")
	echo "${q[@]}"
}

function Statistics._standard_deviation_slow()
{
	local mean="$1"
	local n=${#F_STATISTICS_SERIES[@]}
	local variance=
	local d=

	if [ "$n" -eq 0 ]; then
		echo "0"
		return
	fi

	shift
	for si in "$@"; do
		local v_n=

		v_n=$(( si - mean ))
		v_n=$(( v_n ** 2 ))
		(( variance += v_n ))
	done

	variance=$(( variance / n ))
	d="$(bc <<< "sqrt($variance)")"

	echo "$d"
}

# MARK: Meta
function Statistics.available()
{
	return 0
}

# MARK: Public
function Statistics.init()
{
	F_STATISTICS_SERIES=("$@")
	F_STATISTICS_MEAN=
	F_STATISTICS_MEDIAN=
}

function Statistics.init_excluded()
{
	local curated=()
	local q=($(Statistics._find_quartiles "$@"))
	local q1=${q[0]}
	local q3=${q[2]}
	local iqr=$(( q3 - q1 ))
	local fence_lo=$(bc <<< "q1 - ($iqr * 3 / 2)")
	local fence_hi=$(bc <<< "q3 + ($iqr * 3 / 2)")

	for si in "$@"; do
		if [ $si -lt $fence_lo ]; then
			continue
		fi

		if [ $si -gt $fence_hi ]; then
			continue
		fi

		curated+=("$si")
	done

	Statistics.init "${curated[@]}"
}

function Statistics.mean()
{
	if [ -z "$F_STATISTICS_MEAN" ]; then
		F_STATISTICS_MEAN=$(Statistics._mean_slow "${F_STATISTICS_SERIES[@]}")
	fi

	echo "$F_STATISTICS_MEAN"
}

function Statistics.median()
{
	if [ -z "$F_STATISTICS_MEDIAN" ]; then
		local q=($(Statistics._find_quartiles "$@"))
		F_STATISTICS_MEDIAN="${q[1]}"
	fi

	echo "$F_STATISTICS_MEDIAN"
}

function Statistics.standard_deviation()
{
	local mean=$(Statistics.mean)
	Statistics._standard_deviation_slow "$mean" "${F_STATISTICS_SERIES[@]}"
}
