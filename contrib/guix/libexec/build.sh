#!/usr/bin/env bash
# Copyright (c) 2019-2021 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
export LC_ALL=C
set -e -o pipefail
export TZ=UTC

# Although Guix _does_ set umask when building its own packages (in our case,
# this is all packages in manifest.scm), it does not set it for `guix
# environment`. It does make sense for at least `guix environment --container`
# to set umask, so if that change gets merged upstream and we bump the
# time-machine to a commit which includes the aforementioned change, we can
# remove this line.
#
# This line should be placed before any commands which creates files.
umask 0022

if [ -n "$V" ]; then
    # Print both unexpanded (-v) and expanded (-x) forms of commands as they are
    # read from this file.
    set -vx
    # Set VERBOSE for CMake-based builds
    export VERBOSE="$V"
fi

# Check that required environment variables are set
cat << EOF
Required environment variables as seen inside the container:
    DIST_ARCHIVE_BASE: ${DIST_ARCHIVE_BASE:?not set}
    DISTNAME: ${DISTNAME:?not set}
    HOST: ${HOST:?not set}
    SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH:?not set}
    JOBS: ${JOBS:?not set}
    DISTSRC: ${DISTSRC:?not set}
    OUTDIR: ${OUTDIR:?not set}
EOF

ACTUAL_OUTDIR="${OUTDIR}"
OUTDIR="${DISTSRC}/output"

#####################
# Environment Setup #
#####################

# The depends folder also serves as a base-prefix for depends packages for
# $HOSTs after successfully building.
BASEPREFIX="${PWD}/depends"

# Given a package name and an output name, return the path of that output in our
# current guix environment
store_path() {
    grep --extended-regexp "/[^-]{32}-${1}-[^-]+${2:+-${2}}" "${GUIX_ENVIRONMENT}/manifest" \
        | head --lines=1 \
        | sed --expression='s|^[[:space:]]*"||' \
              --expression='s|"[[:space:]]*$||'
}


# Set environment variables to point the NATIVE toolchain to the right
# includes/libs
NATIVE_GCC="$(store_path gcc-toolchain)"
NATIVE_GCC_STATIC="$(store_path gcc-toolchain static)"

unset LIBRARY_PATH
unset CPATH
unset C_INCLUDE_PATH
unset CPLUS_INCLUDE_PATH
unset OBJC_INCLUDE_PATH
unset OBJCPLUS_INCLUDE_PATH

export LIBRARY_PATH="${NATIVE_GCC}/lib:${NATIVE_GCC}/lib64:${NATIVE_GCC_STATIC}/lib:${NATIVE_GCC_STATIC}/lib64"
export C_INCLUDE_PATH="${NATIVE_GCC}/include"
export CPLUS_INCLUDE_PATH="${NATIVE_GCC}/include/c++:${NATIVE_GCC}/include"
export OBJC_INCLUDE_PATH="${NATIVE_GCC}/include"
export OBJCPLUS_INCLUDE_PATH="${NATIVE_GCC}/include/c++:${NATIVE_GCC}/include"

prepend_to_search_env_var() {
    export "${1}=${2}${!1:+:}${!1}"
}

# Set environment variables to point the CROSS toolchain to the right
# includes/libs for $HOST
case "$HOST" in
    *mingw*)
        # Determine output paths to use in CROSS_* environment variables
        CROSS_GLIBC="$(store_path "mingw-w64-x86_64-winpthreads")"
        CROSS_GCC="$(store_path "gcc-cross-${HOST}")"
        CROSS_GCC_LIB_STORE="$(store_path "gcc-cross-${HOST}" lib)"
        CROSS_GCC_LIBS=( "${CROSS_GCC_LIB_STORE}/lib/gcc/${HOST}"/* ) # This expands to an array of directories...
        CROSS_GCC_LIB="${CROSS_GCC_LIBS[0]}" # ...we just want the first one (there should only be one)

        # The search path ordering is generally:
        #    1. gcc-related search paths
        #    2. libc-related search paths
        #    2. kernel-header-related search paths (not applicable to mingw-w64 hosts)
        export CROSS_C_INCLUDE_PATH="${CROSS_GCC_LIB}/include:${CROSS_GCC_LIB}/include-fixed:${CROSS_GLIBC}/include"
        export CROSS_CPLUS_INCLUDE_PATH="${CROSS_GCC}/include/c++:${CROSS_GCC}/include/c++/${HOST}:${CROSS_GCC}/include/c++/backward:${CROSS_C_INCLUDE_PATH}"
        export CROSS_LIBRARY_PATH="${CROSS_GCC_LIB_STORE}/lib:${CROSS_GCC_LIB}:${CROSS_GLIBC}/lib"
        ;;
    *darwin*)
        # The CROSS toolchain for darwin uses the SDK and ignores environment variables.
        # See depends/hosts/darwin.mk for more details.
        ;;
    *linux*)
        CROSS_GLIBC="$(store_path "glibc-cross-${HOST}")"
        CROSS_GLIBC_STATIC="$(store_path "glibc-cross-${HOST}" static)"
        CROSS_KERNEL="$(store_path "linux-libre-headers-cross-${HOST}")"
        CROSS_GCC="$(store_path "gcc-cross-${HOST}")"
        CROSS_GCC_LIB_STORE="$(store_path "gcc-cross-${HOST}" lib)"
        CROSS_GCC_LIBS=( "${CROSS_GCC_LIB_STORE}/lib/gcc/${HOST}"/* ) # This expands to an array of directories...
        CROSS_GCC_LIB="${CROSS_GCC_LIBS[0]}" # ...we just want the first one (there should only be one)

        export CROSS_C_INCLUDE_PATH="${CROSS_GCC_LIB}/include:${CROSS_GCC_LIB}/include-fixed:${CROSS_GLIBC}/include:${CROSS_KERNEL}/include"
        export CROSS_CPLUS_INCLUDE_PATH="${CROSS_GCC}/include/c++:${CROSS_GCC}/include/c++/${HOST}:${CROSS_GCC}/include/c++/backward:${CROSS_C_INCLUDE_PATH}"
        export CROSS_LIBRARY_PATH="${CROSS_GCC_LIB_STORE}/lib:${CROSS_GCC_LIB}:${CROSS_GLIBC}/lib:${CROSS_GLIBC_STATIC}/lib"
        ;;
    *)
        exit 1 ;;
esac

# Sanity check CROSS_*_PATH directories
IFS=':' read -ra PATHS <<< "${CROSS_C_INCLUDE_PATH}:${CROSS_CPLUS_INCLUDE_PATH}:${CROSS_LIBRARY_PATH}"
for p in "${PATHS[@]}"; do
    if [ -n "$p" ] && [ ! -d "$p" ]; then
        echo "'$p' doesn't exist or isn't a directory... Aborting..."
        exit 1
    fi
done

# Disable Guix ld auto-rpath behavior
case "$HOST" in
    *darwin*)
        # The auto-rpath behavior is necessary for darwin builds as some native
        # tools built by depends refer to and depend on Guix-built native
        # libraries
        #
        # After the native packages in depends are built, the ld wrapper should
        # no longer affect our build, as clang would instead reach for
        # x86_64-apple-darwin-ld from cctools
        ;;
    *) export GUIX_LD_WRAPPER_DISABLE_RPATH=yes ;;
esac

# Make /usr/bin if it doesn't exist
[ -e /usr/bin ] || mkdir -p /usr/bin

# Symlink file and env to a conventional path
[ -e /usr/bin/file ] || ln -s --no-dereference "$(command -v file)" /usr/bin/file
[ -e /usr/bin/env ]  || ln -s --no-dereference "$(command -v env)"  /usr/bin/env

# Determine the correct value for -Wl,--dynamic-linker for the current $HOST
case "$HOST" in
    *linux*)
        glibc_dynamic_linker=$(
            case "$HOST" in
                i686-linux-gnu)        echo /lib/ld-linux.so.2 ;;
                x86_64-linux-gnu)      echo /lib64/ld-linux-x86-64.so.2 ;;
                arm-linux-gnueabihf)   echo /lib/ld-linux-armhf.so.3 ;;
                aarch64-linux-gnu)     echo /lib/ld-linux-aarch64.so.1 ;;
                riscv64-linux-gnu)     echo /lib/ld-linux-riscv64-lp64d.so.1 ;;
                powerpc64-linux-gnu)   echo /lib64/ld64.so.1;;
                powerpc64le-linux-gnu) echo /lib64/ld64.so.2;;
                *)                     exit 1 ;;
            esac
        )
        ;;
esac

# Environment variables for determinism
export TAR_OPTIONS="--owner=0 --group=0 --numeric-owner --mtime='@${SOURCE_DATE_EPOCH}' --sort=name"
export TZ="UTC"
case "$HOST" in
    *darwin*)
        # cctools AR, unlike GNU binutils AR, does not have a deterministic mode
        # or a configure flag to enable determinism by default, it only
        # understands if this env-var is set or not. See:
        #
        # https://github.com/tpoechtrager/cctools-port/blob/55562e4073dea0fbfd0b20e0bf69ffe6390c7f97/cctools/ar/archive.c#L334
        export ZERO_AR_DATE=yes
        ;;
esac

####################
# Depends Building #
####################

# Build the depends tree, overriding variables that assume multilib gcc
make -C depends --jobs="$JOBS" HOST="$HOST" \
                                   ${V:+V=1} \
                                   ${SOURCES_PATH+SOURCES_PATH="$SOURCES_PATH"} \
                                   ${BASE_CACHE+BASE_CACHE="$BASE_CACHE"} \
                                   ${SDK_PATH+SDK_PATH="$SDK_PATH"} \
                                   ${CODESIGN_PATH+CODESIGN_PATH="$CODESIGN_PATH"} \
                                   i686_linux_CC=i686-linux-gnu-gcc \
                                   i686_linux_CXX=i686-linux-gnu-g++ \
                                   i686_linux_AR=i686-linux-gnu-ar \
                                   i686_linux_RANLIB=i686-linux-gnu-ranlib \
                                   i686_linux_NM=i686-linux-gnu-nm \
                                   i686_linux_STRIP=i686-linux-gnu-strip \
                                   x86_64_linux_CC=x86_64-linux-gnu-gcc \
                                   x86_64_linux_CXX=x86_64-linux-gnu-g++ \
                                   x86_64_linux_AR=x86_64-linux-gnu-ar \
                                   x86_64_linux_RANLIB=x86_64-linux-gnu-ranlib \
                                   x86_64_linux_NM=x86_64-linux-gnu-nm \
                                   x86_64_linux_STRIP=x86_64-linux-gnu-strip \
                                   FORCE_USE_SYSTEM_CLANG=1 \
                                   EXTRA_PACKAGES='node_addon_api electron_node_headers'


###########################
# Source Tarball Building #
###########################

GIT_ARCHIVE="${DIST_ARCHIVE_BASE}/${DISTNAME}.tar.gz"

# Create the source tarball if not already there
if [ ! -e "$GIT_ARCHIVE" ]; then
    mkdir -p "$(dirname "$GIT_ARCHIVE")"
    git archive --prefix="${DISTNAME}/" --output="$GIT_ARCHIVE" HEAD
fi

mkdir -p "$OUTDIR"

###########################
# Binary Tarball Building #
###########################

# CONFIGFLAGS
CONFIGFLAGS="--enable-reduce-exports --disable-bench --disable-gui-tests --disable-fuzz-binary --disable-man --enable-zmq --with-node-js-libs --with-qrencode"

# CFLAGS
HOST_CFLAGS="-O2 -g"
HOST_CFLAGS+=$(find /gnu/store -maxdepth 1 -mindepth 1 -type d -exec echo -n " -ffile-prefix-map={}=/usr" \;)
case "$HOST" in
    *linux*)  HOST_CFLAGS+=" -ffile-prefix-map=${PWD}=." ;;
    *mingw*)
        HOST_CFLAGS+=" -fno-ident"
        # Hardening currently breaks mingw builds because it pulls libssp in as a dep; even though this isn't meant to happen (gcc is meant to be providing these symbols)
        # disable for now until we can investigate further
        CONFIGFLAGS+=" --disable-hardening "
    ;;
    *darwin*) unset HOST_CFLAGS ;;
esac

# CXXFLAGS
HOST_CXXFLAGS="$HOST_CFLAGS"

case "$HOST" in
    arm-linux-gnueabihf) HOST_CXXFLAGS="${HOST_CXXFLAGS} -Wno-psabi" ;;
esac

# LDFLAGS
case "$HOST" in
# static libstdc++ is giving is undefined symbol issues when using our lib with the latest electron, so remove it for now, but this should be investigated further.
#    *linux*)  HOST_LDFLAGS="-Wl,--as-needed -Wl,--dynamic-linker=$glibc_dynamic_linker -static-libstdc++ -Wl,-O2" ;;
    *linux*)  HOST_LDFLAGS="-Wl,--as-needed -Wl,--dynamic-linker=$glibc_dynamic_linker -lstdc++ -Wl,-O3" ;;
    *mingw*)  HOST_LDFLAGS="-Wl,--no-insert-timestamp" ;;
esac

# Using --no-tls-get-addr-optimize retains compatibility with glibc 2.18, by
# avoiding a PowerPC64 optimisation available in glibc 2.22 and later.
# https://sourceware.org/binutils/docs-2.35/ld/PowerPC64-ELF64.html
case "$HOST" in
    *powerpc64*) HOST_LDFLAGS="${HOST_LDFLAGS} -Wl,--no-tls-get-addr-optimize" ;;
esac

case "$HOST" in
    powerpc64-linux-*|riscv64-linux-*) HOST_LDFLAGS="${HOST_LDFLAGS} -Wl,-z,noexecstack" ;;
esac

# Make $HOST-specific native binaries from depends available in $PATH
export PATH="${BASEPREFIX}/${HOST}/native/bin:${PATH}"
mkdir -p "$DISTSRC"
(
    cd "$DISTSRC"

    # Extract the source tarball
    tar --strip-components=1 -xf "${GIT_ARCHIVE}"

    case "$HOST" in
        *mingw*)
            export HOST_CXXFLAGS="${HOST_CXXFLAGS} -I/munt/depends/${HOST}/include/node -I/munt/depends/${HOST}/include/node-addon-api -fPIC -fdata-sections -ffunction-sections -fomit-frame-pointer -DNAPI_VERSION=5 -DDJINNI_NODEJS -DNODE_HOST_BINARY=node.exe -DUSING_UV_SHARED=1 -DUSING_V8_SHARED=1 -DV8_DEPRECATION_WARNINGS=1 -DV8_DEPRECATION_WARNINGS -DV8_IMMINENT_DEPRECATION_WARNINGS -DWIN32 -D_CRT_SECURE_NO_DEPRECATE -D_CRT_NONSTDC_NO_DEPRECATE -DBUILDING_NODE_EXTENSION -D_WINDLL -lminiupnpc"
            export HOST_LDFLAGS="${HOST_LDFLAGS} -fPIC -Bsymbolic -lnode -Wl,--gc-sections"
        ;;
        *darwin*)
            export HOST_CXXFLAGS="${HOST_CXXFLAGS} -I/munt/depends/${HOST}/include/node -I/munt/depends/${HOST}/include/node-addon-api -fPIC -fdata-sections -ffunction-sections -fomit-frame-pointer -DNAPI_VERSION=5 -DDJINNI_NODEJS -D_HAS_EXCEPTIONS=1"
            export HOST_LDFLAGS="${HOST_LDFLAGS} -fPIC -Bsymbolic -Wl,-undefined -Wl,dynamic_lookup"
        ;;
        *linux*)
            export HOST_CXXFLAGS="${HOST_CXXFLAGS} -I/munt/depends/${HOST}/include/node -I/munt/depends/${HOST}/include/node-addon-api -fPIC -fdata-sections -ffunction-sections -fomit-frame-pointer -DNAPI_VERSION=5 -DDJINNI_NODEJS -lminiupnpc"
            export HOST_LDFLAGS="${HOST_LDFLAGS} -fPIC -Bsymbolic -Wl,--gc-sections"
        ;;
    esac
    export HOST_CFLAGS=${HOST_CFLAGS}
    #end electron specific setup

    ./autogen.sh

    # Configure this DISTSRC for $HOST
    # shellcheck disable=SC2086
    env CONFIG_SITE="${BASEPREFIX}/${HOST}/share/config.site" \
        ./configure --prefix=/ \
                    --disable-ccache \
                    --disable-maintainer-mode \
                    --disable-dependency-tracking \
                    --with-protoc-bindir=/munt/depends/${HOST}/native/bin/ \
                    ${CONFIGFLAGS} \
                    ${HOST_CFLAGS:+CFLAGS="${HOST_CFLAGS}"} \
                    ${HOST_CXXFLAGS:+CXXFLAGS="${HOST_CXXFLAGS}"} \
                    ${HOST_LDFLAGS:+LDFLAGS="${HOST_LDFLAGS}"}

    sed -i.old 's/-lstdc++ //g' config.status libtool

    # Build Munt
    make --jobs="$JOBS" ${V:+V=1}

    # Check that symbol/security checks tools are sane.
    #make test-security-check ${V:+V=1}
    # Perform basic security checks on a series of executables.
    make -C src --jobs=1 check-security ${V:+V=1}
    # Check that executables only contain allowed version symbols.
    make -C src --jobs=1 check-symbols  ${V:+V=1}

    mkdir -p "$OUTDIR"

    #fixme: We do some duplicate work here (split debug symbols and sign then later do this again); we should improve the process so its only done once.
    case "$HOST" in
        *mingw*)
            # Move executables into release folder
            mkdir release
            find . -name "*.exe" | xargs --max-procs 32 -i cp {} release/
            # Split debug symbols
            find "release" -type f -executable -print0 | xargs -0 -P"$JOBS" -I{} "${DISTSRC}/contrib/devtools/split-debug.sh" {} {} {}.dbg
            #Sign all executables
            find release -name "*.exe" | xargs --max-procs 32 -i sh -c "(osslsigncode -spc \"${CODESIGN_PATH}/codesign.spc\" -key \"${CODESIGN_PATH}/codesign.key\" -n \"Munt\" -i \"https://www.Munt.org\" -in \"{}\" -out \"{}s\") && (mv {}s {})"
            # Make os-specific installer
            make deploy ${V:+V=1}
            # Sign the installer as well; place result in output folder
            find -name "*setup*.exe" | xargs -i sh -c "(osslsigncode -spc \"${CODESIGN_PATH}/codesign.spc\" -key \"${CODESIGN_PATH}/codesign.key\" -n \"Munt\" -i \"https://www.Munt.org\" -in \"{}\" -out \"${OUTDIR}/${DISTNAME}-win64-setup.exe\")"
            ;;
    esac

    # Setup the directory where our Munt build for HOST will be
    # installed. This directory will also later serve as the input for our
    # binary tarballs.
    INSTALLPATH="${PWD}/installed/${DISTNAME}"
    mkdir -p "${INSTALLPATH}"
    # Install built Munt to $INSTALLPATH
    case "$HOST" in
        *darwin*)
            make install-strip DESTDIR="${INSTALLPATH}" ${V:+V=1}
            ;;
        *)
            make install DESTDIR="${INSTALLPATH}" ${V:+V=1}
            ;;
    esac

    mkdir ${OUTDIR}/nodelib
    case "$HOST" in
        *mingw*)
            cp -f src/.libs/lib_unity_node_js-0.dll ${OUTDIR}/nodelib/libmunt_${HOST}.node
        ;;
        *darwin*)
            cp -f src/.libs/lib_unity_node_js.0.so ${OUTDIR}/nodelib/libmunt_${HOST}.node
        ;;
        *)
            cp -f src/.libs/lib_unity_node_js.so.0.0.0 ${OUTDIR}/nodelib/libmunt_${HOST}.node
    esac

    #darwin builds choke one split-debug.sh script, but other platforms need to run it or we have giant binaries to deal with
    #run for every platform except darwin for now until we can make this work also on darwin
    case "$HOST" in
        *darwin*) ;;
        *)
            ${DISTSRC}/contrib/devtools/split-debug.sh ${OUTDIR}/nodelib/libmunt_${HOST}.node ${OUTDIR}/nodelib/libmunt_${HOST}.node ${OUTDIR}/nodelib/libmunt_${HOST}.node.dbg
    esac

    (
        cd installed

        # Prune libtool and object archives
        find . -name "lib*.la" -delete
        find . -name "lib*.a" -delete

        # Prune pkg-config files
        rm -rf "${DISTNAME}/lib/pkgconfig"

        case "$HOST" in
            *darwin*) ;;
            *)
                # Split binaries and libraries from their debug symbols
                {
                    find "${DISTNAME}/bin" -type f -executable -print0
                    if [ -d ${DISTNAME}/lib ]; then
                      find "${DISTNAME}/lib" -type f -print0
                    fi
                } | xargs -0 -P"$JOBS" -I{} "${DISTSRC}/contrib/devtools/split-debug.sh" {} {} {}.dbg
        esac

        # Sign binaries after debug symbols split
        case "$HOST" in
        *mingw*)
            find "${DISTNAME}/bin" -name "*.exe" | xargs --max-procs 32 -i sh -c "(osslsigncode -spc \"${CODESIGN_PATH}/codesign.spc\" -key \"${CODESIGN_PATH}/codesign.key\" -n \"Munt\" -i \"https://www.Munt.org\" -in \"{}\" -out \"{}s\") && (mv {}s {})"
            ;;
        esac

        # Finally, deterministically produce {non-,}debug binary tarballs ready
        # for release
        case "$HOST" in
            *mingw*)
                find "${DISTNAME}" -not -name "*.dbg" -print0 \
                    | xargs -0r touch --no-dereference --date="@${SOURCE_DATE_EPOCH}"
                find "${DISTNAME}" -not -name "*.dbg" \
                    | sort \
                    | zip -X@ "${OUTDIR}/${DISTNAME}-${HOST//x86_64-w64-mingw32/win64}.zip" \
                    || ( rm -f "${OUTDIR}/${DISTNAME}-${HOST//x86_64-w64-mingw32/win64}.zip" && exit 1 )
                find "${DISTNAME}" -name "*.dbg" -print0 \
                    | xargs -0r touch --no-dereference --date="@${SOURCE_DATE_EPOCH}"
                find "${DISTNAME}" -name "*.dbg" \
                    | sort \
                    | zip -X@ "${OUTDIR}/${DISTNAME}-${HOST//x86_64-w64-mingw32/win64}-debug.zip" \
                    || ( rm -f "${OUTDIR}/${DISTNAME}-${HOST//x86_64-w64-mingw32/win64}-debug.zip" && exit 1 )
                ;;
            *linux*)
                find "${DISTNAME}" -not -name "*.dbg" -print0 \
                    | sort --zero-terminated \
                    | tar --create --no-recursion --mode='u+rw,go+r-w,a+X' --null --files-from=- \
                    | pigz -9n > "${OUTDIR}/${DISTNAME}-${HOST}.tar.gz" \
                    || ( rm -f "${OUTDIR}/${DISTNAME}-${HOST}.tar.gz" && exit 1 )
                find "${DISTNAME}" -name "*.dbg" -print0 \
                    | sort --zero-terminated \
                    | tar --create --no-recursion --mode='u+rw,go+r-w,a+X' --null --files-from=- \
                    | pigz -9n > "${OUTDIR}/${DISTNAME}-${HOST}-debug.tar.gz" \
                    || ( rm -f "${OUTDIR}/${DISTNAME}-${HOST}-debug.tar.gz" && exit 1 )
                ;;
            *darwin*)
                find "${DISTNAME}" -print0 \
                    | sort --zero-terminated \
                    | tar --create --no-recursion --mode='u+rw,go+r-w,a+X' --null --files-from=- \
                    | pigz -9n > "${OUTDIR}/${DISTNAME}-${HOST}.tar.gz" \
                    || ( rm -f "${OUTDIR}/${DISTNAME}-${HOST}.tar.gz" && exit 1 )
                ;;
        esac
    )  # $DISTSRC/installed
)  # $DISTSRC

rm -rf "$ACTUAL_OUTDIR"
mv --no-target-directory "$OUTDIR" "$ACTUAL_OUTDIR" \
    || ( rm -rf "$ACTUAL_OUTDIR" && exit 1 )

(
    cd /outdir-base
    {
        echo "$GIT_ARCHIVE"
        find "$ACTUAL_OUTDIR" -type f
    } | xargs realpath --relative-base="$PWD" \
      | xargs sha256sum \
      | sort -k2 \
      | sponge "$ACTUAL_OUTDIR"/SHA256SUMS.part
)
