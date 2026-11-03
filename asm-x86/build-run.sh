#!/bin/bash

PS3="Select a dir: "

dirs=$(ls)

select dir in $dirs;
do
    chosen_dir=$dir
    if [[ "$chosen_dir" ]] ; then
        echo "Chosen dir: " $chosen_dir
        break
    fi
done

cd $chosen_dir

mkdir -p build

echo "Compiling using GAS"
as main.s -o build/main.o
exit_code="$?"
if [[ $exit_code != 0 ]]; then
    echo "Did not compile"
    exit $exit_code
fi

echo "Linking using ld"
ld build/main.o -o build/main
exit_code="$?"
if [[ $exit_code != 0 ]]; then
    echo "Did not link"
    exit $exit_code
fi

echo ""
echo "[[ Running main ]]"
echo ""

build/main
echo "Exited with: $?"