#!/bin/bash

# createCluster.sh
# Spin up Docker container running CB Server with KV and Eventing Services
# Then create a number of buckets and collections to demo using Eventing
# for data consolidation

# wait_for_container seconds ip_address port
# Check for a response from http://ip_address:port and return error code
# if a response is not received in seconds
wait_for_container() {
	local SECONDS=${1}
	local IP=${2}
	local PORT=${3}
	local success=1 # has not (yet) succeeded
	while [ ${SECONDS} -gt 0 ]; do
		SECONDS=$((SECONDS-1))
		curl -sf ${IP}:${PORT} -o /dev/null
		if [ $? -eq 0 ]; then
			success=0 # connection succeeded
			break;
		fi
		sleep 1
		echo -n "."
	done
	echo " " # add carriage return
	return $success
}

# wait_for_bucket seconds bucket ip_address port
# Check for a response from http://ip_address:port and return error code
# if a response is not received in seconds
wait_for_bucket() {
	local SECONDS=${1}
	local BUCKET=${2}
	local IP=${3}
	local PORT=${4}
	local success=1 # has not (yet) succeeded

	# Check if 'jq' available. If not, just do a simple wait
	echo | jq 2>/dev/null
	if [ $? -ne 0 ]; then
	  sleep ${SECONDS}
	  return 0
  fi

	while [ ${SECONDS} -gt 0 ]; do
		SECONDS=$((SECONDS-1))
		VB_SERVER_COUNT=$(expr $(curl -sS -X GET -u Administrator:password http://${IP}:${PORT}/pools/default/buckets/${BUCKET} | jq '.vBucketServerMap.serverList | length'))
		if [ ${VB_SERVER_COUNT} -gt 0 ]; then
			success=0 # connection succeeded
			break;
		fi
		sleep 1
		echo -n "."
	done
	echo " " # add carriage return
	return $success
}

## BEGIN ##
CB_CONTAINERNAME=cb_merge
CB_CONTAINERTAG=enterprise-7.1.0
CB_CLUSTERNAME="Couchbase Eventing Demo"
CB_HOST=localhost


# DEBUG Option: uncomment the following to disable output from curl statements
#               comment the following to allow full output from curl statements
CURL_DEBUG="-sS --output /dev/null" # Uncomment this to silence output
# CURL_DEBUG="-v" # Uncomment this to get full verbosity

export LOCPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
if [ ! -d ${LOCPATH} ]; then # this shouldn't happen unless, of course, the above is overridden
	echo "${0}: LOCPATH does not exist (${LOCPATH})" >&2
	exit 99
fi

# Stop and remove existing containers, if they're running
echo "**** Stopping and removing existing containers"
( docker stop ${CB_CONTAINERNAME} ; docker rm ${CB_CONTAINERNAME} ) >/dev/null 2>/dev/null

################################################################################
# Create Cluster Container
echo "**** Creating Cluster Container"
# echo "**************************************************"
# echo " "
docker run -d -v "$LOCPATH/data":/cb_share \
	-p 8091-8096:8091-8096 \
	-p 11210-11211:11210-11211 \
	--name ${CB_CONTAINERNAME} couchbase:${CB_CONTAINERTAG} >/dev/null

wait=60
echo -n "Waiting up to ${wait} seconds for cluster to start"
wait_for_container ${wait} ${CB_HOST} 8091
success=$?
if [ $success -ne 0 ]; then
	echo "Server container failed to start!" >&2
	exit 99
fi

################################################################################
# Initialize CB Server Node
echo " " ; echo " "
echo "**** Initialize CB Server Node"
# echo " "
curl ${CURL_DEBUG} -u Administrator:password -X POST http://${CB_HOST}:8091/nodes/self/controller/settings \
	-d path=/opt/couchbase/var/lib/couchbase/data \
	-d index_path=/opt/couchbase/var/lib/couchbase/indexes \
	-d cbas_path=/opt/couchbase/var/lib/couchbase/cbas \
	-d eventing_path=/opt/couchbase/var/lib/couchbase/eventing 2>/dev/null

# Rename Node
echo "**** Renaming Node"
curl ${CURL_DEBUG} -u Administrator:password -X POST http://${CB_HOST}:8091/node/controller/rename \
	-d hostname=${CB_HOST} 2>/dev/null

# Set up services (Data [kv], Eventing)
echo "**** Set up Cluster Services (Data & Eventing)"
curl ${CURL_DEBUG} -u Administrator:password -X POST http://${CB_HOST}:8091/node/controller/setupServices \
	-d services=kv%2Ceventing 2>/dev/null

# Set Memory Quotas
echo "**** Set Service Memory Quotas"
curl ${CURL_DEBUG} -u Administrator:password -X POST http://${CB_HOST}:8091/pools/default \
	-d memoryQuota=1024 \
	-d eventingMemoryQuota=512 2>/dev/null

# Use Administrator/password for console login
echo "**** Set console login credentials"
curl ${CURL_DEBUG} -u Administrator:password -X POST http://${CB_HOST}:8091/settings/web \
	-d password=password \
	-d username=Administrator \
	-d port=8091 2>/dev/null

# Create buckets: demobucket - 512mb memory quota, no replicas, enable flush (optional)
for bucket in customer eventing_merge schema1 schema2; do
	echo "**** Creating Bucket: ${bucket}"
	curl ${CURL_DEBUG} -X POST -u Administrator:password http://${CB_HOST}:8091/pools/default/buckets \
		-d name=${bucket} -d ramQuotaMB=128 -d authType=sasl -d saslPassword=9832cae99c0972343d54760f124d1f59 \
		-d replicaNumber=0 \
		-d replicaIndex=0 \
		-d bucketType=couchbase \
		-d flushEnabled=1 2>/dev/null
done

# Create collections
for collection in customers addresses postal_codes; do
	echo "**** Creating schema1 collection: ${collection}"
	curl ${CURL_DEBUG} -u Administrator:password \
		http://${CB_HOST}:8091/pools/default/buckets/schema1/scopes/_default/collections \
		-d name=${collection}
done

wait=30
echo -n "Waiting up to ${wait} seconds for buckets to warm up"
wait_for_bucket ${wait} "schema1" ${CB_HOST} 8091
success=$?
if [ $success -ne 0 ]; then
	echo "Bucket warm up failed to complete!" >&2
	exit 99
fi

echo "**** Loading sample data into CB"
docker exec -it ${CB_CONTAINERNAME} cbimport json --format list -c http://${CB_HOST}:8091 \
	-u Administrator -p password -d 'file:///cb_share/schema1_postcodes.json' \
	-b 'schema1' --scope-collection-exp "_default.postal_codes" -g %postal_code%
docker exec -it ${CB_CONTAINERNAME} cbimport json --format list -c http://${CB_HOST}:8091 \
	-u Administrator -p password -d 'file:///cb_share/schema1_addresses.json' \
	-b 'schema1' --scope-collection-exp "_default.addresses" -g %address_id%
docker exec -it ${CB_CONTAINERNAME} cbimport json --format list -c http://${CB_HOST}:8091 \
	-u Administrator -p password -d 'file:///cb_share/schema1_customers.json' \
	-b 'schema1' --scope-collection-exp "_default.customers" -g %email%
docker exec -it ${CB_CONTAINERNAME} cbimport json --format list -c http://${CB_HOST}:8091 \
	-u Administrator -p password -d 'file:///cb_share/schema2_customers.json' \
	-b 'schema2' -g %email%

echo "**** Renaming Cluster"
curl ${CURL_DEBUG} -X POST --output /dev/null -u Administrator:password http://${CB_HOST}:8091/pools/default \
	-d clusterName="${CB_CLUSTERNAME}"

# Import eventing functions
cd $LOCPATH/scripts
echo "**** Importing eventing functions"
# sleep 3
curl ${CURL_DEBUG} -XPOST -d @./schema1_merge.json \
	http://Administrator:password@${CB_HOST}:8096/api/v1/functions/schema1_merge 
curl ${CURL_DEBUG} -XPOST -d @./schema2_merge.json \
	http://Administrator:password@${CB_HOST}:8096/api/v1/functions/schema2_merge

