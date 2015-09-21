MAJOR  ?= 469
MINOR  ?= 0
PATCH  ?= 0
PREFIX ?= /usr

machine    = $(shell uname -m)
servername = $(shell uname -n)
OS         = $(shell uname -s)

arch = $(machine)

ifeq ($(arch), x86_64)
	arch := amd64
endif

all:	setup
	./Build

versions:
	find lib bin -type f -exec perl -i -pe 's/VERSION\s+=\s+q[[\d.]+]/VERSION = q[$(MAJOR).$(MINOR).$(PATCH)]/g' {} \;

setup:
	perl Build.PL

manifest: setup
	./Build manifest

clean:	setup
	./Build clean
	touch tmp
	rm -rf build.tap MYMETA.yml MYMETA.json _build Build rpmbuild spec tmp *rpm *deb *tar.gz test.db MANIFEST.bak

test:	setup
	TEST_AUTHOR=1 ./Build test verbose=1

cover:	setup
	./Build testcover verbose=1

install:	setup
	./Build install

dist:	setup
	./Build dist

rpm:	clean manifest
	cp spec.header spec
	perl -i -pe 's/MAJOR/$(MAJOR)/g' spec
	perl -i -pe 's/MINOR/$(MINOR)/g' spec
	perl -i -pe 's{PREFIX}{$(PREFIX)}g' spec
	mkdir -p rpmbuild/BUILD rpmbuild/RPMS rpmbuild/SOURCES rpmbuild/SPECS rpmbuild/SRPMS
	perl Build.PL
	./Build dist
	mv ClearPress*gz rpmbuild/SOURCES/libclearpress-perl-$(MAJOR)-$(MINOR).tar.gz
	cp rpmbuild/SOURCES/libclearpress-perl-$(MAJOR)-$(MINOR).tar.gz rpmbuild/BUILD/
	rpmbuild -v --define="_topdir `pwd`/rpmbuild" \
		    --buildroot `pwd`/rpmbuild/libclearpress-perl-$(MAJOR)-$(MINOR)-root \
		    --target=$(arch)-redhat-linux        \
		    -ba spec
	cp rpmbuild/RPMS/*/libclearpress*.rpm .

deb:	rpm
	fakeroot alien  -d libclearpress-perl-$(MAJOR)-$(MINOR).$(arch).rpm
