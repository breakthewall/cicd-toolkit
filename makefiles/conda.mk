include ../.ci_env

SHELL := /bin/bash
PACKAGE = $(shell python ../../setup.py --name)
VERSION = $(shell python ../../setup.py --version)
PLATFORM = $(shell conda info | grep platform | awk '{print $$3}')
recipe := ../recipe
meta := meta.yaml

build-recipe:
	echo "{% set name = \"${PACKAGE}\" %}" > $(recipe)/$(meta)
	cat $(recipe)/_meta1.yaml >> $(recipe)/$(meta)
	sed '1,/dependencies/d' ../../environment.yaml \
		| sed -e 's#.*- \(\)#\1#' \
	> $(recipe)/deps.yaml
	echo -n `grep "^python[ <>=]" $(recipe)/deps.yaml | grep -e "=" -e ">" -e "<"` > $(recipe)/_python
	echo "  host:" >> $(recipe)/$(meta)
	if [ -s $(recipe)/_python ]; then \
		echo -n "    - " >> $(recipe)/$(meta); \
		cat $(recipe)/_python >> $(recipe)/$(meta); \
		echo >> $(recipe)/$(meta); \
		echo "  run:" >> $(recipe)/$(meta); \
		echo -n "    - " >> $(recipe)/$(meta); \
		cat $(recipe)/_python >> $(recipe)/$(meta); \
		echo >> $(recipe)/$(meta) \
		sed /"`cat $(recipe)/_python`"/d $(recipe)/deps.yaml > $(recipe)/deps2.yaml \
		cat $(recipe)/deps2.yaml \
			| sed "s/^\(.*\)::\(.*\)$$/\2/" \
			| awk '{print "    - " $$0}' \
		>> $(recipe)/$(meta); \
		echo "" >> $(recipe)/$(meta); \
	else \
		echo "    - python {{ python }}" >> $(recipe)/$(meta); \
		echo "  run:" >> $(recipe)/$(meta); \
		echo "    - python {{ python }}" >> $(recipe)/$(meta); \
	fi;
	cat $(recipe)/deps.yaml \
		| grep -v python \
		| sed "s/^\(.*\)::\(.*\)$$/\2/" \
		| awk '{print "    - " $$0}' \
	>> $(recipe)/$(meta); \
	cat $(recipe)/_meta2.yaml >> $(recipe)/$(meta)
	sed -ne '/^dependencies:$$/{:a' -e 'n;p;ba' -e '}' ../conda_envs/test.yaml | awk '{print "    - "$$2}' >> $(recipe)/$(meta)
	cat $(recipe)/_meta3.yaml >> $(recipe)/$(meta)
	echo "    - `$(MAKE_CMD) -f test.mk test-cmd`" >> $(recipe)/$(meta)
	cat $(recipe)/_meta4.yaml >> $(recipe)/$(meta)
	echo > $(recipe)/_conda_channels.txt
	cat $(recipe)/deps.yaml \
		| sed "s/^\(.*\)::\(.*\)$$/\2 - \1/" \
		| awk '{print $$3}' \
	>> $(recipe)/_conda_channels.txt
	awk '/channels/,/dependencies/{if(/dependencies|channels/) next; print}' ../../environment.yaml \
		| awk '{print $$2}' \
	>> $(recipe)/_conda_channels.txt
	cat $(recipe)/_conda_channels.txt \
		| tr -d " \t\r" \
		| awk '!/^$$/' \
	> $(recipe)/conda_channels.txt
	rm -f \
		$(recipe)/_conda_channels.txt \
		$(recipe)/deps.yaml \
		$(recipe)/deps2.yaml \
		$(recipe)/_python
	echo -n '--override-channels ' > $(recipe)/_conda_channels_cmd.txt
	for channel in `cat $(recipe)/conda_channels.txt`; do \
		echo -n '--channel '$$channel' ' >> $(recipe)/_conda_channels_cmd.txt; \
	done

# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## Basic help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

help-advanced: ## Advanced help.
	@awk 'BEGIN {FS = ":.*?# "} /^[a-zA-Z_-]+:.*?# / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

# cli args
ARGS = $(filter-out $@,$(MAKECMDGOALS))
CONDA_BUILD_ARGS = --quiet --numpy 1.11
MAKE_CMD = $(MAKE) -s --no-print-directory
ECHO = echo -n ">>>"

conda-clean: conda-clean-build

define check
	$(1) && echo OK
endef


# CONDA

## CONDA BASICS
### update
conda-update:
	@$(ECHO) "Updating conda... "
	@conda update -q -y -n base -c defaults conda > /dev/null \
	&& echo OK
### install package
conda-install-%:
	@$(ECHO) "Installing $*... "
ifeq (,$(channel))
	@check,conda install -y $* > /dev/null \
	&& echo OK
else
	@conda install -y -c $(channel) $* > /dev/null \
	&& echo OK
endif
### check recipe
conda-recipe-check:
	@$(ECHO) "Checking the recipe... "
	@conda run --name $(env) \
		conda build --check $(CONDA_BUILD_ARGS) $(recipe) \
	> /dev/null \
	&& echo OK
### clean build products
conda-clean-build:
	@rm -f ${CONDA_BLD_PATH}/${PLATFORM}/${PACKAGE}-${VERSION}*.tar.bz2
conda-clean-all:
	@rm -rf ${CONDA_BLD_PATH}
# ### Add channels specified in recipe
# conda-add-channel-%:
# 	@conda run -n $(env) conda config --env --quiet --add channels $* > /dev/null
# ## Check channels
# conda-add-channels:
# 	@for channel in $(recipe_channels) ; do \
# 		$(MAKE_CMD) -f conda.mk conda-add-channel-$$channel ; \
# 	done

# Variants
ifneq ($(strip $(variants)),)
	VARIANTS = --variants=\"$(variants)\"
endif

## CONDA BUILD
### build only
conda-build-only: check-environment-build build-recipe
	@$(ECHO) "Building conda package... "
	@conda run --name $(env) \
		conda build \
			`cat $(recipe)/_conda_channels_cmd.txt` \
			--no-test $(CONDA_BUILD_ARGS) $(VARIANTS) \
			--output-folder ${CONDA_BLD_PATH} \
			$(recipe) \
	> /dev/null \
	&& echo OK

conda-test-only: check-environment-build build-recipe
	@$(ECHO) "Testing conda package... "
	@conda run --name $(env) \
		conda build \
			`cat $(recipe)/_conda_channels_cmd.txt` \
			--test $(CONDA_BUILD_ARGS) \
			${CONDA_BLD_PATH}/${PLATFORM}/${PACKAGE}-${VERSION}*.tar.bz2 \
	&& echo OK

### build+test
# conda-build: conda-build-test
conda-build: check-environment-build build-recipe
	@$(ECHO) "Building and Testing conda package... "
	@conda run --name $(env) \
		conda build \
		`cat $(recipe)/_conda_channels_cmd.txt` \
		$(CONDA_BUILD_ARGS) $(VARIANTS) \
		--output-folder ${CONDA_BLD_PATH} \
		$(recipe) \
	> /dev/null \
	&& echo OK

conda-convert: check-conda
	@$(ECHO) "Converting conda package from ${PLATFORM} to osx-64, linux-64 and win-64... "
	@conda run --name $(env) \
		conda convert \
		        --platform osx-64 \
		        --platform linux-64 \
		        --platform win-64 \
		        --output-dir ${CONDA_BLD_PATH} \
		        ${CONDA_BLD_PATH}/${PLATFORM}/${PACKAGE}-${VERSION}*.tar.bz2 > /dev/null \
	&& echo OK


### publish
SECRETS = ../.secrets
ifneq ("","$(wildcard $(SECRETS))")
	ANACONDA_TOKEN = $(shell cat $(SECRETS) | grep ANACONDA_TOKEN | awk 'BEGIN {FS = "="} ; {print $$2}')
	ANACONDA_USER  = $(shell cat $(SECRETS) | grep ANACONDA_USER | awk 'BEGIN {FS = "="} ; {print $$2}')
endif
conda-publish:
	@$(ECHO) "Publishing conda package... "
	conda run --name $(env) \
		anaconda \
			--token ${ANACONDA_TOKEN} \
			upload \
			--user ${ANACONDA_USER} \
			--label ${ANACONDA_LABEL} \
			--skip-existing \
			${CONDA_BLD_PATH}/${PLATFORM}/${PACKAGE}-${VERSION}*.tar.bz2


# ENVIRONMENT CHECKING
## Check conda
ifeq (,$(shell which conda))
    HAS_CONDA=False
else
    HAS_CONDA=True
    ENV_DIR=$(shell conda info --base)
    MY_ENV_DIR=$(ENV_DIR)/envs/$(env)
    CONDA_ACTIVATE=source $$(conda info --base)/etc/profile.d/conda.sh ; conda activate ; conda activate
endif
check-conda:
ifeq (False,$(HAS_CONDA))
	$(error >>> Install conda first.)
endif

## Check conda-build
ifeq (,$(shell which conda-build))
    HAS_CONDA_BUILD=False
else
    HAS_CONDA_BUILD=True
endif
check-conda-build:
ifeq (False,$(HAS_CONDA_BUILD))
	echo conda env -n $(PACKAGE)_build create -f $(recipe)/conda_build_env.yaml
endif

## Check anaconda-client
ifeq (,$(shell which anaconda))
    HAS_ANACONDA_CLIENT=False
else
    HAS_ANACONDA_CLIENT=True
endif
check-anaconda-client:
ifeq (False,$(HAS_ANACONDA_CLIENT))
	@$(MAKE_CMD) -f conda.mk conda-install-anaconda-client channel=conda-forge
endif


build_env_file := ../conda_envs/build.yaml
check_env_file := ../conda_envs/check.yaml
test_env_file := ../conda_envs/test.yaml
main_env_file  := ../../environment.yaml


check-environment-%: check-conda build-environment-%
	@

build-environment-test: check-conda
ifneq ("$(wildcard $(MY_ENV_DIR))","") # check if the directory is there
	@$(ECHO) "'$(env)' environment already exists."
	@echo
else
	@$(ECHO) "Creating '$(env)' environment... "
	@conda env create -n $(env) -f $(main_env_file) > /dev/null
	@conda run -n $(env) conda env update -f $(test_env_file) > /dev/null
	@echo OK
endif

build-environment-%: check-conda
ifneq ("$(wildcard $(MY_ENV_DIR))","") # check if the directory is there
	@$(ECHO) "'$(env)' environment already exists."
	@echo
else
	@$(ECHO) "Creating '$(env)' environment... "
	@conda env create -n $(env) -f $($(*)_env_file) > /dev/null
	@echo OK
endif

# build-environment-check: check-conda
# ifneq ("$(wildcard $(MY_ENV_DIR))","") # check if the directory is there
# 	@$(ECHO) "'$(env)' environment already exists."
# 	@echo
# else
# 	@$(ECHO) "Creating '$(env)' environment... "
# 	@conda env create -n $(env) -f $(check_env_file) > /dev/null
# 	@echo OK
# endif

conda-run-env:
ifneq ($(strip $(cmd)),)
	conda run --name $(env) $(cmd) args="$(args)"
else
	@conda run --name $(env) \
		$(MAKE_CMD) -f conda.mk $(target) args="$(args)"
endif
