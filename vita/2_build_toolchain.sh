#!/bin/bash

# abort on error
set -e

export WORKSPACE=$PWD

export PATH=$PWD/vitasdk/bin:$PATH

export PLATFORM_PREFIX=$WORKSPACE
export TARGET_HOST=arm-vita-eabi
export PKG_CONFIG_PATH=$PLATFORM_PREFIX/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$PKG_CONFIG_PATH
export VITASDK=$PWD/vitasdk
export URL=`curl "https://api.github.com/repos/vitasdk/autobuilds/releases" | grep "browser_download_url" | grep "linux" | head -n 1 | cut -d '"' -f 4`

# Number of CPU
NBPROC=$(getconf _NPROCESSORS_ONLN)

if [ ! -f .patches-applied ]; then
	echo "patching libraries"
	
	# Fix compilation problems
	cp -r icu icu-native
	patch -Np0 < icu.patch

	# disable pixman examples and tests
	cd pixman-0.34.0
	perl -pi -e 's/SUBDIRS = pixman demos test/SUBDIRS = pixman/' Makefile.am
	autoreconf -fi
	cd ..

	# Fix mpg123 compilation
	patch -Np0 < mpg123.patch

	# Fix libsndfile compilation
	patch -Np0 < libsndfile.patch

	touch .patches-applied
fi

function set_build_flags {
	export CFLAGS="-I$WORKSPACE/include -g0 -O2"
	export CPPFLAGS="$CFLAGS"
	export LDFLAGS="-L$WORKSPACE/lib"
}

# Default lib installer
function install_lib {
	cd $1
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static $2
	make clean
	make -j1
	make install
	cd ..
}

# Install zlib
function install_lib_zlib() {
	cd zlib-1.2.11
	CHOST=$TARGET_HOST ./configure --static --prefix=$PLATFORM_PREFIX
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install patched libvita2d
function install_lib_vita2d() {
	cd vita2dlib
	git checkout fbo
	cd libvita2d
	make clean
	make -j1
	make install
	cd ../..
}

# Install precompiled shaders
function install_shaders() {
	cd vitashaders
	cp -a ./lib/. $VITASDK/$TARGET_HOST/lib/
	cp -a ./includes/. $VITASDK/$TARGET_HOST/include/
	cd ..
}

# Install ICU
function install_lib_icu() {
	# Compile native version
        unset CFLAGS
        unset CPPFLAGS
        unset LDFLAGS

	cp icudt58l.dat icu/source/data/in/
	cp icudt58l.dat icu-native/source/data/in/
	cd icu-native/source
	perl -pi -e 's/SMALL_BUFFER_MAX_SIZE 512/SMALL_BUFFER_MAX_SIZE 2048/' tools/toolutil/pkg_genc.h
	# glibc 2.26 removed xlocale.h: https://ssl.icu-project.org/trac/ticket/13329
	perl -pi -e 's/xlocale/locale/' i18n/digitlst.cpp
	chmod u+x configure
	./configure --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools --enable-extras=no --enable-icuio=no --with-data-packaging=static
	make -j$NBPROC
	export ICU_CROSS_BUILD=$PWD

	# Cross compile
	set_build_flags

	cd ../../icu/source

	cp config/mh-linux config/mh-unknown

	chmod u+x configure
	./configure --with-cross-build=$ICU_CROSS_BUILD --enable-strict=no --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools=no --enable-extras=no --enable-icuio=no --host=$TARGET_HOST --with-data-packaging=static --prefix=$PLATFORM_PREFIX
	make clean
	make -j$NBPROC
	make install
	cd ../..
}

function install_vdpm() {
	mkdir vitasdk
	pushd vdpm
	wget -O "vitasdk-nightly-tar.bz2" "$URL"
	tar xf "vitasdk-nightly-tar.bz2" -C $VITASDK --strip-components=1
	./install-all.sh
	popd
}

# Platform libs
install_vdpm
install_lib_vita2d

set_build_flags
# Install libraries
install_lib_zlib
install_lib "libpng-1.6.23"
install_lib "freetype-2.6.3" "--with-harfbuzz=no --without-bzip2"
install_lib "pixman-0.34.0"
install_lib "libogg-1.3.2"
install_lib "libvorbis-1.3.5"
install_lib_icu
install_lib "mpg123-1.23.3" "--enable-fifo=no --enable-ipv6=no --enable-network=no --enable-int-quality=no --with-cpu=generic --with-default-audio=dummy"
install_lib "libsndfile-1.0.27"
install_lib "speexdsp-1.2rc3"

# Precompiled shaders
install_shaders
