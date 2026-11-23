#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

archivos=(
    si_libro.scf.out
    si_ecut40.scf.out
    si_ecut50.scf.out
    si_ecut60.scf.out
    si_ecut70.scf.out
    si_ecut80.scf.out
)

command -v gnuplot >/dev/null || {
    echo "Error: no se encuentra gnuplot."
    exit 1
}

temporal=$(mktemp)
trap 'rm -f "$temporal"' EXIT

for archivo in "${archivos[@]}"; do

    if [[ ! -f "$archivo" ]]; then
        echo "Error: no existe $archivo"
        exit 1
    fi

    if ! grep -q 'convergence has been achieved' "$archivo" ||
       ! grep -q 'JOB DONE' "$archivo"; then
        echo "Error: revisar convergencia y finalizacion en $archivo"
        exit 1
    fi

    awk '
        /kinetic-energy cutoff/ {
            corte = $0
            sub(/^.*=/, "", corte)
            split(corte, partes)
            wfc = partes[1]
        }

        /charge density cutoff/ {
            corte = $0
            sub(/^.*=/, "", corte)
            split(corte, partes)
            rho = partes[1]
        }

        /^[[:space:]]*![[:space:]]+total energy/ {
            energia = $0
            sub(/^.*=/, "", energia)
            split(energia, partes)
            e = partes[1]
        }

        END {
            if (wfc == "" || rho == "" || e == "") {
                print "Error: faltan datos en " FILENAME > "/dev/stderr"
                exit 1
            }
            printf "%.6f %.6f %.10f\n", wfc, rho, e
        }
    ' "$archivo" >> "$temporal"

done

sort -n -k1,1 "$temporal" -o "$temporal"

if ! awk '
    {
        if (visto[$1]++) {
            print "Error: corte repetido de " $1 " Ry." > "/dev/stderr"
            error = 1
        }

        diferencia = $2 - 10*$1
        if (diferencia < 0) diferencia = -diferencia

        if (diferencia > 0.001) {
            print "Error: no se cumple ecutrho = 10*ecutwfc." > "/dev/stderr"
            error = 1
        }
    }
    END { exit error }
' "$temporal"; then
    exit 1
fi

{
    echo "# ecutwfc_Ry ecutrho_Ry energia_total_Ry"
    cat "$temporal"
} > convergencia_cortes.dat

gnuplot <<'GNUPLOT'
set encoding utf8
set terminal pngcairo size 1800,1200 font "Sans,20"
set output "convergencia_cortes.png"

set title "Convergencia de los cortes: silicio"
set xlabel "Energía de corte ecutwfc (Ry)"
set ylabel "Energía total de la celda (Ry)"
set format y "%.5f"
set xtics 10
set grid
set key top right
set border linewidth 1.5
set lmargin 13
set bmargin 4

plot "convergencia_cortes.dat" using 1:3 \
    with linespoints linewidth 2 pointtype 7 pointsize 1.3 \
    linecolor rgb "#17324D" \
    title "ecutrho = 10 × ecutwfc"

set terminal pdfcairo enhanced color font "Sans,12" size 7in,4.8in
set output "convergencia_cortes.pdf"
replot
unset output
GNUPLOT

echo "Archivos generados:"
echo "  convergencia_cortes.dat"
echo "  convergencia_cortes.png"
echo "  convergencia_cortes.pdf"
