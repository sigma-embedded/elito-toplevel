SHELL =		/bin/bash
GIT =		git
MAKE_ORIG =	$(MAKE) -f $(abspath $(firstword $(MAKEFILE_LIST))) ELITO_DIR=$(abspath ${ELITO_DIR})

ELITO_DIR =	de.sigma-chemnitz

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

RELEASE_BRANCH =	master

ifeq (${HOSTNAME},)
HOSTNAME := $(shell hostname -f 2>/dev/null || echo localhost)
endif
ifeq (${DOMAIN},)
DOMAIN := $(shell hostname -d 2>/dev/null || echo localdomain)
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
include ${LOCAL_BUILD_SETUP}
endif
export ELITO_CRT

unexport M S

_fetch_targets = \
	$(addprefix .stamps/elito_fetch-,${ELITO_REPOS})

-include ${ELITO_DIR}/scripts/top-level.mk

prepare:	.stamps/git-submodule
	$(MAKE_ORIG) .stamps/autoconf

.PHONY:		prepare
.NOTPARALLEL:

.stamps:
	mkdir -p $@

.stamps/git-submodule:	Makefile | .stamps
	$(GIT) submodule init
	$(GIT) submodule foreach 'cd $(abspath .) && $(GIT) config --replace-all submodule.$$name.update merge || :'
	$(if ${_fetch_targets},$(MAKE_ORIG) ${_fetch_targets} _MODE=fetch)
	$(GIT) submodule update
	-$(GIT) submodule foreach "$(GIT) config --unset-all remote.orgin.fetch 'refs/tags/\*:refs/tags/\*' || :"
	-$(GIT) submodule foreach "$(GIT) config --add remote.origin.fetch 'refs/tags/*:refs/tags/*' || :"
	-$(GIT) submodule foreach '$(GIT) push . HEAD:refs/heads/${RELEASE_BRANCH} && $(GIT) checkout refs/heads/${RELEASE_BRANCH} || :'
	@touch $@

######################### {{{ _MODE == fetch #############
ifeq (${_MODE},fetch)

# {{{ _register_alternate(alternate, git-repo)
define _register_alternate
	g=`cd "$2" && $$(GIT) rev-parse --git-dir` && \
	echo '$(abspath $1)' >> $$g/objects/info/alternates

endef
# }}} _register_alternate

# {{{ _git_create_branch(git-repo, orig-branch, remote-name)
define _git_create_branch
	-cd $1 && $(GIT) branch --track "$2" remotes/"$3"/"$2"

endef
# }}} _git_create_branch

# _git_init <repo-dir>,<alternates*>,<remote-name>,<remote-url>,<prefix>
define _git_init
	mkdir -p $1
	-cd "$1" && { test -d .git/objects || $5 $$(GIT) init -q; }
	$$(foreach a,$2,$$(call _register_alternate,$$a,$1))
	-cd "$1" && $$(GIT) remote add $3 '$4'
	@touch $$@
endef

# _git_addfetch <repo-dir>,<remote-name>,<ref>
define _git_addfetch
	cd '$1' && $(GIT) config --add 'remote.$2.fetch' +'refs/$3:refs/remotes/$2/$3'
	cd '$1' && $(GIT) config --add 'remote.$2.fetch' +'refs/$3:refs/$3'

endef

# _get_setfetch <repo-dir>,<remote-name>,<branches*>,<tags*>
define _git_setfetch
	echo '$1|$2|$3|$4'
	-cd "$1" && $$(GIT) config --unset 'remote.$2.fetch'
	$$(foreach b,$3,$$(call _git_addfetch,$1,$2,heads/$$b))
	$$(foreach t,$4,$$(call _git_addfetch,$1,$2,tags/$$t))
	@touch $$@
endef

define _git_fetch
	$$(foreach b,$4,$$(call _git_create_branch,$2,$$b,$3))
	@touch $$@
endef

##### _build_upstream_fetch(repo) #######
define _build_upstream_fetch
.stamps/upstream_init-$1:	| .stamps
	$(call _git_init,$${UPSTREAM_DIR_$1},$${ELITO_GLOBAL_ALTERNATES} $${UPSTREAM_ALTERNATES_$1},upstream,$${UPSTREAM_GIT_$1},$${_git_init_prefix})

.stamps/upstream_fetch-$1:	.stamps/upstream_init-$1
	-cd $${UPSTREAM_DIR_$1} && $$(GIT) fetch upstream --no-tags +$${UPSTREAM_BRANCH_$1}:refs/remotes/upstream/$${UPSTREAM_BRANCH_$1}
	$(call _git_fetch,$1,$${UPSTREAM_DIR_$1},upstream,)
endef					# _build_upstream_fetch

##### _build_elito_fetch(repo) #######
# _build_elito_fetch <repo>
define _build_elito_fetch

.stamps/elito_init-$1 \
.stamps/upstream_init-$1:	_git_init_prefix=env GIT_DIR=.

.stamps/elito_init-$1:	| .stamps
	$(call _git_init,$${ELITO_REPO_DIR_$1},$${ELITO_REPO_ALTERNATES_$1},\
		elito,$${ELITO_REPO_URI_$1},$${_git_init_prefix})

.stamps/elito_setfetch-$1:	.stamps/elito_init-$1
	$(if $${ELITO_REPO_BRANCHES_$1},$(call \
		_git_setfetch,$${ELITO_REPO_DIR_$1},elito,$${ELITO_REPO_BRANCHES_$1},$${ELITO_REPO_TAGS_$1}))

.stamps/elito_fetch-$1:		.stamps/elito_setfetch-$1
	-cd $${ELITO_REPO_DIR_$1} && $$(GIT) fetch elito
	$(call _git_fetch,$1,$${ELITO_REPO_DIR_$1},elito,)

.stamps/elito_init-$1:		$$(foreach r,$$(ELITO_REPO_UPSTREAM_$1), .stamps/upstream_fetch-$r)

.PHONY:	.stamps/elito_fetch-$1
endef					# _build_elito_fetch

$(foreach r,$(UPSTREAM_REPOS),$(eval $(call _build_upstream_fetch,$r)))
$(foreach r,$(ELITO_REPOS),$(eval $(call _build_elito_fetch,$r)))

endif					# _MODE == fetch
######################### }}} _MODE == fetch #############
