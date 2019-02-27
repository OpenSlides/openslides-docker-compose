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

function run {
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
    echo "deleting volumes: "
    if [ $verbose == 1 ]; then
        echo "$volumes"
    fi;
    docker volume rm $volumes
}

function dockercleanup {
    echo "removing stopped containers"
    docker rm $(docker ps -aq)
    echo "removing unused images"
    docker rmi $(docker images | grep "^<none>" | awk "{print $3}")
    
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
    echo "The command prefacing docker, will not affect the instance, but docker itself"
    echo "  docker-cleanup: cleans up all stopped containers and unusued images"
}

# Parse the arguments in first place
while getopts "h?vf:" opt; do
    case "$opt" in
    h|\?)
        printhelp
        quit
        ;;
    v)  verbose=1
        ;;
    f)  function=$OPTARG
        ;;
    esac
done
shift $((OPTIND-1))
startfunction $function
exit
