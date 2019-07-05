BASE=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

GOGS_APP_NAME=gogs
GOGS_USER=gogs
DEV_PROJECT=development
PROD_PROJECT=production
REPO_DIR=simpleweb
REPO_URI=$(GOGS_USER)/$(REPO_DIR).git
REPO_DESCRIPTION="A simple Go web server."
JENKINS_JOB_NAME=$(REPO_DIR)
SMARTCHECK_URL=https://CHANGE_ME_SMARTCHECK_URL
SMARTCHECK_USER=CHANGE_ME_SMARTCHECK_USER
SMARTCHECK_PASSWORD=CHANGE_ME_SMARTCHECK_PASSWORD
ROUTING_SUFFIX=$(shell $(BASE)/scripts/getroutingsuffix)


# Uncomment this block if you are installing it on RHPDS but are not running
# this on the bastion. Be sure to set GUID to a value which is appropriate for
# your environment.
#
#GUID=XXX-XXXX
#ROUTING_SUFFIX=apps.$(GUID).openshiftworkshop.com


# Uncomment this block if you are installing it on OPENTLC. Set GUID to a value
# that is appropriate for your environment. Set PROJ_PREFIX to your OPENTLC
# user ID. This ensures that the project names are unique in the OPENTLC
# shared environment.
#
#GUID=naXXX
#PROJ_PREFIX=XXXX
#ROUTING_SUFFIX=apps.$(GUID).openshift.opentlc.com
#DEV_PROJECT=$(PROJ_PREFIX)-dev
#PROD_PROJECT=$(PROJ_PREFIX)-prod


.PHONY: printvar deployall deploygogs waitforgogs setupgogs setupdev \
deployjenkins setupprod clean console gogs jenkins curl loop src

deployall: printvar setupgogs setupdev deployjenkins setupprod
	@echo "Done"

help:
	@echo "Make targets:"
	@echo "deployall - Deploy the demo."
	@echo "clean - Delete all projects created by deployall."
	@echo "console - OpenShift console."
	@echo "gogs - cart repo in Gogs."
	@echo "jenkins - Jenkins web UI."
	@echo "curl - Send a curl request to the production web service."
	@echo "loop - Continually perform a curl request to the production web service."
	@echo "src - main.go in Gogs."

printvar:
	@echo "ROUTING_SUFFIX = $(ROUTING_SUFFIX)"
	@echo "GOGS_APP_NAME = $(GOGS_APP_NAME)"
	@echo "GOGS_USER = $(GOGS_USER)"
	@echo "DEV_PROJECT = $(DEV_PROJECT)"
	@echo "PROD_PROJECT = $(PROD_PROJECT)"
	@echo "REPO_DIR = $(REPO_DIR)"
	@echo "REPO_URI = $(REPO_URI)"
	@echo "REPO_DESCRIPTION = $(REPO_DESCRIPTION)"
	@echo "JENKINS_JOB_NAME = $(JENKINS_JOB_NAME)"
	@echo "SMARTCHECK_URL = $(SMARTCHECK_URL)"
	@echo "SMARTCHECK_USER = $(SMARTCHECK_USER)"
	@echo "SMARTCHECK_PASSWORD = $(SMARTCHECK_PASSWORD)"
	@echo
	@echo "Press enter to proceed"
	@read


deploygogs:
	@echo "Deploying gogs..."
	@$(BASE)/scripts/switchtoproject $(DEV_PROJECT)
	@oc process \
	  -f $(BASE)/yaml/gogs-template.yaml \
	  -p PROJECT=$(DEV_PROJECT) \
	  -p ROUTING_SUFFIX=$(ROUTING_SUFFIX) \
	| \
	oc create -f -
	@oc rollout latest dc/postgresql-gogs


waitforgogs: deploygogs
	@$(BASE)/scripts/waitforgogs $(DEV_PROJECT)


setupgogs: waitforgogs
	@echo "Creating gogs user..."
	@oc rsh dc/postgresql-gogs /bin/sh -c 'LD_LIBRARY_PATH=/opt/rh/rh-postgresql10/root/usr/lib64 /opt/rh/rh-postgresql10/root/usr/bin/psql -U gogs -d gogs -c "INSERT INTO public.user (lower_name,name,email,passwd,rands,salt,max_repo_creation,avatar,avatar_email,num_repos) VALUES ('"'$(GOGS_USER)','$(GOGS_USER)','$(GOGS_USER)@gogs,com','40d76f42148716323d6b398f835438c7aec43f41f3ca1ea6e021192f993e1dc4acd95f36264ffe16812a954ba57492f4c107','konHCHTY7M','9XecGGR6cW',-1,'e4eba08430c43ef06e425e2e9b7a740f','$(GOGS_USER)@gogs.com',1"')"'

	@cp $(BASE)/$(REPO_DIR)/Jenkinsfile /tmp/
	@sed -i -e 's|devProject = "[^"]*|devProject = "$(DEV_PROJECT)|' /tmp/Jenkinsfile
	@sed -i -e 's|prodProject = "[^"]*|prodProject = "$(PROD_PROJECT)|' /tmp/Jenkinsfile
	@sed -i -e 's|smartcheck_url = "[^"]*|smartcheck_url = "$(SMARTCHECK_URL)|' /tmp/Jenkinsfile
	@sed -i -e 's|smartcheck_username = "[^"]*|smartcheck_username = "$(SMARTCHECK_USER)|' /tmp/Jenkinsfile
	@sed -i -e 's|smartcheck_password = "[^"]*|smartcheck_password = "$(SMARTCHECK_PASSWORD)|' /tmp/Jenkinsfile
	@cp -f /tmp/Jenkinsfile $(BASE)/$(REPO_DIR)/
	@rm -f /tmp/Jenkinsfile

	@$(BASE)/scripts/pushtogogs $(DEV_PROJECT) $(GOGS_USER) gogs $(REPO_URI) $(BASE)/$(REPO_DIR) $(REPO_DIR) $(REPO_DESCRIPTION)


setupdev:
	@echo "Setting up development project..."
	@$(BASE)/scripts/switchtoproject $(DEV_PROJECT)
	oc create -f $(BASE)/yaml/dev.yaml


deployjenkins:
	@echo "Deploying Jenkins..."
	@$(BASE)/scripts/switchtoproject $(DEV_PROJECT)
	@oc new-app jenkins-persistent \
	  -n $(DEV_PROJECT) \
	  -p MEMORY_LIMIT=4Gi \
	  -e SMARTCHECK_URL=$(SMARTCHECK_URL)

	@cp $(BASE)/jenkins-job.xml /tmp/jenkins-job-work.xml
	@echo "Update the jenkins template file with the actual demo environment settings..."
	@sed -i -e 's|<url>.*</url>|<url>http://$(GOGS_APP_NAME)-$(DEV_PROJECT).$(ROUTING_SUFFIX)/$(REPO_URI)</url>|' /tmp/jenkins-job-work.xml
	@sed -i -e 's|<name>demo1</name>|<name>$(GOGS_USER)</name>|' /tmp/jenkins-job-work.xml

	@$(BASE)/scripts/jenkinsavailable $(DEV_PROJECT)
	@echo "Create Jenkins job definition..."
	@oc rsh -n $(DEV_PROJECT) dc/jenkins mkdir -p /var/lib/jenkins/jobs/$(JENKINS_JOB_NAME)
	@oc cp -n $(DEV_PROJECT) /tmp/jenkins-job-work.xml `oc get -n $(DEV_PROJECT) pods -o custom-columns=:.metadata.name | grep jenkins | grep -v deploy`:/var/lib/jenkins/jobs/$(JENKINS_JOB_NAME)/config.xml
	@rm -f /tmp/jenkins-job-work.xml
	@oc cp -n $(DEV_PROJECT) $(BASE)/scripts/initiatescan `oc get -n $(DEV_PROJECT) pods -o custom-columns=:.metadata.name | grep jenkins | grep -v deploy`:/usr/bin/
	@oc cp -n $(DEV_PROJECT) $(BASE)/scripts/waitforscan `oc get -n $(DEV_PROJECT) pods -o custom-columns=:.metadata.name | grep jenkins | grep -v deploy`:/usr/bin/
	@oc cp -n $(DEV_PROJECT) $(BASE)/scripts/scanfindings `oc get -n $(DEV_PROJECT) pods -o custom-columns=:.metadata.name | grep jenkins | grep -v deploy`:/usr/bin/
	@oc cp -n $(DEV_PROJECT) scripts/ocdelete `oc get -n $(DEV_PROJECT) pods -o custom-columns=:.metadata.name | grep jenkins | grep -v deploy`:/usr/bin/


setupprod:
	@echo "Setting up production project..."
	@$(BASE)/scripts/switchtoproject $(PROD_PROJECT)
	@oc create -f $(BASE)/yaml/prod.yaml

	# Let the jenkins user promote images to the production project.
	@oc policy add-role-to-user \
	  edit \
	  system:serviceaccount:$(DEV_PROJECT):jenkins \
	  -n $(PROD_PROJECT)


clean:
	@echo "Removing projects..."
	@oc delete project $(DEV_PROJECT)
	@oc delete project $(PROD_PROJECT)


console:
	$(eval URL="`$(BASE)/scripts/masterurl`/console")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi


gogs:
	$(eval URL="http://$(GOGS_APP_NAME)-$(DEV_PROJECT).$(ROUTING_SUFFIX)/$(REPO_URI")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi


jenkins:
	$(eval URL="https://jenkins-$(DEV_PROJECT).$(ROUTING_SUFFIX)")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi


curl:
	@curl http://$(REPO_DIR)-$(PROD_PROJECT).$(ROUTING_SUFFIX)/


loop:
	@while true; do \
	  curl http://$(REPO_DIR)-$(PROD_PROJECT).$(ROUTING_SUFFIX)/; \
	  sleep 1; \
	done

src:
	$(eval URL="http://$(GOGS_APP_NAME)-$(DEV_PROJECT).$(ROUTING_SUFFIX)/$(GOGS_USER)/$(REPO_DIR)/src/master/src/$(REPO_DIR)/main.go")
	@if [ "$(shell uname)" = "Darwin" ]; then \
	  open ${URL}; \
	else \
	  echo "${URL}"; \
	fi
