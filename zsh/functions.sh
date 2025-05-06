function gcof {
  local branch=$(git for-each-ref --sort=-committerdate refs/heads/ --format="%(refname:short)" | fzf --preview "git log --date=format:\"%Y-%m-%d %H:%M:%S\" --max-count=30 {}")
  [ -z $branch ] && return
  git checkout $branch
}

function q-ip {
  local show_ip_only=0
  local show_help=0
  local target=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      show_help=1
      shift
      ;;
    -i | --ip)
      show_ip_only=1
      shift
      ;;
    *)
      target="$1"
      shift
      ;;
    esac
  done

  if [[ $show_help -eq 1 ]]; then
    echo "Usage: q-ip [options] [IP or domain]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -i, --ip       Only output the IP address"
    echo
    echo "Examples:"
    echo "  q-ip               # Info for your own IP"
    echo "  q-ip 8.8.8.8       # Info for 8.8.8.8"
    echo "  q-ip -i google.com # Just print resolved IP"
    return
  fi

  # 获取 JSON 数据
  local response
  response=$(curl -s "http://ip-api.com/json/$target")

  if [[ $show_ip_only -eq 1 ]]; then
    echo "$response" | jq -r '.query'
  else
    echo "$response" | jq
  fi
}

function q-ask {
  echo -n $1$' (y/n):'
  read choice
  case $choice in
  Y | y)
    return 0
    ;;
  esac
  return -1
}

function q-kill-by-name {
  if [[ ! -n $1 ]]; then
    echo "you have not input a keyword!"
  fi
  ps -ef | grep -E $1 | grep -v grep
  echo "\nThe above process will be kill(y/n)"
  read kill_or_not
  case $kill_or_not in
  Y | y)
    ps -ef | grep -E $1 | grep -v grep | awk '{print $2}' | xargs kill
    ;;
  esac
}

function q-color {
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
function q-extract {
  filepath=$(realpath $1)
  if [ -f $1 ]; then
    if [ "$2" ]; then
      mkdir $2
      echo "dir $2 created"
      cd $2
    fi
    case $1 in
    *.tar.bz2) tar -xvjf $filepath ;;
    *.tar.gz) tar -xvzf $filepath ;;
    *.tar.xz) tar -xvJf $filepath ;;
    *.txz) tar -xvJf $filepath ;;
    *.bz2) bunzip2 $filepath ;;
    *.rar) rar x $filepath ;;
    *.gz) gunzip $filepath ;;
    *.tar) tar -xvf $filepath ;;
    *.tbz2) tar -xvjf $filepath ;;
    *.tgz) tar -xvzf $filepath ;;
    *.zip) unzip $filepath ;;
    *.jar) unzip $filepath ;;
    *.Z) uncompress $filepath ;;
    *.7z) 7z x $filepath ;;
    *) echo "don't know how to extract '$1'..." ;;
    esac
    if [ "$2" ]; then
      cd ..
    fi
  else
    echo "'$1' is not a valid file!"
  fi
}

# easy compress - archive wrapper
function q-compress {
  if [ -n "$1" ]; then
    FILE=$1
    case $FILE in
    *.tar) shift && tar -cf $FILE $* ;;
    *.tar.bz2) shift && tar -cjf $FILE $* ;;
    *.tar.xz) shift && tar -cJf $FILE $* ;;
    *.txz) shift && tar -cJf $FILE $* ;;
    *.tar.gz) shift && tar -czf $FILE $* ;;
    *.tgz) shift && tar -czf $FILE $* ;;
    *.zip) shift && zip -r $FILE $* ;;
    *.7z) shift && 7za a $FILE $* ;;
    *.rar) shift && rar $FILE $* ;;
    esac
  else
    echo "usage: q-compress <foobar.tar.gz> ./foo ./bar"
  fi
}

# 在每次目录改变后自动执行 chpwd 函数。
function chpwd() {
  # 原函数中的逻辑放在这里，但不包含 cd 命令本身
  if [[ -z "$VIRTUAL_ENV" ]]; then
    if [[ -d ./.env ]]; then
      source ./.env/bin/activate
    fi
  else
    parentdir="$(dirname "$VIRTUAL_ENV")"
    if [[ "$PWD"/ != "$parentdir"/* ]]; then
      deactivate
    fi
  fi
}
