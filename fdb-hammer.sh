#!/usr/bin/env bash

# --- parse parameters

nodelist_arg=( "localhost" )
ppn=1
NSTEPS=10
NLEVELS=1
NPARAMS=1
config="$HOME/config.yaml.in"
check=no  # no, md, or full
install=no  # yes or no

POSITIONAL=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
./fdb-hammer.sh <MODE> [options]\n\n\
MODE: either write, read, or list\n\n\
Available options:\n\n\
--nodelist <list>\n\nNode list (following Slurm syntax) where to run fdb-hammer processes. E.g. compute-node[000-010]. Default: localhost.\n\n\
--ppn <ppn>\n\nNumber of fdb-hammer processes to run on every client node in the provided node list. Default: 1.\n\n\
--nsteps <nsteps>\n\nNumber of steps to archive by every client process. Default: 10.\n\n\
--nlevels <nlevels>\n\nNumber of levels to archive by every client process. Default: 1.\n\n\
--nparams <nparams>\n\nNumber of params to archive by every client process. Default: 1.\n\n\
--config <path>\n\nPath to an FDB client configuration file. This file will be deployed on all client nodes in nodelist. It can contain wildcards such as @SCHEMA_PATH@ which will be replaced by the actual schema file path on that client node. Default: \$HOME/config.yaml.in.\n\n\
--md-check\n\nFlag to enable metadata consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification.\n\n\
--full-check\n\nFlag to enable metadata and data consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification. This option is more compute demanding than --md-check.\n\n\
--install\n\nFlag to enable installation of fdb-hammer and other necessary binaries on the client nodes. It must be specified on the first run on a given set of client nodes, or if the binaries on these nodes need to be updated with new ones.\n\n\
-h|--help\n\nshow this menu\
"
    exit 0
    ;;
    --nodelist)
    nodelist_arg="$2"
    shift
    shift
    ;;
    --ppn)
    ppn="$2"
    shift
    shift
    ;;
    --nsteps)
    NSTEPS="$2"
    shift
    shift
    ;;
    --nlevels)
    NLEVELS="$2"
    shift
    shift
    ;;
    --nparams)
    NPARAMS="$2"
    shift
    shift
    ;;
    --config)
    config="$2"
    shift
    shift
    ;;
    --md-check)
    check=md
    shift
    ;;
    --full-check)
    check=full
    shift
    ;;
    --install)
    install=yes
    shift
    ;;
    *)
    POSITIONAL+=( "$1" )
    shift
    ;;
esac
done

set -- "${POSITIONAL[@]}"

if [ ${#POSITIONAL[@]} -ne 1 ] ; then
    echo "Exactly 1 positional arguments were expected. Check ./fdb-hammer.sh --help."
    exit 1
fi

mode=$1

nodes=($(python3 - "$nodelist_arg" <<EOF
import sys
import re

if len(sys.argv) != 2:
  raise Exception("Expected 1 argument.")

s = sys.argv[1]

#s = "compute-b24-[1-3,5-9],compute-b22-1,compute-b23-[3],compute-b25-[1,4,8]"

blocks = re.findall(r'[^,\[]+(?:\[[^\]]*\])?', s)
r = []
for b in blocks:
  if '[' in b:
    parts = b.split('[')
    ranges = parts[1].replace(']', '').split(',')
    for i in ranges:
      if '-' in i:
        limits = i.split('-')
        digits = len(limits[0])
        for j in range(int(limits[0]), int(limits[1]) + 1):
          print(parts[0] + (("%0" + str(digits) + "d") % (j,)))
      else:
        print(parts[0] + i)
  else:
    print(b)
EOF
))



# --- copy artifacts ---

artifacts=( \
  "$HOME/git/daos-tests/ngio/fdb_hammer/sample1MiB" \
  "$HOME/git/daos-tests/ngio/fdb_hammer/schema_posix" \
  "$config" \
)

[[ "$install" == "yes" ]] && artifacts+=( \
  "$HOME/git/netcat.tar.gz" \
  "$HOME/install/fdb-bundle.tar.gz" \
)

dest_dir_local=$HOME/artifacts
dest_dir='~/artifacts/'
pids=()

for node in "${nodes[@]}" ; do

  for artifact in "${artifacts[@]}" ; do

    if [[ "${node}" == "$(hostname)" ]] ; then
      mkdir -p $dest_dir_local
      cp $artifact ${dest_dir_local}/ &
    else
      ssh ${node} "mkdir -p ~/artifacts"
      set -m
      scp $artifact ${node}:${dest_dir} &
      set +m
    fi

    pids+=($!)

  done

done

for pid in "${pids[@]}" ; do

  wait $pid

done



# --- execute 

nodelist=""
sep=""
for node in "${nodes[@]}" ; do
  nodelist=${nodelist}${sep}${node}
  sep=","
done

pids=()
outs=()
i=0

[[ "$mode" == "list" ]] && nodelist=${nodes[0]} && nodes=( ${nodelist} ) && ppn=1

for node in "${nodes[@]}" ; do

  args=($i $ppn $mode $nodelist $NSTEPS $NLEVELS $NPARAMS $check $install)

  out=$(mktemp)

  if [[ "$node" == "$(hostname)" ]] ; then
    bash -s -- ${args[@]} < fdbh_one_node.sh > $out &
  else
    set -m
    ssh $node "bash -s -- ${args[@]}" < fdbh_one_node.sh > $out &
    set +m
  fi

  pids+=($!)

  outs+=($out)

  i=$((i + 1))

done

for pid in "${pids[@]}" ; do

  wait $pid

done

echo Done
echo "${outs[@]}"



# --- calculate bandwidth

failures=$(cat "${outs[@]}" | grep -e "failed at:" | wc -l)
consistency_failures=0
[[ "$mode" == "read" ]] && consistency_failures=$(cat "${outs[@]}" | grep -e "Assertion failed" -e "Found less fields" -e "Found a field of different size" | wc -l)

first_ts=$(cat "${outs[@]}" | grep "Timestamp before first IO" | awk '{print $5}' | sort -n | head -n 1)
last_ts=$(cat "${outs[@]}" | grep "Timestamp after last IO" | awk '{print $5}' | sort -nr | head -n 1)

field_size_mb=1
num_nodes=${#nodes[@]}
bw=$(bc <<< "$num_nodes * $ppn * $NSTEPS * $NLEVELS * $NPARAMS * $field_size_mb / ($last_ts - $first_ts)")

for out in "${outs[@]}" ; do

  echo $out
  cat $out
  rm ${out}

done

if [[ "$mode" != "list" ]] ; then
  echo "----------------"
  echo "Total ${mode} bandwidth: ${bw} MiB/s"
  [ "$failures" -ne 0 ] && echo "Got ${failures} failures"
  [ "$consistency_failures" -ne 0 ] && echo "Found ${consistency_failures} inconsistencies"
  echo "----------------"
fi
