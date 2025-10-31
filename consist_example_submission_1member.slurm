#!/bin/bash --login
#SBATCH -p par
#SBATCH -J fdb-benchmark-1member
#SBATCH -o fdb-benchmark-1member-%j.out
#SBATCH -N 9
#SBATCH --ntasks-per-node=128
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
##SBATCH --time=02:30:00
#SBATCH --time=00:45:00

# (C) Copyright 1996- ECMWF.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation nor
# does it submit to any jurisdiction.

pwd
printenv | fgrep SLURM

cd $SLURM_SUBMIT_DIR
pwd

set -eux

nodes=$SLURM_JOB_NUM_NODES
jobid=$SLURM_JOB_ID
jobname=$SLURM_JOB_NAME

writeppn=${1:-16}
readppn=${2:-32}
members=${3:-1}
wnpm=${4:-3}
rnpm=${5:-2}
readersinflight=${6:-3}
fdb_root=${7:-$WORKDIR/fdb_root_syim}

wanted_readers=$(( $readersinflight * $rnpm ))

if [ $wnpm -eq 0 ] ; then
   writernodes=$(( $nodes - $wanted_readers ))
else
   writernodes=$(($members * $wnpm))
fi

build_root=/tmp/$USER/fdb-hammer-parallel
artifact_dir=$SCRATCH/fdb-hammer-parallel/artifacts
write_file=write_${jobname}-${jobid}.out
read_file=read_${jobname}-${jobid}.out

./setup.sh \
    --root $build_root \
    --backend lustre \
    --fdb-root $fdb_root

ALL=$SLURM_JOB_NODELIST

# This is needed on ECMWF systems to get the correct names in nodeset
# but will be different on different systems
ALL=$(nodeset --output-format '%s.bullx' -f $ALL)

ONE=$(nodeset --slice 1 -f $ALL)

# Select the required number of writer nodes at random from the available nodes
WRITERS=$(nodeset -f --pick=$writernodes "$ALL")
# Assign the rest of the nodes to readers
READERS=$(nodeset -f "$ALL" -x "$WRITERS")

# If there are more available nodes for readers than are required 
# then use the pick command again to make READERS even
READERS=$(nodeset -f --pick=$wanted_readers "$READERS")

# Clean up any previous failed runs
rm -rf ${fdb_root}/rd*

# Initial write to set up the binaries
./fdb-benchmark.sh write \
    --nodelist $ONE --ppn 1 --field-size 17.37MiB \
    --nmembers default --nsteps 10 --nlevels 1 --nparams 1 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --artifact-dir-is-shared \
    --install --verbose

# Re-clean to ensure no leftovers
rm -rf ${fdb_root}/rd*

# Set up the main benchmark args
benchmark_args="--nodelist $WRITERS --ppn $writeppn --field-size 17.37MiB \
    --nodelist-read $READERS --ppn-read $readppn --read-nodes-per-step $rnpm \
    --nmembers $members --nsteps 90 --nlevels 120 --nparams 6 \
    --root $build_root --config $build_root/config.yaml.in \
    --artifact-dir $artifact_dir --no-itt --full-check --no-randomise-data --no-prelist"

echo "STARTING RUNS at $(date)"

./fdb-benchmark.sh write \
    $benchmark_args \
    > $write_file < /dev/null &

# Time to wait before launching readers
# Consistency checker requires more writes to have finished so have longer delay
# 16 seconds per member to start up + 10 second step windoe + 200 seconds margin
sleeptime=$((16 * $members + 10 + 200 ))  

sleep $sleeptime

./fdb-benchmark.sh read \
    $benchmark_args \
    > $read_file < /dev/null &

wait

echo "===== WRITE OUTCOME ====="
tail -n 9 $write_file
echo "===== READ OUTCOME ====="
tail -n 9 $read_file
echo "===== FDB SIZE ====="
du -h -s $fdb_root
echo "ACTUAL SIZE OF FDB is $(du -s $fdb_root)"
echo "===================="

# Clean up after ourselves
rm -rf ${fdb_root}/rd*

exit $?
