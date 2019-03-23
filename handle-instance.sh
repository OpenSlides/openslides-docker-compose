# A script for handling different instance-related things

#!/bin/bash

OPTIND=1
verbose=0
function=""
foldername=${PWD##*/}
instancename="${foldername//.}"

function quit {
    exit
}

function warn_insecure_login {
    cat << EOF
WARNING:
 You have not provided a secure admin password.  If you choose to proceed, the
 default password "admin" will be used!

 See ./secrets/adminsecret.env.example on how to set it.
EOF
read -p 'Proceed with insecure password? [y/N] ' PROCEED
case $PROCEED in
    y) return;;
    *) exit 0;;
esac
}

function run {
    [[ -f ./secrets/adminsecret.env ]] || warn_insecure_login
    echo "building the instance"
    docker-compose build
    echo "starting the instance as deamon"
    docker-compose up -d
}

function down {
    echo "shutting down instance"
    docker-compose down
}

function rm {
    down
    echo "removing containers"
    docker-compose rm
    volumes=$(docker volume ls -q | grep $instancename)
    if [[ -n "$volumes" ]]; then
        echo "deleting volumes: "
        if [ $verbose == 1 ]; then
            echo "$volumes"
        fi;
        docker volume rm $volumes
    fi
}

function dockercleanup {
    echo "removing stopped containers"
    docker rm $(docker ps -aq)
    echo "prune images"
    docker image prune
}

function update {
    if [ $verbose == 1 ]; then
        echo "setting commit to $commit"
    fi;
    sed -i "s/GIT_CHECKOUT: .*$/GIT_CHECKOUT: $commit/" docker-compose.yml
    docker-compose build
    docker-compose scale server=0 client=0
    volumename="$instancename\_staticfiles"
    echo "removing staticfiles volume:"
    volume=$(docker volume ls -q | grep $volumename)
    docker volume rm $volume
    docker-compose scale server=1 client=1
}

function flushredis {
    docker-compose scale server=0
    echo "flushing redis"
    rediscontainer=$(docker-compose ps | grep redis | awk '{print $1}')
    docker exec -it $rediscontainer redis-cli flushall
    docker-compose scale server=1
}

function startfunction {
    if [ $1 == "run" ];then
        run
    elif [ $1 == "down" ];then
        down
    elif [ $1 == "rm" ];then
        rm
    elif [ $1 == "docker-cleanup" ];then
        dockercleanup
    elif [ $1 == "update" ]; then
        if [[ $commit = *[!\ ]* ]]; then
            update
        else
            echo "You didn't provide a commit sha with \"-c\""
            quit
        fi;
    elif [ $1 == "flushredis" ]; then
        flushredis
    else
        echo "Command \"$1\" not recognized"
        printhelp
        quit
    fi
}

function printhelp {
    echo "This script can be used as a wrapper for different functions"
    echo "To run the different functions, you use the paramenter \"-f:\""
    echo "  run: let the instance build and run as deamon"
    echo "  down: let the instance shut down completely"
    echo "  rm: shut down the instance and remove all data"
    echo "  update: updates the instance to the given commit \"-c\""
    echo "  flushredis: flushes the redis cache and restarts server"
    echo "The command prefacing docker, will not affect the instance, but docker itself"
    echo "  docker-cleanup: cleans up all stopped containers and unusued images"
}

# Parse the arguments in first place
while getopts "h?vf:c:" opt; do
    case "$opt" in
    h|\?)
        printhelp
        quit
        ;;
    v)  verbose=1
        ;;
    f)  function=$OPTARG
        ;;
    c)  commit=$OPTARG
        ;;
    esac
done
shift $((OPTIND-1))
if [[ $function = *[!\ ]* ]]; then
    startfunction $function
else
    echo "You didn't provide a command sha with \"-f\""
    printhelp
    quit
fi;
exit
