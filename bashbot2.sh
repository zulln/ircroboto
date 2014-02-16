#!/usr/bin/env bash

# Default values for things
nick=IrcRoboto22
name=kebab
channel=ircRobotoTestChannel
server=irc.freenode.net
port=6667
fileToTail=ircTail

readonly modulePath='modules'

# there seems to be a bug(?) in bash which makes it impossible to declare a 
# global array in an included script. This is needed in the IRC module
declare -A privMsg

import() {
    # @desc import a module. Which should be another bash script.
    # @param $1 is the script to import

    local module="$1"

    if [[ -f "$modulePath/$module" ]]; then
        . "$modulePath/$module"
    else
        output.red "Module $modulePath/$module does not exist"
        exit 1;  
    fi
}

import 'string.sh'
import 'irc.sh'
import 'output.sh'

function usage() {
    cat << EOF
Usage:
    $(basename $0) [OPTIONS...]

    Options:
        -s, --server $(string.underline SERVER)
                    IP or domain name of the IRC server
        
        -p, --port $(string.underline PORT)
                    Which port to connect to
        
        -c, --channel $(string.underline CHANNEL)
                    Name of the channel this bot should join
        
        -n, --nick $(string.underline NICK)
                    Nickname this bot sould use
        
        -r, --real-name $(string.underline REALNAME)
                    Real name this bot sould use
        
        -t, --tail-file
                    Tail a file and output the conetent to the channel
        
        -d, --debug
                    Print debugging messages
        
        -h, --help
                    Print this message

EOF
    exit 0
}>&2

TEMP=`getopt -o s:p:n:r:c:t::hd --long server:,port:,nick:,real-name:,channel:,tail-file::,help,debug \
     -n 'bashbot2.sh' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -s|--server) server=$2; shift 2 ;;
        -p|--port) port=$2; shift 2;;
        -n|--nick) nick=$2; shift 2;;
        -r|--real-name) name=$2; shift 2;;
        -c|--channel) channel=$2; shift 2;;
        -t|--tail-file) shouldTailFile=1; shift 2;;
        -d|--debug) debug=1; shift;;
        -h|--help) usage; shift;;
        --) shift; break;;
        *) echo "Parsing error!" ; exit 1;;
    esac
done

onExit() {
    # @desc Will send QUIT to IRC server, remove temporary tail file if there is any,
    # @desc kill forks and close the socket.

    kill 0
    irc.sendToServer 'QUIT :Shutting down'
    [[ $shouldTailFile ]] && rm -f ./$fileToTail
    exec 3<&-
    exec 3>&-
    [[ $debug ]] && output.debugMsg 'Exit caught. Cleaning up and closing connection.'
}

# run onExit when exiting/stopping the script
trap onExit EXIT

irc.connectToServer "$server" "$port"
irc.identify "$nick" "$name" "$channel"

# if -t is set, listen the file
[[ $shouldTailFile ]] && irc.listenToFile

# read every response from the server and handle it line by line
while read line; do
    # Line needs to be trimmed of spaces or it will be impossible to parse. 
    # This was a pain in the ass to find out. Try:
    # exec 3<>/dev/tcp/google.com/80; echo "GET /" >&3; while read line <&3; do echo "BEFORE $line AFTER"; done
    # to get a grip of wtf is happening otherwise.
    string.trim "$line"
    line="$STRING_RESULT"

    irc.getMsgType "$line"
    msgType="$IRC_RESULT"

    echo "$line"
    case "$msgType" in
        PING) irc.handlePing "$line";;
        PRIVMSG) irc.handlePrivMsg "$line";;
        MODE) irc.handleMode "$line";;
    esac
done <&3