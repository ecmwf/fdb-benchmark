# (C) Copyright 1996- ECMWF.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation nor
# does it submit to any jurisdiction.

### Default fdb-hammer mode with pre-population, no reader staggering nor transposed read pattern

# populate FDB
./fdb-benchmark.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies"

# run contending writers and readers
./fdb-benchmark.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

./fdb-benchmark.sh read --nodelist hostname[005-008] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

wait



### ITT fdb-hammer mode without pre-population, with reader staggering and transposed read pattern

# run contending writers and readers
./fdb-benchmark.sh write --itt \
    --nodelist hostname[001-004] --ppn 10 \
    --nmembers default --nsteps 100 --nlevels 100 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

./fdb-benchmark.sh read --itt \
    --nodelist-read hostname[005-008] --ppn-read 10 --poll-period 1 \
    --nodelist hostname[001-004] --ppn 10 \
    --nmembers default --nsteps 100 --nlevels 100 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

wait
