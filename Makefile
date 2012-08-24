SHELL = /bin/bash
GIT = git
TAR = tar
PWD_P = pwd -P
AUTORECONF    = autoreconf
ELITO_DIR     = de.sigma-chemnitz
GITREPO_BASE  = elito

GIT_TAG_FLAGS = -a
GIT_TAG_NOW_FMT = %Y%m%dT%H%M%S
GIT_TAG_PREFIX ?=
GIT_SUBMODULE_STRATEGY = --merge

PACK_OPTS =
PACK_API = 1

UPSTREAM_REPOS = org.openembedded.core org.openembedded.meta kernel

UPSTREAM_DIR_org.openembedded.core = org.openembedded.core
UPSTREAM_GIT_org.openembedded.core = git://git.openembedded.org/openembedded-core
UPSTREAM_BRANCH_org.openembedded.core = master

UPSTREAM_DIR_org.openembedded.meta = org.openembedded.meta
UPSTREAM_GIT_org.openembedded.meta = git://git.openembedded.org/meta-openembedded
UPSTREAM_BRANCH_org.openembedded = master

UPSTREAM_DIR_kernel = workspace/kernel.git
UPSTREAM_GIT_kernel = git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6
UPSTREAM_BRANCH_kernel = master

MAKE_ORIG = $(MAKE) -f $(abspath $(firstword $(MAKEFILE_LIST)))

ifeq (${HOSTNAME},)
HOSTNAME := $(shell hostname -f)
endif
ifeq (${DOMAIN},)
DOMAIN := $(shell hostname -d)
endif

ifneq (${_MODE},configure)
_topdir = .
endif

-include ${_topdir}/project.conf
-include ${_topdir}/.config
-include ${_topdir}/.config_${DOMAIN}
-include ${_topdir}/.config_${HOSTNAME}

ifeq (${_MODE},configure)
-include ./build-setup
-include ./build-setup_${DOMAIN}
-include ./build-setup_${HOSTNAME}
endif
export ELITO_CRT

unexport M S

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
	{ echo "updated submodules"; echo; \
        $(GIT) submodule summary | nl -b a -n rz -w 8 -s '' | \
        sort -k 1.13 | uniq -u -s 13 | sort | \
        sed -e 's/^........//' -e '2,$${/^\*/i\\' -e '' -e '}'; \
        } | $(GIT) commit -F - ${_submodules}

image:	build

ifneq ($M,)
reconfigure:
	cd $M && cd "`$(PWD_P)`" && ./config.status --recheck

init:
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
mrproper-all:		$(addprefix .mrproper-,$(PROJECTS))
init-all:		$(addprefix .init-,$(PROJECTS))
rebuild-all:		$(addprefix .rebuild-,$(PROJECTS))
build-failed:		$(addprefix .build-failed-,$(PROJECTS))
build-incomplete:	$(addprefix .build-incomplete-,$(PROJECTS))
repo-info:		$(addprefix .repo-info-,$(PUSH_REPOS))

.NOTPARALLEL:		$(addprefix .repo-info-,$(PUSH_REPOS))

prepare:	.stamps/git-submodule .stamps/autoconf

update:		prepare
	$(GIT) remote update
	$(GIT) pull
	$(GIT) submodule update $(GIT_SUBMODULE_STRATEGY)
	$(MAKE_ORIG) $(addprefix .stamps/elito_fetch-,${ELITO_REPOS}) _MODE=fetch
	$(MAKE) .stamps/autoconf-update

update-offline:
	@test -r '$P' || { \
		echo 'Can not read pack $$P' >&2; \
		exit 1; }
	$(abspath ${ELITO_DIR}/scripts/apply-update-pack) '$(abspath $P)'
	$(MAKE_ORIG) .stamps/autoconf-update

create-tag:
	+T=$$(mktemp -t create-tag.XXXXXX) && \
	trap "rm -rf $$T" EXIT && \
	$(MAKE_ORIG) .create-tag T=$$T TAG='$(TAG)'

ifneq ($(GIT_TAG_PREFIX),)
create-tag-now:	TAG := $(GIT_TAG_PREFIX)-$(shell date +$(GIT_TAG_NOW_FMT))
create-tag-now:	create-tag
endif

.reconfigure-%:
	+! test -e "$*"/config.status || $(MAKE_ORIG) reconfigure M=$*

.clean-complete-%:
	@rm -f .succeeded-$*

.build-%:	.clean-complete-% .init-%
	@touch .failed-$*
	@! tty -s || echo -ne "\033]0;OE Build $*@$${HOSTNAME%%.*}:$${PWD/#$$HOME/~} - `date`\007"
	+$(S) $(MAKE_ORIG) .build-target-$*
	@rm -f .failed-$*
	@date > .succeeded-$*

.build-failed-%:
	! test -e .failed-$* || $(MAKE_ORIG) .build-$*

.build-incomplete-%:
	test -e .succeeded-$* || $(MAKE_ORIG) .build-$*

.build-target-%:
	$(MAKE_ORIG) M=$* build

.clean-%:	.clean-complete-%
	rm -rf $*/tmp $*/.tmp .succeeded-$* .failed-$*

.mrproper-%:	.clean-complete-%
	+-test -e $*/Makefile && $(MAKE) -C '$*' mrproper
	rm -rf $*/tmp $*/.tmp .succeeded-$* .failed-$*

.init-%:
	$(MAKE_ORIG) init M=$*

.rebuild-%:
	$(MAKE_ORIG) .clean-$*
	$(MAKE_ORIG) .init-$*
	$(MAKE_ORIG) .build-$*

.repo-info-%:
	@printf '%s (%s):\n' "$*" "$(PUSH_DIR_$*)"
	@b='${PUSH_BRANCHES_$*}'; : $${b:=HEAD}; \
	$(GIT) ls-remote "${PUSH_DIR_$*}" $$b | sed -e 's!^!\t!'

.create-tag:	FORCE | .create-tag-check
	$(MAKE_ORIG) -s --no-print-directory repo-info >$T
	$(GIT) tag $(GIT_TAG_FLAGS) -F $T $(TAG)

.create-tag-check:	FORCE
	@test -n "$(TAG)" || { echo "TAG undefined" >&2; false; }
	@! $(GIT) ls-remote --exit-code . refs/tags/$(TAG) || \
		{ echo "tag '$(TAG)' already defined" >&2; false; }

.stamps/autoconf-update:	$(ELITO_DIR)/configure.ac
	rm -f .stamps/autoconf
	$(MAKE_ORIG) prepare
	$(MAKE_ORIG) $(addprefix .reconfigure-,${PROJECTS})
	@mkdir -p $(@D)
	@touch $@

.stamps/git-submodule:	Makefile
	$(GIT) submodule init
	$(if ${_fetch_targets},$(MAKE_ORIG) ${_fetch_targets} _MODE=fetch)
	$(GIT) submodule update
	@mkdir -p $(@D)
	@touch $@

.stamps/autoconf:
	cd $(ELITO_DIR) && $(AUTORECONF) -i -f
	@mkdir -p $(@D)
	@touch $@

endif

FORCE:

.PHONY:	image build clean mrproper init prepare update update-offline
.PHONY:	commit-submodules init reconfigure
.PHONY:	FORCE

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
	cd "`$(PWD_P)`" && env CONFIG_SHELL=/bin/bash /bin/bash ${_topdir}/de.sigma-chemnitz/configure ${_opts} CONFIG_SHELL=/bin/bash PWD_P='$(PWD_P)'

else
.configure-%:	.stamps/autoconf-update
	$(MAKE_ORIG) configure M='$*'

ifneq ($M,)
configure:
	$(MAKE_ORIG) -C '$M' configure _MODE=configure _topdir=$(abspath .)
endif

endif


######################################################################################

ifeq (${_MODE},fetch)

_submodules := ${_submodules}

define _register_alternate
	test -d $2/.git/objects && g=$2/.git || g=$2; \
	echo '$(abspath $1)' >> $$g/objects/info/alternates
endef

define _git_create_branch
	-cd $1 && $(GIT) branch --track "$2" remotes/"$3"/"$2"

endef

define _git_init
	mkdir -p $2
	-cd "$2" && { test -d .git/objects || $6 $$(GIT) init -q; }
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
	$(call _git_init,$1,$${UPSTREAM_DIR_$1},$${ELITO_GLOBAL_ALTERNATES} $${UPSTREAM_ALTERNATES_$1},upstream,$${UPSTREAM_GIT_$1},$${_git_init_prefix})

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
	cd $1 && $$(GIT) config --unset-all remote.orgin.fetch 'refs/tags/\*:refs/tags/\*' || :
	cd $1 && $$(GIT) config --add remote.origin.fetch 'refs/tags/*:refs/tags/*'

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

######################################################################################

ifeq (${_MODE},push)

_generate_pack_prog :=	$(abspath ${ELITO_DIR}/scripts/generate-update-pack)
export GIT

define _build_repo_push

PUSH_BRANCHES_$1 ?= $$(addprefix heads/,$${ELITO_REPO_BRANCHES_$1})
PUSH_TAGS_$1 ?= $${ELITO_REPO_TAGS_$1}
PUSH_PRIO_$1 ?= 00
PUSH_REALDIR_$1 ?=	$${PUSH_DIR_$1}
PACK_OPTS_$1 ?= ${PACK_OPTS}

push:		.push-$1

.push-$1:	$$(foreach r,$$(PUSH_REMOTES_$1) $$(PUSH_REMOTES_COMMON),\
		   ..push+$$r+$1)
..push+%+$1:
	cd $$(PUSH_DIR_$1) && $$(GIT) push $$* $$(PO)

.generate-pack-$1:
	@echo "Packaging repo $1"
	b='$${PUSH_BRANCHES_$1}'; env \
		BRANCHES="$$$${b:-HEAD}" \
		TAGS='$${PUSH_TAGS_$1}' \
	$(_generate_pack_prog) '$$T/$${PUSH_PRIO_$1}-$1' '$$(abspath $$(PUSH_DIR_$1))' '$R' '$$(PUSH_REALDIR_$1)' $$(PACK_OPTS_$1)
	@echo "======================================="

.generate-pack:	.generate-pack-$1

endef

.generate-pack:
	@echo ${PACK_API} > $T/api
	$(TAR) cf ${_packname} -C $T --owner root --group root --mode go-w,a+rX .

generate-pack:
	T=$$(mktemp -d -t update-pack.XXXXXX) && \
	trap "rm -rf $$T" EXIT && \
	$(MAKE_ORIG) T="$$T" _packname=$(if $P,$P,update-pack-`date +%Y%m%dT%H%M%S`.tar) .$@


$(foreach r,$(PUSH_REPOS),$(eval $(call _build_repo_push,$r)))

else

generate-pack push:
	$(MAKE_ORIG)	$@ _MODE=push

endif				# _MODE == push

###############################################################################

ifeq (${_MODE},create-tag)

ifeq (${TAG},)
$(error TAG not defined)
endif

ifeq (${TAG_OPTS},)
$(error TAG_OPTS not defined)
endif

define _build_repo_create_tag

create-tag-recursive:	.create-tag-repo-$1

.create-tag-repo-$1:
	cd $$(PUSH_DIR_$1) && $$(GIT) tag $(GIT_TAG_FLAGS) $(TAG_OPTS) $(TAG)

endef

create-tag-recursive:	.create-tag-repo-top
.create-tag-repo-top:	create-tag

$(foreach r,$(filter-out top,$(PUSH_REPOS)),$(eval $(call _build_repo_create_tag,$r)))

else ifeq (${_MODE},)				# create-tag

create-tag-recursive:
	$(MAKE_ORIG) $@ _MODE=create-tag

endif				# create-tag
