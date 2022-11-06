# **Project Overview**

This project is related to the Couchbase Blog Post, *[Using the Eventing Service to Consolidate Data from Multiple Sources](https://www.couchbase.com/blog/eventing-data-consolidation-in-couchbase/)*, and contains scripts to deploy and configure a Couchbase cluster locally using a *Docker container*, including loading sample data.
### Steps

1) Ensure Docker is installed and the Docker engine is running<br>
2) Create the cluster - *Note that on Unix systems (other than MacOS), this script may require sudo in order to execute the Docker commands*<br>
&nbsp;&nbsp;&nbsp;a) `scripts/createCluster.sh` - For Unix-based systems (or Windows with *Windows Subsystem for Linux* available). <br>
&nbsp;&nbsp;&nbsp;b) `scripts/createCluster.py` - For Windows-based systems (or really for any platform) with Python installed. <br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;*Note - this requires the [Docker SDK for Python](https://docker-py.readthedocs.io/en/stable/) as a prerequisite to run*<br>
3) Deploy the eventing functions
4) Check the customer bucket to see that it has populated. You should see 500 documents.

### Finally

When you're done, you can stop and remove the docker container:

` docker stop cb_merge`<br>
 `docker rm cb_merge`
----
### Disclaimer
*All contacts and company names contained in this demo were generated via code and any similarity to existing names is accidental and unintentional.*
