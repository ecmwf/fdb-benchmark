```
# where the benchmark source will be cloned and the binaries installed
export SCRATCH=$SCRATCH

# fast file system where the benchmark will be built before installing
build_root=/tmp/fdb-benchmark_$USER

# file system where FDB will store the data
fdb_root=/hpc/file/system/fdb_root

# directory (shared or not) in the compute nodes where the benchmark and 
# artifacts will be installed
artifact_dir=$SCRATCH/fdb-benchmark/artifacts

# --- clone fdb-benchmark

cd $SCRATCH

mkdir git
cd git
git clone https://github.com/ecmwf/fdb-benchmark.git
cd fdb-benchmark
git checkout feature/itt

# --- build binaries

mkdir -p $artifact_dir
mkdir -p $fdb_root
mkdir -p $TMPDIR

./setup.sh \
    --root $build_root \
    --backend lustre \
    --fdb-root $fdb_root

# --- allocate compute nodes

NWRITERS=2
NREADERS=2
NALL=$(( NWRITERS + NREADERS ))
salloc -N $NALL -n $NALL --exclusive --no-shell

ALL=<INSERT ALLOCATED NODELIST HERE>
ALL=$(nodeset --output-format '%s.bullx' -f $ALL)

ONE=$(nodeset --slice 1 -f $ALL)
WRITERS=$(nodeset --split 2 -f $ALL | head -n 1)
READERS=$(nodeset --split 2 -f $ALL | tail -n 1)

# --- preliminary single-process small run to install binaries in compute nodes
#     and sanity check
# NOTE: if --install and --artifact-dir-is-shared, and --nodelist has more than one 
# node, all nodes other than the first may fail due to libraries not being found

./fdb-hammer.sh write \
    --nodelist $ONE --ppn 1 \
    --nmembers default --nsteps 10 --nlevels 1 --nparams 1 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --artifact-dir-is-shared \
    --install --verbose

./fdb-hammer.sh read \
    --nodelist $ONE --ppn 1 \
    --nmembers default --nsteps 10 --nlevels 1 --nparams 1 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --artifact-dir-is-shared \
    --verbose

rm -rf ${fdb_root?}/rd:xxxx:enfo:20230713:0000:g:*

# --- run contending writers and readers

./fdb-hammer.sh write \
    --nodelist $WRITERS --ppn 23 \
    --nodelist-read $READERS --ppn-read 13 \
    --nmembers 2 --nsteps 4 \
    --nlevels 120 --nparams 17 \
    --itt --step-window 10 --random-delay 100 --poll-period 10 \
    --poll-max-attempts 200 --prelist \
    --read-nodes-per-step 2 --read-step-window 10 --read-random-delay 0 \
    --barrier-port 7777 --barrier-max-wait 100 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --artifact-dir-is-shared \
    > write.out < /dev/null &

sleep 20

./fdb-hammer.sh read \
    --nodelist $WRITERS --ppn 23 \
    --nodelist-read $READERS --ppn-read 13 \
    --nmembers 2 --nsteps 4 \
    --nlevels 120 --nparams 17 \
    --itt --step-window 10 --random-delay 100 --poll-period 10 \
    --poll-max-attempts 200 --prelist \
    --read-nodes-per-step 2 --read-step-window 10 --read-random-delay 0 \
    --barrier-port 7777 --barrier-max-wait 100 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --artifact-dir-is-shared \
    > read.out < /dev/null &

wait

rm -rf ${fdb_root?}/rd:xxxx:enfo:20230713:0000:g:*

# --- checklist after a benchmark run hangs or terminates abruptly

# list active writer/reader processes on the compute nodes
clush -w $ALL "ps -aux | grep '^$USER ' | wc -l"
# if any, kill as follows
#clush -w $ALL "ps -aux | grep 'fdb-hammer ' | awk '{print \$2}' | xargs -I{} kill {}"
#clush -w $ALL "ps -aux | grep 'bash -s ' | awk '{print \$2}' | xargs -I{} kill {}"
#clush -w $ALL "ps -aux | grep 'timeout 500' | awk '{print \$2}' | xargs -I{} kill {}"

# list active orchestrating processes on the login/orchestrating node
ps -aux | grep fdb-hammer.sh
# if any, kill as follows
#ps -aux | grep fdb-hammer.sh | awk '{print $2}' | xargs -I{} kill {}

# list leftover lock files in the compute nodes
clush -w $ALL 'ls /tmp/$USER/'
# if any, remove as follows
#clush -w $ALL 'rm -rf /tmp/$USER/fdb-hammer*'

# --- other cleanup tasks, usually required if needing to start from scratch,
#     rerun with manipulated artifacts, or recompile the benchmark.
#     Sorted from less to more destructive.

# removes the FDB data directory
#rm -rf ${fdb_root?}

# removes the artifacts installed by setup.sh
#rm -rf ${SCRATCH?}/fdb-benchmark

# removes the benchmark build
#rm -rf ${build_root?}

# removes the benchmark repository
#rm -rf ${SCRATCH?}/git/fdb-benchmark
```
