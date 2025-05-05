#!/usr/bin/env bash

# --- parse parameters

nodelist_arg=( "$(hostname)" )
ppn=1
nmembers=default
NSTEPS=10
NLEVELS=1
NPARAMS=1
root="$HOME/fdb-hammer-parallel"
config=
check=no  # no, md, or full
install=no  # yes or no
artifact_dir='~/fdb-hammer-parallel/artifacts'
artifact_dir_is_shared=no

itt=no
barrier_port=7777
barrier_max_wait=10
poll_period=1
nodelist_read_itt_arg=
ppn_read_itt=

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
--nodelist <list>\n\nNode list (following Slurm syntax) where to run fdb-hammer processes. E.g. compute-node[001-010]. Do not use 'localhost' in this list, use the local host name if needed. Default: a list containing the local host name only (as provided by hostname).\n\n\
--ppn <ppn>\n\nNumber of fdb-hammer processes to run on every client node in the provided node list. Default: 1.\n\n\
--nmembers <nmembers>\n\nTotal number of members to archive/retrieve by all client nodes and process. It must be a multiple or submultiple of the number of nodes in the nodelist. If larger than the number of nodes, a node will produce/consume data for more than one member. If smaller, multiple nodes will produce/consume data for a same member. Default: one per node in --nodelist (this default behaviour can be triggered by providing no value or with --nmembers default).\n\n\
--nsteps <nsteps>\n\nNumber of steps to archive/retrieve by every client process. Default: 10.\n\n\
--nlevels <nlevels>\n\nNumber of levels to archive/retrieve by every client process. Default: 1.\n\n\
--nparams <nparams>\n\nNumber of params to archive/retrieve by every client process. Default: 1.\n\n\
--itt\n\nFlag to enable ITT mode, where the writers barrier at the end of every step, and the readers poll the FDB until their data becomes available. Readers retrieve data in a transposed way (i.e., every reader process accesses data for a single or a few time steps).\nWhen --itt is supplied and the MODE is 'read', the --nodelist, --ppn, --nmembers, --nsteps, --nlevels and --nparams options are interpreted as a description of the span of weather fields archived in the write mode.\n\n\
--barrier-port <port>\n\nIf --itt is specified and MODE is 'write', the port specified in --port will be used on the first writer node to listen for peer nodes to barrier. Default: 7777.\n\n\
--barrier-max-wait <seconds>\n\nIf --itt is specified and MODE is 'write', --barrier-max-write deterimnes the number of seconds to wait for peer nodes during barriers before aborting. Default: 10.\n\n\
--poll-period <period>\n\nIf --itt is specified, --poll-period deterimnes the number of seconds between polling retries in reader processes. Default: 1.\n\n\
--nodelist-read <list>\n\nIf MODE is 'read' and --itt is supplied, a list of nodes to be employed for the 'read' mode, where to run fdb-hammer processes, must be provided via --nodelist-read, following the Slurm node list syntax. E.g. compute-node[011-020]. Do not use 'localhost' in this list, use the local host name if needed.\n\n\
--ppn-read <ppn>\n\nIf MODE is 'read' and --itt is supplied, the number of fdb-hammer processes per node to run for the 'read' mode must be provided via --ppn-read.\n\n\
--root <path>\n\nPath to the root directory where the FDB and other repositories and binaries have been installed. Default: \$HOME/fdb-hammer-parallel.\n\n\
--config <path>\n\nPath to an FDB client configuration file. This file will be deployed on all client nodes in nodelist. It can contain wildcards such as @SCHEMA_PATH@ which will be replaced by the actual schema file path on that client node. Default: <root>/config.yaml.in.\n\n\
--md-check\n\nFlag to enable metadata consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification.\n\n\
--full-check\n\nFlag to enable metadata and data consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification. This option is more compute demanding than --md-check.\n\n\
--install\n\nFlag to enable installation of fdb-hammer and other necessary binaries on the client nodes. It must be specified on the first run on a given set of client nodes, or if the binaries on these nodes need to be updated with new ones.\n\n\
--artifact-dir\n\nPath where to install binaries and artifacts on the client nodes. Use '~' to refer to the home directory on the nodes, but do not set artifact-dir to only '~'. Default: ~/fdb-hammer-parallel/artifacts.\n\n\
--artifact-dir-is-shared\n\nFlag to be provided if the artifact directory on the client nodes is shared via a networked file system.\n\n\
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
    --nmembers)
    nmembers="$2"
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
    --itt)
    itt=yes
    shift
    ;;
    --barrier-port)
    barrier_port="$2"
    shift
    shift
    ;;
    --barrier-max-wait)
    barrier_max_wait="$2"
    shift
    shift
    ;;
    --poll-period)
    poll_period="$2"
    shift
    shift
    ;;
    --nodelist-read)
    nodelist_read_itt_arg="$2"
    shift
    shift
    ;;
    --ppn-read)
    ppn_read_itt="$2"
    shift
    shift
    ;;
    --root)
    root="$2"
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
    --artifact-dir)
    artifact_dir="$2"
    shift
    shift
    ;;
    --artifact-dir-is-shared)
    artifact_dir_is_shared=yes
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

[ -z "$config" ] && config=${root}/config.yaml.in

if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then
  if [ -z "$nodelist_read_itt_arg" ] ; then
    echo "A list of reader nodes must be specified via --nodelist-read if running the benchmark in ITT read mode."
    exit 1
  fi
  if [ -z "$ppn_read_itt" ] ; then
    echo "The number of reader processes to run per node must be specified via --ppn-read if running the benchmark in ITT read mode."
    exit 1
  fi
fi



# --- parse slurm node lists

expand_slurm_nodelist() {
  echo $(python3 - "$1" <<EOF
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
  )
}

nodes_write_or_read=( $(expand_slurm_nodelist "$nodelist_arg") )
nodes=( ${nodes_write_or_read[@]} )

nodes_read_itt=
[[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] && \
  nodes_read_itt=( $(expand_slurm_nodelist "$nodelist_read_itt_arg") ) && nodes=( ${nodes_read_itt[@]} )



# --- copy artifacts

artifacts=( \
  "$root/git/daos-tests/ngio/fdb_hammer/sample1MiB" \
  "$root/git/daos-tests/ngio/fdb_hammer/schema_posix" \
  "$config" \
)

[[ "$install" == "yes" ]] && artifacts+=( \
  "$root/git/netcat.tar.gz" \
  "$root/install/fdb-bundle.tar.gz" \
)

artifact_dir_local="$artifact_dir"
[[ "$artifact_dir" == '~/'* ]] && artifact_dir_local=${HOME}/${artifact_dir#"~/"}

nodes_to_configure=( "${nodes[@]}" )
[[ "$artifact_dir_is_shared" == "yes" ]] && nodes_to_configure=( "${nodes[0]}" )

pids=()

for node in "${nodes_to_configure[@]}" ; do

  for artifact in "${artifacts[@]}" ; do

    if [[ "${node}" == "$(hostname)" ]] ; then
      mkdir -p $artifact_dir_local
      cp $artifact ${artifact_dir_local}/ &
    else
      ssh ${node} "mkdir -p ${artifact_dir#"~/"}"
      set -m
      scp $artifact ${node}:${artifact_dir} &
      set +m
    fi

    pids+=($!)

  done

done

for pid in "${pids[@]}" ; do

  wait $pid

done



# --- sanity check members

num_nodes=${#nodes_write_or_read[@]}

if [[ "$nmembers" == "default" ]] ; then
  nmembers=$num_nodes
fi

if ( ! ( [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ) ) ; then
  if [ "$nmembers" -lt "$num_nodes" ] ; then
    (( "$num_nodes" % "$nmembers" != 0 )) && \
      echo "num_nodes must be divisible by nmembers if nmembers < num_nodes" && \
      exit 1
  else
    (( "$nmembers" % "$num_nodes" != 0 )) && \
      echo "nmembers must be divisible by num_nodes if nmembers >= num_nodes" && \
      exit 1
    (( ( "$num_nodes" * "$ppn" ) % "$nmembers" != 0 )) && \
      echo "num_nodes * ppn must be divisible by nmembers if nmembers >= num_nodes" && \
      exit 1
  fi
fi



if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

  # --- sanity check steps and reader procs if --itt read

  num_nodes_read_itt=${#nodes_read_itt[@]}
  
  if [ "$NSTEPS" -lt "$num_nodes_read_itt" ] ; then
    (( "$num_nodes_read_itt" % "$NSTEPS" != 0 )) && \
      echo "num reader nodes must be divisible by nsteps if nsteps < num reader nodes" && \
      exit 1
  else
    (( "$NSTEPS" % "$num_nodes_read_itt" != 0 )) && \
      echo "NSTEPS must be a multiple of num reader nodes if NSTEPS >= num reader nodes" && \
      exit 1
  fi

  reader_procs_per_step=$ppn_read_itt
  [ "$NSTEPS" -lt "$num_nodes_read_itt" ] && \
    reader_procs_per_step=$(( ppn_read_itt * num_nodes_read_itt / NSTEPS ))

  num_nodes_write=${#nodes_write_or_read[@]}
  if [ "$num_nodes_write" -gt "$nmembers" ] ; then
    nodes_per_member=$(( num_nodes_write / nmembers ))
    procs_per_member=$(( ppn * nodes_per_member ))
    written_levels_per_step=$(( NLEVELS * ppn * nodes_per_member ))
  else
    members_per_node=$(( nmembers / num_nodes_write ))
    procs_per_member=$(( ppn / members_per_node ))
    written_levels_per_step=$(( NLEVELS * ppn / members_per_node ))
  fi
  fields_per_step_per_member=$(( procs_per_member * NLEVELS * NPARAMS ))

  (( "$fields_per_step_per_member" % "$reader_procs_per_step" != 0 )) && \
    echo "The total number of fields archived per step per member (${procs_per_member} x ${NLEVELS} x ${NPARAMS} = ${fields_per_step_per_member}) must be divisible by the number of reader processes per step (${reader_procs_per_step})." && \
    exit 1



  # --- generate lists of randomly ordered levels for each reader node

  # This code assumes every reader node will read data for only one step.
  # One list of randomly ordered levels is passed as input to every reader node.
  # If the benchmark is configured with more reader nodes than steps, and therefore
  # multiple reader nodes read data for the same step, the reader nodes for a given
  # step will all receive the same list of levels and each node will extract a 
  # different subset of levels from the provided list.
  # If the benchmark is configured with less reader nodes than steps, and therefore
  # a reader node reads data for multiple steps, the same list of randomly ordered
  # levels provided as input is used for all steps. Because each reader node will 
  # read its assigned steps with a stride of #number_of_reader nodes, and each 
  # reader process reads parameters in a different order, the read order for every 
  # subsequent step read (both overall and within a reader node) will be different.

  level_lists=()

  for node in `seq 1 $num_nodes_read` ; do
    list=($(seq 1 $written_levels_per_step | shuf))
    level_lists+=( $(echo "${list[@]}" | tr -s ' ' ',') )
  done

fi



# --- execute 

nodelist=""
sep=""
for node in "${nodes_write_or_read[@]}" ; do
  nodelist=${nodelist}${sep}${node}
  sep=","
done

nodelist_read_itt=""
sep=""
for node in "${nodes_read_itt[@]}" ; do
  nodelist_read_itt=${nodelist_read_itt}${sep}${node}
  sep=","
done

pids=()
outs=()
i=0

[[ "$mode" == "list" ]] && nodelist=${nodes_write_or_read[0]} && nodes=( ${nodelist} ) && ppn=1

for node in "${nodes[@]}" ; do

  args=( \
    $i $ppn $mode $nodelist $nmembers $NSTEPS $NLEVELS $NPARAMS \
    $check $install $artifact_dir $artifact_dir_is_shared \
    $itt $barrier_port $barrier_max_wait $nodelist_read_itt $ppn_read_itt \
    $poll_period \
  )

  [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] && \
    args+=( ${level_lists[ $(( i )) ]} )

  out=$(mktemp)

  if [[ "$node" == "$(hostname)" ]] ; then
    bash -s -- ${args[@]} < fdbh_one_node.sh 2>&1 > $out &
  else
    set -m
    ssh $node "bash -s -- ${args[@]}" < fdbh_one_node.sh 2>&1 > $out &
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
  ( ! ( [[ "$mode" == "read" ]] && [[ "$itt" == "yes" ]] ) ) && \
    echo "Total ${mode} bandwidth: ${bw} MiB/s"
  [ "$failures" -ne 0 ] && echo "Got ${failures} failures" || echo "No failures occurred"
  [ "$consistency_failures" -ne 0 ] && echo "Found ${consistency_failures} inconsistencies"
  echo "----------------"
fi
