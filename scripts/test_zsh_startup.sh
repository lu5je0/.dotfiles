#!/usr/bin/env bash

COUNT=10
times=()

echo "Testing zsh startup time ($COUNT runs)"
echo "--------------------------------------"

for i in $(seq 1 $COUNT); do
    start=$(date +%s%N)

    zsh -i -c exit

    end=$(date +%s%N)

    # 转换成毫秒
    duration_ms=$(( (end - start) / 1000000 ))
    times+=($duration_ms)

    printf "Run %2d: %d ms\n" "$i" "$duration_ms"
done

max=${times[0]}
min=${times[0]}
sum=0

for t in "${times[@]}"; do
    (( t > max )) && max=$t
    (( t < min )) && min=$t
    (( sum += t ))
done

avg=$(( sum / COUNT ))

echo "--------------------------------------"
echo "Max : ${max} ms"
echo "Min : ${min} ms"
echo "Avg : ${avg} ms"
