### Default fdb-hammer mode with pre-population, no reader staggering nor transposed read pattern

# populate FDB
./fdb-hammer.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies"

# run contending writers and readers
./fdb-hammer.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

./fdb-hammer.sh read --nodelist hostname[005-008] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

wait



### ITT fdb-hammer mode without pre-population, with reader staggering and transposed read pattern

# run contending writers and readers
./fdb-hammer.sh write --itt \
    --nodelist hostname[001-004] --ppn 10 \
    --nmembers default --nsteps 100 --nlevels 100 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

./fdb-hammer.sh read --itt \
    --nodelist-read hostname[005-008] --ppn-read 10 --poll-period 1 \
    --nodelist hostname[001-004] --ppn 10 \
    --nmembers default --nsteps 100 --nlevels 100 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

wait
