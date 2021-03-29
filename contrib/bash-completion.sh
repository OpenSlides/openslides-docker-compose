_osinstancectl()
{
  local cur prev opts diropts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="ls add rm start stop update erase"
  opts+=" --help --long --metadata --online --offline --error"
  opts+=" --clone-from --force --color --project-dir --fast --patient"
  opts+=" --image-info --version"
  opts+=" --backend-registry --backend-tag --frontend-registry --frontend-tag --all-tags"
  opts+=" --autoupdate-registry --autoupdate-tag"
  opts+=" --local-only --no-add-account"
  opts+=" --yaml-template --env-template"
  diropts="ls|rm|start|stop|update|erase|--clone-from"

  if [[ ${prev} =~ ${diropts} ]]; then
    COMPREPLY=( $(cd /srv/openslides/docker-instances && compgen -d -- ${cur}) )
    return 0
  fi

  if [[ ${prev} == --*template ]]; then
    _filedir
    return 0
  fi

  if [[ ${cur} == * ]] ; then
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
  fi
}

complete -F _osinstancectl osinstancectl
complete -F _osinstancectl osstackctl
