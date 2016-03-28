#!/bin/bash

# Either uncomment the following lines and specify their value,
# or leave them commented and export these vars before calling the script.
#CF_AUTH_USR="" # Account email address.
#CF_AUTH_KEY="" # CloudFlare API key.

#
#	CloudFlare API functions
#

function get_zone {
	local DOMAIN="${1}"

	zone=$(echo "$DOMAIN" | grep -P -o '[^\.]+(?:(?=\.co\.uk)\.co)?\.[a-z]+$')
	if [[ $? != 0 ]]; then
		return 1
	fi

	json=$(curl -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&per_page=1" \
				-H "X-Auth-Email: $CF_AUTH_USR" -H "X-Auth-Key: $CF_AUTH_KEY" -H "Content-Type: application/json" -s)

	if [[ ${json} == *"\"success\":true"* ]]; then
		echo "$json" | grep -P -o '(?<="id":")[^"]+' | head -1
	else
		echo "$json" | grep -P -o '(?<="message":")[^"]+' 1>&2
		return 1
	fi
}

function get_record {
	local DOMAIN="${1}"

	if [[ ! -z $2 ]]; then
		zone_id="${2}"
	else
		zone_id=$(get_zone "$DOMAIN")
		if [[ $? != 0 ]]; then
			echo "$zone_id" 1>&2
			return 1
		fi
	fi

	json=$(curl -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=TXT&name=$DOMAIN&per_page=1" \
				-H "X-Auth-Email: $CF_AUTH_USR" -H "X-Auth-Key: $CF_AUTH_KEY" -H "Content-Type: application/json" -s)

	if [[ ${json} == *"\"success\":true"* && ${json} == *"\"id\":\""* ]]; then
		echo "$json" | grep -P -o '(?<="id":")[^"]+' | head -1
	else
		echo "$json" | grep -P -o '(?<="message":")[^"]+' 1>&2
		return 1
	fi
}

function add_record {
	local DOMAIN="${1}" VALUE="${2}"

	if [[ ! -z $3 ]]; then
		zone_id="${3}"
	else
		zone_id=$(get_zone "$DOMAIN")
		if [[ $? != 0 ]]; then
			echo "$zone_id" 1>&2
			return 1
		fi
	fi

	json=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
				-H "X-Auth-Email: $CF_AUTH_USR" -H "X-Auth-Key: $CF_AUTH_KEY" -H "Content-Type: application/json" -s \
				--data '{"type":"TXT","name":"'"$DOMAIN"'","content":"'"$VALUE"'"}')

	if [[ ${json} == *"\"success\":true"* ]]; then
		echo "$json" | grep -P -o '(?<="id":")[^"]+' | head -1
	else
		echo "$json" | grep -P -o '(?<="message":")[^"]+' 1>&2
		return 1
	fi
}

function del_record {
	local DOMAIN="${1}"

	if [[ ! -z $2 ]]; then
		zone_id="${2}"
	else
		zone_id=$(get_zone "$DOMAIN")
		if [[ $? != 0 ]]; then
			echo "$zone_id" 1>&2
			return 1
		fi
	fi

	record_id=$(get_record "$DOMAIN" "$zone_id")
	if [[ $? != 0 ]]; then
		echo "$record_id" 1>&2
		return 1
	fi

	json=$(curl -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
				-H "X-Auth-Email: $CF_AUTH_USR" -H "X-Auth-Key: $CF_AUTH_KEY" -H "Content-Type: application/json" -s)

	if [[ ${json} == *"\"success\":true"* ]]; then
		echo "$json" | grep -P -o '(?<="id":")[^"]+' | head -1
	else
		echo "$json" | grep -P -o '(?<="message":")[^"]+' 1>&2
		return 1
	fi
}

#
#	LetsEncrypt.sh hook functions
#

function deploy_challenge {
	local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

	echo " + Checking existence of _acme-challenge.$DOMAIN..."

	zone_id=$(get_zone "$DOMAIN")
	if [[ $? != 0 ]]; then
		echo "  - Failed to get zone ID: $zone_id" 1>&2
		return 1
	fi

	delres=$(del_record "_acme-challenge.$DOMAIN" "$zone_id")
	if [[ $? == 0 ]]; then
		echo "  + Removed previous record."
	fi

	echo " + Adding new TXT record _acme-challenge.$DOMAIN..."

	addres=$(add_record "_acme-challenge.$DOMAIN" "$TOKEN_VALUE" "$zone_id")
	if [[ $? == 0 ]]; then
		echo "  + Successfully added."
	else
		echo "  - Failed to add: $addres" 1>&2
	fi

	echo " + Waiting for record propagation..."

	sleep 5

	tries=0
	while [[ ${tries} -lt 30 ]]; do
		digres=$(dig txt +trace +noall +answer "_acme-challenge.$DOMAIN" | grep -P "^_acme-challenge\.$DOMAIN")
		if [[ $? == 0 ]]; then
			echo "  + Successfully propagated."
			break
		fi

		tries=$((tries + 1))
		if [[ ${tries} -ge 30 ]]; then
			echo "  - Failed to propagate record in a timely manner." 2>&1
			return 1
		fi

		echo "  - Retrying in 10s..."
		sleep 10
	done
}

function clean_challenge {
	local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

	echo " + Removing _acme-challenge.$DOMAIN..."

	delres=$(del_record "_acme-challenge.$DOMAIN")
	if [[ $? == 0 ]]; then
		echo "  + Successfully removed."
	else
		echo "  - Failed to remove: $delres" 1>&2
	fi
}

function deploy_cert {
	local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

	if [[ -f deploy.sh ]]; then
		./deploy.sh $@
	fi
}

function unchanged_cert {
	local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

	if [[ -f unchanged.sh ]]; then
		./unchanged.sh $@
	fi
}

#
#   Entry point
#

if [[ -z ${CF_AUTH_USR} || -z ${CF_AUTH_KEY} ]]; then
	echo error: CloudFlare authentication not configured
	exit 1
fi

HANDLER=$1; shift; ${HANDLER} $@
