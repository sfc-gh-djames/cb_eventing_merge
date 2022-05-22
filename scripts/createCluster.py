#!/usr/bin/env python

import os
import re
import docker
import time
import urllib.request
import requests
import json

from requests.auth import HTTPBasicAuth


def wait_for_container(seconds, ip, port):
    http_url = 'http://{}:{}'.format(ip, port)
    success = False
    while seconds > 0 and success is False:
        time.sleep(1)
        try:
            http_status = urllib.request.urlopen(http_url)
            if http_status.code == 200:
                success = True
                break
        except OSError:
            print('.', end='', flush=True)
    return success

def wait_for_bucket(seconds, bucket, ip, port):
    http_url = 'http://{}:{}'.format(ip, port)
    success = False
    while seconds > 0 and success is False:
        time.sleep(1)
        response = requests.get(http_url + '/pools/default/buckets/' + bucket, auth=auth)
        response_json = response.json()
        vb_server_count = len(response_json['vBucketServerMap']['serverList'])
        if vb_server_count > 0:
            success = True
            break
        print('.', end='', flush=True)
    return success

## BEGIN MAIN
CB_CONTAINERNAME = "cb_merge"
CB_CONTAINERTAG = "enterprise-7.1.0"
CB_CLUSTERNAME = "Couchbase Eventing Demo"
CB_HOST = "127.0.0.1"
SCRIPT_PATH = re.sub(r'/scripts', '', os.path.dirname(os.path.realpath(__file__)))
CB_PORTS = {8091: 8091,
            8092: 8092,
            8093: 8093,
            8094: 8094,
            8095: 8095,
            8096: 8096,
            11210: 11210,
            11211: 11211}

docker_client = docker.from_env()

# stop and remove container if already running
try:
    docker_container = docker_client.containers.get(CB_CONTAINERNAME)
    docker_container.stop()
    docker_container.remove()
    print("Docker Container stopped and deleted")
except docker.errors.NotFound:
    print("Docker Container not running. Moving on...")

try:
    docker_container = docker_client.containers.run('couchbase:' + CB_CONTAINERTAG,
                                                    detach=True,
                                                    name=CB_CONTAINERNAME,
                                                    volumes={SCRIPT_PATH + '/data':
                                                                 {'bind': '/cb_share', 'mode': 'rw'}},
                                                    ports=CB_PORTS
                                                    )
    print('Container ' + CB_CONTAINERNAME + ' started with share: ' + SCRIPT_PATH + '/data')
except docker.errors.ImageNotFound:
    print("Docker container unable to start. Image couchbase:" + CB_CONTAINERTAG + " not found.")
    quit()
except docker.errors.APIError:
    print("Docker container unable to start. Perhaps another container is already using one of the following ports: " + str(CB_PORTS.keys()))
    quit()

#
wait = 60
print('Waiting %d seconds for container to start ' % wait, end='', flush=True)
if wait_for_container(wait, CB_HOST, 8091) is False:
    print(' ** CONTAINER FAILED TO START. EXITING...')
    exit(99)
#
print()

print("Container started successfully. Starting configuration...")
kv_url = 'http://{}:8091'.format(CB_HOST)
event_url = 'http://{}:8096'.format(CB_HOST)
auth = HTTPBasicAuth('Administrator', 'password')

print("**** Initialize CB Server Node")
data = {"path": "/opt/couchbase/var/lib/couchbase/data", "index_path": "/opt/couchbase/var/lib/couchbase/indexes",
        "cbas_path": "/opt/couchbase/var/lib/couchbase/cbas",
        "eventing_path": "/opt/couchbase/var/lib/couchbase/eventing"}
response = requests.post(kv_url + '/nodes/self/controller/settings', auth=auth, data=data)

# Rename Node
print("**** Renaming Node")
rename = {'hostname': CB_HOST}
# response = requests.post(kv_url + '/node/controller/rename', auth=auth, data=rename)
response = requests.post(kv_url + '/node/controller/rename', auth=auth, data={"hostname": CB_HOST})
# response = requests.post(kv_url + '/node/controller/rename', auth=auth, data='hostname=' + CB_HOST)

# Set up services (Data [kv], Eventing)
print("**** Set up Cluster Services (Data & Eventing)")
response = requests.post(kv_url + '/node/controller/setupServices', auth=auth, data={"services": "kv,eventing"})

# Set Memory Quotas
print("**** Set Service Memory Quotas")
response = requests.post(kv_url + '/pools/default', auth=auth,
                         data={"memoryQuota": 1024, "eventingMemoryQuota": 512})

# Use Administrator/password for console login
print("**** Set console login credentials")
response = requests.post(kv_url + '/settings/web', auth=auth,
                         data={"password": "password", "username": "Administrator", "port": 8091})

# Create buckets: demobucket - 512mb memory quota, no replicas, enable flush (optional)
for bucket in ["customer", "eventing_merge", "schema1", "schema2"]:
    print("**** Creating Bucket: %s" % bucket)
    response = requests.post(kv_url + '/pools/default/buckets', auth=auth,
                             data={"name": bucket, "ramQuotaMB": 128, "authType": "sasl",
                                   "saslPassword": "9832cae99c0972343d54760f124d1f59", "replicaNumber": 0,
                                   "replicaIndex": 0, "bucketType": "couchbase", "flushEnabled": 1})

# Create Collections in schema1 bucket
for collection in ["customers", "addresses", "postal_codes"]:
    print("**** Creating Collection: schema1.%s" % collection)
    response = requests.post(kv_url + '/pools/default/buckets/schema1/scopes/_default/collections', auth=auth,
                             data={"name": collection})

# Check bucket status
# response = requests.get(kv_url + '/pools/default/buckets/schema1', auth=auth)
# col_response = requests.get(kv_url + '/pools/default/buckets/schema1/scopes', auth=auth)
# response_json = response.json()
# vb_server=response_json['vBucketServerMap']['serverList']
# vb_server_count=len(vb_server)

# Check bucket status
wait = 30
print("Waiting %d seconds for buckets to warm up " % wait, end='', flush=True)
if wait_for_bucket(wait, "schema1", CB_HOST, 8091) is False:
    print(" ** BUCKETS FAILED TO WARM UP. EXITING...")
    exit(99)

print("\nBucket warmup complete. Loading sample data...")

# Load sample data into Buckets
cbimport = "cbimport json --format list -c http://" + CB_HOST + ":8091 -u Administrator -p password -d file:///cb_share/{file}.json -b {bucket} --scope-collection-exp \"_default.{collection}\" -g %{property_id}%"
docker_container.exec_run(
    cbimport.format(file="schema1_postcodes", bucket="schema1", collection="postal_codes", property_id="postal_code"))
docker_container.exec_run(
    cbimport.format(file="schema1_addresses", bucket="schema1", collection="addresses", property_id="address_id"))
docker_container.exec_run(
    cbimport.format(file="schema1_customers", bucket="schema1", collection="customers", property_id="email"))
docker_container.exec_run(
    cbimport.format(file="schema2_customers", bucket="schema2", collection="_default", property_id="email"))

print("**** Rename Cluster")
response = requests.post(kv_url + '/pools/default', auth=auth, data={"clusterName": CB_CLUSTERNAME})

print("**** Import Eventing Functions")
with open(SCRIPT_PATH + "/scripts/schema1_merge.json", 'rb') as payload:
    response = requests.post(event_url + '/api/v1/functions/schema1_merge', auth=auth,
                             data=payload)
with open(SCRIPT_PATH + "/scripts/schema2_merge.json", 'rb') as payload:
    response = requests.post(event_url + '/api/v1/functions/schema2_merge', auth=auth,
                             data=payload)

print("******** DONE ********")
