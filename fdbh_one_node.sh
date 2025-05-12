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
  barrier_port=${16:-}
  barrier_max_wait=${17:-}
  nodes_read=${18:-}
  ppn_read=${19:-}
  poll_period=${20:-}
  level_list=${21:-}

  [[ "$prolog_script" != "none" ]] && source "${artifact_dir}/${prolog_script}"

  levelist=(${level_list//,/ })
  nodelist=(${nodes//,/ })
  num_nodes=${#nodelist[@]}

  # if itt read mode, populate the nodelist, num_nodes, and ppn variables
  # based on the read node list and read ppn. These variables will be used
  # to shape the workload. The write node list and ppn are still required
  # for shaping the workload but are kept in separate variables.

  if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

    nodelist_write=$nodelist
    num_nodes_write=$num_nodes

    nodelist=(${nodes_read//,/ })
    num_nodes=${#nodelist[@]}

    ppn_write=$ppn
    ppn=$ppn_read

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


#  # --- barrier
#
#  NOTE: this barrier is needed specially for the first run of the benchmark where
#  one or multiple parallel processes may spend a significant and variable amount of
#  time installing the benchmark binaries. It is less relevant for subsequent runs.
#
#  TODO: for now commented out as there's a bug. In the meantime, the benchmark can
#  be first run with ppn=1 to trigger installation on all nodes, and then rerun with
#  larger ppn -- installation will be skipped and no significant delays will occur.
#
#  if [ $I -eq 0 ] ; then
#
#    # --- wait for ping from all other nodes
#    for node in "${nodelist[@]}" ; do
#      [[ "$node" == "$(hostname)" ]] && continue
#      echo "WAITING FOR MESSAGE FROM ${node} ON $(hostname)"
#      m=$(${netcat_dir}/netcat.out -l 12345 | bash -c 'read MESSAGE; echo "$(hostname) RECEIVED MESSAGE": $MESSAGE')
#      [[ ! "${m}" =~ "succeeded" ]] && exit 1
#    done
#
#    # --- send ping to all other nodes
#    status="succeeded"
#    for node in "${nodelist[@]}" ; do
#      [[ "$node" == "$(hostname)" ]] && continue
#      #echo "WAITING FOR MESSAGE FROM ${node} ON $(hostname)"
#      #m=$(${netcat_dir}/netcat.out -l 12345 | bash -c 'read MESSAGE; echo "$(hostname) RECEIVED MESSAGE": $MESSAGE')
#      #[[ ! "${m}" =~ "succeeded" ]] && exit 1
#      code=1
#      while [ "$code" -ne 0 ] ; do
#        echo "SENDING MESSAGE FROM $(hostname) TO ${node}"
#        echo "SETUP ON $(hostname) ${status}" | ${netcat_dir}/netcat.out ${node} 12345 2>1 | grep -v 'error'
#        code=$?
#        [ "$code" -ne 0 ] && sleep 2
#      done
#    done
#    [[ "${status}" == "failed" ]] && exit 1
#
#  else
#
#    # --- send ping to first node
#    status="succeeded"
#    code=1
#    while [ "$code" -ne 0 ] ; do
#      echo "SENDING MESSAGE FROM $(hostname) TO ${nodelist[0]}"
#      echo "SETUP ON $(hostname) ${status}" | ${netcat_dir}/netcat.out ${nodelist[0]} 12345 2>1 | grep -v 'error'
#      code=$?
#      [ "$code" -ne 0 ] && sleep 2
#    done
#    [[ "${status}" == "failed" ]] && exit 1
#
#    # --- wait ping from first node
#    echo "WAITING FOR MESSAGE FROM ${nodelist[0]} ON $(hostname)"
#    m=$(${netcat_dir}/netcat.out -l 12345 | bash -c 'read MESSAGE; echo "$(hostname) RECEIVED MESSAGE": $MESSAGE')
#    [[ ! "${m}" =~ "succeeded" ]] && exit 1
#
#  fi



  # --- execute fdb-hammer
  tmp_dir=$(mktemp -d -t test_fdb_hammer_XXX)
  cd $tmp_dir

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

  n_chips=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l)
  n_cores=$(cat /proc/cpuinfo | grep "cpu cores" | sort -u | awk '{print $4}')
  ht=0
  n_procs=$(cat /proc/cpuinfo | grep "processor" | sort -u | wc -l)
  [ "$n_procs" -gt "$(( n_cores * n_chips ))" ] && ht=1

  function client {

    local i=$1

    local failed=0
    local out=

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

    local written_levels_per_step=
    local nodes_per_step=
    local steps_per_node=
    local steps=
    local procs_per_step=
    local step_proc_i=
    local levels_per_reader_proc=
    local level=
    local levels=

    if [[ "$itt" == "yes" ]] && [[ "$mode" == "read" ]] ; then

      if [ "$num_nodes_write" -lt "$nmembers" ] ; then
        members_per_node=$(( nmembers / num_nodes_write ))
        written_levels_per_step=$(( nlevels * ppn / members_per_node ))
      else
        nodes_per_member=$(( num_nodes_write / nmembers ))
        written_levels_per_step=$(( nlevels * ppn * nodes_per_member ))
      fi

      if [ "$num_nodes" -gt "$nsteps" ] ; then
          nodes_per_step=$(( num_nodes / nsteps ))
          steps=( $(( I / nodes_per_step )) )

          procs_per_step=$(( ppn * nodes_per_step ))
          procs_per_db=$(( procs_per_step / ndatabases ))
          step_proc_i=$(( ppn * (I % nodes_per_step) + i ))
          database=$(( step_proc_i / procs_per_db ))

          database_proc_i=$(( step_proc_i % procs_per_db ))
          levels_per_reader_proc=$(( written_levels_per_step / nodes_per_step / ppn ))
          level=$(( ( levels_per_reader_proc * database_proc_i ) + 1 ))
      else
          steps_per_node=$(( nsteps / num_nodes ))
          steps=( $(seq $I $num_nodes $(( nsteps - 1 )) ) )

          procs_per_step=$ppn
          procs_per_db=$(( procs_per_step / ndatabases ))
          step_proc_i=$(( i % procs_per_step ))
          database=$(( step_proc_i / procs_per_db ))

          database_proc_i=$(( step_proc_i % procs_per_db ))
          levels_per_reader_proc=$(( written_levels_per_step / ppn ))
          level=$(( ( levels_per_reader_proc * database_proc_i ) + 1 ))
      fi

      levels=( "${levelist[@]:$(( level - 1 )):${levels_per_reader_proc}}" )
      levels=$(echo "${levels[@]}" | tr -s ' ' ',')

    else

      if [ "$num_nodes" -gt "$nmembers" ] ; then
          nodes_per_member=$(( num_nodes / nmembers ))
          number=$(( I / nodes_per_member + 1 ))

          procs_per_member=$(( ppn * nodes_per_member ))
          procs_per_db=$(( procs_per_member / ndatabases ))
          member_proc_i=$( (ppn * (I % nodes_per_member) + i ))
          database=$(( member_proc_i / procs_per_db ))

          database_proc_i=$(( member_proc_i % procs_per_db ))
          level=$(( ( nlevels * database_proc_i ) + 1 ))
      else
          members_per_node=$(( nmembers / num_nodes ))
          procs_per_member=$(( ppn / members_per_node ))
          number=$(( ( I * members_per_node ) + ( i / procs_per_member ) + 1 ))

          procs_per_db=$(( procs_per_member / ndatabases ))
          member_proc_i=$(( i % procs_per_member ))
          database=$(( member_proc_i / procs_per_db ))

          database_proc_i=$(( member_proc_i % procs_per_db ))
          level=$(( ( nlevels * database_proc_i ) + 1 ))
      fi

    fi

    local fdb_hammer=${artifact_dir}/fdb-bundle/bin/fdb-hammer
    local fdb_read=${artifact_dir}/fdb-bundle/bin/fdb-read

    # run fdb-hammer

    verbose_arg=
    [[ "$verbose" == "yes" ]] && verbose_arg="--verbose"

    if [[ "$mode" == "list" ]] ; then

      out=$(taskset -c $pin_proc $fdb_hammer \
              $tmp_dir/sample1MiB \
              --list \
              --class=rd \
              --expver=xxxx \
              --nsteps=1 \
              --nensembles=$nmembers \
              --number=1 \
              --nlevels=$(( nlevels * procs_per_db )) \
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

        for step in "${steps[@]}" ; do
          out="${out}\n$(taskset -c $pin_proc $fdb_hammer \
                  $tmp_dir/sample1MiB \
                  $mode_arg \
                  --itt \
                  --poll-period=$poll_period \
                  --class=rd \
                  --expver=xxxx \
                  --nsteps=1 \
                  --step=$step \
                  --nensembles=$nmembers \
                  --number=1 \
                  --levels=$levels \
                  --nparams=$nparams \
                  $check_arg \
                  --config=$tmp_dir/config.yaml \
                  ${verbose_arg} \
                  2>&1
          )"
                  #--nlevels=$levels_per_reader_proc \
                  #--level=$level \

        done

      else

        itt_arg=
        [[ "$itt" == "yes" ]] && itt_arg="--itt --ppn=${ppn} --nodes=${nodes} --barrier-port=${barrier_port} --barrier-max-wait=${barrier_max_wait}"


        out=$(taskset -c $pin_proc $fdb_hammer \
                $tmp_dir/sample1MiB \
                $mode_arg \
                $itt_arg \
                --class=rd \
                --expver=xxxx \
                --nsteps=$nsteps \
                --nensembles=1 \
                --number=$number \
                --nlevels=$nlevels \
                --level=$level \
                --nparams=$nparams \
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

  test_src_dir=${artifact_dir}

  cp $test_src_dir/sample1MiB $tmp_dir/sample1MiB
  cp $test_src_dir/schema_posix $tmp_dir/schema
  cp $test_src_dir/config.yaml.in $tmp_dir/config.yaml
  sed -i -e "s#@SCHEMA_PATH@#${tmp_dir}/schema#" $tmp_dir/config.yaml

  #export FDB_ROOT_DIRECTORY=${fdb_root}
  #export FDB_DATA_LUSTRE_STRIPE_COUNT=24

  export FDB_SCHEMA_FILE=${tmp_dir}/schema
  #export FDB_ASYNC_WRITE=1

  procs_to_run=$ppn
  [[ "$mode" == "list" ]] && procs_to_run=1

  for i in $(seq 0 $((procs_to_run - 1))) ; do
    client $i &
  done

  wait

  cd
  rm -rf ${tmp_dir}
