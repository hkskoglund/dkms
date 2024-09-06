#!/bin/bash

test_func()
{
    local test_func1="$1"
    local output_file1="result_$test_func1.txt"
    echo "Testing $test_func1 function"
    time ./read_conf_file.sh "$test_func1" > "$output_file1"
    echo
}

test_func safe_source
test_func read_conf_file_v2

echo 
diff --report-identical-files  "result_safe_source.txt" "result_read_conf_file_v2.txt"
