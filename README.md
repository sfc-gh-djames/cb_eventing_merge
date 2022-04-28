# *<span style="color:orange">WORK IN PROGRESS!</span>*
# **Project Overview**

This project is related to the Couchbase Blog Post, *[Using Eventing to import data from multiple sources](http://blog.couchbase.com/)* and contains scripts to deploy and configure a Couchbase cluster locally using a *Docker container*, including loading sample data.

### Steps

1) Ensure Docker is installed and the Docker engine is running<br>
2) Create the cluster<br>
&nbsp;&nbsp;&nbsp;a) `scripts/createCluster.sh` - For Unix-based systems (or Windows with *Windows Subsystem for Linux* available). <br>
&nbsp;&nbsp;&nbsp;b) `scripts/createCluster.py` - For Windows-based systems with Python installed<br>
   &nbsp;&nbsp;&nbsp;<br>
3) Deploy the eventing functions
4) Check the customer bucket to see that it has populated. You should see 500 documents.

###Finally

When you're done, you can stop and remove the docker container:

` docker stop cb_merge`<br>
 `docker rm cb_merge`
