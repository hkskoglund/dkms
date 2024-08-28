#!/bin/bash

die_is_fatal="yes"

error() (
    exec >&2
    echo -n $"Error! "
    for s in "$@"; do echo "$s"; done
)

# Print an error message and die with the passed error code.
die() {
    # $1 = error code to return with
    # rest = strings to print before we exit.
    ret=$1
    shift
    error "$@"
    [[ $die_is_fatal = yes ]] && exit "$ret" || return "$ret"
}

#shellcheck disable=SC2120 disable=SC2154
mktemp_or_die() {
    local t
    t=$(mktemp "$@") && echo "$t" && return
    [[ $* = *-d* ]] && die 1 $"Unable to make temporary directory"
    die 1 "Unable to make temporary file."
}

deprecated() (
    exec >&2
    echo -n $"Deprecated feature: "
    for s in "$@"; do echo "$s"; done
)

#shellcheck disable=SC1090 disable=SC2086 disable=SC1083 disable=SC1087 disable=SC2119
safe_source() {
    # $1 = file to source
    # $@ = environment variables to echo out
    local to_source_file="$1"; shift
    declare -a -r export_envs=("$@")
    local tmpfile
    tmpfile=$(mktemp_or_die)
    ( exec >"$tmpfile"
    . "$to_source_file" >/dev/null
    # This is really ugly, but a neat hack
    # Remember, in bash 2.0 and greater all variables are really arrays.
    for _export_env in "${export_envs[@]}"; do
        for _i in $(eval echo \${!$_export_env[@]}); do
            eval echo '$_export_env[$_i]=\"${'$_export_env'[$_i]}\"'
        done
    done

    # handle DKMS_DIRECTIVE stuff specially.
    for directive in $(set | grep ^DKMS_DIRECTIVE | cut -d = -f 2-3); do
        directive_name=${directive%%=*}
        directive_value=${directive#*=}
        echo "$directive_name=\"$directive_value\""
    done
    )
    . "$tmpfile"
    rm "$tmpfile"

    (( ${#REMAKE_INITRD[@]} )) && deprecated "REMAKE_INITRD ($to_source_file)"
    (( ${#MODULES_CONF[@]} )) && deprecated "MODULES_CONF ($to_source_file)"
    (( ${#MODULES_CONF_OBSOLETES[@]} )) && deprecated "MODULES_CONF_OBSOLETES ($to_source_file)"
    (( ${#MODULES_CONF_ALIAS_TYPE[@]} )) && deprecated "MODULES_CONF_ALIAS_TYPE ($to_source_file)"
    (( ${#MODULES_CONF_OBSOLETE_ONLY[@]} )) && deprecated "MODULES_CONF_OBSOLETE_ONLY ($to_source_file)"
}

read_conf_file()
{
    local  to_source_file="$1" prev_IFS="$IFS" dkms_var k v i
    shift
    local dkms_vars="$*"

    while IFS="=#" read -r k v; do 

        # skip lines containing # (IFS splits on #)

        if [ -z "$k" ]; then

            continue

        fi

        IFS=" "

        for dkms_var in $dkms_vars; do 

            if [ "$k" = "$dkms_var" ] || [[ $k =~ ^$dkms_var\[[0-9]+\]$ ]]; then  
            
                    eval "$k=$v"
            
            fi

        done

    done < "$to_source_file"
    
    IFS="$prev_IFS"

    # handle DKMS_DIRECTIVE stuff specially. what is the syntax? DKMS_DIRECTIVE_module=1.2.3?
    for directive in $(set | grep ^DKMS_DIRECTIVE | cut -d = -f 2-3); do
        directive_name=${directive%%=*}
        directive_value=${directive#*=}
        echo "$directive_name=\"$directive_value\""
    done

    [[ ${#REMAKE_INITRD[@]} -gt 0  ]]               && deprecated "REMAKE_INITRD ($to_source_file)"
    [[ ${#MODULES_CONF[@]} -gt 0 ]]                 && deprecated "MODULES_CONF ($to_source_file)"
    [[ ${#MODULES_CONF_OBSOLETES[@]} -gt 0 ]]       && deprecated "MODULES_CONF_OBSOLETES ($to_source_file)"
    [[ ${#MODULES_CONF_ALIAS_TYPE[@]} -gt 0 ]]      && deprecated "MODULES_CONF_ALIAS_TYPE ($to_source_file)"
    [[ ${#MODULES_CONF_OBSOLETE_ONLY[@]} -gt 0 ]]   && deprecated "MODULES_CONF_OBSOLETE_ONLY ($to_source_file)"
}

print_conf()
{
    local f=$1 v value i k count
    shift
    echo "file: $f"

    for dkms_var in "$@"; do

        # number of array elements for config variable
        eval count=\$"{#${dkms_var}[@]}"

        if [ "$count" -eq 0 ]; then 

            continue
        
        fi

        i=0

        while [ $i -lt "$count" ]; do 

             k="${dkms_var}[$i]"
             eval value=\$"{$k}"
             i=$(( i + 1 ))
             echo "$k=$value"
        
        done

    done
}

clean_conf()
{
    local dkms_var
    for dkms_var in $dkms_conf_variables; do
        unset "$dkms_var"
    done
}

readonly dkms_conf_variables="CLEAN PACKAGE_NAME
   PACKAGE_VERSION POST_ADD POST_BUILD POST_INSTALL POST_REMOVE PRE_BUILD
   PRE_INSTALL BUILD_DEPENDS BUILD_EXCLUSIVE_ARCH  
 BUILD_EXCLUSIVE_CONFIG
   BUILD_EXCLUSIVE_KERNEL BUILD_EXCLUSIVE_KERNEL_MIN BUILD_EXCLUSIVE_KERNEL_MAX
   build_exclude OBSOLETE_BY MAKE MAKE_MATCH
   PATCH PATCH_MATCH patch_array BUILT_MODULE_NAME
   built_module_name BUILT_MODULE_LOCATION built_module_location
   DEST_MODULE_NAME dest_module_name 

   DEST_MODULE_LOCATION dest_module_name
   STRIP strip AUTOINSTALL NO_WEAK_MODULES
   SIGN_FILE MOK_SIGNING_KEY MOK_CERTIFICATE

   REMAKE_INITRD MODULES_CONF MODULES_CONF_OBSOLETES
   MODULES_CONF_ALIAS_TYPE MODULES_CONF_OBSOLETE_ONLY"


case "$1" in

  "safe_source" | "read_conf_file")

        :
        ;;

    *) echo >&2 "Usage: ./safe_source.sh safe_source | read_conf_file"
       exit 1
       ;;

esac

test_file=$(mktemp)
# relative to dkms directory
test_dir="./test"

if find "$test_dir" -name dkms.conf >"$test_file"; then 

   :

else
  
   exitcode=$?
   echo >&2 "find ./test -name dkms.conf failed, exitcode: $exitcode"
   exit $exitcode

fi

# shellcheck disable=SC2086

while read -r file;  do 

    cat "$file"  
    "$1" "$file" $dkms_conf_variables
    print_conf "$file" $dkms_conf_variables
    echo
    clean_conf

done < "$test_file"

rm "$test_file"


