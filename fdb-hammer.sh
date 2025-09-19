#!/usr/bin/env bash

# --- parse parameters

nodelist_arg=( "$(hostname)" )
ppn=1
nmembers=default
NSTEPS=10
NLEVELS=1
NPARAMS=1
fields_per_member_per_step=
read_nodes_per_step=default
root="$HOME/fdb-hammer-parallel"
config=
prolog_script=none
check=no  # no, md, or full
install=no  # yes or no
artifact_dir='~/fdb-hammer-parallel/artifacts'
artifact_dir_is_shared=no
verbose=no

itt=no
barrier_port=7777
barrier_max_wait=10
poll_period=1
member_delay=0
reader_delay=0
step_window=10
random_delay=100
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
--nsteps <nsteps>\n\nNumber of steps to archive by every client process (if MODE is 'write') or archived by writers (if MODE is 'read'). If MODE is 'write', all processes archive fields for steps 1 to nsteps. Default: 10.\n\n\
--nlevels <nlevels>\n\nNumber of levels to archive by every client process (if MODE is 'write') or archived by writers (if MODE is 'read'). If MODE is 'write', every parallel process in a member archives nlevels unique levels. Default: 1.\n\n\
--nparams <nparams>\n\nNumber of params to archive by every client process (if MODE is 'write') or archived by writers (if MODE is 'read'). If MODE is 'write', all processes archive fields for the same nparams params. Default: 1.\n\n\
--fields-per-member-per-step <nfields>\n\nNumber of fields to archive (if MODE is 'write') or archived (if MODE is 'read') per step by all writer processes of a member. This argument overrides --nlevels, and is equivalent to supplying --nlevels=(nfields / --nparams / --ppn / (length(--nodelist) / --nmembers)).\n\n\
--itt\n\nFlag to enable ITT mode, where the writers barrier at the end of every step, and the readers poll the FDB until their data becomes available. Readers retrieve data in a transposed way (i.e., every reader process accesses data for a single or a few time steps).\nWhen --itt is supplied and the MODE is 'read', the --nodelist, --ppn, --nmembers, --nsteps, --nlevels and --nparams options are interpreted as a description of the span of weather fields archived in the write mode.\n\n\
--read-nodes-per-step <nnodes>\n\nIf --itt is specified and MODE is 'read', --read-nodes-per-step determines the number of reader nodes to employ for reading data for every written step. It must be equal or smaller than the number of nodes in --nodelist-read. If smaller, it must be a divisor. Default: one node in --nodelist-read per step if --nsteps is greater than or equal to the number of nodes in the nodelist, or length(--nodelist-read) / --nsteps otherwise (this default behaviour can be triggered by providing no value or with --read-nodes-per-step default).\n\n
--barrier-port <port>\n\nIf --itt is specified and MODE is 'write', the port specified in --port will be used on the first writer node to listen for peer nodes to barrier. Default: 7777.\n\n\
--barrier-max-wait <seconds>\n\nIf --itt is specified and MODE is 'write', --barrier-max-write deterimnes the number of seconds to wait for peer nodes during barriers before aborting. Default: 10.\n\n\
--poll-period <period>\n\nIf --itt is specified, --poll-period deterimnes the number of seconds between polling retries in reader processes. Default: 1.\n\n\
--member-delay <seconds>\n\nIf --itt is specified and MODE is 'write', writer processes for a given member are launched with a delay of 'seconds' seconds after the processes for the previous member. Decimal numbers supported. Default: 0.\n\n\
--reader-delay <seconds>\n\nIf --itt is specified and MODE is 'read', reader processes for a given step are launched with a delay of 'seconds' seconds after the processes for the previous step. Decimal numbers supported. Default: 0.\n\n\
--step-window <seconds>\n\nIf --itt is specified and MODE is 'write', --step-window deterimnes the number of seconds allowed per writer process to perform the I/O for a step. If this amount of time is not consumed during I/O, the process sleeps until it is fully consumed. If the window is exceeded, the process errors. Default: 10.\n\n\
--random-delay <percent>\n\nIf --itt is specified and MODE is 'write', every writer process sleeps for a random amount of time between 0 and (--step-window * percent / 100) before starting I/O. Default: 100.\n\n\
--nodelist-read <list>\n\nIf MODE is 'read' and --itt is supplied, a list of nodes to be employed for the 'read' mode, where to run fdb-hammer processes, must be provided via --nodelist-read, following the Slurm node list syntax. E.g. compute-node[011-020]. Do not use 'localhost' in this list, use the local host name if needed.\n\n\
--ppn-read <ppn>\n\nIf MODE is 'read' and --itt is supplied, the number of fdb-hammer processes per node to run for the 'read' mode must be provided via --ppn-read.\n\n\
--root <path>\n\nPath to the root directory where the FDB and other repositories and binaries have been installed. Default: \$HOME/fdb-hammer-parallel.\n\n\
--config <path>\n\nPath to an FDB client configuration file. This file will be deployed on all client nodes in nodelist. It can contain wildcards such as @SCHEMA_PATH@ which will be replaced by the actual schema file path on that client node. Default: <root>/config.yaml.in.\n\n\
--prolog-script <path>\n\nPath to a prolog script to be sourced first thing on each node in nodelist, for example to load required modules. Defaults to none.\n\n\
--md-check\n\nFlag to enable metadata consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification.\n\n\
--full-check\n\nFlag to enable metadata and data consistency checks. The reader fdb-hammer processes become memory-hungry if this parameter is enabled, as they need to buffer all fields read for later verification. This option is more compute demanding than --md-check.\n\n\
--install\n\nFlag to enable installation of fdb-hammer and other necessary binaries on the client nodes. It must be specified on the first run on a given set of client nodes, or if the binaries on these nodes need to be updated with new ones.\n\n\
--artifact-dir\n\nPath where to install binaries and artifacts on the client nodes. Use '~' to refer to the home directory on the nodes, but do not set artifact-dir to only '~'. Default: ~/fdb-hammer-parallel/artifacts.\n\n\
--artifact-dir-is-shared\n\nFlag to be provided if the artifact directory on the client nodes is shared via a networked file system.\n\n\
--verbose\nPrint field identifiers archived or retrieved.\n\n\
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
    --fields-per-member-per-step)
    fields_per_member_per_step="$2"
    shift
    shift
    ;;
    --itt)
    itt=yes
    shift
    ;;
    --read-nodes-per-step)
    read_nodes_per_step="$2"
    shift
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
    --member-delay)
    member_delay="$2"
    shift
    shift
    ;;
    --reader-delay)
    reader_delay="$2"
    shift
    shift
    ;;
    --step-window)
    step_window="$2"
    shift
    shift
    ;;
    --random-delay)
    random_delay="$2"
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
    --prolog-script)
    prolog_script="$2"
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
    --verbose)
    verbose=yes
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

blocks = re.findall(r'[^,\[]+(?:\[[^\]]*\][^,]*)?', s)
r = []
for b in blocks:
  if '[' in b:
    parts = b.split('[')
    prefix = parts[0]
    parts = parts[1].split(']')
    suffix = parts[1]
    ranges = parts[0].split(',')
    for i in ranges:
      if '-' in i:
        limits = i.split('-')
        digits = len(limits[0])
        for j in range(int(limits[0]), int(limits[1]) + 1):
          print(prefix + (("%0" + str(digits) + "d") % (j,)) + suffix)
      else:
        print(prefix + i + suffix)
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
  "$root/sample_field" \
  "$root/schema" \
  "$config" \
)

if [[ "$prolog_script" != "none" ]] ; then
  artifacts+=( "$prolog_script" )
  prolog_script=$(basename $prolog_script)
fi

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



# --- apply fields-per-member-per-step if supplied

if [[ ! -z "$fields_per_member_per_step" ]] ; then
    NLEVELS=$( python3 <<EOF
from math import ceil
print(ceil($fields_per_member_per_step / $NPARAMS / $ppn / ($num_nodes / $nmembers)))
EOF
)
fi

if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

  # --- sanity check steps and reader procs if --itt read

  num_nodes_read_itt=${#nodes_read_itt[@]}

  if [[ "$read_nodes_per_step" == "default" ]] ; then
    read_nodes_per_step=1
    if [ "$NSTEPS" -lt "$num_nodes_read_itt" ] ; then
      (( "$num_nodes_read_itt" % "$NSTEPS" != 0 )) && \
        echo "num reader nodes must be divisible by nsteps if nsteps < num reader nodes and read-nodes-per-step is 'default'" && \
        echo "read aborted" && \
        exit 1
      read_nodes_per_step=$(( num_nodes_read_itt / NSTEPS ))
    fi
  fi

  (( "$num_nodes_read_itt" % "$read_nodes_per_step" != 0 )) && \
    echo "num reader nodes must be divisble by read-nodes-per-step" && \
    echo "read aborted" && \
    exit 1

  reader_procs_per_step=$(( ppn_read_itt * read_nodes_per_step ))

  num_nodes_write=${#nodes_write_or_read[@]}
  if [ "$num_nodes_write" -gt "$nmembers" ] ; then
    nodes_per_member=$(( num_nodes_write / nmembers ))
    procs_per_member=$(( ppn * nodes_per_member ))
  else
    members_per_node=$(( nmembers / num_nodes_write ))
    procs_per_member=$(( ppn / members_per_node ))
  fi
  written_levels_per_step=$(( NLEVELS * procs_per_member ))
  fields_per_step_per_member=$(( procs_per_member * NLEVELS * NPARAMS ))

  (( "$fields_per_step_per_member" % "$reader_procs_per_step" != 0 )) && \
    echo "The total number of fields archived per step per member (${procs_per_member} x ${NLEVELS} x ${NPARAMS} = ${fields_per_step_per_member}) must be divisible by the number of reader processes per step (${reader_procs_per_step})." && \
    exit 1



  # --- generate lists of randomly ordered levels for each reader node

  # One list of randomly ordered levels is passed as input to every reader node.
  # If the benchmark is configured with read_nodes_per_step > 1, and therefore
  # multiple reader nodes read data for the same step, the reader nodes for a given
  # step will all receive the same list of levels and each node will extract a
  # different subset of levels from the provided list.
  # If the benchmark is configured with less reader nodes than steps * read_nodes_per_step,
  # and therefore reader nodes read data for multiple steps, the same list of randomly
  # ordered levels provided as input to a reader node is used for all of its steps.
  # Because each reader node will read its assigned steps with a stride of
  # #number_of_reader nodes, and each reader process reads parameters in a different order,
  # the read order for every subsequent step read (both overall and within a reader node)
  # will be different.

  level_lists=()

  max_read_jobs=$(( num_nodes_read_itt / read_nodes_per_step ))
  for job in `seq 1 $max_read_jobs` ; do
    list=($(seq 1 $written_levels_per_step | shuf))
    for node in `seq 1 $read_nodes_per_step` ; do
      level_lists+=( $(echo "${list[@]}" | tr -s ' ' ',') )
    done
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

start_time=$(date +%s)

for node in "${nodes[@]}" ; do

  args=( \
    $i $ppn $mode $nodelist $nmembers $NSTEPS $NLEVELS $NPARAMS \
    $check $install $artifact_dir $artifact_dir_is_shared $prolog_script $verbose \
    $itt $member_delay $reader_delay $step_window $random_delay \
    $barrier_port $barrier_max_wait \
    $nodelist_read_itt $read_nodes_per_step $ppn_read_itt \
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

end_time=$(date +%s)

echo Done



# --- calculate bandwidth

failures=$(cat "${outs[@]}" | grep -e "failed at:" | wc -l)
consistency_failures=0
[[ "$mode" == "read" ]] && consistency_failures=$(cat "${outs[@]}" | grep -e "Assertion failed" -e "Found less fields" -e "Found a field of different size" | wc -l)

first_ts=$(cat "${outs[@]}" | grep "Timestamp before first IO" | awk '{print $5}' | sort -n | head -n 1)
last_ts=$(cat "${outs[@]}" | grep "Timestamp after last IO" | awk '{print $5}' | sort -nr | head -n 1)

field_size_mb=4.175
num_nodes=${#nodes[@]}
bw=$(bc <<< "$num_nodes * $ppn * $NSTEPS * $NLEVELS * $NPARAMS * $field_size_mb / ($last_ts - $first_ts)")

avg_sleep_per_step=0
[[ "$mode" == "write" ]] && [[ "$itt" == "yes" ]] && \
  avg_sleep_per_step=$(cat "${outs[@]}" | grep "time slept per step" | awk '{print $6}' | python3 <(cat <<EOF
import sys
d = [int(val) for val in sys.stdin.read().split()]
print(sum(d) / len(d))
EOF
))

for out in "${outs[@]}" ; do

  echo $out
  cat $out
  echo ""
  rm ${out}

done

echo "----------------"

echo "Start time: $(date --date @${start_time})"
echo "End time: $(date --date @${end_time})"
echo "Wall-clock time: $(( end_time - start_time )) s"

if [[ "$mode" != "list" ]] ; then

  note=

  #[[ "$itt" == "yes" ]] && [[ "$mode" == "write" ]] && \
  #  (( "$step_window" -gt 0 )) && \
  #  note=" (including --step-window sleeps)"

  [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] && \
    note=" (including waiting/polling)"

  echo "Total ${mode} bandwidth${note}: ${bw} MiB/s"

  [[ "$itt" == "yes" ]] && [[ "$mode" == "write" ]] && \
    echo "Average time slept per step: ${avg_sleep_per_step}"

  [ "$failures" -ne 0 ] && echo "Got ${failures} failures" || echo "No failures occurred"

  [ "$consistency_failures" -ne 0 ] && echo "Found ${consistency_failures} inconsistencies"

fi

echo "----------------"
