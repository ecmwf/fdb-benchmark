
  I=$1
  ppn=$2
  mode=$3
  nodes=$4
  NSTEPS=$5
  NLEVELS=$6
  NPARAMS=$7
  check=$8
  reinstall=$9
  artifact_dir=${10}
  artifact_dir_is_shared=${11}

  nodelist=(${nodes//,/ })
  num_nodes=${#nodelist[@]}

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
    [[ "$mode" == "read" ]] && I=$(( ( I + 1 )  % num_nodes ))
    # calculate number and level for this process and node

    local nsteps=$NSTEPS
    local nlevels=$NLEVELS
    local nparams=$NPARAMS
    local nmembers=$num_nodes

    local members_per_node=1
    local procs_per_member=$(( ppn / members_per_node ))
    local number=$(( ( I * members_per_node ) + ( i / procs_per_member ) + 1 ))

    local ndatabases=1
    local procs_per_db=$(( procs_per_member / ndatabases ))
    local member_proc_i=$(( i % procs_per_member ))
    local database=$(( member_proc_i / procs_per_db ))

    local database_proc_i=$(( member_proc_i % procs_per_db ))
    local level=$(( ( nlevels * database_proc_i ) + 1 ))

    local fdb_hammer=${artifact_dir}/fdb-bundle/bin/fdb-hammer
    local fdb_read=${artifact_dir}/fdb-bundle/bin/fdb-read

    # run fdb-hammer

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
              --config=$tmp_dir/config.yaml
      )
      #out=$(echo "taskset -c $pin_proc $fdb_hammer $tmp_dir/sample1MiB --list --class=rd --expver=xxxx --nsteps=1 --nensembles=$nmembers --number=1 --nlevels=$(( nlevels * procs_per_db )) --level=1 --nparams=$nparams --config=$tmp_dir/config.yaml")

    else

      mode_arg=
      [[ "$mode" == "read" ]] && mode_arg="--read"

      check_arg=
      [[ "$check" == "md" ]] && check_arg="--md-check"
      [[ "$check" == "full" ]] && check_arg="--full-check"

#      if [[ "$mode" == "write" ]] ; then

        out=$(taskset -c $pin_proc $fdb_hammer \
                $tmp_dir/sample1MiB \
                $mode_arg \
                --class=rd \
                --expver=xxxx \
                --nsteps=$nsteps \
                --nensembles=1 \
                --number=$number \
                --nlevels=$nlevels \
                --level=$level \
                --nparams=$nparams \
		$check_arg \
                --config=$tmp_dir/config.yaml
        )
        #out=$(echo "taskset -c $pin_proc $fdb_hammer $tmp_dir/sample1MiB $mode_arg --class=rd --expver=xxxx --nsteps=$nsteps --nensembles=1 --number=$number --nlevels=$nlevels --level=$level --nparams=$nparams --config=$tmp_dir/config.yaml")

#      else
#
#        local tmpf=$(mktemp /tmp/req.XXXXXX)
#
#	local awkward_params=( 11 12 13 14 15 16 49 51 52 61 121 122 146 147 169 175 176 177 179 189 201 202 )
#
#        local paramlist=""
#        local param=1
#	local realparam=1
#	local sep=""
#        while [ $param -le $nparams ] ; do
#          while [[ " ${awkward_params[*]} " =~ [[:space:]]${realparam}[[:space:]] ]] ; do
#            realparam=$(( realparam + 1 ))
#          done
#	  paramlist=${paramlist}${sep}${realparam}
#	  param=$(( param + 1 ))
#	  realparam=$(( realparam + 1 ))
#	  sep="/"
#        done
#
#        cat > ${tmpf} <<EOF
#retrieve,
#class=rd,
#expver=xxxx,
#stream=enfo,
#date=20230713,
#time=0000,
#domain=g,
#type=pf,
#levtype=pl,
#levelist=${level}/to/$(( level + nlevels - 1 ))/by/1,
#step=0/to/$(( nsteps - 1 ))/by/1,
#param=${paramlist},
#number=${number}
#EOF
#
#        out=$(taskset -c $pin_proc $fdb_read $tmpf /dev/null --config=$tmp_dir/config.yaml)
#        #out=$(echo "taskset -c $pin_proc $fdb_read $tmpf /dev/null --config=$tmp_dir/config.yaml")
#
#      fi

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

