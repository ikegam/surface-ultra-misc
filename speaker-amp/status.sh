#!/bin/bash
# Show whether both amps run the DSP FW and the tuning, and the amp gain UCM set.
card=$(grep -l mt8901 /proc/asound/card*/id 2>/dev/null | head -1 | sed 's#.*/card\([0-9]*\)/id#\1#')
[ -n "$card" ] || { echo "no mt8901 sound card"; exit 1; }
for n in 1 2; do
    get() { amixer -c "$card" cget name="rt1320-$n $1" 2>/dev/null | sed -n 's/^ *: values=//p'; }
    echo "rt1320-$n: DSP FW $(get 'DSP FW Update'), tuning $(get 'RAE Update'), gain $(get 'FU21 Playback Volume') (87 = 0 dB)"
done
