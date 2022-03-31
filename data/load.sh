#!/bin/bash

desthost=localhost
container=cb_merge

docker cp schema1_postcodes.json ${container}:/tmp/
docker cp schema1_addresses.json ${container}:/tmp/
docker cp schema1_customers.json ${container}:/tmp/
docker cp schema2_customers.json ${container}:/tmp/

docker exec -it ${container} cbimport json --format list -c http://${desthost}:8091 -u Administrator -p password -d 'file:///tmp/schema1_postcodes.json' -b 'schema1' --scope-collection-exp "_default.postal_codes" -g %postal_code%
docker exec -it ${container} cbimport json --format list -c http://${desthost}:8091 -u Administrator -p password -d 'file:///tmp/schema1_addresses.json' -b 'schema1' --scope-collection-exp "_default.addresses" -g %address_id%
docker exec -it ${container} cbimport json --format list -c http://${desthost}:8091 -u Administrator -p password -d 'file:///tmp/schema1_customers.json' -b 'schema1' --scope-collection-exp "_default.customers" -g %email%
docker exec -it ${container} cbimport json --format list -c http://${desthost}:8091 -u Administrator -p password -d 'file:///tmp/schema2_customers.json' -b 'schema2' -g %email%
