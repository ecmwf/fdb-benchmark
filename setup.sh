# --- retrieve and prepare artifacts ---

cwd=$(pwd)

git_dir=$HOME/git

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

ecbuild_bundle( PROJECT eccodes         GIT "https://github.com/ecmwf/eccodes"               TAG 2.38.0   UPDATE)
ecbuild_bundle( PROJECT eckit           GIT "https://github.com/ecmwf/eckit"                 TAG 1.28.0   UPDATE)
ecbuild_bundle( PROJECT odc             GIT "https://github.com/ecmwf/odc"                   TAG 1.5.2    UPDATE)
ecbuild_bundle( PROJECT metkit          GIT "https://github.com/ecmwf/metkit"                TAG 1.11.19  UPDATE)
ecbuild_bundle( PROJECT fdb5            GIT "https://github.com/ecmwf/fdb"                   TAG 5.13.103  UPDATE)

ecbuild_bundle_finalize()
EOF
# watch out, if copy-pasting the EOF is not recognised
fi

fdb_build_dir=$HOME/build/fdb-bundle/
fdb_dir=$HOME/install/fdb-bundle/

if [ ! -e $fdb_dir ] ; then
  mkdir -p $fdb_build_dir
  cd $fdb_build_dir
  export PATH=$PATH:${git_dir}/ecbuild/bin
  cmake ${git_dir}/fdb-bundle -DENABLE_MEMFS=ON -DENABLE_AEC=OFF
  cd ${git_dir}/fdb-bundle/fdb5/src/fdb5/tools
  wget -O fdb-hammer.cc https://raw.githubusercontent.com/ecmwf/fdb/refs/heads/manm_fdbhammer_prof/src/fdb5/tools/fdb-hammer.cc

  # TODO: in src/fdb5/tools/fdb-hammer.cc, for every instances of
  #
  # // uncomment for rados runs
  #
  # comment out the line following it

  # TODO: in src/fdb5/message/MessageArchiver.cc::archive, comment out the following lines
  #
  # eckit::Progress progress("FDB archive", 0, source.estimate());
  # 
  # progress(total_size);
  # 
  # eckit::Log::info() << "FDB archive " << eckit::Plural(count, "message") << ","
  #                    << " size " << eckit::Bytes(total_size) << ","
  #                    << " in " << eckit::Seconds(timer.elapsed()) << " (" << eckit::Bytes(total_size, timer) << ")"
  #                    << std::endl;

  cd $fdb_build_dir
  cmake --build . -j 12
  mkdir -p $fdb_dir
  cmake --install . --prefix $fdb_dir
  cd $HOME/install
  tar -zcvf fdb-bundle.tar.gz fdb-bundle
fi

# --- daos-tests (for seed GRIB files)

if [ ! -e $git_dir/daos-tests ] ; then
  cd $git_dir
  git clone https://github.com/ecmwf-projects/daos-tests
fi

# --- FDB client config

cat > $HOME/config.yaml.in <<EOF
#type: local
#spaces:
#- roots:
#  - path: /path/to/fdb/root
#schema: @SCHEMA_PATH@
#engine: toc
#store: file
#useSubToc: true

type: remote
host: hostname_remote_catalogue
port: 10000
engine: remote
store: remote
EOF

cd $cwd
