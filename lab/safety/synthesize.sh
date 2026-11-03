#!/bin/sh
# lab/safety/synthesize.sh -- re-run the E3 v0 supervisor synthesis and the explicit state-space explorations.
#
# Needs Eclipse ESCET (tested with v13.0, cifdatasynth/cifexplorer 13.0.0.v20260930-072049). Point ESCET_BIN at its bin/
# directory. Writes into lab/safety/synthesis/:
#   <model>.sup.cif           the controlled system (plants + synthesized supervisor), default guard simplifications
#   <model>.synth.log         cifdatasynth's console output (controlled-system state count, warnings)
#   <model>.statespace.cif    cifexplorer's explicit state space of that controlled system
#   post_cell_plant.statespace.cif   the uncontrolled plant's state space
#   post_cell.input.statespace.cif   post_cell.cif explored with its requirements read as plant invariants, i.e. the
#                                    plant restricted by the requirements and nothing else (to compare with synthesis)
# Then run `python3 -I analyze_synthesis.py` to regenerate synthesis/summary.json and synthesis/SUMMARY.md.
set -eu

ESCET_BIN="${ESCET_BIN:-/home/user/escet/v13.0/eclipse-escet-v13.0/bin}"
cd "$(dirname "$0")"
mkdir -p synthesis

# The container sets JAVA_TOOL_OPTIONS, which makes the JVM print a "Picked up ..." line; it is not ESCET's output.
quiet() { grep -v '^Picked up JAVA_TOOL_OPTIONS' || true; }

for m in post_cell post_cell_pre0792 post_cell_strict_r2; do
  "$ESCET_BIN/cifdatasynth" --gui=off --forward-reach=yes --stats=ctrl-sys-states \
      -o "synthesis/$m.sup.cif" "models/$m.cif" 2>&1 | quiet > "synthesis/$m.synth.log"
  "$ESCET_BIN/cifexplorer" --gui=off --progress=off \
      -o "synthesis/$m.statespace.cif" "synthesis/$m.sup.cif" 2>&1 | quiet > "synthesis/$m.explore.log"
done
"$ESCET_BIN/cifexplorer" --gui=off --progress=off \
    -o synthesis/post_cell_plant.statespace.cif models/post_cell_plant.cif 2>&1 | quiet > synthesis/post_cell_plant.explore.log
"$ESCET_BIN/cifexplorer" --gui=off --progress=off \
    -o synthesis/post_cell.input.statespace.cif models/post_cell.cif 2>&1 | quiet > synthesis/post_cell.input.explore.log

grep -H 'Controlled system' synthesis/*.synth.log
grep -H 'Number of' synthesis/*.explore.log
