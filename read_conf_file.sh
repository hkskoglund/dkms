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
# $1 config file, $2 allowed dkms directives
{

    local  config_file="$1" prev_IFS="$IFS" allowed_dkms_directive conf_directive conf_directive_value directive directive_name directive_value 
    shift
    local allowed_dkms_directives="$*" invert_match

    # maintain backwards compability; does conf file contain anything other than =, #, or empty lines ? (conf file probably uses executable code to manipulate dkms_variables that must be sourced)
    # chatgpt was used to construct grep expression

    if invert_match=$(grep --extended-regexp --invert-match --max-count=1 \
                            '^[[:space:]]*$|^[[:space:]]*#|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*(\[[0-9]*\])?=' "$config_file"); then 
        
        echo >&2 "invert_match: $invert_match      running safe_source $config_file $allowed_dkms_directives "
        # shellcheck disable=SC2086
        safe_source "$config_file" $allowed_dkms_directives
        return $?

    fi

    while IFS="=#" read -r conf_directive conf_directive_value; do 

       #echo >&2 "reading conf_directive: $conf_directive conf_directive_value: $conf_directive_value"

        case "$conf_directive" in 

            "")
                # skip lines containing # (IFS splits on #)
                continue
                ;;

           DKMS_DIRECTIVE=*=*)

                # for DKMS_DIRECTIVE=directive=value
                # is this used? allows setting any variable

                # remove DKMS_DIRECTIVE=
                directive=${conf_directive#DKMS_DIRECTIVE=}
                directive_name=${directive%%=*}
                directive_value="${directive#*=}"
                eval "$directive_name=\"$directive_value\""

                ;;

            *)

                IFS=" "

                # filter allowed directives

                for allowed_dkms_directive in $allowed_dkms_directives; do 

                    if [ "$conf_directive" = "$allowed_dkms_directive" ] || [[ $conf_directive =~ ^$allowed_dkms_directive\[[0-9]+\]$ ]]; then  
                    
                            eval "$conf_directive=$conf_directive_value"
                    
                    fi

                done

                ;;

        esac

    done < "$config_file"
    
    IFS="$prev_IFS"

    [[ ${#REMAKE_INITRD[@]} -gt 0  ]]               && deprecated "REMAKE_INITRD ($config_file)"
    [[ ${#MODULES_CONF[@]} -gt 0 ]]                 && deprecated "MODULES_CONF ($config_file)"
    [[ ${#MODULES_CONF_OBSOLETES[@]} -gt 0 ]]       && deprecated "MODULES_CONF_OBSOLETES ($config_file)"
    [[ ${#MODULES_CONF_ALIAS_TYPE[@]} -gt 0 ]]      && deprecated "MODULES_CONF_ALIAS_TYPE ($config_file)"
    [[ ${#MODULES_CONF_OBSOLETE_ONLY[@]} -gt 0 ]]   && deprecated "MODULES_CONF_OBSOLETE_ONLY ($config_file)"
}

print_conf()
{
    # shellcheck disable=SC2034
    local f=$1 directive_value  directive i allowed_dkms_directive_size
    shift
    #echo  >&2 "print_conf file: $f"

    for allowed_dkms_directive in "$@"; do

        # number of array elements for config variable
        eval allowed_dkms_directive_size=\$"{#${allowed_dkms_directive}[@]}"

        if [ "$allowed_dkms_directive_size" -eq 0 ]; then 

            continue
        
        fi

        i=0

        while [ $i -lt "$allowed_dkms_directive_size" ]; do 

            directive="${allowed_dkms_directive}[$i]"
            eval directive_val=\$"{$directive}"
            i=$(( i + 1 ))
            # shellcheck disable=SC2154
            echo "$directive=$directive_val"
        
        done

    done
}

clean_conf()
{
    local allowed_dkms_directive
    for allowed_dkms_directive in $dkms_conf_variables; do
        unset "$allowed_dkms_directive"
    done
}

readonly dkms_conf_variables="CLEAN PACKAGE_NAME
   PACKAGE_VERSION POST_ADD POST_BUILD POST_INSTALL POST_REMOVE PRE_BUILD
   PRE_INSTALL BUILD_DEPENDS BUILD_EXCLUSIVE_ARCH BUILD_EXCLUSIVE_CONFIG
   BUILD_EXCLUSIVE_KERNEL BUILD_EXCLUSIVE_KERNEL_MIN BUILD_EXCLUSIVE_KERNEL_MAX
   build_exclude OBSOLETE_BY MAKE MAKE_MATCH
   PATCH PATCH_MATCH patch_array BUILT_MODULE_NAME
   built_module_name BUILT_MODULE_LOCATION built_module_location
   DEST_MODULE_NAME dest_module_name
   DEST_MODULE_LOCATION dest_module_location
   STRIP strip AUTOINSTALL NO_WEAK_MODULES
   SIGN_FILE MOK_SIGNING_KEY MOK_CERTIFICATE

   REMAKE_INITRD MODULES_CONF MODULES_CONF_OBSOLETES
   MODULES_CONF_ALIAS_TYPE MODULES_CONF_OBSOLETE_ONLY"


case "$1" in

  "safe_source" | "read_conf_file")

        :
        ;;

    *) echo >&2 "Usage: ./read_conf_file.sh safe_source | read_conf_file [TESTDIR]"
       exit 1
       ;;

esac

test_file=$(mktemp)
# relative to dkms directory
test_dir=${2:-"./test"}
if [ "$test_dir" != "./test" ]; then 
    maxdepth=1
else
   maxdepth=5
fi

if find "$test_dir" -maxdepth $maxdepth -name "*.conf" >"$test_file"; then 

   :

else
  
   exitcode=$?
   echo >&2 "find $test_dir -name *.conf failed, exitcode: $exitcode"
   exit $exitcode

fi

# shellcheck disable=SC2086

while read -r file;  do 

    #cat "$file"  
    "$1" "$file" $dkms_conf_variables
    print_conf "$file" $dkms_conf_variables
    echo
    clean_conf

done < "$test_file"

rm "$test_file"


