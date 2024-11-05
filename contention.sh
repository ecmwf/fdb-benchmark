# populate FDB
./fdb-hammer.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies"

# run contending writers and readers
./fdb-hammer.sh write --nodelist hostname[001-004] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

./fdb-hammer.sh read --nodelist hostname[005-008] --ppn 16 --nsteps 100 --nlevels 10 --nparams 10 \
    | grep -e "Total read" -e "Total write" -e "failures" -e "inconsistencies" &

wait
