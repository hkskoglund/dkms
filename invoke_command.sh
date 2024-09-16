#!/bin/bash

on_exit()
{
    local exitcode_on_exit=$?

    kill $(jobs -p >/dev/null) 2>/dev/null

    [[ $make_tarball_cmd_on_exit ]] && eval "$make_tarball_cmd_on_exit"
    [[ $load_tarball_cmd_on_exit ]] && eval "$load_tarball_cmd_on_exit"

    exit $exitcode_on_exit
}

trap on_exit EXIT

# Run a command that we may or may not want to be detailed about.
invoke_command()
{
    # $1 = command to be executed using eval.
    # $2 = Description of command to run
    # $3 = Redirect command output to this file
    # $4 = 'background' if you want to run the command asynchronously.
    local exitval=0
    local -r cmd=$([[ $3 ]] && echo "{ $1; } >> $3 2>&1" || echo "$1")

    [[ $verbose ]] && echo -e "$cmd" || echo -en "$2..."
    if [[ $4 = background && ! $verbose ]]; then
        local pid progresspid
        (eval "$cmd" >/dev/null 2>&1) & pid=$!
        {
            on_exit() {
                kill $(jobs -p) 2>/dev/null
                wait $(jobs -p) 2>/dev/null
            }
            trap on_exit EXIT
            while /bin/kill --signal 0 $pid > /dev/null 2>&1; do
                sleep 3 &
                wait $!
                echo -en "."
            done
        } & progresspid=$!
        wait $pid 2>/dev/null
        exitval=$?
        kill $progresspid 2>/dev/null
        wait $progresspid 2>/dev/null
    else
        eval "$cmd"; exitval=$?
    fi
    if (($exitval > 0)); then
        echo -en "(bad exit status: $exitval)"
        # Print the failing command without the clunky redirection
        [[ ! $verbose ]] && echo -en "\nFailed command:\n$1"
    else
        echo " done."
    fi
    return $exitval
}

# Run a command that we may or may not want to be detailed about.
invoke_command_v2()
{
    # $1 = command to be executed using eval.
    # $2 = Description of command to run
    # $3 = Redirect command output (including stderr) to this file
    # $4 = background, if you want print . each 3 seconds while command runs
    local cmd="$1"
    local cmd_description="$2"
    local cmd_output="$3"
    local cmd_mode="$4"
    local exitval=0
    local progresspid
    
    [[ $cmd_output ]] && cmd="{ $cmd; } >> $cmd_output 2>&1"

    [[ $verbose ]] && echo -e "$cmd" ||  echo -en "$cmd_description..."

    if [[ $cmd_mode == background && ! $verbose ]]; then

        if [[ $package_name != dkms*_test ]]; then  

            while true ; do sleep 3; printf "."; done &
            progresspid=$!
        
        fi
        
        [[ -z "$cmd_output" ]] && cmd="$cmd >/dev/null 2>&1"
        
    fi

    ( eval "$cmd" )
    exitval=$?

    [ -n "$progresspid" ] && kill "$progresspid" >/dev/null 2>&1
    
    if (( exitval > 0)); then
        echo -en "(bad exit status: $exitval)"
        # Print the failing command without the clunky redirection
        [[ ! $verbose ]] && echo -en "\nFailed command:\n$1"
    else
        echo " done."
    fi
    
    return "$exitval"
}

package_name=invoke_test
invoke_command_v2 "echo sleeping; sleep 6" "just sleeping" sleep.log background


