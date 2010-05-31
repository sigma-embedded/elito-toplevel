GIT = git
AUTORECONF    = autoreconf
ELITO_DIR     = de.sigma-chemnitz
GITREPO_BASE  = elito

UPSTREAM_REPOS = org.openembedded kernel

UPSTREAM_DIR_org.openembedded	 = org.openembedded
UPSTREAM_GIT_org.openembedded    = git://git.openembedded.net/openembedded
UPSTREAM_BRANCH_org.openembedded = org.openembedded.dev

UPSTREAM_DIR_kernel = workspace/kernel.git
UPSTREAM_GIT_kernel = git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6
UPSTREAM_BRANCH_kernel = master

ifneq (${_MODE},configure)
_topdir = .
endif

-include ${_topdir}/project.conf
-include ${_topdir}/.config
-include ${_topdir}/.config_$(shell hostname -d)
-include ${_topdir}/.config_${HOSTNAME}

ifeq (${_MODE},configure)
-include ./build-setup
-include ./build-setup_$(shell hostname -d)
-include ./build-setup_${HOSTNAME}
endif
export ELITO_CRT

_fetch_targets = \
	$(addprefix .stamps/elito_fetch-,${ELITO_REPOS})

help:
	@echo -e "\
Usage:  make <op> [M=<module>]\n\
\n\
<op> can be:\n\
    prepare      ...  download submodules and initialize global buildsystem\n\
    update       ...  like 'prepare' but updates existing installation\n\
\n\
    configure M=<module>\n\
    configure-all    ...  calls ./configure for module M or all registered\n\
                          projects; this target will read additional\n\
                          parameters from ./build-setup files in the module\n\
                          directory.\n\
\n\
    reconfigure M=<module>\n\
    reconfigure-all  ...  calls ./config.status --recheck for module M or all\n\
                          registered projects\n\
\n\
    build M=<module>\n\
    build-all        ...  builds module M resp. all registered ones\n\
    build-failed     ...  builds all registered modules which failed during\n\
                          previous 'build-all', 'build-failed' or \n\
                          'build-incomplete' operations\n\
    build-incomplete ...  builds all registered modules which have not been\n\
                          built yet\n\
\n\
"

_submodules = $(shell $(GIT) submodule status --cached | awk '{ print $$2 }')

commit-submodules:
	$(GIT) commit -m "updated submodules:`echo; echo; git submodule summary`" ${_submodules}

ifneq ($M,)
reconfigure:
	cd $M && ./config.status --recheck

init:
	-$(MAKE) update
	$(MAKE) -C $M
	$(MAKE) -C $M init

build:
	make -C $M image MAKEFLAGS= MAKEOVERRIDES= $(if $(TARGETS),TARGETS='$(TARGETS)')

clean mrproper:
	make -C $M $@

else				# ifneq ($M,)

build:	build-all

endif				# ifneq ($M,)

ifeq ($M,)
configure-all:		$(addprefix .configure-,$(PROJECTS))
reconfigure-all:	$(addprefix .reconfigure-,$(PROJECTS))
build-all:		$(addprefix .clean-complete-,$(PROJECTS)) \
			$(addprefix .build-,$(PROJECTS))
clean-all:		$(addprefix .clean-,$(PROJECTS))
init-all:		$(addprefix .init-,$(PROJECTS))
rebuild-all:		$(addprefix .rebuild-,$(PROJECTS))
build-failed:		$(addprefix .build-failed-,$(PROJECTS))
build-incomplete:	$(addprefix .build-incomplete-,$(PROJECTS))

prepare:	.stamps/git-submodule .stamps/autoconf

update:		prepare
	$(GIT) remote update
	$(GIT) pull
	$(GIT) submodule update
	$(MAKE) $(addprefix .stamps/elito_fetch-,${ELITO_REPOS}) _MODE=fetch
	$(MAKE) .stamps/autoconf-update

.reconfigure-%:
	${MAKE} reconfigure M=$*

.clean-complete-%:
	@rm -f .succeeded-$*

.build-%:	.clean-complete-% .init-%
	@touch .failed-$*
	@! tty -s || echo -ne "\033]0;OE Build $*@$${HOSTNAME%%.*}:$${PWD/#$$HOME/~} - `date`\007"
	${MAKE} .build-target-$*
	@rm -f .failed-$*
	@date > .succeeded-$*

.build-failed-%:
	! test -e .failed-$* || $(MAKE) .build-$*

.build-incomplete-%:
	test -e .succeeded-$* || $(MAKE) .build-$*

.build-target-%:
	$(MAKE) M=$* build

.clean-%:	.clean-complete-%
	rm -rf $*/tmp .succeeded-$* .failed-$*

.init-%:
	$(MAKE) init M=$*

.rebuild-%:
	$(MAKE) .clean-$*
	$(MAKE) .init-$*
	$(MAKE) .build-$*

.stamps/autoconf-update:	$(ELITO_DIR)/configure.ac
	rm -f .stamps/autoconf
	$(MAKE) prepare
	$(MAKE) $(addprefix .reconfigure-,${PROJECTS})
	@mkdir -p $(@D)
	@touch $@

.stamps/git-submodule:	Makefile
	$(GIT) submodule init
	$(if ${_fetch_targets},$(MAKE) ${_fetch_targets} _MODE=fetch)
	$(GIT) submodule update
	@mkdir -p $(@D)
	@touch $@

.stamps/autoconf:
	cd $(ELITO_DIR) && $(AUTORECONF) -i -f
	@mkdir -p $(@D)
	@touch $@

endif

########################################################################################

ifeq (${_MODE},configure)
# special handling of configure: targets which require project dependent
# NFSROOT + CACHEROOT variables


ifeq ($(NFSROOT),)
$(error "NFSROOT not set")
endif

ifeq ($(CACHEROOT),)
$(error "CACHEROOT not set")
endif

_opts = \
	--enable-maintainer-mode	\
	--with-cache-dir='${CACHEROOT}' \
	${CONFIGURE_OPTIONS}

configure:
	${_topdir}/de.sigma-chemnitz/configure ${_opts}

else
.configure-%:
	${MAKE} configure M='$*'

ifneq ($M,)
configure:
	${MAKE} -C '$M' -f $(abspath Makefile) configure _MODE=configure _topdir=$(abspath .)
endif

endif


######################################################################################

ifeq (${_MODE},fetch)

_submodules := ${_submodules}

define _register_alternate
	test -d $2/.git/object && g=$2/.git || g=$2; \
	echo $1 > $$g/objects/info/alternates
endef

define _git_create_branch
	-cd $1 && $(GIT) branch --track "$2" remotes/"$3"/"$2"

endef

define _git_init
	mkdir -p $2
	-cd "$2" && $6 $$(GIT) init -q
	$$(foreach a,$3,$$(call _register_alternate,$$a,$2))
	-cd "$2" && $$(GIT) remote add $4 '$5'

	@mkdir -p $$(@D)
	@touch $$@
endef

define _git_fetch
	$$(foreach b,$4,$$(call _git_create_branch,$2,$$b,$3))
	@mkdir -p $$(@D)
	@touch $$@
endef

##### _build_upstream_fetch(repo) #######
define _build_upstream_fetch
.stamps/upstream_init-$1:
	$(call _git_init,$1,$${UPSTREAM_DIR_$1},$${UPSTREAM_ALTERNATES_$1},upstream,$${UPSTREAM_GIT_$1},$${_git_init_prefix})

.stamps/upstream_fetch-$1:	.stamps/upstream_init-$1
	-cd $${UPSTREAM_DIR_$1} && $$(GIT) fetch upstream --no-tags +$${UPSTREAM_BRANCH_$1}:refs/remotes/upstream/$${UPSTREAM_BRANCH_$1}
	$(call _git_fetch,$1,$${UPSTREAM_DIR_$1},upstream,)

.stamps/upstream_setup-$1:	.stamps/upstream_fetch-$1
	@mkdir -p $$(@D)
	@touch $$@

.stamps/submodule_init-$1:	.stamps/upstream_fetch-$1

endef					# _build_upstream_fetch


##### _build_elito_fetch(repo) #######
define _build_elito_fetch

.stamps/elito_init-$1 \
.stamps/upstream_init-$1:	_git_init_prefix=env GIT_DIR=.

.stamps/elito_init-$1:
	$(call _git_init,$1,$${ELITO_REPO_DIR_$1},$${ELITO_REPO_ALTERNATES_$1},\
		--mirror elito,$${ELITO_REPO_URI_$1},$${_git_init_prefix})

.stamps/elito_fetch-$1:		.stamps/elito_init-$1
	-cd $${ELITO_REPO_DIR_$1} && $$(GIT) fetch elito
	$(call _git_fetch,$1,$${ELITO_REPO_DIR_$1},elito,)

.stamps/elito_init-$1:		$$(foreach r,$$(ELITO_REPO_UPSTREAM_$1), .stamps/upstream_fetch-$r)

.PHONY:	.stamps/elito_fetch-$1

endef					# _build_elito_fetch


##### _build_submodule_fetch(submodule) #######
define _build_submodule_fetch
_submodule_$1_uri := $$(shell $$(GIT) config "submodule.$1.url")

.stamps/upstream_setup-$1:	.stamps/submodule_update-$1
.stamps/submodule_update-$1:	.stamps/submodule_fetch-$1

.stamps/submodule_init-$1:
	-cd $1 && $$(GIT) remote add origin $$(_submodule_$1_uri)

.stamps/submodule_fetch-$1:		.stamps/submodule_init-$1
	-cd $1 && $$(GIT) fetch origin --no-tags
	-cd $1 && { test -n "`$$(GIT) ls-remote . HEAD`" || $$(GIT) checkout -q FETCH_HEAD; }

.stamps/submodule_update-$1:
	$$(GIT) submodule update $1
endef					# _build_submodule_fetch


$(foreach r,$(UPSTREAM_REPOS),$(eval $(call _build_upstream_fetch,$r)))
$(foreach r,$(ELITO_REPOS),$(eval $(call _build_elito_fetch,$r)))
$(foreach s,$(_submodules),$(eval $(call _build_submodule_fetch,$s)))

endif					# _MODE == fetch
