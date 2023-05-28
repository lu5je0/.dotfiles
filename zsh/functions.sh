# get public IP
function q-myip
{
  if command -v curl &> /dev/null; then
    curl ifconfig.co
  elif command -v wget &> /dev/null; then
    wget -qO- ifconfig.co
  fi
}

function q-ip-location
{
  curl cip.cc/$1
}

function q-ask
{
  echo -n $1$' (y/n):'
  read choice
  case $choice in
    Y | y)
      return 0
  esac
  return -1
}

# function ta
# {
#   tmux attach -t $1 || (q-ask 'create new session?' && tmux new-session -s $1)
# }

function q-zsh-speed-test
{
  for i ({1..10}) { time zsh -i -c 'exit' }
  }

  function q-kill-by-name
  {
    if [[ ! -n $1 ]]; then
      echo "you have not input a keyword!"
    fi
    ps -ef | grep -E $1 | grep -v grep
    echo "\nThe above process will be kill(y/n)"
    read kill_or_not
    case $kill_or_not in
      Y | y)
        ps -ef | grep -E $1 | grep -v grep | awk '{print $2}' | xargs kill
    esac
  }

  function q-color
  {
    awk 'BEGIN{
    s="/\\/\\/\\/\\/\\"; s=s s s s s s s s;
    for (colnum = 0; colnum<77; colnum++) {
      r = 255-(colnum*255/76);
      g = (colnum*510/76);
      b = (colnum*255/76);
      if (g>255) g = 510-g;
        printf "\033[48;2;%d;%d;%dm", r,g,b;
        printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b;
        printf "%s\033[0m", substr(s,colnum+1,1);
      }
      printf "\n";
    }'
  }

# Easy extract
function q-extract
{
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar -xvjf $1    ;;
      *.tar.gz)    tar -xvzf $1    ;;
      *.tar.xz)    tar -xvJf $1    ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       rar x $1       ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar -xvf $1     ;;
      *.tbz2)      tar -xvjf $1    ;;
      *.tgz)       tar -xvzf $1    ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "don't know how to extract '$1'..." ;;
    esac
  else
    echo "'$1' is not a valid file!"
  fi
}

# easy compress - archive wrapper
function q-compress
{
  if [ -n "$1" ] ; then
    FILE=$1
    case $FILE in
      *.tar) shift && tar -cf $FILE $* ;;
      *.tar.bz2) shift && tar -cjf $FILE $* ;;
      *.tar.xz) shift && tar -cJf $FILE $* ;;
      *.tar.gz) shift && tar -czf $FILE $* ;;
      *.tgz) shift && tar -czf $FILE $* ;;
      *.zip) shift && zip $FILE $* ;;
      *.7z) shift && 7za a $FILE $* ;;
      *.rar) shift && rar $FILE $* ;;
    esac
  else
    echo "usage: q-compress <foo.tar.gz> ./foo ./bar"
  fi
}

# function for pyvenv
function cd() {
    builtin cd "$@"

    if [[ -z "$VIRTUAL_ENV" ]] ; then
        ## If env folder is found then activate the vitualenv
        if [[ -d ./.env ]] ; then
            source ./.env/bin/activate
        fi
    else
        ## check the current folder belong to earlier VIRTUAL_ENV folder
        # if yes then do nothing
        # else deactivate
        parentdir="$(dirname "$VIRTUAL_ENV")"
        if [[ "$PWD"/ != "$parentdir"/* ]] ; then
            deactivate
        fi
    fi
}
