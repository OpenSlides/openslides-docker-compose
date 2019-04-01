_osinstancectl()
{
  local cur prev opts diropts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="ls add rm start stop update erase"
  opts+="--help --long --metadata --online --offline --no-add-account"
  opts+="--revision --repo --clone-from --force --color --project-dir"
  diropts="ls|rm|start|stop|update|erase|--clone-from"

  if [[ ${prev} =~ ${diropts} ]]; then
    COMPREPLY=( $(cd /srv/openslides/docker-instances && compgen -d -- ${cur}) )
    return 0
  fi

  if [[ ${cur} == * ]] ; then
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
  fi
}

complete -F _osinstancectl osinstancectl
