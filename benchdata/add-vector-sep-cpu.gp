
set ylab "Execution time (�s)
set xlab "Vector size"

set key off

plot 'add-vector-sep-cpu.dat' using 1:($2/1000)