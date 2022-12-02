#!/bin/sh
set -euo pipefail

mydir="$(cd $(dirname "$0") && pwd)"
: ${BUILD_DIR:=${mydir}/build}
: ${DOWNLOADS_DIR:=${mydir}/downloads}
: ${PREFIX_DIR:=${CT_PREFIX:-${mydir}/prefix/}}
: ${ARCHIVE_DIR:=${CT_PREFIX:-${mydir}}/archives/}}
: ${HOSTS=x86_64-pc-linux-gnu aarch64-unknown-linux-gnu riscv64-unknown-linux-gnu}
: ${TARGETS:=crosstool-configs/*}
: ${MIRROR_URL=https://cache.nohlgard.se/crosstool-ng/}

if [ -z "${HOSTS}" ]; then
  HOSTS="''"
fi

print_summary() {
  printf 'Build summary\n'
  printf '=============\n\n'
  printf 'Build tree: %s\n' "${BUILD_DIR}"
  printf 'Downloads: %s\n' "${DOWNLOADS_DIR}"
  printf 'Installation prefix: %s\n' "${PREFIX_DIR}"
  printf 'Final release archive directory: %s\n' "${ARCHIVE_DIR}"
  printf '\n'
}

print_build_matrix() {
  printf 'Build matrix\n'
  printf '============\n'
  for host in ${HOSTS}; do
    for target in ${TARGETS}; do
      target="${target##*/}"
      if [ -n "${host}" ] && [ "${host}" != 'native' ]; then
        target="HOST-${host}/${target}"
      fi
      printf '%s\n' "${target}"
    done
  done
  printf '============\n'
  printf '\n'
}

check_crosstool_exists() {
  export PATH="${mydir}/crosstool-ng:${PATH}"
  if ! command -v 'ct-ng' 2>/dev/null >/dev/null; then
    >&2 printf 'ct-ng missing, building from source in %s\n' "${mydir}/crosstool-ng"
    if [ ! -d 'crosstool-ng' ] || [ ! -f 'crosstool-ng/bootstrap' ] ; then
      >&2 printf 'crosstool-ng source missing, cloning from git repo\n'
      git submodule update --init --recursive 'crosstool-ng'
    fi
    (cd "${mydir}/crosstool-ng" && ./bootstrap && ./configure --enable-local && make -j4)
  fi
  printf 'Using %s for toolchain build\n' "$(ct-ng version 2>/dev/null | head -n 1 | sed -e 's/^This is //')"
}

build_configs() {
  for config in "$@"; do (
    config_name="${config##*/}"
    printf 'Building toolchain %s for host %s\n' "${config_name}" "${host:-native}"
    mkdir -p "${BUILD_DIR}${host:+/HOST-${host}}/${config_name}"
    cp "${config}" "${BUILD_DIR}${host:+/HOST-${host}}/${config_name}/defconfig"
    cd "${BUILD_DIR}${host:+/HOST-${host}}/${config_name}"
    if [ -n "${MIRROR_URL}" ]; then
      printf '%s\n' \
        'CT_USE_MIRROR=y' \
        "CT_MIRROR_BASE_URL=\"${MIRROR_URL}\"" \
        >> defconfig
    fi
    if [ -z "${host}" ] || [ "${host}" = 'native' ]; then
      host=$(${CC:-cc} -dumpmachine)
    else
      printf '%s\n' \
        'CT_CANADIAN=y' \
        "CT_HOST=\"${host}\"" \
        >> defconfig
    fi
    printf '%s\n' \
      'CT_CC_GCC_BUILD_ID=y' \
      "CT_LOCAL_TARBALLS_DIR=\"${DOWNLOADS_DIR}\"" \
      >> defconfig
    ct-ng defconfig
    export CT_PREFIX="${PREFIX_DIR}"
    ct-ng build
    gcc_version=$(sed -n -e 's/^CT_GCC_VERSION="\(.*\)"/\1/p' .config)
    picolibc_version=$(sed -n -e 's/^CT_PICOLIBC_VERSION="\(.*\)"/\1/p' .config)
    CT_TARGET=$(ct-ng show-tuple)
    cd "${CT_PREFIX}/${host:+HOST-${host}/}${CT_TARGET}"
    host_vendor=$(printf '%s' "${host}" | cut -d - -f 2)
    host_os=$(printf '%s' "${host}" | cut -d - -f 3)
    if [ "${host_vendor}" != "unknown" ] && [ "${host_vendor}" != "pc" ]; then
      host_os=${host_os}-${host_vendor}
    fi
    host_cpu=${host%%-*}
    release=${CT_TARGET}-toolchain-${gcc_version}-${picolibc_version}
    archive=${release}-${host_cpu}-${host_os}.tar.xz
    find ./. -print0 | \
      LC_ALL=C sort -z | \
      tar --numeric-owner --owner=0 --group=0 \
        --transform "s,^\./\.,${release},S" \
        --no-recursion --null -T - -acf "${ARCHIVE_DIR}/${archive}"
    cp build.log.bz2 "${ARCHIVE_DIR}/build-log-${release}-${host_cpu}-${host_os}.log.bz2"
    cd "${ARCHIVE_DIR}"
    for hash in sha256sum sha512sum b2sum; do
      ${hash} -b "${archive}" > "${archive}.${hash}"
    done
  ) done
}

build_all_configs() {
  build_configs "${mydir}"/crosstool-configs/*
}

check_crosstool_exists

print_summary
print_build_matrix
mkdir -p "${BUILD_DIR}" "${DOWNLOADS_DIR}" "${ARCHIVE_DIR}"

for host in ${HOSTS}; do
  build_all_configs
done
