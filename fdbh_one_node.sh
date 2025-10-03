I=$1
ppn=$2
mode=$3
nodes=$4
nmembers=$5
NSTEPS=$6
NLEVELS=$7
NPARAMS=$8
check=$9
reinstall=${10}
artifact_dir=${11}
artifact_dir_is_shared=${12}
prolog_script=${13}
verbose=${14}
itt=${15:-no}
member_delay=${16:-}
reader_delay=${17:-}
step_window=${18:-}
random_delay=${19:-}
barrier_port=${20:-}
barrier_max_wait=${21:-}
nodes_read=${22:-}
read_nodes_per_step=${23:-}
ppn_read=${24:-}
poll_period=${25:-}
poll_max_attempts=${26:-}
read_step_window=${27:-}
read_random_delay=${28:-}
prelist=${29:-}
level_list=${30:-}

[[ "$prolog_script" != "none" ]] && source "${artifact_dir}/${prolog_script}"

nodelist=(${nodes//,/ })
num_nodes=${#nodelist[@]}

levelist=(${level_list//,/ })

# if itt read mode, populate the nodelist, num_nodes, and ppn variables
# based on the read node list and read ppn. These variables will be used
# to shape the workload. The write node list and ppn are still required
# for shaping the workload but are kept in separate variables.

steps=

if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

  nodelist_write=$nodelist
  num_nodes_write=$num_nodes

  nodelist=(${nodes_read//,/ })
  num_nodes=${#nodelist[@]}

  ppn_write=$ppn
  ppn=$ppn_read

  # calculate the list of steps this node must read
  steps=( $(seq $(( I / read_nodes_per_step )) $(( num_nodes / read_nodes_per_step )) $(( NSTEPS - 1 )) ) )

fi

# expand tilde in artifact dir if needed:
[[ "$artifact_dir" == '~/'* ]] && artifact_dir=${HOME}/${artifact_dir#"~/"}

hostname
echo "index: $I"

this_node=$(hostname)

if [[ "$artifact_dir_is_shared" == "no" ]] || [[ "$this_node" == "${nodelist[0]}" ]] ; then

  # --- prepare netcat

  netcat_dir=${artifact_dir}/netcat

  [[ "$reinstall" == "yes" ]] && rm -rf ${artifact_dir}/netcat

  if [ ! -e $netcat_dir ] ; then

    mkdir -p $netcat_dir

    tar -xzvf ${artifact_dir}/netcat.tar.gz -C ${artifact_dir}

  fi

  # --- prepare fdb

  fdb_dir=${artifact_dir}/fdb-bundle

  [[ "$reinstall" == "yes" ]] && rm -rf ${artifact_dir}/fdb-bundle

  if [ ! -e $fdb_dir ] ; then

    mkdir -p $fdb_dir

    tar -xzvf ${artifact_dir}/fdb-bundle.tar.gz -C ${artifact_dir}

  fi

fi



# --- execute fdb-hammer

tmp_dir=$(mktemp -d -t test_fdb_hammer_XXX)
cd $tmp_dir

n_chips=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l)
n_cores=$(cat /proc/cpuinfo | grep "cpu cores" | sort -u | awk '{print $4}')
ht=0
n_procs=$(cat /proc/cpuinfo | grep "processor" | sort -u | wc -l)
[ "$n_procs" -gt "$(( n_cores * n_chips ))" ] && ht=1



function pin {
        local x=$1
        local ch=$2
        local co=$3
        local ht=$4
        x=$(( x - 1 ))
        local a=$(( x % ch ))
        local tot=$(( ch * co ))
        local of=0
        if [ "$ht" -eq 1 ] ; then
                tot=$(( tot * 2 ))
                [ "$(( x % tot ))" -ge "$(( ch * co ))" ] && of=$(( ch * co ))
        fi
        local i=$(( ( (x % tot) - a) % (ch * co) / ch ))
        local y=$(( of + a * co + i ))
        echo "$y"
}



function client {

  local i=$1

  local failed=0
  local out=
  local listout=

  local prof=
  local prof_sep=

  local log=
  local log_sep=

  # pinning
  local pin_proc=$(pin $((i + 1)) $n_chips $n_cores $ht)

  # local page cache busting
  # (not relevant in itt mode as reading should always be configured
  #  to run on a different set of nodes than for writing, and even if 
  #  run on the same nodes, every reader node would accesses data 
  #  produced by all writer nodes, making the "cache bust shift" irrelevant)

  [[ "$mode" == "read" ]] && [[ "$itt" == "no" ]] && \
    I=$(( ( I + 1 )  % num_nodes ))

  # calculate number and level for this process and node

  local nsteps=$NSTEPS
  local nlevels=$NLEVELS
  local nparams=$NPARAMS
  local nmembers=$nmembers
  local ndatabases=1

  local nodes_per_member=
  local members_per_node=
  local procs_per_member=
  local number=
  local procs_per_db=
  local member_proc_i=
  local database=
  local database_proc_i=

  local nodes_per_step=
  local steps_per_node=
  local procs_per_step=
  local step_proc_i=
  local levels_per_reader_proc=
  local first_level=
  local levels=
  local levels_subset=

  local fields_per_member_per_step=
  local fields_this_proc=
  local remainder=
  local fields_before_this_proc=
  local to_add=
  local nlevels_this_proc=
  local stop_at=

  if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

    nodes_per_step=$read_nodes_per_step

    procs_per_step=$(( ppn * nodes_per_step ))
    procs_per_db=$(( procs_per_step / ndatabases ))
    step_proc_i=$(( ppn * (I % nodes_per_step) + i ))
    database=$(( step_proc_i / procs_per_db ))

    database_proc_i=$(( step_proc_i % procs_per_db ))

  else

    if [ "$num_nodes" -gt "$nmembers" ] ; then
        nodes_per_member=$(( num_nodes / nmembers ))
        number=$(( I / nodes_per_member + 1 ))
        procs_per_member=$(( ppn * nodes_per_member ))
        member_proc_i=$(( ppn * (I % nodes_per_member) + i ))
    else
        members_per_node=$(( nmembers / num_nodes ))
        procs_per_member=$(( ppn / members_per_node ))
        number=$(( ( I * members_per_node ) + ( i / procs_per_member ) + 1 ))
        member_proc_i=$(( i % procs_per_member ))
    fi

    procs_per_db=$(( procs_per_member / ndatabases ))
    database=$(( member_proc_i / procs_per_db ))
    database_proc_i=$(( member_proc_i % procs_per_db ))

  fi

  fields_per_member_per_step=$(( nlevels * nparams ))
  fields_this_proc=$(( fields_per_member_per_step / procs_per_db ))
  remainder=$(( fields_per_member_per_step % procs_per_db ))
  [ $database_proc_i -lt $remainder ] && fields_this_proc=$(( fields_this_proc + 1 ))

  fields_before_this_proc=$(( ( fields_per_member_per_step / procs_per_db ) * database_proc_i ))
  to_add=$remainder
  [ $database_proc_i -lt $remainder ] && to_add=$database_proc_i
  fields_before_this_proc=$(( fields_before_this_proc + to_add ))

  first_level=$(( ( fields_before_this_proc / nparams ) + 1 ))
  start_at=$(( fields_before_this_proc % nparams ))
  nlevels_this_proc=$(( ( start_at + fields_this_proc ) / nparams ))
  [ $(( ( start_at + fields_this_proc ) % nparams )) -gt 0 ] && nlevels_this_proc=$(( nlevels_this_proc + 1 ))
  stop_at=$(( start_at + fields_this_proc - 1 ))

  if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

    levels_subset=( "${levelist[@]:$(( first_level - 1 )):${nlevels_this_proc}}" )
    levels=$(echo "${levels_subset[@]}" | tr -s ' ' ',')

  fi

  local fdb_hammer=${artifact_dir}/fdb-bundle/bin/fdb-hammer

  local fdb_list=${artifact_dir}/fdb-bundle/bin/fdb-list

  # run fdb-hammer

  local verbose_arg=
  [[ "$verbose" == "yes" ]] && verbose_arg="--verbose"

  local start_timestamp=
  local step_timestamp=
  local current_timestamp=
  local wait_time=
  local step_end_timestamp=
  local random_range=

  local uris_arg=

  if [[ "$mode" == "list" ]] ; then

    out=$(taskset -c $pin_proc $fdb_hammer \
            $tmp_dir/sample_field \
            --list \
            --class=rd \
            --expver=xxxx \
            --nsteps=1 \
            --nensembles=$nmembers \
            --number=1 \
            --nlevels=$nlevels \
            --level=1 \
            --nparams=$nparams \
            --config=$tmp_dir/config.yaml \
            ${verbose_arg} \
            2>&1
    )

  else

    mode_arg=
    [[ "$mode" == "read" ]] && mode_arg="--read"

    check_arg=
    [[ "$check" == "md" ]] && check_arg="--md-check"
    [[ "$check" == "full" ]] && check_arg="--full-check"

    if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

      start_timestamp=$(date +%s)

      # read-random-delay
      if [ "$read_random_delay" -gt 0 ] && [ "$read_step_window" -gt 0 ] ; then
        random_range=$(( ( read_step_window * read_random_delay / 100 ) + 1 ))
        sleep $(( ( RANDOM % $random_range ) ))
      fi

      local step=
      for step in "${steps[@]}" ; do

        # reader-delay
        [[ "$step" == "${steps[0]}" ]] && sleep $(( reader_delay * step ))

        # wait until read-step-window due to start
        step_timestamp=$(( start_timestamp + step * read_step_window ))
        current_timestamp=$(date +%s)
        wait_time=$(( step_timestamp - current_timestamp ))
        [ "$wait_time" -gt 0 ] && sleep $wait_time

        if [[ "$prelist" == "yes" ]] ; then

          if [[ "$i" == 0 ]] ; then

            local levels_per_reader_node=$(( nlevels / nodes_per_step ))
            local first_node_level=$(( ( I % nodes_per_step ) * levels_per_reader_node ))
            local node_levels=( "${levelist[@]:${first_node_level}:${levels_per_reader_node}}" )
            local node_levels_str=$( printf '%s/' "${node_levels[@]}" )
            node_levels_str=${node_levels_str%/}

            local attempts=0
            local prelist_time=0
            local t0=
            local tf=
            while [ 1 ] ; do
              # list all locations for fields to be read by this node
              t0=$(date +%s)
              listout=$( ${fdb_list} \
                class=rd,expver=xxxx,stream=enfo,date=20230713,time=0000,domain=g,step=$step,levelist=$node_levels_str \
                --location --config=$tmp_dir/config.yaml 2>&1 | grep URI \
              )

              # ensure number of fields listed matches nparams*length(node_levels)*nmembers
              local found=$( echo "${listout}" | wc -l )
              local expected=$(( nparams * ${#node_levels[@]} * nmembers ))

              tf=$(date +%s)
              prelist_time=$(( prelist_time + tf - t0 ))
              attempts=$(( attempts + 1 ))

              [ $found -gt $expected ] && echo "Listed unexpected number of fields. Expected $expected, found $found." && exit 1
              [ $found -lt $expected ] && [ $attempts -ge $poll_max_attempts ] && echo "Pre-list maximum attempts ($poll_max_attempts) exceeded." && exit 1
              [ $found -eq $expected ] && echo "Pre-listing completed." && break
              sleep $poll_period
            done

            echo "Duration of $attempts pre-list attempts: $prelist_time s"

            t0=$(date +%s)

            # split URIs in subsets and write in a file per process, respecting the order of levels in the supplied levelist
            rm -f $tmp_dir/uris_*
            echo "$listout" | python3 <(cat <<EOF
import sys
import random

ppn = int(sys.argv[1])
nparams = int(sys.argv[2])
nmembers = int(sys.argv[3])
levelist = [int(x) for x in sys.argv[4].split('/')]
tmp_dir = sys.argv[5]

nfields = nparams * nmembers * len(levelist)
fields_per_proc = [nfields // ppn + (1 if x < nfields % ppn else 0) for x in range(ppn)]

uris_per_level = {}

for lev in levelist:
  uris_per_level[lev] = []

count = 0
for val in sys.stdin:
  ident, uri = val.split("TocFieldLocation[uri=URI[scheme=file,name=", 1)
  uri, other = uri.split("],offset=", 1)
  offset, other = other.split(",length=", 1)
  length = other.split(",remapKey=", 1)[0]
  level = int(ident.split("levelist=", 1)[1].split(",param=", 1)[0])
  uris_per_level[level].append("file:" + uri + "?length=" + length + "#" + offset)
  count += 1

if count != nfields:
  raise RuntimeError('Received less URIs than expected')

uris_per_proc = [[] for i in range(ppn)]

proc_i = 0
for lev in levelist:
  for par in range(nparams * nmembers):
    uris_per_proc[proc_i].append(uris_per_level[lev][par])
    fields_per_proc[proc_i] -= 1
    if fields_per_proc[proc_i] < 1:
      proc_i += 1

i = 0
for urilist in uris_per_proc:
  random.shuffle(urilist)
  with open(tmp_dir + "/uris_" + str(i), 'w') as f:
    f.write('\n'.join(urilist))
  i+=1
EOF
) $ppn $nparams $nmembers $node_levels_str $tmp_dir

            tf=$(date +%s)
            echo "Duration of pre-list postprocessing: $(( tf - t0 )) s"

            # notify peer processes listing has completed by opening FIFO for write
            touch $prelist_fifo

          else

            # wait for leader process to notify list completion by opening FIFO for read
            timeout 500 cat $prelist_fifo
            [ $? -ne 0 ] && echo "Timed out waiting for list completion signal." && exit 1

          fi

          uris_arg="--uri-file=${tmp_dir}/uris_${i}"

        fi

        out="${out}\n$(taskset -c $pin_proc $fdb_hammer \
                $tmp_dir/sample_field \
                $mode_arg \
                --itt \
                --poll-period=$poll_period \
                --poll-max-attempts=$poll_max_attempts \
                --class=rd \
                --expver=xxxx \
                --nsteps=1 \
                --step=$step \
                --nensembles=$nmembers \
                --number=1 \
                --levels=$levels \
                --nparams=$nparams \
                --start-at=$start_at \
                --stop-at=$stop_at \
                $uris_arg \
                $check_arg \
                --config=$tmp_dir/config.yaml \
                ${verbose_arg} \
                2>&1
        )"

        rc=$?

        # notify the reporter that this process has read step 'step'
        echo "$step" >&3

        # consume read-step-window
        step_end_timestamp=$(( step_timestamp + read_step_window ))
        current_timestamp=$(date +%s)
        wait_time=$(( step_end_timestamp - current_timestamp ))
        [ "$wait_time" -gt 0 ] && sleep $wait_time

        eval [ $rc -eq 0 ]

      done

    else

      itt_arg=
      [[ "$itt" == "yes" ]] && itt_arg="--itt --ppn=${ppn} --nodes=${nodes} --step-window=${step_window} --random-delay=${random_delay} --barrier-port=${barrier_port} --barrier-max-wait=${barrier_max_wait}"

      # reproduce delay among members if ITT write
      [[ "$itt" == "yes" ]] && sleep $(( member_delay * ( number - 1 ) ))

      out=$(taskset -c $pin_proc $fdb_hammer \
              $tmp_dir/sample_field \
              $mode_arg \
              $itt_arg \
              --class=rd \
              --expver=xxxx \
              --nsteps=$nsteps \
              --nensembles=1 \
              --number=$number \
              --nlevels=$nlevels_this_proc \
              --level=$first_level \
              --nparams=$nparams \
              --start-at=$start_at \
              --stop-at=$stop_at \
              $check_arg \
              --config=$tmp_dir/config.yaml \
              ${verbose_arg} \
              2>&1
      )

    fi

  fi

  [ $? != 0 ] && failed=1 && log="${log}"${log_sep}"log: $out" && log_sep="\n"

  prof="${prof}"${prof_sep}$(echo "$out") && prof_sep="\n"

  [ $failed -ne 0 ] && echo "Node $I client $i failed at: ${mode}" \
          && echo -e "${log}" && echo -e "${prof}" && return

  echo -e "Node $I client $i succeeded\n${prof}"

}



function step_end_reporter {

  local done_count=()
  local step=
  for step in "${steps[@]}" ; do
    done_count+=(0)
  done

  local steps_done=0

  local message=

  while [ "$steps_done" -lt "${#steps[@]}" ] ; do

    # reads one line from the anonymous pipe into the 'message' variable
    read -t 1000 -ru 3 message
    [ $? -ne 0 ] && echo "Timed out waiting for list completion signal." && exit 1

    # find step counter position in done_count
    local pos=0
    local step_id=
    for step in "${steps[@]}" ; do
      [[ "$step" == "$message" ]] && step_id=$step && break
      pos=$(( pos + 1 ))
    done

    [ -z $step_id ] && echo "Received unexpected step number." && exit 1

    done_count[$pos]=$(( done_count[$pos] + 1 ))

    if [ "${done_count[$pos]}" -eq $ppn ] ; then
      echo "Step $step_id read at $(date +%s)"
      steps_done=$(( steps_done + 1 ))
    fi

  done

}



test_src_dir=${artifact_dir}

cp $test_src_dir/sample_field $tmp_dir/sample_field
cp $test_src_dir/schema $tmp_dir/schema
cp $test_src_dir/config.yaml.in $tmp_dir/config.yaml
sed -i -e "s#@SCHEMA_PATH@#${tmp_dir}/schema#" $tmp_dir/config.yaml

#export FDB_ROOT_DIRECTORY=${fdb_root}
#export FDB_DATA_LUSTRE_STRIPE_COUNT=1
#export FDB_DATA_LUSTRE_STRIPE_SIZE=1048576

export FDB_SCHEMA_FILE=${tmp_dir}/schema
#export FDB_ASYNC_WRITE=1

export FDB_HAMMER_RUN_PATH=/tmp/${USER}
mkdir -p $FDB_HAMMER_RUN_PATH

prelist_fifo=

if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

  # --- set up anonymous pipe for workers to signal step end to reporter

  # create a FIFO (named pipe) in tmpfs
  pipe=$(mktemp -u)
  mkfifo $pipe
  # attach it to fd 3
  exec 3<>$pipe
  # turn the pipe into an anonymous pipe by removing the file
  rm $pipe

  # --- fire the reporter

  step_end_reporter &

  # create a FIFO for process 0 to signal other processes that the pre-list has completed
  if [[ "$prelist" == "yes" ]] ; then
    prelist_fifo=$(mktemp -u)
    mkfifo $prelist_fifo
  fi

fi

procs_to_run=$ppn
[[ "$mode" == "list" ]] && procs_to_run=1

for i in $(seq 0 $((procs_to_run - 1))) ; do
  client $i &
done

wait

cd
rm -rf ${tmp_dir}
