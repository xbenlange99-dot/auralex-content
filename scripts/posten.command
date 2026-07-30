#!/usr/bin/env bash
# Auralex-Reels JETZT posten (manueller Trigger, ersetzt den 15-Min-Dauerjob).
# Doppelklick im Finder oder Aufruf im Terminal. Ein Lauf, dann Ende.
export AURALEX_BLOG_ID="6521208"
/Users/bl/Code/auralex-content/scripts/tick.sh
echo
echo "Fertig. Log: /Users/bl/Code/auralex-content/out/tick.log"
read -r -p "Enter zum Schliessen..."
