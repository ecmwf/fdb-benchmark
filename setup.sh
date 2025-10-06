#!/usr/bin/env bash

set -e

src_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")



# --- parse arguments

root=/tmp/fdb-hammer-parallel
rebuild="false"
backend=
fdb_root=
fdb_root_pool=
fdb_remote_endpoint=

POSITIONAL=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
./setup.sh [options]\n\n\
Available options:\n\n\
--root <path>\n\nPath to a root directory where to build and install FDB and other repositories. Defaults to /tmp/fdb-hammer-parallel.\n\n\
--rebuild\n\nFlag to trigger rebuild from scratch rather than reuse previously built binaries.\n\n\
--backend <backend>\n\nName of the storage backend the benchmark will be run against. Can be posix, lustre, nfs, remote, daos, or ceph. Has no default.\n\n\
--fdb-root <path>\n\nPath to an existing root directory for the FDB posix, lustre, or nfs backend to internally store its data and indices.\n\n\
--fdb-root-pool <pool>\n\nName of an existing root pool for the FDB daos or ceph backend to internally store its data and indices.\n\n\
--fdb-remote-endpoint <host:port>\n\nHost and port where the remote FDB server is running.\n\n\
-h|--help\n\nshow this menu\
"
    exit 0
    ;;
    --root)
    root="$2"
    shift
    shift
    ;;
    --rebuild)
    rebuild="true"
    shift
    ;;
    --backend)
    backend="$2"
    shift
    shift
    ;;
    --fdb-root)
    fdb_root="$2"
    shift
    shift
    ;;
    --fdb-root-pool)
    fdb_root_pool="$2"
    shift
    shift
    ;;
    --fdb-remote-endpoint)
    fdb_remote_endpoint="$2"
    shift
    shift
    ;;
    *)
    POSITIONAL+=( "$1" )
    shift
    ;;
esac
done

set -- "${POSITIONAL[@]}"

if [ ${#POSITIONAL[@]} -ne 0 ] ; then
    echo "No positional arguments were expected. Check ./setup.sh --help."
    exit 1
fi



# --- check backend and set build flags

build_flags=""

[[ -z "$backend" ]] && echo "A --backend must be specified." && exit 1

case $backend in

  posix)
  build_flags="-DENABLE_LUSTRE=OFF"
  ;;

  lustre)
  build_flags="-DENABLE_LUSTRE=ON"
  ;;

  nfs)
  build_flags="-DENABLE_NFS=ON"
  echo "fdb-hammer on NFS not available" && exit 1
  ;;

  remote)
  build_flags="-DENABLE_REMOTE_FDB=ON"
  ;;

  daos)
  build_flags="-DENABLE_DAOSFDB=ON"
  ;;

  ceph)
  build_flags="-DENABLE_RADOSFDB=ON"
  echo "fdb-hammer on Ceph not available" && exit 1
  ;;

  *)
  echo "backend not recognised" && exit 1
  ;;

esac

if [[ "$backend" == "posix" ]] || [[ "$backend" == "lustre" ]] || [[ "$backend" == "nfs" ]] ; then
  [[ -z "$fdb_root" ]] && echo "Must provide an --fdb-root directory if ---backend is ${backend}." && exit 1
fi

if [[ "$backend" == "daos" ]] || [[ "$backend" == "ceph" ]] ; then
  [[ -z "$fdb_root_pool" ]] && echo "Must provide an --fdb-root-pool if --backend is ${backend}." && exit 1
fi

if [[ "$backend" == "remote" ]] ; then
  [[ -z "$fdb_remote_endpoint" ]] && echo "Must provide an --fdb-remote-endpoint if --backend is ${backend}." && exit 1
fi



# --- retrieve and prepare artifacts ---

cwd=$(pwd)

git_dir=$root/git
mkdir -p $git_dir

# --- netcat

if [ ! -e $git_dir/netcat ] ; then
  cd $git_dir
  git clone https://github.com/guzlewski/netcat
  sed -i -e '165,177d' netcat/netcat.c
  cd netcat
  make
  cd ..
  tar -zcvf netcat.tar.gz netcat
fi

# --- ecbuild

if [ ! -e $git_dir/ecbuild ] ; then
  cd $git_dir
  git clone https://github.com/ecmwf/ecbuild
fi

# --- fdb

if [ ! -e $git_dir/fdb-bundle ] ; then
  cd $git_dir
  mkdir fdb-bundle
  cd fdb-bundle
  cat > CMakeLists.txt <<'EOF'
cmake_minimum_required( VERSION 3.12 FATAL_ERROR )

find_package( ecbuild 3.6 REQUIRED HINTS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../ecbuild)

project( eckit-bundle VERSION 0.0.1 LANGUAGES CXX )

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if( LOCALCONFIG )
    include( ${LOCALCONFIG} OPTIONAL )
endif()

ecbuild_bundle_initialize()

ecbuild_bundle( PROJECT eccodes         GIT "https://github.com/ecmwf/eccodes"               TAG 2.41.0   UPDATE)
ecbuild_bundle( PROJECT eckit           GIT "https://github.com/ecmwf/eckit"                 TAG 1.29.3   UPDATE)
ecbuild_bundle( PROJECT odc             GIT "https://github.com/ecmwf/odc"                   TAG 1.6.1   UPDATE)
ecbuild_bundle( PROJECT metkit          GIT "https://github.com/ecmwf/metkit"                TAG 1.13.3   UPDATE)
ecbuild_bundle( PROJECT fdb5            GIT "https://github.com/ecmwf/fdb"                   TAG f1ddcc9986c661691f4542b4cf83ccd0422cb480 UPDATE)

ecbuild_bundle_finalize()
EOF
# watch out, if copy-pasting the EOF is not recognised
fi

fdb_build_dir=$root/build/fdb-bundle/
fdb_dir=$root/install/fdb-bundle/

if [ ! -e $fdb_dir ] || [[ "$rebuild" == "true" ]] ; then
  mkdir -p $fdb_build_dir
  cd $fdb_build_dir
  export PATH=$PATH:${git_dir}/ecbuild/bin
  cmake ${git_dir}/fdb-bundle -DENABLE_MEMFS=ON -DENABLE_AEC=ON ${build_flags}

  cmake --build . -j 12
  mkdir -p $fdb_dir
  cmake --install . --prefix $fdb_dir
  cd $root/install
  tar -zcvf fdb-bundle.tar.gz fdb-bundle
fi

# --- FDB client config

if [[ "$backend" == "posix" ]] || [[ "$backend" == "lustre" ]] || [[ "$backend" == "nfs" ]] ; then

  cat > ${root}/config.yaml.in <<EOF
type: local
spaces:
- roots:
  - path: ${fdb_root}
schema: @SCHEMA_PATH@
engine: toc
store: file
useSubToc: true
EOF

fi


if [[ "$backend" == "daos" ]] ; then

  cat > ${root}/config.yaml.in <<EOF
type: local
schema: @SCHEMA_PATH@
engine: daos
store: daos
daos:
  catalogue:
    pool: ${root_pool}
    root_cont: root_container
  store:
    pool: ${root_pool}
  client:
    container_oids_per_alloc: 10000
EOF

fi


if [[ "$backend" == "ceph" ]] ; then

  cat > ${root}/config.yaml.in <<EOF
type: local
schema: @SCHEMA_PATH@
engine: rados
store: rados
rados:
  pool: ${root_pool}
  store:
    maxHandleBuffSize: 100000
EOF

fi


if [[ "$backend" == "remote" ]] ; then

  fdb_remote_host=${fdb_remote_endpoint%:*}
  fdb_remote_port=${fdb_remote_endpoint#*:}

  cat > ${root}/config.yaml.in <<EOF
type: remote
host: $fdb_remote_host
port: $fdb_remote_port
engine: remote
store: remote
EOF

fi

cp ${src_dir}/artifacts/${backend}/schema ${root}/schema

cp ${src_dir}/artifacts/sample*MiB_ccsds ${root}/



cd $cwd
