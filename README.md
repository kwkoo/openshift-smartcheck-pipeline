# OpenShift Smart Check Pipeline

This project sets up a Jenkins pipeline that builds a simple Go web app and runs the image through the Trend Micro Deep Security Smart Check image scanner. It does not setup Smart Check.

You can setup Smart Check by following the instructions [here](https://github.com/deep-security/smartcheck-helm).


## Installation

You need to have the `oc` binary before running the install. You will also need to have run the `oc login` command to log into the OpenShift API.

Edit the `Makefile` and set the variables to the necessary values. At a minimum, you will need to set the `SMARTCHECK_URL`, `SMARTCHECK_USER`, and `SMARTCHECK_PASSWORD` variables.

If you are deploying this to RHPDS and are running this on the bastion, the rest of the variables should be set automatically. The variables should also be set automatically if you are deploying this to minishift. If you are deploying this on some other setup, you may need to manually set the `ROUTING_SUFFIX` to the appropriate value.

Once you're ready, start the install by running `make`. You'll get a chance to verify the variable values before proceeding with the actual install.

After the installation is done, 2 projects should be created - `development` and `production`.

The `development` project should contains a Gogs git server as well as Jenkins. The Go web app is stored in Gogs. You can login to Gogs with the username `gogs` and the password `gogs`. The Jenkins pipeline is located in `simpleweb/Jenkinsfile`.

* The pipeline will compile the Go source code using the source-to-image process.
* Once an executable binary is created, a second build process will be kicked off to create an image based on the centos:7 base image. The second build process uses `simpleweb/Dockerfile` for the build.
* Once the image is created, an API call is made to Smart Check to perform a scan on the newly-created image.
* If the scan completes with no high-level vulnerabilities found, a pod is instantiated in the `development` project, and a `curl` request is performed against the app to make sure that the app runs without any errors,
* The Jenkins user is then prompted to check if this image should be promoted to the `production` project.
* If this request is approved, the image is tagged to the app running in the `production` project.

