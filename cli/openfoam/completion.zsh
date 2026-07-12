# Zsh tab completion for the openfoam CLI.
# Pip install registers share/zsh/site-functions/_openfoam automatically.
# Optional:
#   eval "$(openfoam completion zsh)"

source "${0:A:h}/_openfoam"
autoload -Uz compdef
compdef _openfoam openfoam
